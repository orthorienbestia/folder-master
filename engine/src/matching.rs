//! Pure evaluation of supplied metadata; this module never reads files.
use crate::rules::{
    DateSource, EqualityOperator, ExtensionTest, FinderLabel, KindValue, NameOperator, NameScope,
    Predicate, SetOperator, SizeTest, TagTest,
};
use regex::{Regex, RegexBuilder, RegexSet, RegexSetBuilder};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::os::unix::ffi::OsStrExt;
use unicode_normalization::UnicodeNormalization;

mod glob;
pub mod time;
pub mod tree;
pub const MAX_PATTERN_BYTES: usize = 16_384;
const COMPILED_REGEX_BYTES: usize = 1_048_576;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Metadata<T> {
    Known(T),
    Unavailable(MetadataIssue),
}
impl<T> Default for Metadata<T> {
    fn default() -> Self {
        Self::Unavailable(MetadataIssue::Missing)
    }
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum MetadataIssue {
    Missing,
    PermissionDenied,
    ReadFailed,
}
#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum KindCategory {
    Document,
    Image,
    Pdf,
    Audio,
    Video,
    Archive,
}
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct KindFacts {
    pub identifier: String,
    pub categories: BTreeSet<KindCategory>,
    pub custom_conformance: BTreeMap<String, Option<bool>>,
}
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct MetadataSnapshot {
    pub filename: Metadata<Vec<u8>>,
    pub size: Metadata<u64>,
    pub kind: Metadata<KindFacts>,
    pub dates: DateFacts,
    pub tags: Metadata<Vec<String>>,
    pub label: Metadata<crate::rules::FinderLabel>,
}
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct DateFacts {
    pub created: Metadata<i64>,
    pub modified: Metadata<i64>,
    pub last_opened: Metadata<i64>,
    pub added_to_folder: Metadata<i64>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Truth {
    True,
    False,
    Unknown,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Basis {
    Filename,
    Stem,
    FinalExtension,
    PlatformType,
    ByteSize,
    Date(crate::rules::DateSource),
    FinderTags,
    FinderLabel,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnknownReason {
    Metadata(MetadataIssue),
    InvalidFilename,
    NonUtf8,
    UnresolvedType,
    MissingEvaluationContext,
    CalendarUnavailable,
    InvalidCalendarContext,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Evaluation {
    pub truth: Truth,
    pub basis: Basis,
    pub reason: Option<UnknownReason>,
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CompileError {
    pub code: &'static str,
}
#[derive(Debug)]
pub struct CompiledMetadataPredicate(Compiled);
#[derive(Debug)]
enum Compiled {
    Name {
        scope: NameScope,
        regex: Regex,
        negative: bool,
    },
    Extension {
        regex: Option<Regex>,
        negative: bool,
    },
    Kind {
        target: KindValue,
        negative: bool,
    },
    Size(SizeTest),
    Date {
        source: DateSource,
        predicate: time::CompiledDate,
    },
    Tags {
        mode: TagMode,
        patterns: Option<RegexSet>,
    },
    Label {
        negative: bool,
        labels: Vec<FinderLabel>,
    },
}
#[derive(Debug)]
enum TagMode {
    Any,
    All,
    None,
    Empty,
}
fn error(code: &'static str) -> CompileError {
    CompileError { code }
}
fn bounded_text(value: &str) -> Result<String, CompileError> {
    if value.len() > MAX_PATTERN_BYTES {
        return Err(error("pattern_too_long"));
    }
    let normalized: String = value.nfc().collect();
    if normalized.len() > MAX_PATTERN_BYTES {
        return Err(error("pattern_too_long"));
    }
    Ok(normalized)
}
fn regex(source: &str, sensitive: bool, code: &'static str) -> Result<Regex, CompileError> {
    RegexBuilder::new(source)
        .case_insensitive(!sensitive)
        .unicode(true)
        .size_limit(COMPILED_REGEX_BYTES)
        .dfa_size_limit(COMPILED_REGEX_BYTES)
        .nest_limit(64)
        .build()
        .map_err(|_| error(code))
}
impl CompiledMetadataPredicate {
    pub fn evaluate(&self, snapshot: &MetadataSnapshot) -> Evaluation {
        self.evaluate_with_context(snapshot, None)
    }
    pub fn calendar_date(&self) -> Option<&crate::rules::CalendarDate> {
        match &self.0 {
            Compiled::Date { predicate, .. } => predicate.calendar_date(),
            _ => None,
        }
    }
    pub fn compile(predicate: &Predicate) -> Result<Self, CompileError> {
        if !matches!(
            predicate,
            Predicate::Name { .. }
                | Predicate::Extension { .. }
                | Predicate::Kind { .. }
                | Predicate::Size { .. }
                | Predicate::Date { .. }
                | Predicate::Tags { .. }
                | Predicate::Label { .. }
        ) {
            return Err(error("unsupported_predicate"));
        }
        predicate
            .validate("predicate")
            .map_err(|_| error("invalid_predicate"))?;
        Ok(Self(match predicate {
            Predicate::Name {
                op,
                value,
                scope,
                case_sensitive,
            } => {
                let value = bounded_text(value)?;
                let literal = regex::escape(&value);
                let source = match op {
                    NameOperator::Is | NameOperator::IsNot => format!(r"\A(?:{literal})\z"),
                    NameOperator::Contains | NameOperator::DoesNotContain => literal,
                    NameOperator::BeginsWith => format!(r"\A(?:{literal})"),
                    NameOperator::EndsWith => format!(r"(?:{literal})\z"),
                    NameOperator::Regex => value,
                    NameOperator::Glob => glob::regex_source(&value)?,
                };
                let code = if *op == NameOperator::Glob {
                    "invalid_glob"
                } else {
                    "invalid_regex"
                };
                Compiled::Name {
                    scope: scope.clone(),
                    regex: regex(&source, *case_sensitive, code)?,
                    negative: matches!(op, NameOperator::IsNot | NameOperator::DoesNotContain),
                }
            }
            Predicate::Extension { test } => match test {
                ExtensionTest::IsEmpty {} => Compiled::Extension {
                    regex: None,
                    negative: false,
                },
                ExtensionTest::OneOf { values } | ExtensionTest::NotOneOf { values } => {
                    let mut total = 0usize;
                    let mut alternatives = Vec::new();
                    for value in values {
                        total = total.saturating_add(value.len());
                        if total > MAX_PATTERN_BYTES {
                            return Err(error("pattern_too_long"));
                        };
                        alternatives.push(regex::escape(&bounded_text(value)?));
                    }
                    let source = format!(r"\A(?:{})\z", alternatives.join("|"));
                    Compiled::Extension {
                        regex: Some(regex(&source, false, "invalid_extension")?),
                        negative: matches!(test, ExtensionTest::NotOneOf { .. }),
                    }
                }
            },
            Predicate::Kind { op, kind } => Compiled::Kind {
                target: kind.clone(),
                negative: *op == EqualityOperator::IsNot,
            },
            Predicate::Size { test, .. } => Compiled::Size(test.clone()),
            Predicate::Date { source, test } => Compiled::Date {
                source: source.clone(),
                predicate: time::CompiledDate::new(test),
            },
            Predicate::Label { op, labels } => Compiled::Label {
                negative: *op == SetOperator::NotOneOf,
                labels: labels.clone(),
            },
            Predicate::Tags {
                case_sensitive,
                test,
            } => {
                let (mode, names) = match test {
                    TagTest::ContainsAny { names } => (TagMode::Any, Some(names)),
                    TagTest::ContainsAll { names } => (TagMode::All, Some(names)),
                    TagTest::ContainsNone { names } => (TagMode::None, Some(names)),
                    TagTest::IsEmpty {} => (TagMode::Empty, None),
                };
                let patterns = if let Some(names) = names {
                    let mut total = 0usize;
                    let mut patterns = Vec::new();
                    for name in names {
                        total = total.saturating_add(name.len());
                        if total > MAX_PATTERN_BYTES {
                            return Err(error("pattern_too_long"));
                        };
                        patterns.push(format!(r"\A(?:{})\z", regex::escape(&bounded_text(name)?)));
                    }
                    Some(
                        RegexSetBuilder::new(patterns)
                            .case_insensitive(!case_sensitive)
                            .unicode(true)
                            .size_limit(COMPILED_REGEX_BYTES)
                            .dfa_size_limit(COMPILED_REGEX_BYTES)
                            .nest_limit(64)
                            .build()
                            .map_err(|_| error("invalid_tag_set"))?,
                    )
                } else {
                    None
                };
                Compiled::Tags { mode, patterns }
            }
            _ => unreachable!("supported family checked before validation"),
        }))
    }
    pub fn evaluate_with_context(
        &self,
        snapshot: &MetadataSnapshot,
        context: Option<&time::EvaluationContext>,
    ) -> Evaluation {
        match &self.0 {
            Compiled::Name {
                scope,
                regex,
                negative,
            } => {
                let basis = if *scope == NameScope::Stem {
                    Basis::Stem
                } else {
                    Basis::Filename
                };
                let result = (|| {
                    let path = filename(&snapshot.filename)?;
                    let value = if *scope == NameScope::Stem {
                        path.file_stem().ok_or(UnknownReason::InvalidFilename)?
                    } else {
                        path.as_os_str()
                    };
                    let text = std::str::from_utf8(value.as_bytes())
                        .map_err(|_| UnknownReason::NonUtf8)?;
                    let text: String = text.nfc().collect();
                    Ok(regex.is_match(&text) ^ negative)
                })();
                Evaluation::from_result(basis, result)
            }
            Compiled::Extension { regex, negative } => {
                let result = (|| {
                    let path = filename(&snapshot.filename)?;
                    let bytes = path.extension().map(|s| s.as_bytes()).unwrap_or(b"");
                    let text = std::str::from_utf8(bytes).map_err(|_| UnknownReason::NonUtf8)?;
                    // The schema/UI lowercase extension values before saving;
                    // apply the same expansion before Unicode simple folding.
                    let text: String = text.to_lowercase().nfc().collect();
                    Ok(regex
                        .as_ref()
                        .map_or(text.is_empty(), |re| re.is_match(&text))
                        ^ negative)
                })();
                Evaluation::from_result(Basis::FinalExtension, result)
            }
            Compiled::Size(test) => Evaluation::from_result(
                Basis::ByteSize,
                known(&snapshot.size).map(|bytes| match test {
                    SizeTest::Equals { bytes: expected } => bytes == expected,
                    SizeTest::LessThan { bytes: expected } => bytes < expected,
                    SizeTest::GreaterThan { bytes: expected } => bytes > expected,
                    SizeTest::Between { minimum, maximum } => bytes >= minimum && bytes <= maximum,
                }),
            ),
            Compiled::Kind { target, negative } => Evaluation::from_result(
                Basis::PlatformType,
                known(&snapshot.kind).and_then(|facts| {
                    if facts.identifier.is_empty() || facts.identifier.contains('\0') {
                        return Err(UnknownReason::UnresolvedType);
                    }
                    let category = match target {
                        KindValue::Document {} => Some(KindCategory::Document),
                        KindValue::Image {} => Some(KindCategory::Image),
                        KindValue::Pdf {} => Some(KindCategory::Pdf),
                        KindValue::Audio {} => Some(KindCategory::Audio),
                        KindValue::Video {} => Some(KindCategory::Video),
                        KindValue::Archive {} => Some(KindCategory::Archive),
                        KindValue::Other {} => None,
                        KindValue::UtType { identifier } => {
                            return facts
                                .custom_conformance
                                .get(identifier)
                                .copied()
                                .flatten()
                                .map(|v| v ^ negative)
                                .ok_or(UnknownReason::UnresolvedType)
                        }
                    };
                    Ok(category.map_or(facts.categories.is_empty(), |c| {
                        facts.categories.contains(&c)
                    }) ^ negative)
                }),
            ),
            Compiled::Date { source, predicate } => Evaluation::from_result(
                Basis::Date(source.clone()),
                known(snapshot.dates.source(source))
                    .and_then(|timestamp| predicate.evaluate(*timestamp, context)),
            ),
            Compiled::Label { negative, labels } => Evaluation::from_result(
                Basis::FinderLabel,
                known(&snapshot.label).map(|label| labels.contains(label) ^ negative),
            ),
            Compiled::Tags { mode, patterns } => Evaluation::from_result(
                Basis::FinderTags,
                known(&snapshot.tags).map(|names| {
                    let Some(patterns) = patterns else {
                        return names.is_empty();
                    };
                    let names: Vec<String> =
                        names.iter().map(|name| name.nfc().collect()).collect();
                    match mode {
                        TagMode::Any => names.iter().any(|name| patterns.is_match(name)),
                        TagMode::None => !names.iter().any(|name| patterns.is_match(name)),
                        TagMode::All => {
                            let mut matched = BTreeSet::new();
                            for name in names {
                                matched.extend(patterns.matches(&name).into_iter());
                                if matched.len() == patterns.len() {
                                    return true;
                                }
                            }
                            false
                        }
                        TagMode::Empty => unreachable!("empty tag predicate has no matcher"),
                    }
                }),
            ),
        }
    }
}
impl DateFacts {
    fn source(&self, source: &DateSource) -> &Metadata<i64> {
        match source {
            DateSource::Created => &self.created,
            DateSource::Modified => &self.modified,
            DateSource::LastOpened => &self.last_opened,
            DateSource::AddedToFolder => &self.added_to_folder,
        }
    }
}
fn known<T>(field: &Metadata<T>) -> Result<&T, UnknownReason> {
    match field {
        Metadata::Known(value) => Ok(value),
        Metadata::Unavailable(reason) => Err(UnknownReason::Metadata(reason.clone())),
    }
}
fn filename(field: &Metadata<Vec<u8>>) -> Result<&std::path::Path, UnknownReason> {
    let bytes = known(field)?;
    if bytes.is_empty()
        || bytes == b"."
        || bytes == b".."
        || bytes.contains(&b'/')
        || bytes.contains(&0)
    {
        return Err(UnknownReason::InvalidFilename);
    }
    Ok(std::path::Path::new(std::ffi::OsStr::from_bytes(bytes)))
}
impl Evaluation {
    fn from_result(basis: Basis, result: Result<bool, UnknownReason>) -> Self {
        match result {
            Ok(value) => Self {
                truth: if value { Truth::True } else { Truth::False },
                basis,
                reason: None,
            },
            Err(reason) => Self {
                truth: Truth::Unknown,
                basis,
                reason: Some(reason),
            },
        }
    }
}
