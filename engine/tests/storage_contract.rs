use folder_master_engine::storage::Store;
use rusqlite::Connection;
use serde_json::json;
use std::{
    fs,
    io::{BufRead, BufReader},
    os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt},
    path::PathBuf,
    process::{Command, Stdio},
    sync::atomic::{AtomicU64, Ordering},
};

static NEXT: AtomicU64 = AtomicU64::new(0);
struct Fixture(PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "folder-master-store-{}-{}-{}",
            std::process::id(),
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::DirBuilder::new().mode(0o700).create(&path).unwrap();
        Self(path)
    }
    fn data(&self) -> PathBuf {
        self.0.join("data")
    }
    fn watched(&self, name: &str) -> PathBuf {
        let p = self.0.join(name);
        fs::create_dir(&p).unwrap();
        p
    }
}
impl Drop for Fixture {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

#[test]
fn retains_folders_settings_and_rule_revisions_after_reopen() {
    let f = Fixture::new();
    let watched = f.watched("inbox");
    let mut store = Store::open(&f.data()).unwrap();
    let folder = store
        .add_folder("folder-1", "Inbox", &watched, "Ym9va21hcms=")
        .unwrap();
    assert!(!folder.enabled);
    assert_eq!(folder.revision, 1);
    assert!(!folder.recursive);
    assert!(!folder.include_hidden);
    store.set_setting("paused", &json!(false)).unwrap();
    store
        .save_rule_snapshot(
            "rule-1",
            "folder-1",
            1,
            &json!({"name":"PDFs","conditions":{"extension":"pdf"}}),
        )
        .unwrap();
    store
        .save_rule_snapshot(
            "rule-1",
            "folder-1",
            2,
            &json!({"name":"Invoices","conditions":{"text":"invoice"}}),
        )
        .unwrap();
    drop(store);
    let store = Store::open(&f.data()).unwrap();
    assert_eq!(store.folders().unwrap(), vec![folder]);
    assert_eq!(store.setting("paused").unwrap(), Some(json!(false)));
    assert_eq!(
        store.rule_snapshot("rule-1", 1).unwrap().unwrap()["name"],
        "PDFs"
    );
    assert_eq!(
        store.rule_snapshot("rule-1", 2).unwrap().unwrap()["name"],
        "Invoices"
    );
}

#[test]
fn immutable_revision_and_stale_folder_update_do_not_overwrite_state() {
    let f = Fixture::new();
    let watched = f.watched("inbox");
    let mut store = Store::open(&f.data()).unwrap();
    let original = store.add_folder("folder-1", "Inbox", &watched, "").unwrap();
    let mut edit = original.clone();
    edit.display_name = "Receipts".into();
    edit.recursive = true;
    let saved = store.update_folder(&edit).unwrap();
    assert_eq!(saved.revision, 2);
    assert_eq!(
        store.update_folder(&original).unwrap_err().code,
        "stale_revision"
    );
    assert_eq!(store.folders().unwrap(), vec![saved]);
    store
        .save_rule_snapshot("r", "folder-1", 1, &json!({"name":"First"}))
        .unwrap();
    assert_eq!(
        store
            .save_rule_snapshot("r", "folder-1", 1, &json!({"name":"Other"}))
            .unwrap_err()
            .code,
        "revision_exists"
    );
    assert_eq!(
        store.rule_snapshot("r", 1).unwrap().unwrap()["name"],
        "First"
    );
}

#[test]
fn rejects_duplicate_and_nested_scopes_and_keeps_original_files_when_removing_config() {
    let f = Fixture::new();
    let watched = f.watched("inbox");
    let nested = watched.join("nested");
    fs::create_dir(&nested).unwrap();
    let original = watched.join("original.txt");
    fs::write(&original, b"keep me").unwrap();
    let mut store = Store::open(&f.data()).unwrap();
    let folder = store.add_folder("f", "Inbox", &watched, "").unwrap();
    assert_eq!(
        store
            .add_folder("same", "Again", &watched, "")
            .unwrap_err()
            .code,
        "overlapping_scope"
    );
    assert_eq!(
        store
            .add_folder("nested", "Nested", &nested, "")
            .unwrap_err()
            .code,
        "overlapping_scope"
    );
    assert_eq!(
        store
            .add_folder("parent", "Parent", &f.0, "")
            .unwrap_err()
            .code,
        "overlapping_scope"
    );
    store
        .save_rule_snapshot("r", "f", 1, &json!({"name":"Historical"}))
        .unwrap();
    store.remove_folder("f", folder.revision).unwrap();
    assert!(store.folders().unwrap().is_empty());
    assert_eq!(fs::read(&original).unwrap(), b"keep me");
    assert_eq!(
        store.rule_snapshot("r", 1).unwrap().unwrap()["name"],
        "Historical"
    );
}

#[test]
fn newer_schema_is_rejected_without_altering_database_bytes() {
    let f = Fixture::new();
    fs::DirBuilder::new().mode(0o700).create(f.data()).unwrap();
    let path = f.data().join("state.sqlite3");
    let c = Connection::open(&path).unwrap();
    c.execute_batch("PRAGMA user_version=99; CREATE TABLE future(value TEXT); INSERT INTO future VALUES('keep');").unwrap();
    drop(c);
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    let before = fs::read(&path).unwrap();
    assert_eq!(
        Store::open(&f.data()).err().unwrap().code,
        "incompatible_schema"
    );
    assert_eq!(fs::read(&path).unwrap(), before);
}

#[test]
fn migration_failure_rolls_back_and_preserves_existing_data() {
    let f = Fixture::new();
    fs::DirBuilder::new().mode(0o700).create(f.data()).unwrap();
    let path = f.data().join("state.sqlite3");
    let c = Connection::open(&path).unwrap();
    c.execute_batch(
        "CREATE TABLE rule_revisions(unexpected TEXT); INSERT INTO rule_revisions VALUES('preserve');",
    )
    .unwrap();
    drop(c);
    fs::set_permissions(&path, fs::Permissions::from_mode(0o600)).unwrap();
    assert_eq!(
        Store::open(&f.data()).err().unwrap().code,
        "migration_failed"
    );
    let c = Connection::open(&path).unwrap();
    assert_eq!(
        c.query_row("PRAGMA user_version", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        0
    );
    assert_eq!(
        c.query_row("SELECT unexpected FROM rule_revisions", [], |r| r
            .get::<_, String>(0))
            .unwrap(),
        "preserve"
    );
    assert_eq!(
        c.query_row(
            "SELECT COUNT(*) FROM sqlite_master WHERE name IN ('folders', 'settings')",
            [],
            |r| r.get::<_, i64>(0)
        )
        .unwrap(),
        0
    );
}

#[test]
fn online_backup_includes_uncheckpointed_wal_and_never_replaces_existing_backup() {
    let f = Fixture::new();
    let watched = f.watched("inbox");
    let mut store = Store::open(&f.data()).unwrap();
    store.add_folder("f", "Inbox", &watched, "").unwrap();
    store.set_setting("paused", &json!(false)).unwrap();
    let wal = f.data().join("state.sqlite3-wal");
    assert!(fs::metadata(&wal).unwrap().len() > 0);
    let backup = f.0.join("backup.sqlite3");
    store.backup(&backup).unwrap();
    let c = Connection::open(&backup).unwrap();
    assert_eq!(
        c.query_row(
            "SELECT value_json FROM settings WHERE key='paused'",
            [],
            |r| r.get::<_, String>(0)
        )
        .unwrap(),
        "false"
    );
    assert_eq!(
        c.query_row("SELECT COUNT(*) FROM folders", [], |r| r.get::<_, i64>(0))
            .unwrap(),
        1
    );
    drop(c);
    let before = fs::read(&backup).unwrap();
    assert_eq!(
        store.backup(&backup).unwrap_err().code,
        "destination_exists"
    );
    assert_eq!(fs::read(&backup).unwrap(), before);
}

#[test]
fn private_data_permissions_and_symlink_rejection_protect_store_boundary() {
    let f = Fixture::new();
    let store = Store::open(&f.data()).unwrap();
    assert_eq!(fs::metadata(f.data()).unwrap().mode() & 0o777, 0o700);
    assert_eq!(
        fs::metadata(store.database_path()).unwrap().mode() & 0o777,
        0o600
    );
    drop(store);
    let alias = f.0.join("alias");
    std::os::unix::fs::symlink(f.data(), &alias).unwrap();
    assert_eq!(Store::open(&alias).err().unwrap().code, "unsafe_data_root");
}

#[test]
fn same_process_second_owner_is_rejected_until_first_store_drops() {
    let f = Fixture::new();
    let first = Store::open(&f.data()).unwrap();
    assert_eq!(Store::open(&f.data()).err().unwrap().code, "store_owned");
    drop(first);
    assert!(Store::open(&f.data()).is_ok());
}

#[test]
fn trailing_slash_does_not_hide_symlink_data_root() {
    let f = Fixture::new();
    drop(Store::open(&f.data()).unwrap());
    let alias = f.0.join("alias");
    std::os::unix::fs::symlink(f.data(), &alias).unwrap();
    let mut raw = alias.into_os_string();
    raw.push("/");
    assert_eq!(
        Store::open(&PathBuf::from(raw)).err().unwrap().code,
        "unsafe_data_root"
    );
}

#[test]
fn another_process_cannot_own_store_and_process_death_releases_kernel_lock() {
    let f = Fixture::new();
    let mut child = Command::new(env!("CARGO_BIN_EXE_store-probe"))
        .arg("hold")
        .arg(f.data())
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut line = String::new();
    BufReader::new(child.stdout.take().unwrap())
        .read_line(&mut line)
        .unwrap();
    if line.trim() != "owned" {
        let _ = child.kill();
        let _ = child.wait();
        panic!("probe did not acquire ownership: {line}");
    }
    let second = Store::open(&f.data());
    assert_eq!(second.err().unwrap().code, "store_owned");
    let lock_inode = fs::metadata(f.data().join("store.lock")).unwrap().ino();
    child.kill().unwrap();
    child.wait().unwrap();
    let _next = Store::open(&f.data()).unwrap();
    assert_eq!(
        fs::metadata(f.data().join("store.lock")).unwrap().ino(),
        lock_inode
    );
}
