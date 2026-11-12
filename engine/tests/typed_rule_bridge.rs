#[path = "support/rule_fixture.rs"]
mod rule_fixture;
mod support;
use folder_master_engine::{
    bridge::{fm_engine_submit, Status},
    storage::encode_path,
};
use rule_fixture::{definition, id};
use serde_json::{json, Value};
use std::{fs, os::unix::fs::DirBuilderExt, path::PathBuf};
use support::Engine;
static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "folder-master-typed-bridge-{}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
        ));
        fs::DirBuilder::new().mode(0o700).create(&p).unwrap();
        Self(p)
    }
    fn data(&self) -> PathBuf {
        self.0.join("data")
    }
    fn open(&self, e: &Engine) {
        assert_eq!(
            call(
                e,
                "open",
                json!({"op":"open_store","path_bytes_base64":encode_path(&self.data())})
            )["type"],
            "completed"
        );
    }
    fn enroll(&self, e: &Engine) {
        let watched = self.0.join("inbox");
        fs::create_dir(&watched).unwrap();
        fs::write(watched.join("sentinel.txt"), b"untouched").unwrap();
        assert_eq!(
            call(
                e,
                "add",
                json!({"op":"add_folder","id":"inbox","name":"Inbox","path_bytes_base64":encode_path(&watched),"bookmark_base64":""})
            )["type"],
            "completed"
        );
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn call(e: &Engine, key: &str, command: Value) -> Value {
    assert_eq!(
        e.submit(json!({"version":1,"request_id":key,"command":command})),
        Status::Ok
    );
    e.next()
}
fn raw(e: &Engine, text: &str) -> Value {
    assert_eq!(
        unsafe { fm_engine_submit(e.0, text.as_ptr(), text.len()) },
        Status::Ok
    );
    e.next()
}
#[test]
fn typed_rule_commands_roundtrip_revisions_and_restart_without_file_effects() {
    let f = Fixture::new();
    let original = definition();
    {
        let e = Engine::new();
        f.open(&e);
        f.enroll(&e);
        let valid = call(
            &e,
            "validate",
            json!({"op":"validate_rule","definition":original}),
        );
        assert_eq!(valid["payload"]["valid"], true);
        let saved = call(
            &e,
            "save",
            json!({"op":"save_rule","folder_id":"inbox","expected_revision":null,"definition":original}),
        );
        assert_eq!(saved["payload"]["rule"]["revision"], 1);
        assert_eq!(saved["payload"]["rule"]["definition"], original);
        let mut edited = original.clone();
        edited["name"] = json!("Edited");
        assert_eq!(
            call(
                &e,
                "edit",
                json!({"op":"save_rule","folder_id":"inbox","expected_revision":1,"definition":edited})
            )["payload"]["rule"]["revision"],
            2
        );
        assert_eq!(
            call(
                &e,
                "stale",
                json!({"op":"save_rule","folder_id":"inbox","expected_revision":1,"definition":original})
            )["payload"]["code"],
            "stale_revision"
        );
    }
    let e = Engine::new();
    f.open(&e);
    assert_eq!(
        call(
            &e,
            "get-old",
            json!({"op":"get_rule","id":id(900),"revision":1})
        )["payload"]["rule"]["definition"],
        original
    );
    assert_eq!(
        call(
            &e,
            "get-head",
            json!({"op":"get_rule","id":id(900),"revision":null})
        )["payload"]["rule"]["definition"]["name"],
        "Edited"
    );
    let page = call(
        &e,
        "list",
        json!({"op":"list_rules","folder_id":"inbox","offset":0}),
    );
    assert_eq!(page["payload"]["rule_count"], 1);
    assert_eq!(page["payload"]["rules"][0]["revision"], 2);
    assert!(page["payload"]["rules"][0].get("definition").is_none());
    assert_eq!(
        call(&e, "status", json!({"op":"status"}))["payload"]["automation_available"],
        false
    );
    assert_eq!(
        fs::read(f.0.join("inbox/sentinel.txt")).unwrap(),
        b"untouched"
    );
}
#[test]
fn rejected_definitions_cannot_replace_a_saved_rule() {
    let f = Fixture::new();
    let e = Engine::new();
    f.open(&e);
    f.enroll(&e);
    let original = definition();
    assert_eq!(
        call(
            &e,
            "save",
            json!({"op":"save_rule","folder_id":"inbox","expected_revision":null,"definition":original})
        )["type"],
        "completed"
    );
    let mut invalid = original.clone();
    invalid["conditions"]["expression"]["children"] = json!([]);
    let checked = call(
        &e,
        "validate",
        json!({"op":"validate_rule","definition":invalid}),
    );
    assert_eq!(checked["payload"]["valid"], false);
    assert_eq!(checked["payload"]["issues"][0]["code"], "empty_group");
    assert_eq!(
        call(
            &e,
            "invalid",
            json!({"op":"save_rule","folder_id":"inbox","expected_revision":1,"definition":invalid})
        )["payload"]["code"],
        "invalid_rule"
    );
    invalid = original.clone();
    invalid["schema_version"] = json!(2);
    assert_eq!(
        call(
            &e,
            "future",
            json!({"op":"save_rule","folder_id":"inbox","expected_revision":1,"definition":invalid})
        )["payload"]["code"],
        "unsupported_rule_version"
    );
    invalid = original.clone();
    invalid["enabled"] = json!(true);
    invalid["actions"][0]["action"] = json!({"type":"delete"});
    assert_eq!(
        call(
            &e,
            "guarded",
            json!({"op":"save_rule","folder_id":"inbox","expected_revision":1,"definition":invalid})
        )["payload"]["code"],
        "invalid_rule"
    );
    assert_eq!(
        call(
            &e,
            "get",
            json!({"op":"get_rule","id":id(900),"revision":null})
        )["payload"]["rule"]["definition"],
        original
    );
}
#[test]
fn nested_duplicates_remain_visible_to_the_strict_validator() {
    let e = Engine::new();
    let definition = definition().to_string().replacen(
        "\"name\":\"Original\"",
        "\"name\":\"First\",\"name\":\"Second\"",
        1,
    );
    let request=format!("{{\"version\":1,\"request_id\":\"duplicate\",\"command\":{{\"op\":\"validate_rule\",\"definition\":{definition}}}}}");
    let result = raw(&e, &request);
    assert_eq!(result["payload"]["valid"], false);
    assert_eq!(result["payload"]["issues"][0]["code"], "invalid_format");
}
#[test]
fn fieldless_status_command_rejects_unknown_parameters() {
    let e = Engine::new();
    assert_eq!(
        e.submit(
            json!({"version":1,"request_id":"extra","command":{"op":"status","ignored":true}})
        ),
        Status::InvalidInput
    );
}

#[test]
fn rule_command_parameters_remain_strict_before_queueing() {
    let engine = Engine::new();
    for command in [
        json!({"op":"validate_rule","definition":definition(),"ignored":true}),
        json!({"op":"validate_rule"}),
        json!({"op":"save_rule","folder_id":"inbox","definition":definition(),"revision":1}),
        json!({"op":"save_rule","definition":definition()}),
    ] {
        assert_eq!(
            engine.submit(json!({"version":1,"request_id":"strict","command":command})),
            Status::InvalidInput
        );
    }
    let duplicate = definition().to_string().replacen(
        "\"name\":\"Original\"",
        "\"name\":\"First\",\"name\":\"Second\"",
        1,
    );
    let fixture = Fixture::new();
    fixture.open(&engine);
    fixture.enroll(&engine);
    let request = format!("{{\"version\":1,\"request_id\":\"duplicate-save\",\"command\":{{\"op\":\"save_rule\",\"folder_id\":\"inbox\",\"expected_revision\":null,\"definition\":{duplicate}}}}}");
    assert_eq!(raw(&engine, &request)["payload"]["code"], "invalid_rule");
    assert_eq!(
        call(
            &engine,
            "empty",
            json!({"op":"list_rules","folder_id":"inbox","offset":0})
        )["payload"]["rule_count"],
        0
    );
}
