#ifndef FOLDER_MASTER_ENGINE_H
#define FOLDER_MASTER_ENGINE_H
#include <stdint.h>
#include <stddef.h>

// Stable protocol v1. All calls must be serialized by each client. Input bytes
// are copied before submit returns. Returned buffers stay readable until their
// allocation token is released exactly once; tokens cannot be reused.
typedef enum FMStatus {
    FM_OK = 0, FM_EMPTY = 1, FM_INVALID_HANDLE = 2, FM_INVALID_INPUT = 3,
    FM_QUEUE_FULL = 4, FM_DUPLICATE_REQUEST = 5, FM_NOT_FOUND = 6, FM_FATAL = 7,
    FM_TOO_LATE = 8
} FMStatus;
typedef struct { FMStatus status; uint64_t handle; } FMHandleResult;
typedef struct {
    FMStatus status;
    const uint8_t *data;
    size_t len;
    uint64_t allocation;
} FMPollResult;

FMHandleResult fm_engine_create(void);
FMStatus fm_engine_submit(uint64_t handle, const uint8_t *data, size_t len);
FMPollResult fm_engine_poll(uint64_t handle);
FMStatus fm_engine_cancel(uint64_t handle, const uint8_t *request_id, size_t len);
FMStatus fm_buffer_release(uint64_t allocation);
FMStatus fm_engine_destroy(uint64_t handle);
#endif
