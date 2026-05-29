-- Harness v0 schema - migration 002
-- Allow code-review trace records to use outcome='review' instead of
-- overloading completed.

PRAGMA foreign_keys = OFF;
BEGIN TRANSACTION;

ALTER TABLE trace RENAME TO trace_old;

CREATE TABLE trace (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    created_at      TEXT    NOT NULL DEFAULT (datetime('now')),
    task_summary    TEXT    NOT NULL,
    intake_id       INTEGER REFERENCES intake(id),
    story_id        TEXT    REFERENCES story(id),
    agent           TEXT,
    actions_taken   TEXT,
    files_read      TEXT,
    files_changed   TEXT,
    decisions_made  TEXT,
    errors          TEXT,
    outcome         TEXT
                    CHECK(outcome IN (
                      'completed','blocked','partial','failed','review'
                    )),
    duration_seconds INTEGER,
    token_estimate   INTEGER,
    harness_friction TEXT,
    notes            TEXT
);

INSERT INTO trace SELECT * FROM trace_old;
DROP TABLE trace_old;

INSERT INTO schema_version (version) VALUES (2);
COMMIT;
PRAGMA foreign_keys = ON;
