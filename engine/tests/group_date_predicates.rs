use folder_master_engine::{
    matching::{time::*, tree::*, *},
    rules::*,
};
fn id(n: usize) -> RuleId {
    format!("00000000-0000-4000-8000-{n:012x}")
        .try_into()
        .unwrap()
}
fn predicate(p: Predicate, n: usize) -> ConditionNode {
    ConditionNode {
        id: id(n),
        expression: ConditionExpression::Predicate { predicate: p },
    }
}
fn group(mode: GroupMode, children: Vec<ConditionNode>) -> ConditionNode {
    ConditionNode {
        id: id(999),
        expression: match mode {
            GroupMode::All => ConditionExpression::All { children },
            GroupMode::Any => ConditionExpression::Any { children },
            GroupMode::None => ConditionExpression::None { children },
        },
    }
}
fn context() -> EvaluationContext {
    EvaluationContext {
        now_ms: 100_000,
        timezone_identifier: "UTC".into(),
        today: Some(DayWindow {
            start_ms: 0,
            end_ms: 86_400_000,
        }),
        yesterday: Some(DayWindow {
            start_ms: -86_400_000,
            end_ms: 0,
        }),
        dates: vec![],
    }
}
fn evaluate(p: Predicate, s: &MetadataSnapshot, c: Option<&EvaluationContext>) -> Evaluation {
    CompiledMetadataPredicate::compile(&p)
        .unwrap()
        .evaluate_with_context(s, c)
}
fn date(test: DateTest) -> Predicate {
    Predicate::Date {
        source: DateSource::Modified,
        test,
    }
}
#[test]
fn all_tag_operators_are_exact_unicode_names_and_known_empty_is_distinct() {
    let mut s = MetadataSnapshot {
        tags: Metadata::Known(vec![
            "Annual, reports".into(),
            "Cafe\u{301}".into(),
            "WORK".into(),
        ]),
        ..Default::default()
    };
    for (test, truth) in [
        (
            TagTest::ContainsAny {
                names: vec!["work".into()],
            },
            Truth::True,
        ),
        (
            TagTest::ContainsAll {
                names: vec!["café".into(), "Annual, reports".into()],
            },
            Truth::True,
        ),
        (
            TagTest::ContainsNone {
                names: vec!["reports".into()],
            },
            Truth::True,
        ),
        (
            TagTest::ContainsNone {
                names: vec!["work".into()],
            },
            Truth::False,
        ),
        (TagTest::IsEmpty {}, Truth::False),
    ] {
        assert_eq!(
            evaluate(
                Predicate::Tags {
                    case_sensitive: false,
                    test
                },
                &s,
                None
            )
            .truth,
            truth
        );
    }
    assert_eq!(
        evaluate(
            Predicate::Tags {
                case_sensitive: true,
                test: TagTest::ContainsAny {
                    names: vec!["work".into()]
                }
            },
            &s,
            None
        )
        .truth,
        Truth::False
    );
    s.tags = Metadata::Known(vec![]);
    assert_eq!(
        evaluate(
            Predicate::Tags {
                case_sensitive: false,
                test: TagTest::IsEmpty {}
            },
            &s,
            None
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            Predicate::Tags {
                case_sensitive: false,
                test: TagTest::ContainsNone {
                    names: vec!["work".into()]
                }
            },
            &s,
            None
        )
        .truth,
        Truth::True
    );
    s.tags = Metadata::Unavailable(MetadataIssue::PermissionDenied);
    assert_eq!(
        evaluate(
            Predicate::Tags {
                case_sensitive: false,
                test: TagTest::ContainsNone {
                    names: vec!["work".into()]
                }
            },
            &s,
            None
        )
        .truth,
        Truth::Unknown
    );
}
#[test]
fn finder_none_is_known_and_named_tags_never_supply_color_labels() {
    let mut s = MetadataSnapshot {
        tags: Metadata::Known(vec!["Red".into()]),
        label: Metadata::Known(FinderLabel::None),
        ..Default::default()
    };
    for color in [
        FinderLabel::None,
        FinderLabel::Gray,
        FinderLabel::Green,
        FinderLabel::Purple,
        FinderLabel::Blue,
        FinderLabel::Yellow,
        FinderLabel::Red,
        FinderLabel::Orange,
    ] {
        s.label = Metadata::Known(color.clone());
        assert_eq!(
            evaluate(
                Predicate::Label {
                    op: SetOperator::OneOf,
                    labels: vec![color.clone()]
                },
                &s,
                None
            )
            .truth,
            Truth::True
        );
        assert_eq!(
            evaluate(
                Predicate::Label {
                    op: SetOperator::NotOneOf,
                    labels: vec![color]
                },
                &s,
                None
            )
            .truth,
            Truth::False
        );
    }
    s.label = Metadata::Known(FinderLabel::None);
    assert_eq!(
        evaluate(
            Predicate::Label {
                op: SetOperator::OneOf,
                labels: vec![FinderLabel::Red]
            },
            &s,
            None
        )
        .truth,
        Truth::False
    );
    s.label = Metadata::Unavailable(MetadataIssue::ReadFailed);
    assert_eq!(
        evaluate(
            Predicate::Label {
                op: SetOperator::NotOneOf,
                labels: vec![FinderLabel::Red]
            },
            &s,
            None
        )
        .truth,
        Truth::Unknown
    );
}
#[test]
fn dates_use_selected_source_and_exact_strict_or_inclusive_boundaries() {
    let mut s = MetadataSnapshot::default();
    s.dates.modified = Metadata::Known(1000);
    s.dates.created = Metadata::Known(500);
    for (test, truth) in [
        (DateTest::Before { timestamp_ms: 1000 }, Truth::False),
        (DateTest::After { timestamp_ms: 1000 }, Truth::False),
        (DateTest::Before { timestamp_ms: 1001 }, Truth::True),
        (DateTest::After { timestamp_ms: 999 }, Truth::True),
        (
            DateTest::DateRange {
                start_ms: 1000,
                end_ms: 1000,
            },
            Truth::True,
        ),
    ] {
        assert_eq!(evaluate(date(test), &s, None).truth, truth);
    }
    for source in [DateSource::LastOpened, DateSource::AddedToFolder] {
        assert_eq!(
            evaluate(
                Predicate::Date {
                    source,
                    test: DateTest::Before {
                        timestamp_ms: 10_000
                    }
                },
                &s,
                None
            )
            .truth,
            Truth::Unknown
        );
    }
    s.dates.last_opened = Metadata::Known(200);
    s.dates.added_to_folder = Metadata::Known(300);
    for (source, instant) in [
        (DateSource::Created, 500),
        (DateSource::Modified, 1000),
        (DateSource::LastOpened, 200),
        (DateSource::AddedToFolder, 300),
    ] {
        let result = evaluate(
            Predicate::Date {
                source: source.clone(),
                test: DateTest::DateRange {
                    start_ms: instant,
                    end_ms: instant,
                },
            },
            &s,
            None,
        );
        assert_eq!(result.truth, Truth::True);
        assert_eq!(result.basis, Basis::Date(source));
    }
}
#[test]
fn elapsed_age_uses_captured_clock_and_preserves_milliseconds_at_large_epochs() {
    let mut s = MetadataSnapshot::default();
    let mut c = context();
    c.now_ms = 9_007_199_254_740_993;
    s.dates.modified = Metadata::Known(c.now_ms - 60_000);
    for (test, truth) in [
        (
            DateTest::OlderThan {
                amount: 1.0,
                unit: AgeUnit::Minutes,
            },
            Truth::False,
        ),
        (
            DateTest::NewerThan {
                amount: 1.0,
                unit: AgeUnit::Minutes,
            },
            Truth::False,
        ),
    ] {
        assert_eq!(evaluate(date(test), &s, Some(&c)).truth, truth);
    }
    s.dates.modified = Metadata::Known(c.now_ms - 60_001);
    assert_eq!(
        evaluate(
            date(DateTest::OlderThan {
                amount: 1.0,
                unit: AgeUnit::Minutes
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    s.dates.modified = Metadata::Known(c.now_ms + 1);
    assert_eq!(
        evaluate(
            date(DateTest::NewerThan {
                amount: 0.0,
                unit: AgeUnit::Days
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    s.dates.modified = Metadata::Known(i64::MIN);
    c.now_ms = i64::MAX;
    assert_eq!(
        evaluate(
            date(DateTest::OlderThan {
                amount: 1.0,
                unit: AgeUnit::Weeks
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            date(DateTest::OlderThan {
                amount: 0.5,
                unit: AgeUnit::Hours
            }),
            &s,
            None
        )
        .truth,
        Truth::Unknown
    );
}
#[test]
fn calendar_predicates_use_captured_half_open_windows_and_never_assume_24_hours() {
    let mut c = context();
    c.now_ms = 5000;
    c.today = Some(DayWindow {
        start_ms: 1000,
        end_ms: 82_801_000,
    });
    c.yesterday = Some(DayWindow {
        start_ms: -86_399_000,
        end_ms: 1000,
    });
    let d = CalendarDate {
        year: 2026,
        month: 3,
        day: 8,
    };
    c.dates.push(CalendarDateWindow {
        date: d.clone(),
        window: c.today.clone(),
    });
    let mut s = MetadataSnapshot::default();
    s.dates.modified = Metadata::Known(1000);
    assert_eq!(
        evaluate(date(DateTest::Today {}), &s, Some(&c)).truth,
        Truth::True
    );
    assert_eq!(
        evaluate(date(DateTest::Yesterday {}), &s, Some(&c)).truth,
        Truth::False
    );
    s.dates.modified = Metadata::Known(82_801_000);
    assert_eq!(
        evaluate(date(DateTest::OnDate { date: d.clone() }), &s, Some(&c)).truth,
        Truth::False
    );
    s.dates.modified = Metadata::Known(999);
    assert_eq!(
        evaluate(date(DateTest::Yesterday {}), &s, Some(&c)).truth,
        Truth::True
    );
    c.dates[0].window = None;
    assert_eq!(
        evaluate(date(DateTest::OnDate { date: d.clone() }), &s, Some(&c)).truth,
        Truth::Unknown
    );
    c.dates.push(CalendarDateWindow {
        date: d.clone(),
        window: Some(DayWindow {
            start_ms: 0,
            end_ms: 10,
        }),
    });
    assert_eq!(
        evaluate(date(DateTest::OnDate { date: d }), &s, Some(&c)).reason,
        Some(UnknownReason::InvalidCalendarContext)
    );
}
fn leaf_for(value: &Truth, n: usize) -> ConditionNode {
    match value {
        Truth::True => predicate(
            Predicate::Size {
                unit: SizeUnit::Bytes,
                test: SizeTest::Equals { bytes: 1 },
            },
            n,
        ),
        Truth::False => predicate(
            Predicate::Size {
                unit: SizeUnit::Bytes,
                test: SizeTest::Equals { bytes: 2 },
            },
            n,
        ),
        Truth::Unknown => predicate(
            Predicate::Label {
                op: SetOperator::NotOneOf,
                labels: vec![FinderLabel::Red],
            },
            n,
        ),
    }
}
#[test]
fn complete_ternary_group_truth_tables_preserve_unknown_under_negation() {
    let values = [Truth::True, Truth::False, Truth::Unknown];
    let s = MetadataSnapshot {
        size: Metadata::Known(1),
        ..Default::default()
    };
    for a in &values {
        for b in &values {
            for mode in [GroupMode::All, GroupMode::Any, GroupMode::None] {
                let expected = match mode {
                    GroupMode::All => {
                        if *a == Truth::False || *b == Truth::False {
                            Truth::False
                        } else if *a == Truth::Unknown || *b == Truth::Unknown {
                            Truth::Unknown
                        } else {
                            Truth::True
                        }
                    }
                    _ => {
                        let any = if *a == Truth::True || *b == Truth::True {
                            Truth::True
                        } else if *a == Truth::Unknown || *b == Truth::Unknown {
                            Truth::Unknown
                        } else {
                            Truth::False
                        };
                        if mode == GroupMode::None {
                            match any {
                                Truth::True => Truth::False,
                                Truth::False => Truth::True,
                                Truth::Unknown => Truth::Unknown,
                            }
                        } else {
                            any
                        }
                    }
                };
                let root = group(mode, vec![leaf_for(a, 1), leaf_for(b, 2)]);
                assert_eq!(
                    CompiledConditions::compile(&root)
                        .unwrap()
                        .evaluate(&s, None)
                        .truth,
                    expected
                );
            }
        }
    }
}
#[test]
fn decisive_branches_record_skipped_ids_and_invalid_trees_do_not_compile() {
    let s = MetadataSnapshot {
        size: Metadata::Known(1),
        ..Default::default()
    };
    let root = group(
        GroupMode::Any,
        vec![leaf_for(&Truth::True, 1), leaf_for(&Truth::Unknown, 2)],
    );
    let result = CompiledConditions::compile(&root)
        .unwrap()
        .evaluate(&s, None);
    match result.evidence {
        ConditionEvidence::Group {
            evaluated, skipped, ..
        } => {
            assert_eq!(evaluated.len(), 1);
            assert_eq!(skipped, vec![id(2)]);
        }
        _ => panic!("missing group evidence"),
    }
    assert!(CompiledConditions::compile(&group(GroupMode::All, vec![])).is_err());
    let leaf = leaf_for(&Truth::True, 1);
    assert!(CompiledConditions::compile(&leaf).is_err());
    assert!(CompiledConditions::compile(&group(GroupMode::All, vec![leaf.clone(), leaf])).is_err());
}

#[test]
fn native_calendar_fixture_json_drives_the_same_boundary_results_in_rust() {
    #[derive(serde::Deserialize)]
    struct Fixture {
        cases: Vec<Case>,
    }
    #[derive(serde::Deserialize)]
    struct Case {
        name: String,
        context: EvaluationContext,
    }
    let fixture: Fixture = serde_json::from_str(include_str!(
        "../../native/Tests/Fixtures/calendar-context.json"
    ))
    .unwrap();
    assert_eq!(fixture.cases.len(), 6);
    for case in fixture.cases {
        let c = case.context;
        let mut s = MetadataSnapshot::default();
        let today = c.today.as_ref().unwrap();
        s.dates.modified = Metadata::Known(today.start_ms);
        assert_eq!(
            evaluate(date(DateTest::Today {}), &s, Some(&c)).truth,
            Truth::True,
            "{}",
            case.name
        );
        s.dates.modified = Metadata::Known(today.end_ms);
        assert_eq!(
            evaluate(date(DateTest::Today {}), &s, Some(&c)).truth,
            Truth::False
        );
        s.dates.modified = Metadata::Known(c.yesterday.as_ref().unwrap().end_ms - 1);
        assert_eq!(
            evaluate(date(DateTest::Yesterday {}), &s, Some(&c)).truth,
            Truth::True
        );
        for target in &c.dates {
            s.dates.modified =
                Metadata::Known(target.window.as_ref().map_or(c.now_ms, |w| w.start_ms));
            let expected = if target.window.is_some() {
                Truth::True
            } else {
                Truth::Unknown
            };
            assert_eq!(
                evaluate(
                    date(DateTest::OnDate {
                        date: target.date.clone()
                    }),
                    &s,
                    Some(&c)
                )
                .truth,
                expected
            );
        }
        // A previous calendar date can be less than 24 elapsed hours old.
        s.dates.modified = Metadata::Known(today.start_ms - 1);
        if c.now_ms - today.start_ms < 86_399_999 {
            assert_eq!(
                evaluate(
                    date(DateTest::OlderThan {
                        amount: 1.0,
                        unit: AgeUnit::Days
                    }),
                    &s,
                    Some(&c)
                )
                .truth,
                Truth::False
            );
        }
    }
}

#[test]
fn fractional_elapsed_thresholds_and_invalid_calendar_contexts_fail_precisely() {
    let mut c = context();
    let mut s = MetadataSnapshot::default();
    s.dates.modified = Metadata::Known(c.now_ms);
    let newer = date(DateTest::NewerThan {
        amount: 0.00001,
        unit: AgeUnit::Minutes,
    });
    assert_eq!(evaluate(newer.clone(), &s, Some(&c)).truth, Truth::True);
    s.dates.modified = Metadata::Known(c.now_ms - 1);
    assert_eq!(evaluate(newer, &s, Some(&c)).truth, Truth::False);
    assert_eq!(
        evaluate(
            date(DateTest::OlderThan {
                amount: 0.00001,
                unit: AgeUnit::Minutes
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            date(DateTest::NewerThan {
                amount: 1e300,
                unit: AgeUnit::Weeks
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    c.today = Some(DayWindow {
        start_ms: 200_000,
        end_ms: 300_000,
    });
    assert_eq!(
        evaluate(date(DateTest::Today {}), &s, Some(&c)).reason,
        Some(UnknownReason::InvalidCalendarContext)
    );
    c.today = None;
    assert_eq!(
        evaluate(date(DateTest::Today {}), &s, Some(&c)).reason,
        Some(UnknownReason::CalendarUnavailable)
    );
}

#[test]
fn nested_groups_keep_distinct_evidence_and_collect_unique_calendar_queries() {
    let d = CalendarDate {
        year: 2026,
        month: 3,
        day: 8,
    };
    let child = ConditionNode {
        id: id(500),
        expression: ConditionExpression::None {
            children: vec![leaf_for(&Truth::Unknown, 1)],
        },
    };
    let root = group(GroupMode::All, vec![leaf_for(&Truth::True, 2), child]);
    assert_eq!(
        CompiledConditions::compile(&root)
            .unwrap()
            .evaluate(
                &MetadataSnapshot {
                    size: Metadata::Known(1),
                    ..Default::default()
                },
                None
            )
            .truth,
        Truth::Unknown
    );
    let dates = group(
        GroupMode::Any,
        vec![
            predicate(date(DateTest::OnDate { date: d.clone() }), 3),
            predicate(date(DateTest::OnDate { date: d.clone() }), 4),
        ],
    );
    assert_eq!(
        CompiledConditions::compile(&dates)
            .unwrap()
            .calendar_dates(),
        vec![d]
    );
    let mut deep = leaf_for(&Truth::True, 7);
    for n in 10..14 {
        deep = ConditionNode {
            id: id(n),
            expression: ConditionExpression::All {
                children: vec![deep],
            },
        };
    }
    assert!(CompiledConditions::compile(&deep).is_err());
    let many = group(
        GroupMode::All,
        (0..51).map(|n| leaf_for(&Truth::True, n)).collect(),
    );
    assert!(CompiledConditions::compile(&many).is_err());
}

#[test]
fn canonical_decimal_ages_do_not_shift_strict_millisecond_boundaries() {
    let c = context();
    let mut s = MetadataSnapshot::default();
    for (amount, milliseconds) in [(0.00005, 3), (0.009, 540)] {
        s.dates.modified = Metadata::Known(c.now_ms - milliseconds);
        // 0.009 minutes can round down to 539.9999999999999 ms.
        for test in [
            DateTest::OlderThan {
                amount,
                unit: AgeUnit::Minutes,
            },
            DateTest::NewerThan {
                amount,
                unit: AgeUnit::Minutes,
            },
        ] {
            assert_eq!(evaluate(date(test), &s, Some(&c)).truth, Truth::False);
        }
    }
    s.dates.modified = Metadata::Known(c.now_ms);
    assert_eq!(
        evaluate(
            date(DateTest::NewerThan {
                amount: f64::from_bits(1),
                unit: AgeUnit::Minutes
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::True
    );
    assert_eq!(
        evaluate(
            date(DateTest::OlderThan {
                amount: -0.0,
                unit: AgeUnit::Minutes
            }),
            &s,
            Some(&c)
        )
        .truth,
        Truth::False
    );
}

#[test]
fn every_elapsed_unit_uses_its_canonical_decimal_boundary() {
    let c = context();
    let mut s = MetadataSnapshot::default();
    for (amount, unit, milliseconds) in [
        (0.1, AgeUnit::Minutes, 6000),
        (0.1, AgeUnit::Hours, 360000),
        (0.1, AgeUnit::Days, 8640000),
        (0.1, AgeUnit::Weeks, 60480000),
        (7.25, AgeUnit::Weeks, 4384800000),
    ] {
        for (offset, older, newer) in [
            (0, Truth::False, Truth::False),
            (1, Truth::True, Truth::False),
            (-1, Truth::False, Truth::True),
        ] {
            s.dates.modified = Metadata::Known(c.now_ms - milliseconds - offset);
            assert_eq!(
                evaluate(
                    date(DateTest::OlderThan {
                        amount,
                        unit: unit.clone()
                    }),
                    &s,
                    Some(&c)
                )
                .truth,
                older
            );
            assert_eq!(
                evaluate(
                    date(DateTest::NewerThan {
                        amount,
                        unit: unit.clone()
                    }),
                    &s,
                    Some(&c)
                )
                .truth,
                newer
            );
        }
    }
}
