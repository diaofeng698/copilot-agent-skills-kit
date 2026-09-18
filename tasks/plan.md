# Implementation Plan: Portable Copilot Agent Skills Kit

## Overview

Build a dedicated Git repository around a pinned `agent-skills` submodule. Add tested Bash tooling that installs the pinned content into arbitrary workspaces, updates the pin deliberately, and verifies both the kit and target installation.

## Architecture Decisions

- Use a Git submodule instead of copying third-party files, preserving provenance and making updates reviewable.
- Use a kit-specific lock file in target projects instead of depending on the currently broken system `npm/npx` installation.
- Treat installed upstream Skills, references, and Personas as managed mirrors while preserving unrelated target files.
- Copy the Copilot instructions template only when the target has no instructions file.

## Task List

### Phase 1: Repository foundation

- [x] Initialize Git on `main` and commit the approved spec and plan.
- [x] Add `addyosmani/agent-skills` as `vendor/agent-skills` submodule pinned to release `0.6.10`.

### Checkpoint: Foundation

- [x] `git submodule status` reports the expected commit.
- [x] The superproject working tree is clean after commits.

### Phase 2: Installer behavior

- [x] Write failing integration tests for install, preservation, and dry-run behavior.
- [x] Implement `scripts/install.sh` until the tests pass.
- [x] Add the Copilot instructions template.

### Checkpoint: Installer

- [x] `tests/run.sh` passes.
- [x] Re-running installation is idempotent.

### Phase 3: Maintenance and documentation

- [x] Implement explicit upstream-update and repository-verification scripts.
- [x] Copy the Chinese guide into `docs/` and adapt it to the kit workflow.
- [x] Add README quick start, maintenance, rollback, and publishing instructions.
- [x] Add shell-safe editor settings and repository instructions.

### Checkpoint: Complete

- [x] All shell scripts pass `bash -n`.
- [x] Integration tests pass.
- [x] Repository verification passes.
- [x] Git history is split into reviewable commits.

## Risks and Mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Upstream removes or renames content | Partial target install | Verify required directories and agents before copying |
| Installer overwrites project customizations | Lost work | Preserve unrelated Skills and never overwrite existing instructions |
| Moving upstream branch changes unexpectedly | Unreviewed workflow changes | Pin a submodule commit and update explicitly |
| Generic formatter corrupts Bash | Broken maintenance command | Disable format-on-save for shell scripts and run `bash -n` |
| Missing `npm/npx` | Installer unavailable | Use Bash, Git, and rsync only |

## Open Questions

- The remote repository URL will be configured only after the user selects a Git hosting location.
