use super::{
    error, time::EvaluationContext, CompileError, CompiledMetadataPredicate, Evaluation,
    MetadataSnapshot, Truth,
};
use crate::rules::{CalendarDate, ConditionExpression, ConditionNode, RuleId};
use std::collections::HashSet;
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GroupMode {
    All,
    Any,
    None,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConditionEvaluation {
    pub id: RuleId,
    pub truth: Truth,
    pub evidence: ConditionEvidence,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ConditionEvidence {
    Predicate(Evaluation),
    Group {
        mode: GroupMode,
        evaluated: Vec<ConditionEvaluation>,
        skipped: Vec<RuleId>,
    },
}
#[derive(Debug)]
pub struct CompiledConditions {
    root: Node,
}
#[derive(Debug)]
struct Node {
    id: RuleId,
    kind: NodeKind,
}
#[derive(Debug)]
enum NodeKind {
    Predicate(CompiledMetadataPredicate),
    Group {
        mode: GroupMode,
        children: Vec<Node>,
    },
}
impl CompiledConditions {
    pub fn compile(root: &ConditionNode) -> Result<Self, CompileError> {
        if matches!(root.expression, ConditionExpression::Predicate { .. }) {
            return Err(error("root_group"));
        }
        root.validate(
            1,
            "conditions",
            true,
            &mut HashSet::new(),
            &mut HashSet::new(),
            &mut 0,
        )
        .map_err(|_| error("invalid_conditions"))?;
        Ok(Self {
            root: Node::compile(root)?,
        })
    }
    pub fn evaluate(
        &self,
        snapshot: &MetadataSnapshot,
        context: Option<&EvaluationContext>,
    ) -> ConditionEvaluation {
        self.root.evaluate(snapshot, context)
    }
    pub fn calendar_dates(&self) -> Vec<CalendarDate> {
        let mut dates = Vec::new();
        self.root.collect_dates(&mut dates);
        dates
    }
}
impl Node {
    fn compile(node: &ConditionNode) -> Result<Self, CompileError> {
        let kind = match &node.expression {
            ConditionExpression::Predicate { predicate } => {
                NodeKind::Predicate(CompiledMetadataPredicate::compile(predicate)?)
            }
            ConditionExpression::All { children }
            | ConditionExpression::Any { children }
            | ConditionExpression::None { children } => NodeKind::Group {
                mode: match node.expression {
                    ConditionExpression::All { .. } => GroupMode::All,
                    ConditionExpression::Any { .. } => GroupMode::Any,
                    _ => GroupMode::None,
                },
                children: children
                    .iter()
                    .map(Self::compile)
                    .collect::<Result<_, _>>()?,
            },
        };
        Ok(Self {
            id: node.id.clone(),
            kind,
        })
    }
    fn collect_dates(&self, dates: &mut Vec<CalendarDate>) {
        match &self.kind {
            NodeKind::Predicate(p) => {
                if let Some(date) = p.calendar_date() {
                    if !dates.contains(date) {
                        dates.push(date.clone());
                    }
                }
            }
            NodeKind::Group { children, .. } => {
                for child in children {
                    child.collect_dates(dates)
                }
            }
        }
    }
    fn evaluate(
        &self,
        snapshot: &MetadataSnapshot,
        context: Option<&EvaluationContext>,
    ) -> ConditionEvaluation {
        match &self.kind {
            NodeKind::Predicate(predicate) => {
                let result = predicate.evaluate_with_context(snapshot, context);
                ConditionEvaluation {
                    id: self.id.clone(),
                    truth: result.truth.clone(),
                    evidence: ConditionEvidence::Predicate(result),
                }
            }
            NodeKind::Group { mode, children } => {
                let mut evaluated = Vec::new();
                let mut unknown = false;
                let mut decisive = false;
                for child in children {
                    let result = child.evaluate(snapshot, context);
                    unknown |= result.truth == Truth::Unknown;
                    decisive = if *mode == GroupMode::All {
                        result.truth == Truth::False
                    } else {
                        result.truth == Truth::True
                    };
                    evaluated.push(result);
                    if decisive {
                        break;
                    }
                }
                let skipped = children[evaluated.len()..]
                    .iter()
                    .map(|node| node.id.clone())
                    .collect();
                let truth = if *mode == GroupMode::All {
                    if decisive {
                        Truth::False
                    } else if unknown {
                        Truth::Unknown
                    } else {
                        Truth::True
                    }
                } else {
                    let any = if decisive {
                        Truth::True
                    } else if unknown {
                        Truth::Unknown
                    } else {
                        Truth::False
                    };
                    if *mode == GroupMode::None {
                        match any {
                            Truth::True => Truth::False,
                            Truth::False => Truth::True,
                            Truth::Unknown => Truth::Unknown,
                        }
                    } else {
                        any
                    }
                };
                ConditionEvaluation {
                    id: self.id.clone(),
                    truth,
                    evidence: ConditionEvidence::Group {
                        mode: mode.clone(),
                        evaluated,
                        skipped,
                    },
                }
            }
        }
    }
}
