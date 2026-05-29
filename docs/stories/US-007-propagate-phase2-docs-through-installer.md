# US-007 Propagate Phase 2 Docs Through Installer

## Status

implemented

## Lane

normal

## Product Contract

Installed Harness projects receive the Phase 2 operating docs that agents now
need for observability, maturity tracking, trace quality, and context
selection. Existing Harness installs using `--merge` receive missing Phase 2
docs without overwriting existing files. Existing installs using
`--merge --refresh-agent-shim` also receive an `AGENTS.md` Harness block that
references `docs/CONTEXT_RULES.md`.

## Relevant Product Docs

- `AGENTS.md`
- `docs/CONTEXT_RULES.md`
- `docs/HARNESS_COMPONENTS.md`
- `docs/HARNESS_MATURITY.md`
- `docs/TRACE_SPEC.md`
- `scripts/README.md`
- `scripts/install-harness.sh`

## Acceptance Criteria

- The installer payload includes:
  - `docs/CONTEXT_RULES.md`
  - `docs/HARNESS_COMPONENTS.md`
  - `docs/HARNESS_MATURITY.md`
  - `docs/TRACE_SPEC.md`
- The hardcoded AGENTS shim refresh block includes `docs/CONTEXT_RULES.md`.
- A fresh local install creates the Phase 2 docs.
- A merge install into an existing Harness target creates missing Phase 2 docs
  without overwriting existing Harness files.
- A merge install with `--refresh-agent-shim` refreshes the marked Harness
  block to include `docs/CONTEXT_RULES.md`.

## Design Notes

- Commands: `scripts/install-harness.sh --directory <target> --yes`
- Queries: none.
- API: none.
- Tables: none.
- Domain rules: preserve the stable `scripts/harness` entrypoint and only
  expand the Harness operating-doc payload.
- UI surfaces: terminal installer output.

## Validation

| Layer | Expected proof |
| --- | --- |
| Unit | `bash -n scripts/install-harness.sh`; `rg` finds Phase 2 docs in payload and AGENTS shim. |
| Integration | Fresh local install into a temporary target creates Phase 2 docs and AGENTS context-rule reference. |
| E2E | Merge install into an existing Harness target creates missing Phase 2 docs; `--merge --refresh-agent-shim` refreshes the marked Harness block. |
| Platform | Local macOS shell execution. |
| Release | Not attempted; release publication remains outside this story. |

## Harness Delta

Implements backlog item #2, which was created when Phase 2 docs were complete
but not yet propagated by the installer.

## Evidence

- `bash -n scripts/install-harness.sh`
- `rg -n "docs/(CONTEXT_RULES|HARNESS_COMPONENTS|HARNESS_MATURITY|TRACE_SPEC)\.md" scripts/install-harness.sh`
- `rg -n "docs/CONTEXT_RULES.md" scripts/install-harness.sh AGENTS.md`
- Fresh local install into a temporary target using a local
  `HARNESS_CLI_BASE_URL` created all four Phase 2 docs, wrote an AGENTS shim
  with `docs/CONTEXT_RULES.md`, and installed an executable
  `scripts/bin/harness-cli`.
- Merge install into a temporary existing Harness target created the missing
  Phase 2 docs while preserving existing `docs/README.md` and
  `scripts/harness`.
- Merge install with `--refresh-agent-shim` created the missing Phase 2 docs
  and refreshed the marked AGENTS Harness block to include
  `docs/CONTEXT_RULES.md`.
