//! Pure evaluation of supplied metadata; this module never reads files.
use crate::rules::{
    EqualityOperator, ExtensionTest, KindValue, NameOperator, NameScope, Predicate, SizeTest,
};
use regex::{Regex, RegexBuilder};
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, BTreeSet};
use std::os::unix::ffi::OsStrExt;
use unicode_normalization::UnicodeNormalization;

mod glob;
pub const MAX_PATTERN_BYTES: usize = 16_384;
const COMPILED_REGEX_BYTES: usize = 1_048_576;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Metadata<T> {
    Known(T),
    Unavailable(MetadataIssue),
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
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MetadataSnapshot {
    pub filename: Metadata<Vec<u8>>,
    pub size: Metadata<u64>,
    pub kind: Metadata<KindFacts>,
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
}
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UnknownReason {
    Metadata(MetadataIssue),
    InvalidFilename,
    NonUtf8,
    UnresolvedType,
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
    pub fn compile(predicate: &Predicate) -> Result<Self, CompileError> {
        if !matches!(
            predicate,
            Predicate::Name { .. }
                | Predicate::Extension { .. }
                | Predicate::Kind { .. }
                | Predicate::Size { .. }
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
            _ => unreachable!("supported family checked before validation"),
        }))
    }
    pub fn evaluate(&self, snapshot: &MetadataSnapshot) -> Evaluation {
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
