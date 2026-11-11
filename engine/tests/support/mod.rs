use folder_master_engine::bridge::*;
use serde_json::Value;
use std::time::{Duration, Instant};

pub struct Engine(pub u64);
impl Engine {
    pub fn new() -> Self {
        let result = fm_engine_create();
        assert_eq!(result.status, Status::Ok);
        assert_ne!(result.handle, 0);
        Self(result.handle)
    }
    pub fn submit(&self, value: Value) -> Status {
        let bytes = serde_json::to_vec(&value).unwrap();
        unsafe { fm_engine_submit(self.0, bytes.as_ptr(), bytes.len()) }
    }
    pub fn next(&self) -> Value {
        let deadline = Instant::now() + Duration::from_secs(3);
        loop {
            let event = fm_engine_poll(self.0);
            if event.status == Status::Ok {
                let bytes = unsafe { std::slice::from_raw_parts(event.data, event.len) }.to_vec();
                assert_eq!(fm_buffer_release(event.allocation), Status::Ok);
                assert_eq!(fm_buffer_release(event.allocation), Status::NotFound);
                return serde_json::from_slice(&bytes).unwrap();
            }
            assert_eq!(event.status, Status::Empty);
            assert!(
                Instant::now() < deadline,
                "engine did not produce a terminal event"
            );
            std::thread::yield_now();
        }
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        assert_eq!(fm_engine_destroy(self.0), Status::Ok);
    }
}
