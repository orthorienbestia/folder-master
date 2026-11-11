mod support;
use folder_master_engine::{bridge::Status, storage::encode_path};
use serde_json::json;
use std::{fs, os::unix::fs::DirBuilderExt, path::PathBuf};
use support::Engine;

static NEXT: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let p = std::env::temp_dir().join(format!(
            "folder-master-bridge-{}-{}-{}",
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
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}
fn call(engine: &Engine, id: &str, command: serde_json::Value) -> serde_json::Value {
    assert_eq!(
        engine.submit(json!({"version":1,"request_id":id,"command":command})),
        Status::Ok
    );
    engine.next()
}
fn open(engine: &Engine, f: &Fixture) -> serde_json::Value {
    call(
        engine,
        "open",
        json!({"op":"open_store","path_bytes_base64":encode_path(&f.data())}),
    )
}

#[test]
fn bridge_persists_pause_and_real_folder_metadata_across_engine_lifetimes() {
    let f = Fixture::new();
    let watched = f.0.join("inbox");
    fs::create_dir(&watched).unwrap();
    fs::write(watched.join("keep.txt"), b"untouched").unwrap();
    {
        let e = Engine::new();
        assert_eq!(open(&e, &f)["type"], "completed");
        let added = call(
            &e,
            "add",
            json!({"op":"add_folder","id":"f-1","name":"Inbox","path_bytes_base64":encode_path(&watched),"bookmark_base64":""}),
        );
        assert_eq!(added["type"], "completed");
        assert_eq!(added["payload"]["folder"]["enabled"], false);
        assert_eq!(
            call(&e, "pause", json!({"op":"set_paused","paused":false}))["payload"]["paused"],
            false
        );
    }
    let e = Engine::new();
    assert_eq!(open(&e, &f)["payload"]["paused"], false);
    let page = call(&e, "list", json!({"op":"list_folders","offset":0}));
    assert_eq!(page["payload"]["folders"][0]["display_name"], "Inbox");
    assert_eq!(page["payload"]["folder_count"], 1);
    assert_eq!(fs::read(watched.join("keep.txt")).unwrap(), b"untouched");
}

#[test]
fn second_engine_cannot_open_or_mutate_owned_store() {
    let f = Fixture::new();
    let first = Engine::new();
    assert_eq!(open(&first, &f)["type"], "completed");
    let second = Engine::new();
    assert_eq!(open(&second, &f)["payload"]["code"], "store_owned");
    assert_eq!(
        call(&second, "pause", json!({"op":"set_paused","paused":false}))["payload"]["code"],
        "store_unavailable"
    );
    assert_eq!(
        call(&first, "status", json!({"op":"status"}))["payload"]["paused"],
        true
    );
}

#[test]
fn page_bound_and_revisioned_update_remove_are_visible_through_bridge() {
    let f = Fixture::new();
    let e = Engine::new();
    assert_eq!(open(&e, &f)["type"], "completed");
    for i in 0..11 {
        let path = f.0.join(format!("inbox-{i}"));
        fs::create_dir(&path).unwrap();
        let r = call(
            &e,
            &format!("add-{i}"),
            json!({"op":"add_folder","id":format!("f-{i}"),"name":format!("Inbox {i}"),"path_bytes_base64":encode_path(&path),"bookmark_base64":""}),
        );
        assert_eq!(r["type"], "completed");
    }
    let first = call(&e, "first-page", json!({"op":"list_folders","offset":0}));
    assert_eq!(first["payload"]["folders"].as_array().unwrap().len(), 10);
    assert_eq!(first["payload"]["next_offset"], 10);
    let last = call(&e, "last-page", json!({"op":"list_folders","offset":10}));
    assert_eq!(last["payload"]["folders"].as_array().unwrap().len(), 1);
    assert!(last["payload"]["next_offset"].is_null());
    let mut folder = first["payload"]["folders"][0].clone();
    folder["display_name"] = json!("Changed");
    folder["recursive"] = json!(true);
    let saved = call(&e, "save", json!({"op":"update_folder","folder":folder}));
    assert_eq!(saved["payload"]["folder"]["revision"], 2);
    assert_eq!(
        call(&e, "stale", json!({"op":"update_folder","folder":folder}))["payload"]["code"],
        "stale_revision"
    );
    assert_eq!(
        call(
            &e,
            "remove",
            json!({"op":"remove_folder","id":"f-0","revision":2})
        )["type"],
        "completed"
    );
    assert!(f.0.join("inbox-0").is_dir());
}
