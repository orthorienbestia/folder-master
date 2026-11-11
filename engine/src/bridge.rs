use crate::worker::{Command, WorkerState};
use base64::{engine::general_purpose::STANDARD, Engine as _};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicU8, Ordering},
        mpsc, Arc, Mutex, OnceLock,
    },
    thread,
};

const MAX_INPUT: usize = 1_048_576;
const MAX_PENDING: usize = 64;
const MAX_BUFFERS: usize = 128;
const QUEUED: u8 = 0;
const RUNNING: u8 = 1;
const COMPLETE: u8 = 2;
const CANCELED: u8 = 3;

#[repr(u32)]
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Status {
    Ok = 0,
    Empty = 1,
    InvalidHandle = 2,
    InvalidInput = 3,
    QueueFull = 4,
    DuplicateRequest = 5,
    NotFound = 6,
    Fatal = 7,
    TooLate = 8,
}

#[repr(C)]
pub struct HandleResult {
    pub status: Status,
    pub handle: u64,
}

#[repr(C)]
pub struct PollResult {
    pub status: Status,
    pub data: *const u8,
    pub len: usize,
    pub allocation: u64,
}

impl PollResult {
    fn empty(status: Status) -> Self {
        Self {
            status,
            data: ptr::null(),
            len: 0,
            allocation: 0,
        }
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    version: u32,
    request_id: String,
    command: Command,
}

struct Job {
    envelope: Envelope,
    state: Arc<AtomicU8>,
}

struct Event {
    id: String,
    bytes: Vec<u8>,
}

struct Engine {
    input: Mutex<Option<mpsc::SyncSender<Job>>>,
    output: Mutex<mpsc::Receiver<Event>>,
    pending: Arc<Mutex<HashMap<String, Arc<AtomicU8>>>>,
    failed: Arc<AtomicBool>,
    worker: Mutex<Option<thread::JoinHandle<()>>>,
}

type Engines = HashMap<u64, Arc<Engine>>;
static ENGINES: OnceLock<Mutex<Engines>> = OnceLock::new();
static BUFFERS: OnceLock<Mutex<HashMap<u64, Box<[u8]>>>> = OnceLock::new();
static NEXT_ID: AtomicU64 = AtomicU64::new(1);

fn engines() -> &'static Mutex<Engines> {
    ENGINES.get_or_init(Mutex::default)
}
fn buffers() -> &'static Mutex<HashMap<u64, Box<[u8]>>> {
    BUFFERS.get_or_init(Mutex::default)
}
fn lock<T>(value: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    value
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
}
fn find(handle: u64) -> Result<Arc<Engine>, Status> {
    lock(engines())
        .get(&handle)
        .cloned()
        .ok_or(Status::InvalidHandle)
}
fn boundary(action: impl FnOnce() -> Status) -> Status {
    catch_unwind(AssertUnwindSafe(action)).unwrap_or(Status::Fatal)
}

fn terminal(id: String, kind: &str, payload: Value) -> Event {
    // Value serialization is infallible for this bounded, fully-owned payload.
    let bytes = json!({"version":1, "request_id":id, "type":kind, "payload":payload})
        .to_string()
        .into_bytes();
    Event { id, bytes }
}

fn execute(job: Job, worker: &mut WorkerState, failed: &AtomicBool) -> Event {
    let id = job.envelope.request_id;
    if job
        .state
        .compare_exchange(QUEUED, RUNNING, Ordering::SeqCst, Ordering::SeqCst)
        .is_err()
    {
        return terminal(id, "canceled", json!({"code":"canceled_before_start"}));
    }
    if failed.load(Ordering::SeqCst) {
        job.state.store(COMPLETE, Ordering::SeqCst);
        return terminal(id, "error", json!({"code":"engine_failed"}));
    }
    let result = catch_unwind(AssertUnwindSafe(|| worker.perform(job.envelope.command)));
    job.state.store(COMPLETE, Ordering::SeqCst);
    match result {
        Ok(Ok(payload)) => terminal(id, "completed", payload),
        Ok(Err(error)) => terminal(
            id,
            "error",
            json!({"code":error.code,"message":error.message}),
        ),
        Err(_) => {
            failed.store(true, Ordering::SeqCst);
            terminal(id, "error", json!({"code":"engine_panicked"}))
        }
    }
}

impl Engine {
    fn new() -> Result<Self, Status> {
        let (input, commands) = mpsc::sync_channel::<Job>(MAX_PENDING);
        let (events, output) = mpsc::channel();
        let failed = Arc::new(AtomicBool::new(false));
        let worker_failed = failed.clone();
        let worker = thread::Builder::new()
            .name("folder-master-engine".into())
            .spawn(move || {
                let mut worker = WorkerState::default();
                for job in commands {
                    let event = execute(job, &mut worker, &worker_failed);
                    if events.send(event).is_err() {
                        break;
                    }
                }
            })
            .map_err(|_| Status::Fatal)?;
        Ok(Self {
            input: Mutex::new(Some(input)),
            output: Mutex::new(output),
            pending: Arc::new(Mutex::new(HashMap::new())),
            failed,
            worker: Mutex::new(Some(worker)),
        })
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        for state in lock(&self.pending).values() {
            let _ = state.compare_exchange(QUEUED, CANCELED, Ordering::SeqCst, Ordering::SeqCst);
        }
        lock(&self.input).take();
        if let Some(worker) = lock(&self.worker).take() {
            let _ = worker.join();
        }
    }
}

#[no_mangle]
pub extern "C" fn fm_engine_create() -> HandleResult {
    catch_unwind(AssertUnwindSafe(|| {
        let mut registry = lock(engines());
        if registry.len() >= 16 {
            return HandleResult {
                status: Status::QueueFull,
                handle: 0,
            };
        }
        match Engine::new() {
            Ok(engine) => {
                let handle = NEXT_ID.fetch_add(1, Ordering::Relaxed);
                registry.insert(handle, Arc::new(engine));
                HandleResult {
                    status: Status::Ok,
                    handle,
                }
            }
            Err(status) => HandleResult { status, handle: 0 },
        }
    }))
    .unwrap_or(HandleResult {
        status: Status::Fatal,
        handle: 0,
    })
}

/// # Safety
/// Input must be readable for `len` bytes for this call's duration.
#[no_mangle]
pub unsafe extern "C" fn fm_engine_submit(handle: u64, data: *const u8, len: usize) -> Status {
    boundary(|| {
        let engine = match find(handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if data.is_null() || len == 0 || len > MAX_INPUT {
            return Status::InvalidInput;
        }
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        let envelope: Envelope = match serde_json::from_slice(bytes) {
            Ok(value) => value,
            Err(_) => return Status::InvalidInput,
        };
        if envelope.version != 1
            || envelope.request_id.is_empty()
            || envelope.request_id.len() > 128
            || envelope.request_id.chars().any(char::is_control)
        {
            return Status::InvalidInput;
        }
        if let Command::EchoPath { path_bytes_base64 } = &envelope.command {
            match STANDARD.decode(path_bytes_base64) {
                Ok(path) if !path.is_empty() && path.len() <= 32768 && !path.contains(&0) => (),
                _ => return Status::InvalidInput,
            }
        }
        if engine.failed.load(Ordering::SeqCst) {
            return Status::Fatal;
        }
        let mut pending = lock(&engine.pending);
        if pending.contains_key(&envelope.request_id) {
            return Status::DuplicateRequest;
        }
        if pending.len() >= MAX_PENDING {
            return Status::QueueFull;
        }
        let state = Arc::new(AtomicU8::new(QUEUED));
        let id = envelope.request_id.clone();
        pending.insert(id.clone(), state.clone());
        let input = lock(&engine.input);
        match input
            .as_ref()
            .map(|sender| sender.try_send(Job { envelope, state }))
        {
            Some(Ok(())) => Status::Ok,
            Some(Err(mpsc::TrySendError::Full(_))) => {
                pending.remove(&id);
                Status::QueueFull
            }
            _ => {
                pending.remove(&id);
                Status::Fatal
            }
        }
    })
}

#[no_mangle]
pub extern "C" fn fm_engine_poll(handle: u64) -> PollResult {
    catch_unwind(AssertUnwindSafe(|| {
        let engine = match find(handle) {
            Ok(value) => value,
            Err(status) => return PollResult::empty(status),
        };
        let mut storage = lock(buffers());
        if storage.len() >= MAX_BUFFERS {
            return PollResult::empty(Status::QueueFull);
        }
        let next = lock(&engine.output).try_recv();
        match next {
            Ok(event) => {
                lock(&engine.pending).remove(&event.id);
                let allocation = NEXT_ID.fetch_add(1, Ordering::Relaxed);
                let bytes = event.bytes.into_boxed_slice();
                let result = PollResult {
                    status: Status::Ok,
                    data: bytes.as_ptr(),
                    len: bytes.len(),
                    allocation,
                };
                storage.insert(allocation, bytes);
                result
            }
            Err(mpsc::TryRecvError::Empty) => PollResult::empty(Status::Empty),
            Err(mpsc::TryRecvError::Disconnected) => PollResult::empty(Status::Fatal),
        }
    }))
    .unwrap_or(PollResult::empty(Status::Fatal))
}

/// # Safety
/// Input must be readable for `len` bytes for this call's duration.
#[no_mangle]
pub unsafe extern "C" fn fm_engine_cancel(handle: u64, data: *const u8, len: usize) -> Status {
    boundary(|| {
        let engine = match find(handle) {
            Ok(value) => value,
            Err(status) => return status,
        };
        if data.is_null() || len == 0 || len > 128 {
            return Status::InvalidInput;
        }
        let bytes = unsafe { std::slice::from_raw_parts(data, len) };
        let id = match std::str::from_utf8(bytes) {
            Ok(value) => value,
            Err(_) => return Status::InvalidInput,
        };
        let pending = lock(&engine.pending);
        let Some(state) = pending.get(id) else {
            return Status::NotFound;
        };
        match state.compare_exchange(QUEUED, CANCELED, Ordering::SeqCst, Ordering::SeqCst) {
            Ok(_) | Err(CANCELED) => Status::Ok,
            Err(_) => Status::TooLate,
        }
    })
}

#[no_mangle]
pub extern "C" fn fm_buffer_release(allocation: u64) -> Status {
    boundary(|| {
        if lock(buffers()).remove(&allocation).is_some() {
            Status::Ok
        } else {
            Status::NotFound
        }
    })
}

#[no_mangle]
pub extern "C" fn fm_engine_destroy(handle: u64) -> Status {
    boundary(|| {
        // Drop/join outside the registry lock, so other engines can finish.
        let engine = lock(engines()).remove(&handle);
        if engine.is_some() {
            drop(engine);
            Status::Ok
        } else {
            Status::InvalidHandle
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn panic_cannot_escape_the_status_boundary() {
        let result = std::panic::catch_unwind(|| boundary(|| panic!("synthetic internal failure")));
        assert_eq!(result.unwrap(), Status::Fatal);
    }

    #[test]
    fn canceled_queued_work_does_not_change_engine_state() {
        let mut worker = WorkerState::default();
        let failed = AtomicBool::new(false);
        let job = Job {
            envelope: Envelope {
                version: 1,
                request_id: "cancel".into(),
                command: Command::SetPaused { paused: false },
            },
            state: Arc::new(AtomicU8::new(CANCELED)),
        };
        let event = execute(job, &mut worker, &failed);
        let value: Value = serde_json::from_slice(&event.bytes).unwrap();
        assert_eq!(value["type"], "canceled");
        assert!(worker.paused);
    }

    #[test]
    fn failed_engine_cannot_apply_later_work() {
        let mut worker = WorkerState::default();
        let failed = AtomicBool::new(true);
        let job = Job {
            envelope: Envelope {
                version: 1,
                request_id: "later".into(),
                command: Command::SetPaused { paused: false },
            },
            state: Arc::new(AtomicU8::new(QUEUED)),
        };
        let event = execute(job, &mut worker, &failed);
        let value: Value = serde_json::from_slice(&event.bytes).unwrap();
        assert_eq!(value["payload"]["code"], "engine_failed");
        assert!(worker.paused);
    }
}
