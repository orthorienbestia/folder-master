use folder_master_engine::rules::RuleDefinition;
use serde_json::{json, Value};
fn id(n: usize) -> String {
    format!("00000000-0000-4000-8000-{n:012x}")
}
fn template(text: &str) -> Value {
    json!({"text":text,"capture_condition_id":null})
}
fn location() -> Value {
    json!({"path_bytes_base64":"L2ZpeHR1cmUvb3V0cHV0","bookmark_base64":"Ym9va21hcms="})
}
fn destination() -> Value {
    json!({"root":location(),"subfolder":template(""),"create_missing":true,"conflict":"keep_both"})
}
fn name() -> Value {
    json!({"field":"name","op":"contains","value":"invoice","scope":"filename","case_sensitive":false})
}
fn leaf(n: usize, predicate: Value) -> Value {
    json!({"id":id(n),"expression":{"type":"predicate","predicate":predicate}})
}
fn group(n: usize, children: Vec<Value>) -> Value {
    json!({"id":id(n),"expression":{"type":"all","children":children}})
}
fn rename() -> Value {
    json!({"type":"rename","rename":{"mode":"template","template":template("{stem}")},"preserve_extension":true})
}
fn script() -> Value {
    json!({"type":"script","script":location(),"interpreter":{"type":"zsh"},"arguments":["","a b, c; $(literal)"],"timeout_seconds":30,"publish_output":null})
}
fn document(predicate: Value, actions: Vec<Value>) -> Value {
    json!({"schema_version":1,"id":id(999),"name":"Invoices","enabled":false,"conditions":group(1,vec![leaf(2,predicate)]),"actions":actions.into_iter().enumerate().map(|(i,a)|json!({"id":id(100+i),"action":a})).collect::<Vec<_>>(),"behavior":"stop"})
}
fn parse(v: &Value) -> Result<RuleDefinition, Vec<folder_master_engine::rules::ValidationIssue>> {
    RuleDefinition::from_json(&v.to_string())
}
fn rejects(v: &Value, code: &str) {
    let issues = parse(v).expect_err("invalid rule was accepted");
    assert!(
        issues.iter().any(|i| i.code == code),
        "expected {code}, got {issues:?}"
    );
}
#[test]
fn all_condition_and_action_families_roundtrip_without_effects() {
    let predicates = vec![
        name(),
        json!({"field":"extension","test":{"op":"one_of","values":["pdf","gz"]}}),
        json!({"field":"kind","op":"is_not","kind":{"type":"ut_type","identifier":"public.jpeg"}}),
        json!({"field":"size","unit":"gib","test":{"op":"between","minimum":0,"maximum":u64::MAX}}),
        json!({"field":"date","source":"modified","test":{"op":"older_than","amount":1.5,"unit":"days"}}),
        json!({"field":"tags","case_sensitive":false,"test":{"op":"contains_all","names":["Annual, reports","Work"]}}),
        json!({"field":"label","op":"one_of","labels":["none","blue"]}),
        json!({"field":"text","op":"does_not_contain","value":"invoice","source":"embedded_then_ocr","case_sensitive":false}),
    ];
    let mut extraction = destination();
    extraction["subfolder"] = template("{stem}");
    let actions = vec![
        json!({"type":"move","destination":destination()}),
        json!({"type":"copy","destination":destination()}),
        rename(),
        json!({"type":"metadata","tags":{"mode":"add","names":["Annual, reports"]},"label":{"mode":"set","color":"blue"}}),
        json!({"type":"compress","destination":destination(),"filename":template("{stem}.zip")}),
        json!({"type":"uncompress","destination":extraction}),
        json!({"type":"trash"}),
        json!({"type":"delete"}),
        script(),
    ];
    for predicate in predicates {
        for action in &actions {
            let original = document(predicate.clone(), vec![action.clone()]);
            let typed = parse(&original).unwrap();
            assert_eq!(serde_json::to_value(&typed).unwrap(), original);
        }
    }
}
#[test]
fn wrong_field_operator_unknown_fields_and_duplicate_keys_are_rejected() {
    let mut v = document(name(), vec![rename()]);
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"]["op"] =
        json!("greater_than");
    assert!(parse(&v).is_err());
    v = document(name(), vec![rename()]);
    v["unexpected"] = json!(true);
    assert!(parse(&v).is_err());
    v = document(name(), vec![rename()]);
    v["actions"][0]["action"]["overwrite"] = json!(true);
    assert!(parse(&v).is_err());
    let raw = document(name(), vec![rename()]).to_string().replacen(
        "\"name\":\"Invoices\"",
        "\"name\":\"First\",\"name\":\"Second\"",
        1,
    );
    assert!(RuleDefinition::from_json(&raw).is_err());
}
#[test]
fn future_version_is_rejected_without_interpreting_future_fields() {
    let mut v = document(name(), vec![rename()]);
    v["schema_version"] = json!(2);
    v["future_field"] = json!({"unknown":true});
    rejects(&v, "unsupported_rule_version");
}
#[test]
fn groups_limits_and_global_node_identity_are_validated() {
    let mut v = document(name(), vec![rename()]);
    v["conditions"] = group(1, vec![]);
    rejects(&v, "empty_group");
    v["conditions"] = group(
        1,
        vec![group(
            3,
            vec![group(4, vec![group(5, vec![leaf(2, name())])])],
        )],
    );
    rejects(&v, "max_depth");
    v["conditions"] = group(1, (2..53).map(|n| leaf(n, name())).collect());
    rejects(&v, "max_predicates");
    v["conditions"] = group(1, (2..52).map(|n| leaf(n, name())).collect());
    assert!(parse(&v).is_ok());
    v["actions"][0]["id"] = json!(id(2));
    rejects(&v, "duplicate_id");
    v = document(name(), vec![]);
    rejects(&v, "action_count");
    v = document(name(), (0..21).map(|_| rename()).collect());
    rejects(&v, "action_count");
}
#[test]
fn terminal_actions_reject_following_actions_and_continue() {
    let mut extraction = destination();
    extraction["subfolder"] = template("{stem}");
    for action in [
        json!({"type":"trash"}),
        json!({"type":"delete"}),
        json!({"type":"uncompress","destination":extraction}),
        script(),
    ] {
        rejects(
            &document(name(), vec![action.clone(), rename()]),
            "after_terminal",
        );
        let mut v = document(name(), vec![action]);
        v["behavior"] = json!("continue_rules");
        rejects(&v, "terminal_continue");
    }
}
#[test]
fn unavailable_capabilities_cannot_enable_guarded_rules() {
    for action in [json!({"type":"delete"}), script()] {
        let mut v = document(name(), vec![action]);
        assert!(parse(&v).is_ok());
        v["enabled"] = json!(true);
        rejects(&v, "capability_unavailable");
    }
}
#[test]
fn size_date_and_empty_values_are_not_coerced_into_valid_input() {
    let mut v = document(
        json!({"field":"size","unit":"bytes","test":{"op":"between","minimum":2,"maximum":1}}),
        vec![rename()],
    );
    rejects(&v, "reversed_range");
    v = document(
        json!({"field":"date","source":"created","test":{"op":"on_date","date":{"year":2025,"month":2,"day":29}}}),
        vec![rename()],
    );
    rejects(&v, "invalid_date");
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"]["test"]["date"]
        ["year"] = json!(2024);
    assert!(parse(&v).is_ok());
    v = document(
        json!({"field":"date","source":"added_to_folder","test":{"op":"older_than","amount":-1,"unit":"days"}}),
        vec![rename()],
    );
    rejects(&v, "invalid_age");
    v = document(name(), vec![rename()]);
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"]["value"] = json!("");
    rejects(&v, "required_value");
    v["conditions"]["expression"]["children"][0]["expression"]["predicate"]["value"] = json!(" ");
    assert!(parse(&v).is_ok());
}
#[test]
fn unicode_name_limit_counts_user_perceived_characters() {
    let mut v = document(name(), vec![rename()]);
    v["name"] = json!("e\u{301}".repeat(200));
    assert!(parse(&v).is_ok());
    v["name"] = json!("e\u{301}".repeat(201));
    rejects(&v, "name_length");
}

#[test]
fn identities_are_canonical_and_byte_locations_remain_lossless() {
    use base64::{engine::general_purpose::STANDARD, Engine as _};
    let mut value = document(name(), vec![rename()]);
    value["id"] = json!("ABCDEFAB-1234-4000-8000-ABCDEFABCDEF");
    let rule = parse(&value).unwrap();
    assert_eq!(rule.id.as_str(), "abcdefab-1234-4000-8000-abcdefabcdef");
    value["actions"][0]["id"] = json!("abcdefab-1234-4000-8000-abcdefabcdef");
    rejects(&value, "duplicate_id");
    value["actions"][0]["id"] = json!("not-a-uuid");
    rejects(&value, "invalid_format");

    let path = STANDARD.encode(b"/fixture/\xff-output");
    let mut target = destination();
    target["root"]["path_bytes_base64"] = json!(path);
    value = document(name(), vec![json!({"type":"copy","destination":target})]);
    assert_eq!(serde_json::to_value(parse(&value).unwrap()).unwrap(), value);
}
#[test]
fn output_paths_and_metadata_require_valid_configuration() {
    let mut dest = destination();
    dest["root"]["path_bytes_base64"] = json!("cmVsYXRpdmU=");
    rejects(
        &document(name(), vec![json!({"type":"move","destination":dest})]),
        "invalid_location",
    );
    dest = destination();
    dest["subfolder"] = template("../outside");
    rejects(
        &document(name(), vec![json!({"type":"copy","destination":dest})]),
        "invalid_template",
    );
    rejects(
        &document(
            name(),
            vec![
                json!({"type":"metadata","tags":{"mode":"unchanged"},"label":{"mode":"unchanged"}}),
            ],
        ),
        "metadata_no_change",
    );
    assert!(parse(&document(
        name(),
        vec![json!({"type":"metadata","tags":{"mode":"add","names":[]},"label":{"mode":"clear"}})]
    ))
    .is_ok());
    rejects(
        &document(
            name(),
            vec![
                json!({"type":"metadata","tags":{"mode":"replace","names":[],"acknowledged":false},"label":{"mode":"unchanged"}}),
            ],
        ),
        "replacement_acknowledgement",
    );
}
#[test]
fn script_timeout_and_literal_arguments_preserve_their_meaning() {
    let mut action = script();
    action["timeout_seconds"] = json!(0);
    rejects(&document(name(), vec![action.clone()]), "script_timeout");
    action["timeout_seconds"] = json!(601);
    rejects(&document(name(), vec![action.clone()]), "script_timeout");
    action["timeout_seconds"] = json!(600);
    let v = document(name(), vec![action]);
    assert_eq!(
        serde_json::to_value(parse(&v).unwrap()).unwrap()["actions"][0]["action"]["arguments"],
        json!(["", "a b, c; $(literal)"])
    );
}
#[test]
fn fieldless_variants_do_not_accept_unknown_options() {
    for action in [
        json!({"type":"trash","overwrite":true}),
        json!({"type":"delete","approved":true}),
        json!({"type":"metadata","tags":{"mode":"unchanged","hidden":true},"label":{"mode":"clear"}}),
    ] {
        assert!(parse(&document(name(), vec![action])).is_err());
    }
    for predicate in [
        json!({"field":"extension","test":{"op":"is_empty","values":["pdf"]}}),
        json!({"field":"kind","op":"is","kind":{"type":"pdf","identifier":"extra"}}),
        json!({"field":"date","source":"created","test":{"op":"today","timestamp_ms":0}}),
        json!({"field":"tags","case_sensitive":false,"test":{"op":"is_empty","names":["ignored"]}}),
    ] {
        assert!(parse(&document(predicate, vec![rename()])).is_err());
    }
    let mut action = script();
    action["interpreter"] = json!({"type":"zsh","executable":location()});
    assert!(parse(&document(name(), vec![action])).is_err());
}
#[test]
fn capture_sources_must_exist_under_decisive_all_groups() {
    let predicate = json!({"field":"name","op":"regex","value":"(?P<year>[0-9]+)","scope":"filename","case_sensitive":false});
    let mut action = rename();
    action["rename"]["template"] = template("{capture:year}");
    let mut v = document(predicate, vec![action]);
    rejects(&v, "invalid_capture_source");
    v["actions"][0]["action"]["rename"]["template"]["capture_condition_id"] = json!(id(2));
    assert!(parse(&v).is_ok());
    v["conditions"]["expression"]["type"] = json!("any");
    rejects(&v, "invalid_capture_source");
}
