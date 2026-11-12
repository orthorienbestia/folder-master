use folder_master_engine::{rules::RuleDefinition, storage::Store};
use serde_json::{json, Value};
use std::{fs, os::unix::fs::DirBuilderExt, path::PathBuf};
#[path = "support/rule_fixture.rs"]
mod rule_fixture;
use rule_fixture::id;
fn document(n: usize, name: &str) -> Value {
    let mut value = rule_fixture::definition();
    value["id"] = json!(id(n));
    value["name"] = json!(name);
    value
}
fn rule(n: usize, name: &str) -> RuleDefinition {
    RuleDefinition::from_json(&document(n, name).to_string()).unwrap()
}
static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "folder-master-rule-store-{}-{}-{}",
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
    fn folder(&self, store: &mut Store, id: &str) {
        let path = self.0.join(id);
        fs::create_dir(&path).unwrap();
        store.add_folder(id, id, &path, "").unwrap();
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
#[test]
fn typed_revisions_survive_reopen_and_stale_writes_preserve_history() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let original = rule(900, "Original");
    let first = store
        .save_rule_definition("inbox", None, &original)
        .unwrap();
    assert_eq!(first.revision, 1);
    let mut edit = original.clone();
    edit.name = "Edited".into();
    let second = store.save_rule_definition("inbox", Some(1), &edit).unwrap();
    assert_eq!(second.revision, 2);
    assert_eq!(
        store
            .save_rule_definition("inbox", Some(1), &original)
            .unwrap_err()
            .code,
        "stale_revision"
    );
    assert_eq!(
        store
            .save_rule_definition("inbox", None, &original)
            .unwrap_err()
            .code,
        "rule_exists"
    );
    drop(store);
    let store = Store::open(&f.data()).unwrap();
    assert_eq!(store.rule_definition(&id(900), None).unwrap(), Some(second));
    assert_eq!(
        store.rule_definition(&id(900), Some(1)).unwrap(),
        Some(first)
    );
    assert!(store.rule_definition(&id(901), None).unwrap().is_none());
}
#[test]
fn invalid_or_cross_folder_saves_never_move_or_replace_a_rule() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    f.folder(&mut store, "other");
    let original = rule(900, "Original");
    assert_eq!(
        store
            .save_rule_definition("missing", None, &original)
            .unwrap_err()
            .code,
        "folder_missing"
    );
    let saved = store
        .save_rule_definition("inbox", None, &original)
        .unwrap();
    assert_eq!(
        store
            .save_rule_definition("other", Some(1), &original)
            .unwrap_err()
            .code,
        "folder_mismatch"
    );
    let mut invalid = original.clone();
    invalid.name = "".into();
    assert_eq!(
        store
            .save_rule_definition("inbox", Some(1), &invalid)
            .unwrap_err()
            .code,
        "invalid_rule"
    );
    assert_eq!(store.rule_definition(&id(900), None).unwrap(), Some(saved));
    assert_eq!(
        store.rule_definitions_page("other", 0).unwrap().rule_count,
        0
    );
}
#[test]
fn listing_is_stable_and_folder_removal_keeps_only_historical_revisions() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let sentinel = f.0.join("inbox/original.txt");
    fs::write(&sentinel, b"untouched").unwrap();
    for n in [900, 901] {
        store
            .save_rule_definition("inbox", None, &rule(n, "Sample"))
            .unwrap();
    }
    store
        .save_rule_definition("inbox", Some(1), &rule(900, "Updated"))
        .unwrap();
    let page = store.rule_definitions_page("inbox", 0).unwrap();
    assert_eq!(
        page.rules.iter().map(|r| r.id.as_str()).collect::<Vec<_>>(),
        vec![id(900), id(901)]
    );
    assert_eq!(page.rules[0].revision, 2);
    assert_eq!(page.rule_count, 2);
    assert!(page.next_offset.is_none());
    store.remove_folder("inbox", 1).unwrap();
    assert!(store.rule_definition(&id(900), None).unwrap().is_none());
    assert!(store.rule_definition(&id(900), Some(1)).unwrap().is_some());
    assert_eq!(
        store.rule_definitions_page("inbox", 0).unwrap_err().code,
        "folder_missing"
    );
    assert_eq!(fs::read(&sentinel).unwrap(), b"untouched");
}
#[test]
fn incompatible_saved_document_is_reported_without_rewriting_it() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let mut future = document(900, "Future");
    future["schema_version"] = json!(2);
    store
        .save_rule_snapshot(&id(900), "inbox", 1, &future)
        .unwrap();
    assert_eq!(
        store.rule_definition(&id(900), None).unwrap_err().code,
        "invalid_saved_rule"
    );
    assert_eq!(
        store
            .save_rule_definition("inbox", Some(1), &rule(900, "Older app edit"))
            .unwrap_err()
            .code,
        "invalid_saved_rule"
    );
    assert!(store.rule_snapshot(&id(900), 2).unwrap().is_none());
    assert_eq!(
        store.rule_definition(&id(900), None).unwrap_err().code,
        "invalid_saved_rule"
    );
    assert_eq!(store.rule_snapshot(&id(900), 1).unwrap(), Some(future));
}
#[test]
fn rule_list_pages_have_a_byte_budget_as_well_as_an_item_limit() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let large_name = format!("e{}", "\u{301}".repeat(300_000));
    for n in [900, 901] {
        store
            .save_rule_definition("inbox", None, &rule(n, &large_name))
            .unwrap();
    }
    let page = store.rule_definitions_page("inbox", 0).unwrap();
    assert_eq!(page.rules.len(), 1);
    assert_eq!(page.next_offset, Some(1));
    assert!(serde_json::to_vec(&page).unwrap().len() < 1_048_576);
    let last = store.rule_definitions_page("inbox", 1).unwrap();
    assert_eq!(last.rules[0].id.as_str(), id(901));
    assert!(last.next_offset.is_none());
}

#[test]
fn saves_reject_invalid_patterns_templates_and_capture_names_without_advancing_head() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let original = rule(900, "Original");
    let saved = store
        .save_rule_definition("inbox", None, &original)
        .unwrap();
    let mut bad_regex = document(900, "Bad pattern");
    bad_regex["conditions"]["expression"]["children"][0]["expression"]["predicate"]["op"] =
        json!("regex");
    bad_regex["conditions"]["expression"]["children"][0]["expression"]["predicate"]["value"] =
        json!("(");
    let mut bad_token = document(900, "Bad token");
    bad_token["actions"][0]["action"]["rename"]["template"]["text"] = json!("{unknown}");
    let mut bad_capture = document(900, "Bad capture");
    bad_capture["conditions"]["expression"]["children"][0]["expression"]["predicate"]["op"] =
        json!("regex");
    bad_capture["conditions"]["expression"]["children"][0]["expression"]["predicate"]["value"] =
        json!("(?P<invoice>[0-9]+)");
    bad_capture["actions"][0]["action"]["rename"]["template"] =
        json!({"text":"{capture:missing}","capture_condition_id":id(2)});
    for value in [bad_regex, bad_token, bad_capture] {
        let typed = RuleDefinition::from_json(&value.to_string()).unwrap();
        assert_eq!(
            store
                .save_rule_definition("inbox", Some(1), &typed)
                .unwrap_err()
                .code,
            "invalid_rule"
        );
        assert_eq!(
            store.rule_definition(&id(900), None).unwrap(),
            Some(saved.clone())
        );
        assert!(store.rule_definition(&id(900), Some(2)).unwrap().is_none());
    }
}

#[test]
fn old_structurally_valid_invalid_pattern_remains_editable_and_can_be_repaired() {
    let f = Fixture::new();
    let mut store = Store::open(&f.data()).unwrap();
    f.folder(&mut store, "inbox");
    let mut old = document(900, "Old invalid pattern");
    old["conditions"]["expression"]["children"][0]["expression"]["predicate"]["op"] =
        json!("regex");
    old["conditions"]["expression"]["children"][0]["expression"]["predicate"]["value"] = json!("(");
    store
        .save_rule_snapshot(&id(900), "inbox", 1, &old)
        .unwrap();
    let loaded = store.rule_definition(&id(900), None).unwrap().unwrap();
    assert_eq!(serde_json::to_value(&loaded.definition).unwrap(), old);
    assert_eq!(
        store
            .save_rule_definition("inbox", Some(1), &rule(900, "Repaired"))
            .unwrap()
            .revision,
        2
    );
    assert_eq!(store.rule_snapshot(&id(900), 1).unwrap(), Some(old));
}
