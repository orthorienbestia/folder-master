CREATE TABLE folders (
    id TEXT PRIMARY KEY NOT NULL,
    revision INTEGER NOT NULL CHECK(revision > 0),
    identity TEXT NOT NULL UNIQUE,
    document_json TEXT NOT NULL CHECK(json_valid(document_json))
);
CREATE TABLE settings (
    key TEXT PRIMARY KEY NOT NULL,
    value_json TEXT NOT NULL CHECK(json_valid(value_json))
);
CREATE TABLE rule_revisions (
    rule_id TEXT NOT NULL,
    revision INTEGER NOT NULL CHECK(revision > 0),
    folder_id TEXT NOT NULL,
    document_json TEXT NOT NULL CHECK(json_valid(document_json)),
    PRIMARY KEY(rule_id,revision)
);
CREATE TABLE rule_heads (
    rule_id TEXT PRIMARY KEY NOT NULL,
    folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    revision INTEGER NOT NULL,
    FOREIGN KEY(rule_id,revision) REFERENCES rule_revisions(rule_id,revision)
);
CREATE TABLE runs (
    id TEXT PRIMARY KEY NOT NULL,
    trigger TEXT NOT NULL,
    started_at TEXT NOT NULL,
    ended_at TEXT,
    status TEXT NOT NULL,
    summary_json TEXT NOT NULL CHECK(json_valid(summary_json))
);
CREATE TABLE operation_journal (
    id TEXT PRIMARY KEY NOT NULL,
    run_id TEXT NOT NULL REFERENCES runs(id),
    file_key TEXT NOT NULL,
    step_index INTEGER NOT NULL,
    state TEXT NOT NULL,
    intent_json TEXT NOT NULL CHECK(json_valid(intent_json)),
    outcome_json TEXT CHECK(outcome_json IS NULL OR json_valid(outcome_json)),
    UNIQUE(run_id,file_key,step_index)
);
CREATE TABLE history (
    operation_id TEXT PRIMARY KEY NOT NULL REFERENCES operation_journal(id),
    created_at TEXT NOT NULL,
    status TEXT NOT NULL,
    detail_json TEXT NOT NULL CHECK(json_valid(detail_json)),
    undo_expires_at TEXT
);
CREATE TABLE receipts (
    file_key TEXT NOT NULL,
    file_version TEXT NOT NULL,
    rule_revision_key TEXT NOT NULL,
    provenance_json TEXT NOT NULL CHECK(json_valid(provenance_json)),
    PRIMARY KEY(file_key,file_version,rule_revision_key)
);
CREATE TABLE deadlines (
    folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
    file_key TEXT NOT NULL,
    rule_revision_key TEXT NOT NULL,
    next_due TEXT,
    truth_signature TEXT NOT NULL,
    PRIMARY KEY(folder_id,file_key,rule_revision_key)
);
INSERT INTO settings(key,value_json) VALUES('paused','true');
