mod rule_store;
pub use rule_store::{RulePage, RuleRecord, RuleSummary};

use base64::{engine::general_purpose::STANDARD, Engine as _};
use rusqlite::{backup::Backup, params, Connection, OpenFlags, OptionalExtension};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    ffi::{CString, OsString},
    fs::{self, File, OpenOptions},
    os::fd::AsRawFd,
    os::unix::{
        ffi::{OsStrExt, OsStringExt},
        fs::{DirBuilderExt, MetadataExt, OpenOptionsExt},
    },
    path::{Path, PathBuf},
    sync::atomic::{AtomicU64, Ordering},
    time::Duration,
};

const SCHEMA_VERSION: i64 = 1;
static BACKUP_ID: AtomicU64 = AtomicU64::new(1);

#[derive(Debug)]
pub struct StoreError {
    pub code: &'static str,
    pub message: String,
}
pub type Result<T> = std::result::Result<T, StoreError>;
impl std::fmt::Display for StoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}: {}", self.code, self.message)
    }
}
impl std::error::Error for StoreError {}
fn error(code: &'static str, message: impl Into<String>) -> StoreError {
    StoreError {
        code,
        message: message.into(),
    }
}
fn sql(e: rusqlite::Error) -> StoreError {
    error("storage_error", e.to_string())
}
fn io(e: std::io::Error) -> StoreError {
    error("storage_error", e.to_string())
}

pub fn encode_path(path: &Path) -> String {
    STANDARD.encode(path.as_os_str().as_bytes())
}
pub fn decode_path(encoded: &str) -> Result<PathBuf> {
    let bytes = STANDARD
        .decode(encoded)
        .map_err(|_| error("invalid_path", "The path encoding is invalid."))?;
    if bytes.is_empty() || bytes.len() > 32768 || bytes.contains(&0) {
        return Err(error(
            "invalid_path",
            "The path is empty, too long or contains NUL.",
        ));
    }
    let path = PathBuf::from(OsString::from_vec(bytes));
    if !path.is_absolute() {
        return Err(error("invalid_path", "Choose an absolute local path."));
    }
    Ok(path)
}

fn local_volume(path: &Path) -> Result<()> {
    #[cfg(target_os = "macos")]
    {
        let c = CString::new(path.as_os_str().as_bytes())
            .map_err(|_| error("invalid_path", "Invalid path."))?;
        let mut stat = std::mem::MaybeUninit::<libc::statfs>::uninit();
        if unsafe { libc::statfs(c.as_ptr(), stat.as_mut_ptr()) } != 0 {
            return Err(io(std::io::Error::last_os_error()));
        }
        if unsafe { stat.assume_init() }.f_flags & libc::MNT_LOCAL as u32 == 0 {
            return Err(error(
                "remote_volume",
                "Only local mounted volumes are supported.",
            ));
        }
    }
    Ok(())
}

fn private_file(path: &Path) -> Result<File> {
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .mode(0o600)
        .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
        .open(path)
        .map_err(io)?;
    let m = file.metadata().map_err(io)?;
    if !m.is_file()
        || m.nlink() != 1
        || m.uid() != unsafe { libc::geteuid() }
        || m.mode() & 0o077 != 0
    {
        return Err(error(
            "unsafe_data_root",
            "App data files must be private regular files owned by this user.",
        ));
    }
    Ok(file)
}

struct StoreLease {
    _file: File,
}
impl StoreLease {
    fn acquire(root: &Path) -> Result<(PathBuf, Self)> {
        let normalized: PathBuf = root.components().collect();
        let root = normalized.as_path();
        if !root.is_absolute() || root.file_name().is_none() {
            return Err(error(
                "unsafe_data_root",
                "Choose a private app data directory.",
            ));
        }
        match fs::symlink_metadata(root) {
            Ok(m) if m.file_type().is_symlink() || !m.is_dir() => {
                return Err(error(
                    "unsafe_data_root",
                    "App data cannot be a symlink or regular file.",
                ))
            }
            Ok(_) => (),
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                fs::DirBuilder::new().mode(0o700).create(root).map_err(io)?
            }
            Err(e) => return Err(io(e)),
        }
        let root = root.canonicalize().map_err(io)?;
        let m = fs::metadata(&root).map_err(io)?;
        if m.uid() != unsafe { libc::geteuid() } || m.mode() & 0o077 != 0 {
            return Err(error(
                "unsafe_data_root",
                "The app data directory must have user-only access.",
            ));
        }
        local_volume(&root)?;
        let file = private_file(&root.join("store.lock"))?;
        if unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            let e = std::io::Error::last_os_error();
            if matches!(e.raw_os_error(), Some(libc::EWOULDBLOCK)) {
                return Err(error("store_owned","Another Folder Master instance owns this data. Close that instance before retrying."));
            }
            return Err(io(e));
        }
        Ok((root, Self { _file: file }))
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct FolderRecord {
    pub id: String,
    pub display_name: String,
    pub path_bytes_base64: String,
    pub bookmark_base64: String,
    pub identity: String,
    pub enabled: bool,
    pub recursive: bool,
    pub include_hidden: bool,
    pub exclusions: Vec<String>,
    pub watch_mode: String,
    pub poll_interval_seconds: u32,
    pub revision: u64,
}

pub struct Store {
    root: PathBuf,
    database: PathBuf,
    connection: Connection,
    // Last field: SQLite must close before the process-wide writer lease drops.
    _lease: StoreLease,
}
impl Store {
    pub fn open(root: &Path) -> Result<Self> {
        let (root, lease) = StoreLease::acquire(root)?;
        let database = root.join("state.sqlite3");
        let existed = database.exists();
        let _db_file = private_file(&database)?;
        for suffix in ["-wal", "-shm", "-journal"] {
            let sidecar = root.join(format!("state.sqlite3{suffix}"));
            if fs::symlink_metadata(&sidecar).is_ok() {
                let _ = private_file(&sidecar)?;
            }
        }
        let common = OpenFlags::SQLITE_OPEN_NO_MUTEX | OpenFlags::SQLITE_OPEN_NOFOLLOW;
        if existed {
            let peek =
                Connection::open_with_flags(&database, common | OpenFlags::SQLITE_OPEN_READ_ONLY)
                    .map_err(sql)?;
            let version: i64 = peek
                .pragma_query_value(None, "user_version", |row| row.get(0))
                .map_err(sql)?;
            if version > SCHEMA_VERSION {
                return Err(error("incompatible_schema",format!("This data uses schema {version}. Open it with a newer Folder Master version; no migration was performed.")));
            }
        }
        let mut connection =
            Connection::open_with_flags(&database, common | OpenFlags::SQLITE_OPEN_READ_WRITE)
                .map_err(sql)?;
        connection
            .busy_timeout(Duration::from_secs(2))
            .map_err(sql)?;
        connection
            .pragma_update(None, "foreign_keys", true)
            .map_err(sql)?;
        let version: i64 = connection
            .pragma_query_value(None, "user_version", |row| row.get(0))
            .map_err(sql)?;
        if version == 0 {
            let tx = connection.transaction().map_err(sql)?;
            let migration = (|| -> rusqlite::Result<()> {
                tx.execute_batch(include_str!("schema_v1.sql"))?;
                tx.pragma_update(None, "user_version", SCHEMA_VERSION)?;
                Ok(())
            })();
            if let Err(e) = migration {
                return Err(error(
                    "migration_failed",
                    format!("The schema migration failed and was rolled back: {e}"),
                ));
            }
            tx.commit().map_err(sql)?;
        } else if version != SCHEMA_VERSION {
            return Err(error(
                "incompatible_schema",
                "Unsupported app database version.",
            ));
        }
        let mode: String = connection
            .pragma_query_value(None, "journal_mode", |row| row.get(0))
            .map_err(sql)?;
        if mode.to_lowercase() != "wal" {
            connection
                .pragma_update(None, "journal_mode", "WAL")
                .map_err(sql)?;
        }
        connection
            .pragma_update(None, "synchronous", "FULL")
            .map_err(sql)?;
        connection
            .pragma_update(None, "trusted_schema", false)
            .map_err(sql)?;
        Ok(Self {
            root,
            database,
            connection,
            _lease: lease,
        })
    }

    pub fn add_folder(
        &mut self,
        id: &str,
        name: &str,
        path: &Path,
        bookmark: &str,
    ) -> Result<FolderRecord> {
        let normalized: PathBuf = path.components().collect();
        let path = normalized.as_path();
        validate_id(id)?;
        validate_name(name)?;
        validate_bookmark(bookmark)?;
        let meta = fs::symlink_metadata(path).map_err(io)?;
        if !meta.is_dir() || meta.file_type().is_symlink() {
            return Err(error(
                "invalid_folder",
                "Choose a real directory rather than a file or link.",
            ));
        }
        let path = path.canonicalize().map_err(io)?;
        local_volume(&path)?;
        if path == Path::new("/")
            || ["/System", "/usr", "/bin", "/sbin", "/dev"]
                .iter()
                .any(|p| path.starts_with(p))
        {
            return Err(error(
                "invalid_folder",
                "Choose a personal folder rather than a system location.",
            ));
        }
        self.check_overlap(&path, None)?;
        if path.starts_with(&self.root) || self.root.starts_with(&path) {
            return Err(error(
                "overlapping_scope",
                "Watch scopes cannot contain the app data directory.",
            ));
        }
        let folder = FolderRecord {
            id: id.into(),
            display_name: name.trim().into(),
            path_bytes_base64: encode_path(&path),
            bookmark_base64: bookmark.into(),
            identity: format!("{}:{}", meta.dev(), meta.ino()),
            enabled: false,
            recursive: false,
            include_hidden: false,
            exclusions: vec![
                "*.download".into(),
                "*.crdownload".into(),
                "*.part".into(),
                "*.partial".into(),
            ],
            watch_mode: "automatic".into(),
            poll_interval_seconds: 30,
            revision: 1,
        };
        let exists: bool = self
            .connection
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM folders WHERE id=?1)",
                [id],
                |r| r.get(0),
            )
            .map_err(sql)?;
        if exists {
            return Err(error(
                "folder_exists",
                "This folder identifier already exists.",
            ));
        }
        self.connection
            .execute(
                "INSERT INTO folders(id,revision,identity,document_json) VALUES(?1,1,?2,?3)",
                params![
                    id,
                    folder.identity,
                    serde_json::to_string(&folder).map_err(json_error)?
                ],
            )
            .map_err(sql)?;
        Ok(folder)
    }

    pub fn folders(&self) -> Result<Vec<FolderRecord>> {
        self.read_folders("SELECT document_json FROM folders ORDER BY rowid", [])
    }
    pub fn folders_page(&self, offset: u64) -> Result<Vec<FolderRecord>> {
        self.read_folders(
            "SELECT document_json FROM folders ORDER BY rowid LIMIT 10 OFFSET ?1",
            [offset.min(i64::MAX as u64) as i64],
        )
    }
    fn read_folders<P: rusqlite::Params>(&self, query: &str, args: P) -> Result<Vec<FolderRecord>> {
        let mut statement = self.connection.prepare(query).map_err(sql)?;
        let rows = statement
            .query_map(args, |r| r.get::<_, String>(0))
            .map_err(sql)?;
        rows.map(|row| serde_json::from_str(&row.map_err(sql)?).map_err(json_error))
            .collect()
    }
    pub fn folder_count(&self) -> Result<u64> {
        let count: i64 = self
            .connection
            .query_row("SELECT COUNT(*) FROM folders", [], |r| r.get(0))
            .map_err(sql)?;
        u64::try_from(count).map_err(|_| error("invalid_data", "Negative folder count."))
    }

    fn check_overlap(&self, path: &Path, excluding: Option<&str>) -> Result<()> {
        for existing in self.folders()? {
            if Some(existing.id.as_str()) == excluding {
                continue;
            }
            let other = decode_path(&existing.path_bytes_base64)?;
            if path.starts_with(&other) || other.starts_with(path) {
                return Err(error(
                    "overlapping_scope",
                    "This scope overlaps an existing watched folder.",
                ));
            }
        }
        Ok(())
    }

    pub fn update_folder(&mut self, folder: &FolderRecord) -> Result<FolderRecord> {
        validate_name(&folder.display_name)?;
        if !["automatic", "polling"].contains(&folder.watch_mode.as_str())
            || !(5..=3600).contains(&folder.poll_interval_seconds)
            || folder.exclusions.len() > 100
            || folder
                .exclusions
                .iter()
                .any(|s| s.len() > 4096 || s.contains('\0'))
        {
            return Err(error(
                "invalid_folder",
                "Check the watcher mode, polling interval and exclusions.",
            ));
        }
        let existing: Option<String> = self
            .connection
            .query_row(
                "SELECT document_json FROM folders WHERE id=?1",
                [&folder.id],
                |r| r.get(0),
            )
            .optional()
            .map_err(sql)?;
        let old: FolderRecord = serde_json::from_str(
            &existing.ok_or_else(|| error("folder_missing", "This folder was removed."))?,
        )
        .map_err(json_error)?;
        if old.revision != folder.revision {
            return Err(error(
                "stale_revision",
                "The folder changed. Refresh before saving.",
            ));
        }
        if old.identity != folder.identity
            || old.path_bytes_base64 != folder.path_bytes_base64
            || old.bookmark_base64 != folder.bookmark_base64
        {
            return Err(error(
                "identity_changed",
                "Folder location and identity require the reconnect workflow.",
            ));
        }
        let mut next = folder.clone();
        next.display_name = next.display_name.trim().into();
        next.revision = next
            .revision
            .checked_add(1)
            .ok_or_else(|| error("invalid_revision", "Revision overflow."))?;
        self.connection
            .execute(
                "UPDATE folders SET document_json=?1,revision=?2 WHERE id=?3 AND revision=?4",
                params![
                    serde_json::to_string(&next).map_err(json_error)?,
                    database_revision(next.revision)?,
                    next.id,
                    database_revision(folder.revision)?
                ],
            )
            .map_err(sql)?;
        Ok(next)
    }

    pub fn remove_folder(&mut self, id: &str, revision: u64) -> Result<()> {
        let revision = database_revision(revision)?;
        let changed = self
            .connection
            .execute(
                "DELETE FROM folders WHERE id=?1 AND revision=?2",
                params![id, revision],
            )
            .map_err(sql)?;
        if changed == 0 {
            return Err(error(
                "stale_revision",
                "The folder changed or was already removed. Refresh first.",
            ));
        }
        Ok(())
    }
    pub fn set_setting(&mut self, key: &str, value: &Value) -> Result<()> {
        validate_id(key)?;
        let value = serde_json::to_string(value).map_err(json_error)?;
        if value.len() > 65536 {
            return Err(error("invalid_setting", "This setting is too large."));
        }
        self.connection.execute("INSERT INTO settings(key,value_json) VALUES(?1,?2) ON CONFLICT(key) DO UPDATE SET value_json=excluded.value_json",params![key,value]).map_err(sql)?;
        Ok(())
    }
    pub fn setting(&self, key: &str) -> Result<Option<Value>> {
        self.connection
            .query_row("SELECT value_json FROM settings WHERE key=?1", [key], |r| {
                r.get::<_, String>(0)
            })
            .optional()
            .map_err(sql)?
            .map(|s| serde_json::from_str(&s).map_err(json_error))
            .transpose()
    }
    pub fn save_rule_snapshot(
        &mut self,
        id: &str,
        folder_id: &str,
        revision: u64,
        document: &Value,
    ) -> Result<()> {
        let revision = database_revision(revision)?;
        validate_id(id)?;
        if revision == 0 || !document.is_object() {
            return Err(error(
                "invalid_rule",
                "A rule snapshot needs a positive revision and an object document.",
            ));
        }
        let tx = self.connection.transaction().map_err(sql)?;
        let exists: bool = tx
            .query_row(
                "SELECT EXISTS(SELECT 1 FROM rule_revisions WHERE rule_id=?1 AND revision=?2)",
                params![id, revision],
                |r| r.get(0),
            )
            .map_err(sql)?;
        if exists {
            return Err(error("revision_exists", "Rule revisions are immutable."));
        }
        let data = serde_json::to_string(document).map_err(json_error)?;
        tx.execute("INSERT INTO rule_revisions(rule_id,revision,folder_id,document_json) VALUES(?1,?2,?3,?4)",params![id,revision,folder_id,data]).map_err(sql)?;
        tx.execute("INSERT INTO rule_heads(rule_id,folder_id,revision) VALUES(?1,?2,?3) ON CONFLICT(rule_id) DO UPDATE SET revision=excluded.revision,folder_id=excluded.folder_id",params![id,folder_id,revision]).map_err(sql)?;
        tx.commit().map_err(sql)
    }
    pub fn rule_snapshot(&self, id: &str, revision: u64) -> Result<Option<Value>> {
        let revision = database_revision(revision)?;
        self.connection
            .query_row(
                "SELECT document_json FROM rule_revisions WHERE rule_id=?1 AND revision=?2",
                params![id, revision],
                |r| r.get::<_, String>(0),
            )
            .optional()
            .map_err(sql)?
            .map(|s| serde_json::from_str(&s).map_err(json_error))
            .transpose()
    }
    pub fn backup(&self, target: &Path) -> Result<()> {
        if target.exists() || fs::symlink_metadata(target).is_ok() {
            return Err(error(
                "destination_exists",
                "The backup destination already exists.",
            ));
        }
        let parent = target
            .parent()
            .ok_or_else(|| error("invalid_path", "Choose an existing local backup directory."))?;
        local_volume(parent)?;
        let stage = parent.join(format!(
            ".folder-master-backup-{}-{}.sqlite3",
            std::process::id(),
            BACKUP_ID.fetch_add(1, Ordering::Relaxed)
        ));
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&stage)
            .map_err(io)?;
        let result = (|| {
            let mut destination = Connection::open(&stage).map_err(sql)?;
            Backup::new(&self.connection, &mut destination)
                .map_err(sql)?
                .run_to_completion(64, Duration::from_millis(5), None)
                .map_err(sql)?;
            destination
                .pragma_update(None, "journal_mode", "DELETE")
                .map_err(sql)?;
            destination.close().map_err(|(_, e)| sql(e))?;
            file.sync_all().map_err(io)?;
            fs::hard_link(&stage, target).map_err(|e| {
                if e.kind() == std::io::ErrorKind::AlreadyExists {
                    error(
                        "destination_exists",
                        "The backup destination already exists.",
                    )
                } else {
                    io(e)
                }
            })?;
            File::open(parent).and_then(|f| f.sync_all()).map_err(io)?;
            Ok(())
        })();
        drop(file);
        let _ = fs::remove_file(&stage);
        result
    }
    pub fn database_path(&self) -> PathBuf {
        self.database.clone()
    }
}
fn json_error(e: serde_json::Error) -> StoreError {
    error("invalid_data", e.to_string())
}
fn validate_id(id: &str) -> Result<()> {
    if id.is_empty() || id.len() > 128 || id.chars().any(char::is_control) {
        Err(error(
            "invalid_id",
            "Choose a nonempty identifier of at most 128 bytes.",
        ))
    } else {
        Ok(())
    }
}
fn validate_name(name: &str) -> Result<()> {
    if name.trim().is_empty() || name.chars().count() > 200 {
        Err(error("invalid_name", "Names need 1–200 characters."))
    } else {
        Ok(())
    }
}
fn validate_bookmark(value: &str) -> Result<()> {
    if value.len() > 65536 || STANDARD.decode(value).is_err() {
        Err(error(
            "invalid_bookmark",
            "The folder bookmark is invalid or too large.",
        ))
    } else {
        Ok(())
    }
}

fn database_revision(value: u64) -> Result<i64> {
    let value = i64::try_from(value)
        .map_err(|_| error("invalid_revision", "Revision exceeds database range."))?;
    if value <= 0 {
        Err(error("invalid_revision", "Revision must be positive."))
    } else {
        Ok(value)
    }
}
