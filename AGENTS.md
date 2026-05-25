# Agent Instructions

Add project-specific agent instructions here.

<!-- HARNESS:BEGIN -->
## Harness

This repo uses Harness. Before work, read:

- `README.md`
- `docs/HARNESS.md`
- `docs/FEATURE_INTAKE.md`
- `docs/ARCHITECTURE.md`
- `scripts/harness query matrix`

On native Windows, run Harness through `scripts\harness.cmd` instead of the
POSIX `scripts/harness` shell launcher.

Use the Rust Harness CLI as the main operational tool. Run it through the
stable repo-local entrypoint (`scripts/harness` on POSIX,
`scripts\harness.cmd` on Windows), which uses the prebuilt Rust binary in
`scripts/bin/` in installed projects.
<!-- HARNESS:END -->
