//! Save-time pattern/output compilation and pure byte-preserving expansion.
//! No clock, filesystem lookup, counter reservation or effects occur here.
use crate::{
    matching::{self, CompiledMetadataPredicate},
    rules::*,
};
use regex::Regex;
use std::{collections::HashMap, os::unix::ffi::OsStrExt, path::Path};
use unicode_normalization::UnicodeNormalization;
const MAX_OUTPUT_BYTES: usize = 16_384;
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ExpansionError {
    pub code: &'static str,
}
fn err(code: &'static str) -> ExpansionError {
    ExpansionError { code }
}
type Result<T> = std::result::Result<T, ExpansionError>;
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TemplateSlot {
    Rename,
    Destination,
    ArchiveFilename,
}
#[derive(Debug)]
pub struct CompiledRule {
    templates: Vec<(RuleId, TemplateSlot, CompiledTemplate)>,
    renames: Vec<(RuleId, CompiledRename)>,
}
#[derive(Debug, Clone)]
struct CapturePattern {
    regex: Regex,
    source: CaptureSource,
    eligible: bool,
}
#[derive(Debug, Clone)]
enum CaptureSource {
    Name(NameScope),
    Text(ContentSource),
}
#[derive(Debug, Clone)]
pub struct CompiledTemplate {
    parts: Vec<Part>,
    purpose: Purpose,
    capture: Option<BoundCapture>,
}
#[derive(Debug, Clone, Copy)]
enum Purpose {
    Filename,
    Relative { allow_empty: bool },
}
#[derive(Debug, Clone)]
enum Part {
    Literal(Vec<u8>),
    Name,
    Stem,
    Ext,
    Date(DateField, Vec<DatePart>),
    Counter(usize),
    Capture(String),
}
#[derive(Debug, Clone)]
enum DateField {
    Created,
    Modified,
    Now,
}
#[derive(Debug, Clone)]
enum DatePart {
    Year,
    Month,
    Day,
    Hour,
    Minute,
    Second,
    Literal(u8),
}
#[derive(Debug, Clone, Copy)]
pub struct DateParts {
    year: u16,
    month: u8,
    day: u8,
    hour: u8,
    minute: u8,
    second: u8,
}
impl DateParts {
    pub fn new(year: u16, month: u8, day: u8, hour: u8, minute: u8, second: u8) -> Result<Self> {
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
        let days = match month {
            2 => {
                if leap {
                    29
                } else {
                    28
                }
            }
            4 | 6 | 9 | 11 => 30,
            1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
            _ => 0,
        };
        if year == 0
            || year > 9999
            || day == 0
            || day > days
            || hour > 23
            || minute > 59
            || second > 59
        {
            return Err(err("invalid_date_parts"));
        }
        Ok(Self {
            year,
            month,
            day,
            hour,
            minute,
            second,
        })
    }
}
#[derive(Debug)]
pub struct TextCaptureInput {
    pub text: String,
    pub complete: bool,
    pub source: ContentSource,
}
pub struct ExpansionContext<'a> {
    pub filename: &'a [u8],
    pub created: Option<DateParts>,
    pub modified: Option<DateParts>,
    pub now: Option<DateParts>,
    pub counter: Option<u64>,
    pub texts: Option<&'a HashMap<RuleId, TextCaptureInput>>,
}
impl<'a> ExpansionContext<'a> {
    pub fn new(filename: &'a [u8]) -> Self {
        Self {
            filename,
            created: None,
            modified: None,
            now: None,
            counter: None,
            texts: None,
        }
    }
}
// Capture identity stays with the compiled token, independently for each output.
#[derive(Debug, Clone)]
struct BoundCapture {
    id: RuleId,
    pattern: CapturePattern,
}
#[derive(Debug, Clone)]
pub struct CompiledRename {
    kind: RenameKind,
    preserve_extension: bool,
}
#[derive(Debug, Clone)]
enum RenameKind {
    Template(CompiledTemplate),
    Literal {
        find: Vec<u8>,
        replacement: Vec<u8>,
        all: bool,
    },
    Regex {
        regex: Regex,
        replacement: Vec<Replacement>,
        all: bool,
    },
}
#[derive(Debug, Clone)]
enum Replacement {
    Literal(Vec<u8>),
    Group(usize),
}
fn issue(code: &'static str, path: &str, id: &RuleId) -> ValidationIssue {
    let message = match code {
        "invalid_regex" => {
            "Enter a valid Rust regex; look-around and backreferences are unsupported."
        }
        "invalid_glob" => "Correct the filename glob, including paired classes and alternatives.",
        "unknown_token" => "Choose a supported template token from the token picker.",
        "invalid_date_format" => "Use yyyy, MM, dd, HH, mm, ss and literal hyphens or underscores.",
        "invalid_counter" => "Counter padding must be between 1 and 20 decimal digits.",
        "unknown_capture" => "Choose a named group defined by the selected regex condition.",
        "invalid_capture_source" => {
            "Choose a regex condition under All groups; Any and None captures are ambiguous."
        }
        "unknown_replacement_capture" => {
            "Use an existing capture group, ${name} or ${1}; $$ produces a literal dollar."
        }
        "pattern_too_long" | "template_too_long" => {
            "Shorten the pattern or template to at most 16 KiB."
        }
        _ => "Correct this pattern or template before saving.",
    };
    ValidationIssue {
        code,
        path: path.into(),
        message,
        node_id: Some(id.clone()),
    }
}
fn regex(value: &str, sensitive: bool) -> Result<Regex> {
    let value = matching::bounded_text(value).map_err(|e| err(e.code))?;
    matching::regex(&value, sensitive, "invalid_regex").map_err(|e| err(e.code))
}
fn raw_rename_regex(value: &str) -> Result<Regex> {
    if value.len() > matching::MAX_PATTERN_BYTES {
        return Err(err("pattern_too_long"));
    }
    matching::regex(value, true, "invalid_regex").map_err(|e| err(e.code))
}
impl CompiledRule {
    pub fn compile(rule: &RuleDefinition) -> std::result::Result<Self, Vec<ValidationIssue>> {
        let structural = rule.validation_issues();
        if !structural.is_empty() {
            return Err(structural);
        }
        let mut captures = HashMap::new();
        let mut issues = Vec::new();
        collect_patterns(
            &rule.conditions,
            "conditions",
            true,
            &mut captures,
            &mut issues,
        );
        let mut compiled = Self {
            templates: Vec::new(),
            renames: Vec::new(),
        };
        for (i, node) in rule.actions.iter().enumerate() {
            let path = format!("actions[{i}].action");
            let mut add_template =
                |template: &Template, slot: TemplateSlot, purpose: Purpose, field: &str| {
                    match CompiledTemplate::compile(template, purpose, &captures) {
                        Ok(t) => {
                            compiled.templates.push((node.id.clone(), slot, t.clone()));
                            Some(t)
                        }
                        Err(e) => {
                            issues.push(issue(e.code, &format!("{path}.{field}"), &node.id));
                            None
                        }
                    }
                };
            match &node.action {
                Action::Rename {
                    rename,
                    preserve_extension,
                } => {
                    let kind = match rename {
                        Rename::Template { template } => add_template(
                            template,
                            TemplateSlot::Rename,
                            Purpose::Filename,
                            "rename.template",
                        )
                        .map(RenameKind::Template),
                        Rename::Replace {
                            find,
                            replacement,
                            regex: use_regex,
                            replace_all,
                        } => {
                            if *use_regex {
                                match raw_rename_regex(find)
                                    .and_then(|r| Ok((replacement_parts(replacement, &r)?, r)))
                                {
                                    Ok((replacement, regex)) => Some(RenameKind::Regex {
                                        regex,
                                        replacement,
                                        all: *replace_all,
                                    }),
                                    Err(e) => {
                                        issues.push(issue(
                                            e.code,
                                            &format!(
                                                "{path}.rename.{}",
                                                if matches!(
                                                    e.code,
                                                    "unknown_replacement_capture"
                                                        | "template_too_long"
                                                ) {
                                                    "replacement"
                                                } else {
                                                    "find"
                                                }
                                            ),
                                            &node.id,
                                        ));
                                        None
                                    }
                                }
                            } else if find.len() > matching::MAX_PATTERN_BYTES
                                || replacement.len() > MAX_OUTPUT_BYTES
                            {
                                issues.push(issue(
                                    "pattern_too_long",
                                    &format!("{path}.rename"),
                                    &node.id,
                                ));
                                None
                            } else {
                                Some(RenameKind::Literal {
                                    find: find.as_bytes().to_vec(),
                                    replacement: replacement.as_bytes().to_vec(),
                                    all: *replace_all,
                                })
                            }
                        }
                    };
                    if let Some(kind) = kind {
                        compiled.renames.push((
                            node.id.clone(),
                            CompiledRename {
                                kind,
                                preserve_extension: *preserve_extension,
                            },
                        ));
                    }
                }
                Action::Move { destination }
                | Action::Copy { destination }
                | Action::Uncompress { destination } => {
                    add_template(
                        &destination.subfolder,
                        TemplateSlot::Destination,
                        Purpose::Relative {
                            allow_empty: !matches!(node.action, Action::Uncompress { .. }),
                        },
                        "destination.subfolder",
                    );
                }
                Action::Compress {
                    destination,
                    filename,
                } => {
                    add_template(
                        &destination.subfolder,
                        TemplateSlot::Destination,
                        Purpose::Relative { allow_empty: true },
                        "destination.subfolder",
                    );
                    add_template(
                        filename,
                        TemplateSlot::ArchiveFilename,
                        Purpose::Filename,
                        "filename",
                    );
                }
                Action::Script {
                    publish_output: Some(destination),
                    ..
                } => {
                    add_template(
                        &destination.subfolder,
                        TemplateSlot::Destination,
                        Purpose::Relative { allow_empty: true },
                        "publish_output.subfolder",
                    );
                }
                _ => {}
            }
        }
        if issues.is_empty() {
            Ok(compiled)
        } else {
            Err(issues)
        }
    }
    pub fn template(&self, id: &RuleId, slot: TemplateSlot) -> Option<&CompiledTemplate> {
        self.templates
            .iter()
            .find(|(node, s, _)| node == id && *s == slot)
            .map(|(_, _, t)| t)
    }
    pub fn rename(&self, id: &RuleId) -> Option<&CompiledRename> {
        self.renames
            .iter()
            .find(|(node, _)| node == id)
            .map(|(_, r)| r)
    }
}
fn collect_patterns(
    node: &ConditionNode,
    path: &str,
    eligible: bool,
    captures: &mut HashMap<RuleId, CapturePattern>,
    issues: &mut Vec<ValidationIssue>,
) {
    match &node.expression {
        ConditionExpression::Predicate { predicate } => {
            let field = format!("{path}.expression.predicate");
            let result = match predicate {
                Predicate::Text {
                    op,
                    value,
                    source,
                    case_sensitive,
                } => {
                    if *op == TextOperator::Regex {
                        regex(value, *case_sensitive).map(|regex| {
                            Some(CapturePattern {
                                regex,
                                source: CaptureSource::Text(source.clone()),
                                eligible,
                            })
                        })
                    } else {
                        matching::bounded_text(value)
                            .map(|_| None)
                            .map_err(|e| err(e.code))
                    }
                }
                Predicate::Name {
                    op: NameOperator::Regex,
                    value,
                    scope,
                    case_sensitive,
                } => regex(value, *case_sensitive).map(|regex| {
                    Some(CapturePattern {
                        regex,
                        source: CaptureSource::Name(scope.clone()),
                        eligible,
                    })
                }),
                _ => CompiledMetadataPredicate::compile(predicate)
                    .map(|_| None)
                    .map_err(|e| err(e.code)),
            };
            match result {
                Ok(Some(pattern)) => {
                    captures.insert(node.id.clone(), pattern);
                }
                Ok(None) => {}
                Err(e) => {
                    let value_path = match predicate {
                        Predicate::Extension { .. } => "test.values",
                        Predicate::Tags { .. } => "test.names",
                        _ => "value",
                    };
                    issues.push(issue(e.code, &format!("{field}.{value_path}"), &node.id));
                }
            }
        }
        ConditionExpression::All { children }
        | ConditionExpression::Any { children }
        | ConditionExpression::None { children } => {
            let eligible = eligible && matches!(node.expression, ConditionExpression::All { .. });
            for (i, child) in children.iter().enumerate() {
                collect_patterns(
                    child,
                    &format!("{path}.expression.children[{i}]"),
                    eligible,
                    captures,
                    issues,
                )
            }
        }
    }
}
impl CompiledTemplate {
    fn supplies_extension(&self, suffix: &[u8]) -> bool {
        match self.parts.last() {
            Some(Part::Name | Part::Ext) => true,
            Some(Part::Literal(bytes)) => bytes.ends_with(suffix),
            _ => false,
        }
    }
    fn compile(
        template: &Template,
        purpose: Purpose,
        captures: &HashMap<RuleId, CapturePattern>,
    ) -> Result<Self> {
        if template.text.len() > matching::MAX_PATTERN_BYTES {
            return Err(err("template_too_long"));
        }
        let mut parts = Vec::new();
        let mut rest = template.text.as_str();
        let mut capture = None;
        while !rest.is_empty() {
            let end = rest.find(['{', '}']).unwrap_or(rest.len());
            if end > 0 {
                parts.push(Part::Literal(rest.as_bytes()[..end].to_vec()));
                rest = &rest[end..];
            }
            if rest.is_empty() {
                break;
            }
            if !rest.starts_with('{') {
                return Err(err("unknown_token"));
            }
            let end = rest.find('}').ok_or_else(|| err("unknown_token"))?;
            let token = &rest[1..end];
            rest = &rest[end + 1..];
            let part = match token {
                "name" => Part::Name,
                "stem" => Part::Stem,
                "ext" => Part::Ext,
                _ => {
                    let (kind, value) =
                        token.split_once(':').ok_or_else(|| err("unknown_token"))?;
                    match kind {
                        "created" | "modified" | "now" => Part::Date(
                            match kind {
                                "created" => DateField::Created,
                                "modified" => DateField::Modified,
                                _ => DateField::Now,
                            },
                            date_format(value)?,
                        ),
                        "counter" => {
                            let width = value
                                .parse::<usize>()
                                .ok()
                                .filter(|n| (1..=20).contains(n))
                                .filter(|_| value.bytes().all(|b| b.is_ascii_digit()))
                                .ok_or_else(|| err("invalid_counter"))?;
                            Part::Counter(width)
                        }
                        "capture" => {
                            let id = template
                                .capture_condition_id
                                .as_ref()
                                .ok_or_else(|| err("invalid_capture_source"))?;
                            let pattern = captures
                                .get(id)
                                .filter(|p| p.eligible)
                                .ok_or_else(|| err("invalid_capture_source"))?;
                            if !pattern.regex.capture_names().flatten().any(|n| n == value) {
                                return Err(err("unknown_capture"));
                            }
                            capture = Some(BoundCapture {
                                id: id.clone(),
                                pattern: pattern.clone(),
                            });
                            Part::Capture(value.into())
                        }
                        _ => return Err(err("unknown_token")),
                    }
                }
            };
            parts.push(part);
        }
        Ok(Self {
            parts,
            purpose,
            capture,
        })
    }
    pub fn expand(&self, context: &ExpansionContext<'_>) -> Result<Vec<u8>> {
        let (stem, extension) = filename_parts(context.filename)?;
        // Evaluate each bound source once. Incomplete text cannot supply captures.
        let capture_text = self
            .capture
            .as_ref()
            .map(|bound| match &bound.pattern.source {
                CaptureSource::Name(scope) => {
                    let bytes = if *scope == NameScope::Stem {
                        stem
                    } else {
                        context.filename
                    };
                    std::str::from_utf8(bytes)
                        .map(|s| s.nfc().collect::<String>())
                        .map_err(|_| err("non_utf8_capture"))
                }
                CaptureSource::Text(source) => {
                    let input = context
                        .texts
                        .and_then(|map| map.get(&bound.id))
                        .ok_or_else(|| err("missing_capture"))?;
                    if !input.complete {
                        return Err(err("incomplete_capture"));
                    }
                    if input.source != *source {
                        return Err(err("capture_source_mismatch"));
                    }
                    Ok(input.text.nfc().collect())
                }
            })
            .transpose()?;
        let groups = match (&self.capture, &capture_text) {
            (Some(bound), Some(text)) => Some(
                bound
                    .pattern
                    .regex
                    .captures(text)
                    .ok_or_else(|| err("missing_capture"))?,
            ),
            _ => None,
        };
        let mut output = Vec::new();
        for part in &self.parts {
            let value = match part {
                Part::Literal(bytes) => {
                    append(&mut output, bytes)?;
                    continue;
                }
                Part::Name => context.filename.to_vec(),
                Part::Stem => stem.to_vec(),
                Part::Ext => extension
                    .filter(|value| !value.is_empty())
                    .ok_or_else(|| err("missing_extension"))?
                    .to_vec(),
                Part::Counter(width) => {
                    let n = context
                        .counter
                        .filter(|n| *n > 0)
                        .ok_or_else(|| err("missing_counter"))?;
                    format!("{n:0width$}").into_bytes()
                }
                Part::Date(field, format) => {
                    let date = match field {
                        DateField::Created => context.created,
                        DateField::Modified => context.modified,
                        DateField::Now => context.now,
                    }
                    .ok_or_else(|| err("missing_date"))?;
                    format_date(date, format)
                }
                Part::Capture(name) => {
                    let value = groups
                        .as_ref()
                        .and_then(|g| g.name(name))
                        .map(|g| g.as_str())
                        .filter(|s| !s.is_empty())
                        .ok_or_else(|| err("empty_capture"))?;
                    value.as_bytes().to_vec()
                }
            };
            if value.contains(&0) || value.contains(&b'/') {
                return Err(err("unsafe_token"));
            }
            append(&mut output, &value)?;
        }
        safe_output(&output, self.purpose)?;
        Ok(output)
    }
}
fn date_format(mut format: &str) -> Result<Vec<DatePart>> {
    if format.is_empty() {
        return Err(err("invalid_date_format"));
    }
    let mut parts = Vec::new();
    while !format.is_empty() {
        if format.starts_with('-') || format.starts_with('_') {
            parts.push(DatePart::Literal(format.as_bytes()[0]));
            format = &format[1..];
            continue;
        }
        let mut found = false;
        for (token, part) in [
            ("yyyy", DatePart::Year),
            ("MM", DatePart::Month),
            ("dd", DatePart::Day),
            ("HH", DatePart::Hour),
            ("mm", DatePart::Minute),
            ("ss", DatePart::Second),
        ] {
            if format.starts_with(token) {
                parts.push(part);
                format = &format[token.len()..];
                found = true;
                break;
            }
        }
        if !found {
            return Err(err("invalid_date_format"));
        }
    }
    Ok(parts)
}
fn format_date(date: DateParts, parts: &[DatePart]) -> Vec<u8> {
    let mut output = Vec::new();
    for part in parts {
        let (value, width) = match part {
            DatePart::Literal(b) => {
                output.push(*b);
                continue;
            }
            DatePart::Year => (date.year, 4),
            DatePart::Month => (date.month as u16, 2),
            DatePart::Day => (date.day as u16, 2),
            DatePart::Hour => (date.hour as u16, 2),
            DatePart::Minute => (date.minute as u16, 2),
            DatePart::Second => (date.second as u16, 2),
        };
        output.extend_from_slice(format!("{value:0width$}").as_bytes());
    }
    output
}
fn append(output: &mut Vec<u8>, value: &[u8]) -> Result<()> {
    if output.len().saturating_add(value.len()) > MAX_OUTPUT_BYTES {
        return Err(err("output_too_long"));
    }
    output.extend_from_slice(value);
    Ok(())
}
fn safe_output(bytes: &[u8], purpose: Purpose) -> Result<()> {
    if bytes.len() > MAX_OUTPUT_BYTES {
        return Err(err("output_too_long"));
    }
    if bytes.is_empty() && matches!(purpose, Purpose::Relative { allow_empty: true }) {
        return Ok(());
    }
    if bytes.is_empty()
        || bytes.contains(&0)
        || bytes.starts_with(b"/")
        || (matches!(purpose, Purpose::Filename) && bytes.contains(&b'/'))
        || bytes
            .split(|b| *b == b'/')
            .any(|c| c.is_empty() || c == b"." || c == b"..")
    {
        return Err(err("unsafe_output"));
    }
    Ok(())
}
fn filename_parts(filename: &[u8]) -> Result<(&[u8], Option<&[u8]>)> {
    safe_output(filename, Purpose::Filename)?;
    let path = Path::new(std::ffi::OsStr::from_bytes(filename));
    Ok((
        path.file_stem()
            .ok_or_else(|| err("unsafe_output"))?
            .as_bytes(),
        path.extension().map(|s| s.as_bytes()),
    ))
}
impl CompiledRename {
    pub fn expand(&self, context: &ExpansionContext<'_>) -> Result<Vec<u8>> {
        let (stem, extension) = filename_parts(context.filename)?;
        let input = if self.preserve_extension {
            stem
        } else {
            context.filename
        };
        let mut output = match &self.kind {
            RenameKind::Template(template) => template.expand(context)?,
            RenameKind::Literal {
                find,
                replacement,
                all,
            } => {
                let mut output = Vec::new();
                let mut rest = input;
                while let Some(i) = rest.windows(find.len()).position(|bytes| bytes == find) {
                    append(&mut output, &rest[..i])?;
                    append(&mut output, replacement)?;
                    rest = &rest[i + find.len()..];
                    if !all {
                        break;
                    }
                }
                append(&mut output, rest)?;
                output
            }
            RenameKind::Regex {
                regex,
                replacement,
                all,
            } => {
                let text = std::str::from_utf8(input).map_err(|_| err("non_utf8_rename"))?;
                let mut output = Vec::new();
                let mut end = 0;
                for groups in regex.captures_iter(text) {
                    let matched = groups.get(0).ok_or_else(|| err("missing_capture"))?;
                    append(&mut output, &text.as_bytes()[end..matched.start()])?;
                    for part in replacement {
                        match part {
                            Replacement::Literal(bytes) => append(&mut output, bytes)?,
                            Replacement::Group(index) => {
                                let value = groups
                                    .get(*index)
                                    .map(|g| g.as_str())
                                    .filter(|v| !v.is_empty())
                                    .ok_or_else(|| err("empty_capture"))?;
                                append(&mut output, value.as_bytes())?;
                            }
                        }
                    }
                    end = matched.end();
                    if !all {
                        break;
                    }
                }
                append(&mut output, &text.as_bytes()[end..])?;
                output
            }
        };
        // A template may already include the original extension (e.g. {name}).
        if let Some(extension) = extension.filter(|_| self.preserve_extension) {
            let mut suffix = vec![b'.'];
            suffix.extend_from_slice(extension);
            let supplied = match &self.kind {
                RenameKind::Template(template) => template.supplies_extension(&suffix),
                _ => false,
            };
            if !supplied || !output.ends_with(&suffix) {
                append(&mut output, &suffix)?;
            }
        }
        safe_output(&output, Purpose::Filename)?;
        Ok(output)
    }
}
/// Assign within one action/destination-prefix scope supplied by the planner.
/// These values are proposals: persistence/commit reservation belongs to the executor.
pub fn assign_counters(paths: &[Vec<u8>], start: u64) -> Result<Vec<(Vec<u8>, u64)>> {
    if start == 0 {
        return Err(err("invalid_counter"));
    }
    let mut sorted = paths.to_vec();
    sorted.sort();
    if sorted.windows(2).any(|pair| pair[0] == pair[1]) {
        return Err(err("duplicate_counter_input"));
    }
    let mut result = Vec::with_capacity(sorted.len());
    for (i, path) in sorted.into_iter().enumerate() {
        safe_output(&path, Purpose::Relative { allow_empty: false })?;
        let index = u64::try_from(i).map_err(|_| err("counter_overflow"))?;
        result.push((
            path,
            start
                .checked_add(index)
                .ok_or_else(|| err("counter_overflow"))?,
        ));
    }
    Ok(result)
}
fn replacement_parts(text: &str, regex: &Regex) -> Result<Vec<Replacement>> {
    if text.len() > MAX_OUTPUT_BYTES {
        return Err(err("template_too_long"));
    }
    let mut rest = text;
    let mut parts = Vec::new();
    while !rest.is_empty() {
        let i = rest.find('$').unwrap_or(rest.len());
        if i > 0 {
            parts.push(Replacement::Literal(rest.as_bytes()[..i].to_vec()));
            rest = &rest[i..];
        }
        if rest.is_empty() {
            break;
        }
        if rest.starts_with("$$") {
            parts.push(Replacement::Literal(vec![b'$']));
            rest = &rest[2..];
            continue;
        }
        let tail = &rest[1..];
        let reference = if let Some(braced) = tail.strip_prefix('{') {
            braced.find('}').map(|end| (&braced[..end], end + 3))
        } else {
            let end = tail
                .bytes()
                .take_while(|b| b.is_ascii_alphanumeric() || *b == b'_')
                .count();
            (end > 0).then(|| (&tail[..end], end + 1))
        };
        if let Some((name, length)) = reference {
            let group = if name.bytes().all(|b| b.is_ascii_digit()) && !name.is_empty() {
                name.parse::<usize>()
                    .ok()
                    .filter(|i| *i < regex.captures_len())
            } else {
                regex.capture_names().position(|n| n == Some(name))
            };
            parts.push(Replacement::Group(
                group.ok_or_else(|| err("unknown_replacement_capture"))?,
            ));
            rest = &rest[length..];
        } else {
            parts.push(Replacement::Literal(vec![b'$']));
            rest = tail;
        }
    }
    Ok(parts)
}
