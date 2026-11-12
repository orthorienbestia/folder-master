use folder_master_engine::{matching::*, rules::*};
use std::collections::{BTreeMap, BTreeSet};
fn snapshot(name: &[u8]) -> MetadataSnapshot {
    MetadataSnapshot {
        filename: Metadata::Known(name.to_vec()),
        size: Metadata::Known(1024),
        kind: Metadata::Unavailable(MetadataIssue::Missing),
    }
}
fn name(op: NameOperator, value: &str, case_sensitive: bool) -> Predicate {
    Predicate::Name {
        op,
        value: value.into(),
        scope: NameScope::Filename,
        case_sensitive,
    }
}
fn evaluate(p: Predicate, s: &MetadataSnapshot) -> Evaluation {
    CompiledMetadataPredicate::compile(&p).unwrap().evaluate(s)
}
#[test]
fn every_name_operator_obeys_literal_search_and_anchor_semantics() {
    let s = snapshot(b"Invoice[1].PDF");
    for (op, value, truth) in [
        (NameOperator::Is, "invoice[1].pdf", Truth::True),
        (NameOperator::IsNot, "invoice[1].pdf", Truth::False),
        (NameOperator::Contains, "[1]", Truth::True),
        (NameOperator::DoesNotContain, "[1]", Truth::False),
        (NameOperator::BeginsWith, "invoice", Truth::True),
        (NameOperator::EndsWith, "pdf", Truth::True),
        (NameOperator::Regex, r"\[[0-9]+\]", Truth::True),
        (NameOperator::Regex, "^pdf$", Truth::False),
        (NameOperator::Glob, "invoice*.pdf", Truth::True),
        (NameOperator::Glob, "voice*", Truth::False),
    ] {
        assert_eq!(evaluate(name(op, value, false), &s).truth, truth);
    }
    assert_eq!(
        evaluate(name(NameOperator::Contains, "invoice", true), &s).truth,
        Truth::False
    );
    assert_eq!(
        evaluate(name(NameOperator::Contains, ".*", false), &s).truth,
        Truth::False
    );
}
#[test]
fn unicode_case_and_canonical_forms_are_consistent_across_name_modes() {
    let s = snapshot("Cafe\u{301}-Σ-🙂.PDF".as_bytes());
    for op in [
        NameOperator::Contains,
        NameOperator::Regex,
        NameOperator::Glob,
    ] {
        let value = if op == NameOperator::Glob {
            "*CAFÉ-ς-?.pdf"
        } else {
            "CAFÉ-ς-🙂"
        };
        assert_eq!(evaluate(name(op, value, false), &s).truth, Truth::True);
    }
    assert_eq!(
        evaluate(
            name(NameOperator::Is, "STRASSE", false),
            &snapshot("Straße".as_bytes())
        )
        .truth,
        Truth::False
    );
    assert_eq!(
        evaluate(
            name(NameOperator::Is, "ß", false),
            &snapshot("ẞ".as_bytes())
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            name(NameOperator::Is, "i", false),
            &snapshot("İ".as_bytes())
        )
        .truth,
        Truth::False
    );
}
#[test]
fn glob_classes_alternation_escapes_and_single_unicode_scalar_work() {
    for (pattern, filename, matched) in [
        ("[Σ]?-{a,b}.pdf", "ς🙂-b.PDF", true),
        ("[!a-c]*", "Zebra", true),
        ("[!a-c]*", "Banana", false),
        (r"literal\[x\]\?.txt", "literal[x]?.txt", true),
        ("{report,{invoice,receipt}}-?.pdf", "receipt-é.pdf", true),
        ("?.txt", "é.txt", true),
        ("?.txt", "🙂.txt", true),
        ("?.txt", "ab.txt", false),
        ("*.txt", "line\nbreak.txt", true),
        ("[a-z].txt", "K.txt", true),
        ("*.{pdf,txt}", "hello.pdf.bak", false),
    ] {
        assert_eq!(
            evaluate(
                name(NameOperator::Glob, pattern, false),
                &snapshot(filename.as_bytes())
            )
            .truth
                == Truth::True,
            matched,
            "{pattern} / {filename}"
        );
    }
}
#[test]
fn invalid_patterns_and_unsupported_fields_cannot_be_compiled() {
    for pattern in ["[abc", "{a,b", r"dangling\", "a}", "[z-a]", "[]"] {
        assert!(
            CompiledMetadataPredicate::compile(&name(NameOperator::Glob, pattern, false)).is_err(),
            "{pattern}"
        );
    }
    for pattern in ["(", "(?=x)", r"(a)\1", &"a".repeat(20_000)] {
        assert!(
            CompiledMetadataPredicate::compile(&name(NameOperator::Regex, pattern, false)).is_err(),
            "invalid/overlong regex accepted"
        );
    }
    let p = Predicate::Date {
        source: DateSource::Modified,
        test: DateTest::Today {},
    };
    assert_eq!(
        CompiledMetadataPredicate::compile(&p).err().unwrap().code,
        "unsupported_predicate"
    );
    assert!(CompiledMetadataPredicate::compile(&name(NameOperator::Is, "", false)).is_err());
}
#[test]
fn extension_and_stem_use_only_the_final_suffix_with_dotfile_rules() {
    for (filename, extension, stem) in [
        ("archive.tar.GZ", "gz", "archive.tar"),
        (".gitignore", "", ".gitignore"),
        ("report.", "", "report"),
        (".config.JSON", "json", ".config"),
        ("README", "", "README"),
    ] {
        let p = if extension.is_empty() {
            Predicate::Extension {
                test: ExtensionTest::IsEmpty {},
            }
        } else {
            Predicate::Extension {
                test: ExtensionTest::OneOf {
                    values: vec![extension.into()],
                },
            }
        };
        assert_eq!(
            evaluate(p, &snapshot(filename.as_bytes())).truth,
            Truth::True
        );
        assert_eq!(
            evaluate(
                Predicate::Name {
                    op: NameOperator::Is,
                    value: stem.into(),
                    scope: NameScope::Stem,
                    case_sensitive: true
                },
                &snapshot(filename.as_bytes())
            )
            .truth,
            Truth::True
        );
    }
    assert_eq!(
        evaluate(
            Predicate::Extension {
                test: ExtensionTest::NotOneOf {
                    values: vec!["pdf".into()]
                }
            },
            &snapshot(b"README")
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            Predicate::Extension {
                test: ExtensionTest::OneOf {
                    values: vec!["é".into()]
                }
            },
            &snapshot("file.E\u{301}".as_bytes())
        )
        .truth,
        Truth::True
    );
}
#[test]
fn unavailable_and_non_utf8_values_never_turn_into_negative_matches() {
    for filename in [
        Metadata::Unavailable(MetadataIssue::PermissionDenied),
        Metadata::Known(b"invalid\xff.pdf".to_vec()),
    ] {
        let mut s = snapshot(b"ok");
        s.filename = filename;
        assert_eq!(
            evaluate(name(NameOperator::IsNot, "other", false), &s).truth,
            Truth::Unknown
        );
    }
    assert_eq!(
        evaluate(
            Predicate::Extension {
                test: ExtensionTest::OneOf {
                    values: vec!["pdf".into()]
                }
            },
            &snapshot(b"invalid\xff.PDF")
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            Predicate::Extension {
                test: ExtensionTest::NotOneOf {
                    values: vec!["pdf".into()]
                }
            },
            &snapshot(b"file.\xff")
        )
        .truth,
        Truth::Unknown
    );
    assert_eq!(
        evaluate(
            Predicate::Name {
                op: NameOperator::Is,
                value: "valid".into(),
                scope: NameScope::Stem,
                case_sensitive: true
            },
            &snapshot(b"valid.\xff")
        )
        .truth,
        Truth::True
    );
    for filename in [b"".as_slice(), b".", b"..", b"folder/file", b"a\0b"] {
        assert_eq!(
            evaluate(
                name(NameOperator::IsNot, "other", false),
                &snapshot(filename)
            )
            .truth,
            Truth::Unknown
        );
    }
}
#[test]
fn size_uses_exact_integer_bytes_and_inclusive_ranges() {
    for (size, test, truth) in [
        (1024, SizeTest::Equals { bytes: 1024 }, Truth::True),
        (1024, SizeTest::LessThan { bytes: 1024 }, Truth::False),
        (1024, SizeTest::GreaterThan { bytes: 1024 }, Truth::False),
        (
            1024,
            SizeTest::Between {
                minimum: 1024,
                maximum: 2048,
            },
            Truth::True,
        ),
        (u64::MAX, SizeTest::Equals { bytes: u64::MAX }, Truth::True),
        (
            0,
            SizeTest::Between {
                minimum: 0,
                maximum: 0,
            },
            Truth::True,
        ),
    ] {
        let mut s = snapshot(b"file");
        s.size = Metadata::Known(size);
        assert_eq!(
            evaluate(
                Predicate::Size {
                    unit: SizeUnit::Gib,
                    test
                },
                &s
            )
            .truth,
            truth
        );
    }
    let mut s = snapshot(b"file");
    s.size = Metadata::Unavailable(MetadataIssue::ReadFailed);
    let result = evaluate(
        Predicate::Size {
            unit: SizeUnit::Bytes,
            test: SizeTest::LessThan { bytes: 1 },
        },
        &s,
    );
    assert_eq!(result.truth, Truth::Unknown);
    assert_eq!(result.basis, Basis::ByteSize);
    assert!(CompiledMetadataPredicate::compile(&Predicate::Size {
        unit: SizeUnit::Bytes,
        test: SizeTest::Between {
            minimum: 2,
            maximum: 1
        }
    })
    .is_err());
}
#[test]
fn kind_uses_native_categories_and_explicit_conformance_never_extensions() {
    for (category, target) in [
        (KindCategory::Document, KindValue::Document {}),
        (KindCategory::Image, KindValue::Image {}),
        (KindCategory::Pdf, KindValue::Pdf {}),
        (KindCategory::Audio, KindValue::Audio {}),
        (KindCategory::Video, KindValue::Video {}),
        (KindCategory::Archive, KindValue::Archive {}),
    ] {
        let mut s = snapshot(b"irrelevant.extension");
        s.kind = Metadata::Known(KindFacts {
            identifier: "fixture.native-type".into(),
            categories: BTreeSet::from([category]),
            custom_conformance: BTreeMap::new(),
        });
        assert_eq!(
            evaluate(
                Predicate::Kind {
                    op: EqualityOperator::Is,
                    kind: target.clone()
                },
                &s
            )
            .truth,
            Truth::True
        );
        assert_eq!(
            evaluate(
                Predicate::Kind {
                    op: EqualityOperator::IsNot,
                    kind: target
                },
                &s
            )
            .truth,
            Truth::False
        );
    }
    let mut s = snapshot(b"misleading.pdf");
    s.kind = Metadata::Known(KindFacts {
        identifier: "public.jpeg".into(),
        categories: BTreeSet::from([KindCategory::Image]),
        custom_conformance: BTreeMap::from([
            ("public.image".into(), Some(true)),
            ("public.pdf".into(), Some(false)),
            ("unregistered.target".into(), None),
        ]),
    });
    for (kind, truth) in [
        (KindValue::Image {}, Truth::True),
        (KindValue::Pdf {}, Truth::False),
        (KindValue::Document {}, Truth::False),
        (KindValue::Other {}, Truth::False),
        (
            KindValue::UtType {
                identifier: "public.image".into(),
            },
            Truth::True,
        ),
    ] {
        assert_eq!(
            evaluate(
                Predicate::Kind {
                    op: EqualityOperator::Is,
                    kind
                },
                &s
            )
            .truth,
            truth
        );
    }
    assert_eq!(
        evaluate(
            Predicate::Kind {
                op: EqualityOperator::IsNot,
                kind: KindValue::UtType {
                    identifier: "unregistered.target".into()
                }
            },
            &s
        )
        .truth,
        Truth::Unknown
    );
    assert_eq!(
        evaluate(
            Predicate::Kind {
                op: EqualityOperator::IsNot,
                kind: KindValue::UtType {
                    identifier: "not.requested".into()
                }
            },
            &s
        )
        .truth,
        Truth::Unknown
    );
    s.kind = Metadata::Known(KindFacts {
        identifier: "public.data".into(),
        categories: BTreeSet::new(),
        custom_conformance: BTreeMap::new(),
    });
    assert_eq!(
        evaluate(
            Predicate::Kind {
                op: EqualityOperator::Is,
                kind: KindValue::Other {}
            },
            &s
        )
        .truth,
        Truth::True
    );
    s.kind = Metadata::Unavailable(MetadataIssue::Missing);
    assert_eq!(
        evaluate(
            Predicate::Kind {
                op: EqualityOperator::IsNot,
                kind: KindValue::Image {}
            },
            &s
        )
        .truth,
        Truth::Unknown
    );
}

#[test]
fn compiler_budgets_fail_closed_without_compatibility_normalization() {
    let nested = format!("{}a{}", "{".repeat(17), "}".repeat(17));
    assert_eq!(
        CompiledMetadataPredicate::compile(&name(NameOperator::Glob, &nested, false))
            .unwrap_err()
            .code,
        "glob_too_deep"
    );
    assert_eq!(
        CompiledMetadataPredicate::compile(&name(
            NameOperator::Contains,
            &"a".repeat(MAX_PATTERN_BYTES + 1),
            false
        ))
        .unwrap_err()
        .code,
        "pattern_too_long"
    );
    assert!(
        CompiledMetadataPredicate::compile(&name(NameOperator::Regex, r"\w{100000}", false))
            .is_err()
    );
    for (value, filename) in [("1", "①"), ("ff", "ﬀ")] {
        assert_eq!(
            evaluate(
                name(NameOperator::Is, value, false),
                &snapshot(filename.as_bytes())
            )
            .truth,
            Truth::False
        );
    }
    assert_eq!(
        evaluate(
            name(NameOperator::Is, "CAFÉ", true),
            &snapshot("CAFE\u{301}".as_bytes())
        )
        .truth,
        Truth::True
    );
}

#[test]
fn explanations_preserve_requested_basis_and_missing_field_reason() {
    let mut s = snapshot(b"file.PDF");
    s.filename = Metadata::Unavailable(MetadataIssue::ReadFailed);
    let extension = evaluate(
        Predicate::Extension {
            test: ExtensionTest::NotOneOf {
                values: vec!["txt".into()],
            },
        },
        &s,
    );
    assert_eq!(
        extension,
        Evaluation {
            truth: Truth::Unknown,
            basis: Basis::FinalExtension,
            reason: Some(UnknownReason::Metadata(MetadataIssue::ReadFailed))
        }
    );
    // An independent known field remains usable when a different field fails.
    let size = evaluate(
        Predicate::Size {
            unit: SizeUnit::Kib,
            test: SizeTest::Equals { bytes: 1024 },
        },
        &s,
    );
    assert_eq!(
        size,
        Evaluation {
            truth: Truth::True,
            basis: Basis::ByteSize,
            reason: None
        }
    );
    for (pattern, filename) in [
        ("[]a]", "]"),
        ("[-a]", "-"),
        ("[a&&b]", "&"),
        ("a{,b}", "a"),
        (r"[\-]", "-"),
    ] {
        assert_eq!(
            evaluate(
                name(NameOperator::Glob, pattern, false),
                &snapshot(filename.as_bytes())
            )
            .truth,
            Truth::True,
            "{pattern} / {filename}"
        );
    }
}

#[test]
fn observed_extensions_follow_the_same_lowercasing_as_saved_values() {
    // Both native UI and rule schema normalize the user's .İ to i + dot.
    let values = vec!["i\u{307}".into()];
    let positive = Predicate::Extension {
        test: ExtensionTest::OneOf {
            values: values.clone(),
        },
    };
    let negative = Predicate::Extension {
        test: ExtensionTest::NotOneOf { values },
    };
    assert_eq!(
        evaluate(positive.clone(), &snapshot("file.İ".as_bytes())).truth,
        Truth::True
    );
    assert_eq!(
        evaluate(negative, &snapshot("file.İ".as_bytes())).truth,
        Truth::False
    );
    assert_eq!(evaluate(positive, &snapshot(b"file.i")).truth, Truth::False);
}
