//! Versioned rule configuration. Validation is pure: no discovery or effects.
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use unicode_segmentation::UnicodeSegmentation;

// Empty struct variants retain unknown-field checks in the pinned Serde build.
pub const RULE_SCHEMA_VERSION: u32 = 1;
// Leave room for IDs, revision metadata and the bridge response envelope.
pub const MAX_RULE_JSON_BYTES: usize = 1_048_576 - 4096;

#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(try_from = "String", into = "String")]
pub struct RuleId(String);
impl RuleId {
    pub fn as_str(&self) -> &str {
        &self.0
    }
}
impl TryFrom<String> for RuleId {
    type Error = &'static str;
    fn try_from(value: String) -> Result<Self, Self::Error> {
        let bytes = value.as_bytes();
        if bytes.len() != 36
            || bytes.iter().enumerate().any(|(i, b)| {
                if [8, 13, 18, 23].contains(&i) {
                    *b != b'-'
                } else {
                    !b.is_ascii_hexdigit()
                }
            })
        {
            return Err("Expected a UUID identifier.");
        }
        Ok(Self(value.to_ascii_lowercase()))
    }
}
impl From<RuleId> for String {
    fn from(value: RuleId) -> Self {
        value.0
    }
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct RuleDefinition {
    pub schema_version: u32,
    pub id: RuleId,
    pub name: String,
    pub enabled: bool,
    pub conditions: ConditionNode,
    pub actions: Vec<ActionNode>,
    pub behavior: RuleBehavior,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RuleBehavior {
    Stop,
    ContinueRules,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ConditionNode {
    pub id: RuleId,
    pub expression: ConditionExpression,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum ConditionExpression {
    All { children: Vec<ConditionNode> },
    Any { children: Vec<ConditionNode> },
    None { children: Vec<ConditionNode> },
    Predicate { predicate: Predicate },
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "field", rename_all = "snake_case", deny_unknown_fields)]
pub enum Predicate {
    Name {
        op: NameOperator,
        value: String,
        scope: NameScope,
        case_sensitive: bool,
    },
    Extension {
        test: ExtensionTest,
    },
    Kind {
        op: EqualityOperator,
        kind: KindValue,
    },
    Size {
        unit: SizeUnit,
        test: SizeTest,
    },
    Date {
        source: DateSource,
        test: DateTest,
    },
    Tags {
        case_sensitive: bool,
        test: TagTest,
    },
    Label {
        op: SetOperator,
        labels: Vec<FinderLabel>,
    },
    Text {
        op: TextOperator,
        value: String,
        source: ContentSource,
        case_sensitive: bool,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NameOperator {
    Is,
    IsNot,
    Contains,
    DoesNotContain,
    BeginsWith,
    EndsWith,
    Glob,
    Regex,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum NameScope {
    Filename,
    Stem,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum ExtensionTest {
    OneOf { values: Vec<String> },
    NotOneOf { values: Vec<String> },
    IsEmpty {},
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EqualityOperator {
    Is,
    IsNot,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum KindValue {
    Document {},
    Image {},
    Pdf {},
    Audio {},
    Video {},
    Archive {},
    Other {},
    UtType { identifier: String },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SizeUnit {
    Bytes,
    Kib,
    Mib,
    Gib,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum SizeTest {
    Equals { bytes: u64 },
    LessThan { bytes: u64 },
    GreaterThan { bytes: u64 },
    Between { minimum: u64, maximum: u64 },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum DateSource {
    Created,
    Modified,
    LastOpened,
    AddedToFolder,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum DateTest {
    Before { timestamp_ms: i64 },
    After { timestamp_ms: i64 },
    OnDate { date: CalendarDate },
    DateRange { start_ms: i64, end_ms: i64 },
    OlderThan { amount: f64, unit: AgeUnit },
    NewerThan { amount: f64, unit: AgeUnit },
    Today {},
    Yesterday {},
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct CalendarDate {
    pub year: u16,
    pub month: u8,
    pub day: u8,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum AgeUnit {
    Minutes,
    Hours,
    Days,
    Weeks,
}
impl AgeUnit {
    pub fn seconds(&self) -> f64 {
        match self {
            Self::Minutes => 60.0,
            Self::Hours => 3600.0,
            Self::Days => 86400.0,
            Self::Weeks => 604800.0,
        }
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum TagTest {
    ContainsAny { names: Vec<String> },
    ContainsAll { names: Vec<String> },
    ContainsNone { names: Vec<String> },
    IsEmpty {},
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SetOperator {
    OneOf,
    NotOneOf,
}
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum FinderLabel {
    None,
    Gray,
    Green,
    Purple,
    Blue,
    Yellow,
    Red,
    Orange,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum TextOperator {
    Contains,
    DoesNotContain,
    Regex,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContentSource {
    EmbeddedOnly,
    EmbeddedThenOcr,
    ForceOcr,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ActionNode {
    pub id: RuleId,
    pub action: Action,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Action {
    Move {
        destination: Destination,
    },
    Copy {
        destination: Destination,
    },
    Rename {
        rename: Rename,
        preserve_extension: bool,
    },
    Metadata {
        tags: TagChange,
        label: LabelChange,
    },
    Compress {
        destination: Destination,
        filename: Template,
    },
    Uncompress {
        destination: Destination,
    },
    Trash {},
    Delete {},
    Script {
        script: LocationReference,
        interpreter: Interpreter,
        arguments: Vec<String>,
        timeout_seconds: u16,
        publish_output: Option<Destination>,
    },
}
impl Action {
    pub fn terminal(&self) -> bool {
        matches!(
            self,
            Self::Uncompress { .. }
                | Self::Trash { .. }
                | Self::Delete { .. }
                | Self::Script { .. }
        )
    }
    pub fn guarded(&self) -> bool {
        matches!(self, Self::Delete { .. } | Self::Script { .. })
    }
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocationReference {
    pub path_bytes_base64: String,
    pub bookmark_base64: String,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Destination {
    pub root: LocationReference,
    pub subfolder: Template,
    pub create_missing: bool,
    pub conflict: ConflictPolicy,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConflictPolicy {
    KeepBoth,
    Skip,
    Ask,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Template {
    pub text: String,
    pub capture_condition_id: Option<RuleId>,
}
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum Rename {
    Template {
        template: Template,
    },
    Replace {
        find: String,
        replacement: String,
        regex: bool,
        replace_all: bool,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum TagChange {
    Unchanged {},
    Add {
        names: Vec<String>,
    },
    Remove {
        names: Vec<String>,
    },
    Replace {
        names: Vec<String>,
        acknowledged: bool,
    },
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "mode", rename_all = "snake_case", deny_unknown_fields)]
pub enum LabelChange {
    Unchanged {},
    Set { color: FinderLabel },
    Clear {},
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case", deny_unknown_fields)]
pub enum Interpreter {
    Zsh {},
    Sh {},
    Executable {},
    Custom { executable: LocationReference },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ValidationIssue {
    pub code: &'static str,
    pub path: String,
    pub message: &'static str,
}
type Validation = Result<(), ValidationIssue>;
fn issue(code: &'static str, path: impl Into<String>, message: &'static str) -> ValidationIssue {
    ValidationIssue {
        code,
        path: path.into(),
        message,
    }
}
fn required(value: &str, path: &str) -> Validation {
    if value.is_empty() {
        Err(issue(
            "required_value",
            path,
            "Enter a nonempty value; literal spaces are allowed.",
        ))
    } else {
        Ok(())
    }
}
fn tag_names(names: &[String], path: &str) -> Validation {
    if names
        .iter()
        .any(|s| s.trim().is_empty() || s.contains('\0'))
    {
        return Err(issue(
            "invalid_tag",
            path,
            "Tag names must be nonempty and NUL-free.",
        ));
    }
    let mut seen = HashSet::new();
    if names.iter().any(|s| !seen.insert(s)) {
        return Err(issue("duplicate_value", path, "Remove duplicate values."));
    }
    Ok(())
}
impl RuleDefinition {
    /// Return the first actionable issue. Full pattern/template compilation is a later gate.
    pub fn from_json(text: &str) -> Result<Self, Vec<ValidationIssue>> {
        if text.len() > MAX_RULE_JSON_BYTES {
            return Err(vec![issue(
                "rule_too_large",
                "definition",
                "The rule document exceeds the bounded bridge budget.",
            )]);
        }
        #[derive(Deserialize)]
        struct Version {
            schema_version: u32,
        }
        let bad_format = || {
            vec![issue(
                "invalid_format",
                "definition",
                "The rule format has missing, duplicate, unknown or incompatible fields.",
            )]
        };
        let version: Version = serde_json::from_str(text).map_err(|_| bad_format())?;
        if version.schema_version != RULE_SCHEMA_VERSION {
            return Err(vec![issue(
                "unsupported_rule_version",
                "schema_version",
                "This rule format requires a different app version; it was not rewritten.",
            )]);
        }
        let rule: Self = serde_json::from_str(text).map_err(|_| bad_format())?;
        let issues = rule.validation_issues();
        if issues.is_empty() {
            Ok(rule)
        } else {
            Err(issues)
        }
    }
    pub fn validation_issues(&self) -> Vec<ValidationIssue> {
        self.validate().err().into_iter().collect()
    }
    fn validate(&self) -> Validation {
        if self.schema_version != RULE_SCHEMA_VERSION {
            return Err(issue(
                "unsupported_rule_version",
                "schema_version",
                "This rule format is unsupported.",
            ));
        }
        if self.name.trim().is_empty() || self.name.graphemes(true).count() > 200 {
            return Err(issue(
                "name_length",
                "name",
                "Rule names need 1–200 user-perceived characters.",
            ));
        }
        if matches!(
            self.conditions.expression,
            ConditionExpression::Predicate { .. }
        ) {
            return Err(issue(
                "root_group",
                "conditions",
                "Start with an All, Any or None group.",
            ));
        }
        if self.actions.is_empty() || self.actions.len() > 20 {
            return Err(issue(
                "action_count",
                "actions",
                "Use between 1 and 20 actions.",
            ));
        }
        let mut seen = HashSet::from([self.id.clone()]);
        let mut captures = HashSet::new();
        let mut count = 0;
        self.conditions
            .validate(1, "conditions", true, &mut seen, &mut captures, &mut count)?;
        for (i, node) in self.actions.iter().enumerate() {
            let path = format!("actions[{i}]");
            if !seen.insert(node.id.clone()) {
                return Err(issue(
                    "duplicate_id",
                    format!("{path}.id"),
                    "Every rule node needs a unique UUID.",
                ));
            }
            if node.action.terminal() && i + 1 != self.actions.len() {
                return Err(issue(
                    "after_terminal",
                    path,
                    "A terminal action must be last.",
                ));
            }
            if node.action.terminal() && self.behavior != RuleBehavior::Stop {
                return Err(issue(
                    "terminal_continue",
                    "behavior",
                    "Terminal actions require Stop after match.",
                ));
            }
            node.action.validate(&format!("{path}.action"), &captures)?;
            // No real approval/global-capability mechanism is integrated yet.
            if self.enabled && node.action.guarded() {
                return Err(issue("capability_unavailable","enabled","Delete and script rules cannot enable until their execution and approval gates pass."));
            }
        }
        if serde_json::to_vec(self)
            .map_err(|_| {
                issue(
                    "invalid_format",
                    "definition",
                    "The rule cannot be encoded.",
                )
            })?
            .len()
            > MAX_RULE_JSON_BYTES
        {
            return Err(issue(
                "rule_too_large",
                "definition",
                "The rule exceeds the bounded bridge budget.",
            ));
        }
        Ok(())
    }
    pub fn condition_count(&self) -> usize {
        self.conditions.leaf_count()
    }
}
impl ConditionNode {
    fn leaf_count(&self) -> usize {
        match &self.expression {
            ConditionExpression::Predicate { .. } => 1,
            ConditionExpression::All { children }
            | ConditionExpression::Any { children }
            | ConditionExpression::None { children } => children.iter().map(Self::leaf_count).sum(),
        }
    }
    pub(crate) fn validate(
        &self,
        level: usize,
        path: &str,
        all: bool,
        seen: &mut HashSet<RuleId>,
        captures: &mut HashSet<RuleId>,
        count: &mut usize,
    ) -> Validation {
        if !seen.insert(self.id.clone()) {
            return Err(issue(
                "duplicate_id",
                format!("{path}.id"),
                "Every rule node needs a unique UUID.",
            ));
        }
        match &self.expression {
            ConditionExpression::Predicate { predicate } => {
                *count += 1;
                if *count > 50 {
                    return Err(issue(
                        "max_predicates",
                        "conditions",
                        "Use at most 50 leaf predicates.",
                    ));
                }
                predicate.validate(&format!("{path}.expression.predicate"))?;
                if all
                    && matches!(
                        predicate,
                        Predicate::Name {
                            op: NameOperator::Regex,
                            ..
                        } | Predicate::Text {
                            op: TextOperator::Regex,
                            ..
                        }
                    )
                {
                    captures.insert(self.id.clone());
                }
            }
            ConditionExpression::All { children }
            | ConditionExpression::Any { children }
            | ConditionExpression::None { children } => {
                if level > 3 {
                    return Err(issue("max_depth", path, "Use at most three group levels."));
                }
                if children.is_empty() {
                    return Err(issue("empty_group", path, "Empty groups cannot be saved."));
                }
                let all = all && matches!(self.expression, ConditionExpression::All { .. });
                for (i, child) in children.iter().enumerate() {
                    child.validate(
                        level + 1,
                        &format!("{path}.expression.children[{i}]"),
                        all,
                        seen,
                        captures,
                        count,
                    )?;
                }
            }
        }
        Ok(())
    }
}
impl Predicate {
    pub(crate) fn validate(&self, path: &str) -> Validation {
        match self {
            Self::Name { value, .. } | Self::Text { value, .. } => {
                required(value, &format!("{path}.value"))?
            }
            Self::Extension {
                test: ExtensionTest::OneOf { values } | ExtensionTest::NotOneOf { values },
            } => {
                if values.is_empty()
                    || values.iter().any(|v| {
                        v.is_empty()
                            || v.contains(['.', '/', '\0'])
                            || v != &v.to_lowercase()
                            || v != v.trim()
                    })
                {
                    return Err(issue(
                        "invalid_extension",
                        path,
                        "Use normalized final extensions without dots, paths or empty values.",
                    ));
                }
                let mut seen = HashSet::new();
                if values.iter().any(|v| !seen.insert(v)) {
                    return Err(issue(
                        "duplicate_value",
                        path,
                        "Remove duplicate extensions.",
                    ));
                }
            }
            Self::Kind {
                kind: KindValue::UtType { identifier },
                ..
            } => {
                if identifier.trim().is_empty() || identifier.contains('\0') {
                    return Err(issue("required_value", path, "Enter a UTType identifier."));
                }
            }
            Self::Size {
                test: SizeTest::Between { minimum, maximum },
                ..
            } if minimum > maximum => {
                return Err(issue(
                    "reversed_range",
                    path,
                    "The lower size must not exceed the upper size.",
                ))
            }
            Self::Date { test, .. } => match test {
                DateTest::OnDate { date } if !date.valid() => {
                    return Err(issue(
                        "invalid_date",
                        path,
                        "Choose a valid Gregorian calendar date.",
                    ))
                }
                DateTest::DateRange { start_ms, end_ms } if start_ms > end_ms => {
                    return Err(issue(
                        "reversed_range",
                        path,
                        "The start must not exceed the end.",
                    ))
                }
                DateTest::OlderThan { amount, unit } | DateTest::NewerThan { amount, unit }
                    if !amount.is_finite()
                        || *amount < 0.0
                        || !(amount * unit.seconds()).is_finite() =>
                {
                    return Err(issue(
                        "invalid_age",
                        path,
                        "Choose a finite nonnegative elapsed age.",
                    ))
                }
                _ => (),
            },
            Self::Tags {
                test:
                    TagTest::ContainsAny { names }
                    | TagTest::ContainsAll { names }
                    | TagTest::ContainsNone { names },
                ..
            } => {
                if names.is_empty() {
                    return Err(issue(
                        "required_value",
                        path,
                        "Choose at least one exact tag name.",
                    ));
                }
                tag_names(names, path)?;
            }
            Self::Label { labels, .. } => {
                let unique: HashSet<_> = labels.iter().collect();
                if labels.is_empty() || unique.len() != labels.len() {
                    return Err(issue(
                        "invalid_labels",
                        path,
                        "Choose at least one label without duplicates.",
                    ));
                }
            }
            _ => (),
        }
        Ok(())
    }
}
impl CalendarDate {
    fn valid(&self) -> bool {
        if self.year == 0 || self.year > 9999 || self.month == 0 || self.month > 12 {
            return false;
        }
        let leap = self.year % 4 == 0 && (self.year % 100 != 0 || self.year % 400 == 0);
        let days = match self.month {
            2 => {
                if leap {
                    29
                } else {
                    28
                }
            }
            4 | 6 | 9 | 11 => 30,
            _ => 31,
        };
        self.day > 0 && self.day <= days
    }
}
impl LocationReference {
    fn validate(&self, path: &str) -> Validation {
        let bytes = STANDARD
            .decode(&self.path_bytes_base64)
            .map_err(|_| issue("invalid_location", path, "Invalid byte-path encoding."))?;
        if bytes.first() != Some(&b'/')
            || bytes.len() > 32768
            || bytes.contains(&0)
            || self.bookmark_base64.is_empty()
            || self.bookmark_base64.len() > 65536
            || STANDARD.decode(&self.bookmark_base64).is_err()
        {
            return Err(issue(
                "invalid_location",
                path,
                "Choose a valid absolute byte-path and opaque bookmark reference.",
            ));
        }
        Ok(())
    }
}
impl Template {
    fn validate(
        &self,
        path: &str,
        filename: bool,
        allow_empty: bool,
        captures: &HashSet<RuleId>,
    ) -> Validation {
        let text = &self.text;
        if (!allow_empty && text.is_empty())
            || text.contains('\0')
            || text.starts_with('/')
            || (filename && text.contains('/'))
            || (!text.is_empty()
                && text
                    .split('/')
                    .any(|s| s.is_empty() || s == "." || s == ".."))
        {
            return Err(issue("invalid_template",path,"Use a nonempty contained filename or relative path without NUL, dot or parent components."));
        }
        if text.contains("{capture:")
            && !self
                .capture_condition_id
                .as_ref()
                .is_some_and(|id| captures.contains(id))
        {
            return Err(issue(
                "invalid_capture_source",
                path,
                "Capture tokens require a regex condition under unambiguous All groups.",
            ));
        }
        Ok(())
    }
}
impl Destination {
    fn validate(&self, path: &str, extraction: bool, captures: &HashSet<RuleId>) -> Validation {
        self.root.validate(&format!("{path}.root"))?;
        self.subfolder
            .validate(&format!("{path}.subfolder"), false, !extraction, captures)
    }
}
impl Action {
    fn validate(&self, path: &str, captures: &HashSet<RuleId>) -> Validation {
        match self {
            Self::Move { destination } | Self::Copy { destination } => {
                destination.validate(&format!("{path}.destination"), false, captures)?
            }
            Self::Rename { rename, .. } => match rename {
                Rename::Template { template } => {
                    template.validate(&format!("{path}.rename.template"), true, false, captures)?
                }
                Rename::Replace {
                    find, replacement, ..
                } => {
                    required(find, &format!("{path}.rename.find"))?;
                    if replacement.contains(['/', '\0']) {
                        return Err(issue(
                            "invalid_replacement",
                            path,
                            "Replacement text cannot contain a separator or NUL.",
                        ));
                    }
                }
            },
            Self::Metadata { tags, label } => {
                let changed = match tags {
                    TagChange::Unchanged { .. } => false,
                    TagChange::Add { names } | TagChange::Remove { names } => {
                        tag_names(names, path)?;
                        !names.is_empty()
                    }
                    TagChange::Replace {
                        names,
                        acknowledged,
                    } => {
                        tag_names(names, path)?;
                        if !acknowledged {
                            return Err(issue(
                                "replacement_acknowledgement",
                                path,
                                "Confirm replacement of the existing tag names.",
                            ));
                        }
                        true
                    }
                };
                if !changed && matches!(label, LabelChange::Unchanged { .. }) {
                    return Err(issue(
                        "metadata_no_change",
                        path,
                        "Choose a tag or color-label change.",
                    ));
                }
                if matches!(
                    label,
                    LabelChange::Set {
                        color: FinderLabel::None
                    }
                ) {
                    return Err(issue("invalid_label", path, "Choose a color or use Clear."));
                }
            }
            Self::Compress {
                destination,
                filename,
            } => {
                destination.validate(&format!("{path}.destination"), false, captures)?;
                filename.validate(&format!("{path}.filename"), true, false, captures)?;
            }
            Self::Uncompress { destination } => {
                destination.validate(&format!("{path}.destination"), true, captures)?
            }
            Self::Script {
                script,
                interpreter,
                arguments,
                timeout_seconds,
                publish_output,
            } => {
                script.validate(&format!("{path}.script"))?;
                if let Interpreter::Custom { executable } = interpreter {
                    executable.validate(&format!("{path}.interpreter.executable"))?;
                }
                if !(1..=600).contains(timeout_seconds) {
                    return Err(issue(
                        "script_timeout",
                        path,
                        "Use a whole timeout from 1 to 600 seconds.",
                    ));
                }
                if arguments.iter().any(|v| v.contains('\0')) {
                    return Err(issue("invalid_argument",path,"Arguments cannot contain NUL; empty arguments and shell punctuation remain literal."));
                }
                if let Some(destination) = publish_output {
                    destination.validate(&format!("{path}.publish_output"), false, captures)?;
                }
            }
            Self::Trash { .. } | Self::Delete { .. } => (),
        }
        Ok(())
    }
}
