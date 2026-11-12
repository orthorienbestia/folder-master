use folder_master_engine::{
    compiler::{
        assign_counters, CompiledRule, DateParts, ExpansionContext, TemplateSlot, TextCaptureInput,
    },
    rules::{ContentSource, RuleDefinition, RuleId},
};
use serde_json::{json, Value};
use std::collections::HashMap;
#[path = "support/rule_fixture.rs"]
mod rule_fixture;
use rule_fixture::{definition, id};
fn rid(n: usize) -> RuleId {
    RuleId::try_from(id(n)).unwrap()
}
fn compile(v: &Value) -> Result<CompiledRule, Vec<folder_master_engine::rules::ValidationIssue>> {
    RuleDefinition::from_json(&v.to_string()).and_then(|rule| CompiledRule::compile(&rule))
}
fn template(text: &str) -> Value {
    let mut v = definition();
    v["actions"][0]["action"]["rename"]["template"]["text"] = json!(text);
    v
}
fn context(name: &[u8]) -> ExpansionContext<'_> {
    ExpansionContext::new(name)
}
#[test]
fn compiler_rejects_unknown_tokens_formats_patterns_and_replacement_references() {
    for text in [
        "{unknown}",
        "{stem",
        "stem}",
        "{now:yyyy/MM}",
        "{now:YYYY}",
        "{counter:0}",
        "{counter:21}",
        "{counter:999999999999999999999999}",
    ] {
        assert!(compile(&template(text)).is_err(), "{text}");
    }
    for (field, op, value, code) in [
        ("name", "regex", "(", "invalid_regex"),
        ("name", "glob", "[abc", "invalid_glob"),
        ("text", "regex", "(?=a)", "invalid_regex"),
    ] {
        let mut v = definition();
        v["conditions"]["expression"]["children"][0]["expression"]["predicate"] = if field == "name"
        {
            json!({"field":field,"op":op,"value":value,"scope":"filename","case_sensitive":false})
        } else {
            json!({"field":field,"op":op,"value":value,"source":"embedded_only","case_sensitive":false})
        };
        assert_eq!(compile(&v).unwrap_err()[0].code, code);
    }
    for replacement in ["$missing", "${missing}", "$2", "$1suffix"] {
        let mut v = definition();
        v["actions"][0]["action"]["rename"] = json!({"mode":"replace","find":"(?P<n>[0-9]+)","replacement":replacement,"regex":true,"replace_all":true});
        assert!(compile(&v).is_err(), "{replacement}");
    }
}
#[test]
fn templates_expand_lossless_names_dates_and_checked_counters() {
    let c = compile(&template(
        "{name}-{stem}-{ext}-{created:yyyyMMdd}-{modified:HH_mm_ss}-{now:yyyy-MM-dd}-{counter:3}",
    ))
    .unwrap();
    let mut ctx = context(b"a\xff.pdf");
    ctx.created = Some(DateParts::new(2024, 2, 29, 3, 4, 5).unwrap());
    ctx.modified = Some(DateParts::new(2026, 11, 12, 3, 4, 5).unwrap());
    ctx.now = ctx.modified;
    ctx.counter = Some(7);
    assert_eq!(
        c.template(&rid(100), TemplateSlot::Rename)
            .unwrap()
            .expand(&ctx)
            .unwrap(),
        b"a\xff.pdf-a\xff-pdf-20240229-03_04_05-2026-11-12-007"
    );
    assert!(DateParts::new(2023, 2, 29, 0, 0, 0).is_err());
    assert!(DateParts::new(2024, 2, 29, 24, 0, 0).is_err());
    for name in [b"no-extension".as_slice(), b".hidden", b"name."] {
        assert_eq!(
            compile(&template("{ext}"))
                .unwrap()
                .template(&rid(100), TemplateSlot::Rename)
                .unwrap()
                .expand(&context(name))
                .unwrap_err()
                .code,
            "missing_extension"
        );
    }
    assert_eq!(
        compile(&template("{now:yyyy}"))
            .unwrap()
            .template(&rid(100), TemplateSlot::Rename)
            .unwrap()
            .expand(&context(b"a"))
            .unwrap_err()
            .code,
        "missing_date"
    );
    assert_eq!(
        compile(&template("{counter:3}"))
            .unwrap()
            .template(&rid(100), TemplateSlot::Rename)
            .unwrap()
            .expand(&context(b"a"))
            .unwrap_err()
            .code,
        "missing_counter"
    );
}
#[test]
fn capture_binding_checks_group_scope_completeness_and_path_fragments() {
    let mut v = template("{capture:invoice}");
    v["actions"][0]["action"]["rename"]["template"]["capture_condition_id"] = json!(id(2));
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"] = json!({"field":"name","op":"regex","value":"(?P<invoice>.+)","scope":"stem","case_sensitive":false});
    let c = compile(&v).unwrap();
    assert_eq!(
        c.template(&rid(100), TemplateSlot::Rename)
            .unwrap()
            .expand(&context(b"Invoice.pdf"))
            .unwrap(),
        b"Invoice"
    );
    v["conditions"]["expression"]["type"] = json!("any");
    assert!(compile(&v).is_err());
    v["conditions"]["expression"]["type"] = json!("all");
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"] = json!({"field":"text","op":"regex","value":"(?P<invoice>.*)","source":"embedded_only","case_sensitive":true});
    let c = compile(&v).unwrap();
    let t = c.template(&rid(100), TemplateSlot::Rename).unwrap();
    for (text, complete, source, code) in [
        (
            "ok",
            false,
            ContentSource::EmbeddedOnly,
            "incomplete_capture",
        ),
        ("", true, ContentSource::EmbeddedOnly, "empty_capture"),
        (
            "../escape",
            true,
            ContentSource::EmbeddedOnly,
            "unsafe_token",
        ),
        ("a/b", true, ContentSource::EmbeddedOnly, "unsafe_token"),
        (".", true, ContentSource::EmbeddedOnly, "unsafe_output"),
        (
            "ok",
            true,
            ContentSource::ForceOcr,
            "capture_source_mismatch",
        ),
    ] {
        let inputs = HashMap::from([(
            rid(2),
            TextCaptureInput {
                text: text.into(),
                complete,
                source,
            },
        )]);
        let mut ctx = context(b"a.pdf");
        ctx.texts = Some(&inputs);
        assert_eq!(t.expand(&ctx).unwrap_err().code, code);
    }
}
#[test]
fn renames_preserve_extension_once_and_literal_replacements_do_not_expand_dollars() {
    for (template, name, want) in [
        ("{stem}", b"a.pdf".as_slice(), b"a.pdf".as_slice()),
        ("{name}", b"a.pdf", b"a.pdf"),
        ("{stem}", b".hidden", b".hidden"),
        ("renamed", b"a\xff.pdf", b"renamed.pdf"),
    ] {
        let c = compile(&self::template(template)).unwrap();
        assert_eq!(
            c.rename(&rid(100)).unwrap().expand(&context(name)).unwrap(),
            want
        );
    }
    for (regex, all, replacement, want) in [
        (false, false, "$1", b"$1a.pdf".as_slice()),
        (false, true, "$1", b"$1$1.pdf"),
        (true, true, "$$${n}", b"$a$a.pdf"),
    ] {
        let mut v = definition();
        v["actions"][0]["action"]["rename"] = json!({"mode":"replace","find":if regex {"(?P<n>a)"} else {"a"},"replacement":replacement,"regex":regex,"replace_all":all});
        assert_eq!(
            compile(&v)
                .unwrap()
                .rename(&rid(100))
                .unwrap()
                .expand(&context(b"aa.pdf"))
                .unwrap(),
            want
        );
    }
    let mut v = definition();
    v["actions"][0]["action"]["rename"] = json!({"mode":"replace","find":"a(?P<n>b)?","replacement":"${n}","regex":true,"replace_all":true});
    assert_eq!(
        compile(&v)
            .unwrap()
            .rename(&rid(100))
            .unwrap()
            .expand(&context(b"a.pdf"))
            .unwrap_err()
            .code,
        "empty_capture"
    );
}
#[test]
fn subfolders_allow_literal_hierarchy_but_not_dynamic_traversal_and_counters_sort_bytes() {
    let mut v = definition();
    v["actions"][0]["action"] = json!({"type":"copy","destination":{"root":{"path_bytes_base64":"L291dA==","bookmark_base64":"Yg=="},"subfolder":{"text":"sorted/{stem}","capture_condition_id":null},"create_missing":true,"conflict":"keep_both"}});
    let c = compile(&v).unwrap();
    let t = c.template(&rid(100), TemplateSlot::Destination).unwrap();
    assert_eq!(
        t.expand(&context(b"invoice.pdf")).unwrap(),
        b"sorted/invoice"
    );
    for name in [b"../escape.pdf".as_slice(), b"a\0.pdf", b"..pdf"] {
        assert!(t.expand(&context(name)).is_err());
    }
    assert_eq!(
        assign_counters(&[b"z".to_vec(), b"a\xff".to_vec(), b"a".to_vec()], 8).unwrap(),
        vec![
            (b"a".to_vec(), 8),
            (b"a\xff".to_vec(), 9),
            (b"z".to_vec(), 10)
        ]
    );
    assert!(assign_counters(&[b"a".to_vec(), b"a".to_vec()], 1).is_err());
    assert!(assign_counters(&[b"a".to_vec(), b"b".to_vec()], u64::MAX).is_err());
    assert!(assign_counters(&[b"../a".to_vec()], 1).is_err());
}

#[test]
fn expansion_bounds_and_capture_bindings_are_independent_for_archive_outputs() {
    let mut v = template("{name}{name}");
    let c = compile(&v).unwrap();
    let name = vec![b'a'; 9000];
    assert_eq!(
        c.template(&rid(100), TemplateSlot::Rename)
            .unwrap()
            .expand(&context(&name))
            .unwrap_err()
            .code,
        "output_too_long"
    );
    v["actions"][0]["action"]["rename"]["template"]["text"] = json!("x".repeat(16_385));
    assert_eq!(compile(&v).unwrap_err()[0].code, "template_too_long");
    let mut v = definition();
    v["conditions"]["expression"]["children"] = json!([
      {"id":id(2),"expression":{"type":"predicate","predicate":{"field":"name","op":"regex","value":"(?P<directory>invoice)","scope":"stem","case_sensitive":true}}},
      {"id":id(3),"expression":{"type":"predicate","predicate":{"field":"name","op":"regex","value":"(?P<archive>[0-9]+)","scope":"stem","case_sensitive":true}}}
    ]);
    v["actions"][0]["action"] = json!({"type":"compress","destination":{"root":{"path_bytes_base64":"L291dA==","bookmark_base64":"Yg=="},"subfolder":{"text":"{capture:directory}","capture_condition_id":id(2)},"create_missing":true,"conflict":"keep_both"},"filename":{"text":"{capture:archive}.zip","capture_condition_id":id(3)}});
    let c = compile(&v).unwrap();
    let ctx = context(b"invoice-123.pdf");
    assert_eq!(
        c.template(&rid(100), TemplateSlot::Destination)
            .unwrap()
            .expand(&ctx)
            .unwrap(),
        b"invoice"
    );
    assert_eq!(
        c.template(&rid(100), TemplateSlot::ArchiveFilename)
            .unwrap()
            .expand(&ctx)
            .unwrap(),
        b"123.zip"
    );
    v["actions"][0]["action"]["filename"]["capture_condition_id"] = json!(id(2));
    let issue = compile(&v).unwrap_err().remove(0);
    assert_eq!(issue.code, "unknown_capture");
    assert_eq!(issue.node_id, Some(rid(100)));
}
#[test]
fn optional_and_empty_captures_fail_instead_of_silently_disappearing() {
    let mut v = template("prefix-{capture:n}");
    v["actions"][0]["action"]["rename"]["template"]["capture_condition_id"] = json!(id(2));
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"] = json!({"field":"name","op":"regex","value":"^(?P<n>z)?a","scope":"stem","case_sensitive":true});
    let c = compile(&v).unwrap();
    let t = c.template(&rid(100), TemplateSlot::Rename).unwrap();
    assert_eq!(
        t.expand(&context(b"a.pdf")).unwrap_err().code,
        "empty_capture"
    );
    assert_eq!(
        t.expand(&context(b"x.pdf")).unwrap_err().code,
        "missing_capture"
    );
    assert_eq!(
        t.expand(&context(b"\xff.pdf")).unwrap_err().code,
        "non_utf8_capture"
    );
    assert_eq!(t.expand(&context(b"za.pdf")).unwrap(), b"prefix-z");
}

#[test]
fn preservation_keeps_repeated_extensions_and_regex_leaves_unmatched_bytes_unchanged() {
    let c = compile(&template("{stem}")).unwrap();
    assert_eq!(
        c.rename(&rid(100))
            .unwrap()
            .expand(&context(b"report.pdf.pdf"))
            .unwrap(),
        b"report.pdf.pdf"
    );
    for use_regex in [false, true] {
        let mut v = definition();
        v["actions"][0]["action"]["rename"] = json!({"mode":"replace","find":"missing","replacement":"x","regex":use_regex,"replace_all":true});
        assert_eq!(
            compile(&v)
                .unwrap()
                .rename(&rid(100))
                .unwrap()
                .expand(&context(b"report.pdf.pdf"))
                .unwrap(),
            b"report.pdf.pdf"
        );
        assert_eq!(
            compile(&v)
                .unwrap()
                .rename(&rid(100))
                .unwrap()
                .expand(&context(b"report."))
                .unwrap(),
            b"report."
        );
    }
    let mut v = definition();
    v["actions"][0]["action"]["rename"] =
        json!({"mode":"replace","find":"x","replacement":"y","regex":true,"replace_all":true});
    for (name, want) in [
        ("cafe\u{301}.pdf", "cafe\u{301}.pdf"),
        ("cafe\u{301}-x.pdf", "cafe\u{301}-y.pdf"),
    ] {
        assert_eq!(
            compile(&v)
                .unwrap()
                .rename(&rid(100))
                .unwrap()
                .expand(&context(name.as_bytes()))
                .unwrap(),
            want.as_bytes()
        );
    }
}
