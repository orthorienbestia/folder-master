use super::{database_revision, error, json_error, sql, validate_id, Result, Store};
use crate::rules::{RuleDefinition, RuleId, MAX_RULE_JSON_BYTES};
use rusqlite::{params, OptionalExtension};
use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RuleRecord {
    pub folder_id: String,
    pub revision: u64,
    pub definition: RuleDefinition,
}
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RuleSummary {
    pub id: RuleId,
    pub revision: u64,
    pub name: String,
    pub enabled: bool,
    pub condition_count: usize,
    pub action_count: usize,
}
#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct RulePage {
    pub folder_id: String,
    pub rules: Vec<RuleSummary>,
    pub rule_count: u64,
    pub next_offset: Option<u64>,
}
fn canonical_id(id: &str) -> Result<RuleId> {
    RuleId::try_from(id.to_owned()).map_err(|_| error("invalid_id", "Choose a valid rule UUID."))
}
fn saved_record(id: &str, folder_id: String, revision: i64, data: &str) -> Result<RuleRecord> {
    validate_id(&folder_id).map_err(|_| {
        error(
            "invalid_saved_rule",
            "Saved rule folder metadata is invalid; it was not changed.",
        )
    })?;
    let definition = RuleDefinition::from_json(data).map_err(|_| {
        error(
            "invalid_saved_rule",
            "A saved rule is invalid or incompatible; it was not changed.",
        )
    })?;
    if definition.id.as_str() != id || revision <= 0 {
        return Err(error(
            "invalid_saved_rule",
            "Saved rule identity/revision metadata is inconsistent.",
        ));
    }
    Ok(RuleRecord {
        folder_id,
        revision: revision as u64,
        definition,
    })
}
impl Store {
    pub fn save_rule_definition(
        &mut self,
        folder_id: &str,
        expected_revision: Option<u64>,
        definition: &RuleDefinition,
    ) -> Result<RuleRecord> {
        validate_id(folder_id)?;
        if let Err(issues) = crate::compiler::CompiledRule::compile(definition) {
            let issue = &issues[0];
            return Err(error(
                "invalid_rule",
                format!("{}: {}", issue.path, issue.message),
            ));
        }
        let expected = expected_revision.map(database_revision).transpose()?;
        let data = serde_json::to_string(definition).map_err(json_error)?;
        let id = definition.id.as_str();
        let tx = self.connection.transaction().map_err(sql)?;
        let folder_exists: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM folders WHERE id=?1)",
                [folder_id],
                |r| r.get(0),
            )
            .map_err(sql)?;
        if !folder_exists {
            return Err(error(
                "folder_missing",
                "The watched folder was removed. Refresh before saving.",
            ));
        }
        let head: Option<(String, i64)> = tx
            .query_row(
                "SELECT folder_id,revision FROM rule_heads WHERE rule_id=?1",
                [id],
                |r| Ok((r.get(0)?, r.get(1)?)),
            )
            .optional()
            .map_err(sql)?;
        let revision = match (expected, head.as_ref()) {
            (None, None) => {
                let used: bool = tx
                    .query_row(
                        "SELECT EXISTS(SELECT 1 FROM rule_revisions WHERE rule_id=?1)",
                        [id],
                        |r| r.get(0),
                    )
                    .map_err(sql)?;
                if used {
                    return Err(error(
                        "rule_exists",
                        "This UUID belongs to a historical rule. Duplicate with a new identity.",
                    ));
                }
                1
            }
            (None, Some(_)) => {
                return Err(error(
                    "rule_exists",
                    "This rule already exists. Refresh before saving.",
                ))
            }
            (Some(_), None) => {
                return Err(error(
                    "rule_missing",
                    "The rule was removed. Refresh before saving.",
                ))
            }
            (Some(expected), Some((old_folder, old_revision))) => {
                if old_folder != folder_id {
                    return Err(error(
                        "folder_mismatch",
                        "A rule cannot be moved to another folder by saving its revision.",
                    ));
                }
                if *old_revision != expected {
                    return Err(error(
                        "stale_revision",
                        "The rule changed. Refresh before saving.",
                    ));
                }
                let (saved_folder, saved_json): (String, String) = tx.query_row(
                    "SELECT folder_id,document_json FROM rule_revisions WHERE rule_id=?1 AND revision=?2",
                    params![id, old_revision],
                    |row| Ok((row.get(0)?, row.get(1)?)),
                ).map_err(sql)?;
                if saved_folder != *old_folder {
                    return Err(error(
                        "invalid_saved_rule",
                        "The current rule revision belongs to a different folder.",
                    ));
                }
                saved_record(id, saved_folder, *old_revision, &saved_json)?;
                old_revision
                    .checked_add(1)
                    .ok_or_else(|| error("invalid_revision", "Rule revision overflow."))?
            }
        };
        tx.execute("INSERT INTO rule_revisions(rule_id,revision,folder_id,document_json) VALUES(?1,?2,?3,?4)",params![id,revision,folder_id,data]).map_err(sql)?;
        if let Some((_, old_revision)) = head {
            let changed=tx.execute("UPDATE rule_heads SET revision=?1 WHERE rule_id=?2 AND folder_id=?3 AND revision=?4",params![revision,id,folder_id,old_revision]).map_err(sql)?;
            if changed != 1 {
                return Err(error(
                    "stale_revision",
                    "The rule changed before its revision was committed.",
                ));
            }
        } else {
            tx.execute(
                "INSERT INTO rule_heads(rule_id,folder_id,revision) VALUES(?1,?2,?3)",
                params![id, folder_id, revision],
            )
            .map_err(sql)?;
        }
        tx.commit().map_err(sql)?;
        Ok(RuleRecord {
            folder_id: folder_id.into(),
            revision: revision as u64,
            definition: definition.clone(),
        })
    }
    pub fn rule_definition(&self, id: &str, revision: Option<u64>) -> Result<Option<RuleRecord>> {
        let id = canonical_id(id)?;
        let columns:Option<(String,i64,String,String)>=match revision {
            Some(revision)=>self.connection.query_row("SELECT folder_id,revision,document_json,folder_id FROM rule_revisions WHERE rule_id=?1 AND revision=?2",params![id.as_str(),database_revision(revision)?],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).optional().map_err(sql)?,
            None=>self.connection.query_row("SELECT r.folder_id,r.revision,r.document_json,h.folder_id FROM rule_heads h JOIN rule_revisions r ON r.rule_id=h.rule_id AND r.revision=h.revision WHERE h.rule_id=?1",[id.as_str()],|r|Ok((r.get(0)?,r.get(1)?,r.get(2)?,r.get(3)?))).optional().map_err(sql)?,
        };
        columns
            .map(|(folder, revision, data, head_folder)| {
                if folder != head_folder {
                    return Err(error(
                        "invalid_saved_rule",
                        "The rule head belongs to a different folder.",
                    ));
                }
                saved_record(id.as_str(), folder, revision, &data)
            })
            .transpose()
    }
    pub fn rule_definitions_page(&self, folder_id: &str, offset: u64) -> Result<RulePage> {
        validate_id(folder_id)?;
        let exists: bool = self
            .connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM folders WHERE id=?1)",
                [folder_id],
                |r| r.get(0),
            )
            .map_err(sql)?;
        if !exists {
            return Err(error(
                "folder_missing",
                "The watched folder was removed. Refresh first.",
            ));
        }
        let rule_count: i64 = self
            .connection
            .query_row(
                "SELECT COUNT(*) FROM rule_heads WHERE folder_id=?1",
                [folder_id],
                |r| r.get(0),
            )
            .map_err(sql)?;
        let rule_count = u64::try_from(rule_count)
            .map_err(|_| error("invalid_saved_rule", "Rule count is invalid."))?;
        // Return only summaries; cap both row count and serialized byte budget.
        let mut statement=self.connection.prepare("SELECT r.rule_id,r.folder_id,r.revision,r.document_json FROM rule_heads h JOIN rule_revisions r ON r.rule_id=h.rule_id AND r.revision=h.revision WHERE h.folder_id=?1 ORDER BY h.rowid LIMIT 50 OFFSET ?2").map_err(sql)?;
        let mut rows = statement
            .query(params![
                folder_id,
                i64::try_from(offset).unwrap_or(i64::MAX)
            ])
            .map_err(sql)?;
        let mut rules = Vec::new();
        let mut bytes = 0usize;
        while let Some(row) = rows.next().map_err(sql)? {
            let record = saved_record(
                &row.get::<_, String>(0).map_err(sql)?,
                row.get(1).map_err(sql)?,
                row.get(2).map_err(sql)?,
                &row.get::<_, String>(3).map_err(sql)?,
            )?;
            if record.folder_id != folder_id {
                return Err(error(
                    "invalid_saved_rule",
                    "Rule head/folder metadata is inconsistent.",
                ));
            }
            let definition = record.definition;
            let summary = RuleSummary {
                condition_count: definition.condition_count(),
                action_count: definition.actions.len(),
                id: definition.id,
                revision: record.revision,
                name: definition.name,
                enabled: definition.enabled,
            };
            let size = serde_json::to_vec(&summary).map_err(json_error)?.len() + 1;
            if size > MAX_RULE_JSON_BYTES {
                return Err(error(
                    "invalid_saved_rule",
                    "Rule summary exceeds the response budget.",
                ));
            }
            if bytes + size > MAX_RULE_JSON_BYTES {
                break;
            }
            bytes += size;
            rules.push(summary);
        }
        let next = offset.saturating_add(rules.len() as u64);
        Ok(RulePage {
            folder_id: folder_id.into(),
            rules,
            rule_count,
            next_offset: if next < rule_count && next > offset {
                Some(next)
            } else {
                None
            },
        })
    }
}
