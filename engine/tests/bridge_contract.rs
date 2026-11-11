use folder_master_engine::bridge::*;
use serde_json::json;
mod support;
use support::Engine;

// These tests catch dropped/miscorrelated responses, unsafe buffer reuse,
// protocol acceptance bugs, invalid-handle dereferences, and path corruption.

#[test]
fn correlates_real_worker_status_response_and_releases_owned_buffer_once() {
    let engine = Engine::new();
    assert_eq!(
        engine.submit(json!({"version":1,"request_id":"status-1","command":{"op":"status"}})),
        Status::Ok
    );
    let result = engine.next();
    assert_eq!(result["version"], 1);
    assert_eq!(result["request_id"], "status-1");
    assert_eq!(result["type"], "completed");
    assert_eq!(result["payload"]["automation_available"], false);
}

#[test]
fn retains_acknowledged_pause_state_and_never_claims_file_automation_available() {
    let engine = Engine::new();
    assert_eq!(
        engine.submit(
            json!({"version":1,"request_id":"pause","command":{"op":"set_paused","paused":true}})
        ),
        Status::Ok
    );
    assert_eq!(engine.next()["payload"]["paused"], true);
    assert_eq!(
        engine.submit(json!({"version":1,"request_id":"state","command":{"op":"status"}})),
        Status::Ok
    );
    let result = engine.next();
    assert_eq!(result["payload"]["paused"], true);
    assert_eq!(result["payload"]["automation_available"], false);
}

#[test]
fn rejects_malformed_oversized_future_and_unknown_commands_without_events() {
    let engine = Engine::new();
    let bad = b"not json";
    assert_eq!(
        unsafe { fm_engine_submit(engine.0, bad.as_ptr(), bad.len()) },
        Status::InvalidInput
    );
    assert_eq!(
        unsafe { fm_engine_submit(engine.0, std::ptr::null(), 0) },
        Status::InvalidInput
    );
    assert_eq!(
        unsafe { fm_engine_submit(engine.0, bad.as_ptr(), 1_048_577) },
        Status::InvalidInput
    );
    for command in [
        json!({"version":2,"request_id":"future","command":{"op":"status"}}),
        json!({"version":1,"request_id":"","command":{"op":"status"}}),
        json!({"version":1,"request_id":"bad","command":{"op":"delete_all"}}),
        json!({"version":1,"request_id":"extra","command":{"op":"status"},"unexpected":true}),
    ] {
        assert_eq!(engine.submit(command), Status::InvalidInput);
    }
    assert_eq!(fm_engine_poll(engine.0).status, Status::Empty);
}

#[test]
fn preserves_non_utf8_path_bytes_through_json_boundary() {
    let engine = Engine::new();
    // /tmp/<0xff>.pdf, independently encoded; no lossy UTF-8 path conversion.
    assert_eq!(engine.submit(json!({"version":1,"request_id":"path","command":{"op":"echo_path","path_bytes_base64":"L3RtcC//LnBkZg=="}})), Status::Ok);
    assert_eq!(
        engine.next()["payload"]["path_bytes_base64"],
        "L3RtcC//LnBkZg=="
    );
}

#[test]
fn invalid_and_destroyed_handles_are_rejected_without_pointer_dereference() {
    assert_eq!(fm_engine_poll(u64::MAX).status, Status::InvalidHandle);
    assert_eq!(fm_engine_destroy(u64::MAX), Status::InvalidHandle);
    let result = fm_engine_create();
    assert_eq!(result.status, Status::Ok);
    assert_eq!(fm_engine_destroy(result.handle), Status::Ok);
    assert_eq!(fm_engine_poll(result.handle).status, Status::InvalidHandle);
    let id = b"missing";
    assert_eq!(
        unsafe { fm_engine_cancel(result.handle, id.as_ptr(), id.len()) },
        Status::InvalidHandle
    );
}

#[test]
fn duplicate_request_cannot_be_accepted_before_its_terminal_event_is_consumed() {
    let engine = Engine::new();
    let command = json!({"version":1,"request_id":"duplicate","command":{"op":"status"}});
    assert_eq!(engine.submit(command.clone()), Status::Ok);
    assert_eq!(engine.submit(command), Status::DuplicateRequest);
    assert_eq!(engine.next()["request_id"], "duplicate");
    assert_eq!(fm_engine_poll(engine.0).status, Status::Empty);
}

#[test]
fn cancel_unknown_request_is_explicit_and_does_not_create_phantom_result() {
    let engine = Engine::new();
    let id = b"never-submitted";
    assert_eq!(
        unsafe { fm_engine_cancel(engine.0, id.as_ptr(), id.len()) },
        Status::NotFound
    );
    assert_eq!(fm_engine_poll(engine.0).status, Status::Empty);
}

#[test]
fn backpressure_retains_all_accepted_terminal_results() {
    let engine = Engine::new();
    for index in 0..64 {
        assert_eq!(engine.submit(json!({"version":1,"request_id":format!("bounded-{index}"),"command":{"op":"status"}})), Status::Ok);
    }
    assert_eq!(
        engine.submit(json!({"version":1,"request_id":"overflow","command":{"op":"status"}})),
        Status::QueueFull
    );
    let mut seen = std::collections::HashSet::new();
    for _ in 0..64 {
        seen.insert(engine.next()["request_id"].as_str().unwrap().to_string());
    }
    assert_eq!(seen.len(), 64);
    assert_eq!(fm_engine_poll(engine.0).status, Status::Empty);
    assert_eq!(
        engine.submit(json!({"version":1,"request_id":"after-drain","command":{"op":"status"}})),
        Status::Ok
    );
    assert_eq!(engine.next()["request_id"], "after-drain");
}
