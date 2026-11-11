use crate::storage::{self, FolderRecord, Store, StoreError};
use serde::Deserialize;
use serde_json::{json, Value};

#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub(crate) enum Command {
    Status,
    SetPaused {
        paused: bool,
    },
    EchoPath {
        path_bytes_base64: String,
    },
    OpenStore {
        path_bytes_base64: String,
    },
    ListFolders {
        offset: u64,
    },
    AddFolder {
        id: String,
        name: String,
        path_bytes_base64: String,
        bookmark_base64: String,
    },
    UpdateFolder {
        folder: FolderRecord,
    },
    RemoveFolder {
        id: String,
        revision: u64,
    },
}

pub(crate) struct WorkerState {
    pub paused: bool,
    store: Option<Store>,
    store_requested: bool,
}
impl Default for WorkerState {
    fn default() -> Self {
        Self {
            paused: true,
            store: None,
            store_requested: false,
        }
    }
}
fn unavailable() -> StoreError {
    StoreError{code:"store_unavailable",message:"Local storage is unavailable. Resolve the storage problem before changing configuration.".into()}
}

impl WorkerState {
    fn status(&self) -> storage::Result<Value> {
        Ok(
            json!({"engine_version":env!("CARGO_PKG_VERSION"),"paused":self.paused,"automation_available":false,"store_open":self.store.is_some(),"folder_count":self.store.as_ref().map(Store::folder_count).transpose()?.unwrap_or(0)}),
        )
    }
    pub fn perform(&mut self, command: Command) -> storage::Result<Value> {
        match command {
            Command::Status => self.status(),
            Command::SetPaused { paused } => {
                if let Some(store) = &mut self.store {
                    store.set_setting("paused", &json!(paused))?;
                } else if self.store_requested {
                    return Err(unavailable());
                }
                self.paused = paused;
                self.status()
            }
            Command::EchoPath { path_bytes_base64 } => {
                Ok(json!({"path_bytes_base64":path_bytes_base64}))
            }
            Command::OpenStore { path_bytes_base64 } => {
                if self.store.is_some() {
                    return Err(StoreError {
                        code: "store_already_open",
                        message: "This engine already owns a data store.".into(),
                    });
                }
                self.store_requested = true;
                let store = Store::open(&storage::decode_path(&path_bytes_base64)?)?;
                self.paused = store
                    .setting("paused")?
                    .and_then(|v| v.as_bool())
                    .ok_or_else(|| StoreError {
                        code: "invalid_data",
                        message: "The saved pause setting is invalid.".into(),
                    })?;
                self.store = Some(store);
                self.status()
            }
            Command::ListFolders { offset } => {
                let store = self.store.as_ref().ok_or_else(unavailable)?;
                let folders = store.folders_page(offset)?;
                let count = store.folder_count()?;
                let next = offset.saturating_add(folders.len() as u64);
                Ok(
                    json!({"folders":folders,"folder_count":count,"next_offset":if next<count && next>offset {Some(next)}else{None}}),
                )
            }
            Command::AddFolder {
                id,
                name,
                path_bytes_base64,
                bookmark_base64,
            } => {
                let store = self.store.as_mut().ok_or_else(unavailable)?;
                let folder = store.add_folder(
                    &id,
                    &name,
                    &storage::decode_path(&path_bytes_base64)?,
                    &bookmark_base64,
                )?;
                Ok(json!({"folder":folder}))
            }
            Command::UpdateFolder { folder } => {
                let store = self.store.as_mut().ok_or_else(unavailable)?;
                Ok(json!({"folder":store.update_folder(&folder)?}))
            }
            Command::RemoveFolder { id, revision } => {
                let store = self.store.as_mut().ok_or_else(unavailable)?;
                store.remove_folder(&id, revision)?;
                Ok(json!({"removed_folder_id":id}))
            }
        }
    }
}
