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

- [ ] Initialize Git on `main` and commit the approved spec and plan.
- [ ] Add `addyosmani/agent-skills` as `vendor/agent-skills` submodule pinned to release `0.6.10`.

### Checkpoint: Foundation

- [ ] `git submodule status` reports the expected commit.
- [ ] The superproject working tree is clean after commits.

### Phase 2: Installer behavior

- [ ] Write failing integration tests for install, preservation, and dry-run behavior.
- [ ] Implement `scripts/install.sh` until the tests pass.
- [ ] Add the Copilot instructions template.

### Checkpoint: Installer

- [ ] `tests/run.sh` passes.
- [ ] Re-running installation is idempotent.

### Phase 3: Maintenance and documentation

- [ ] Implement explicit upstream-update and repository-verification scripts.
- [ ] Copy the Chinese guide into `docs/` and adapt it to the kit workflow.
- [ ] Add README quick start, maintenance, rollback, and publishing instructions.
- [ ] Add shell-safe editor settings and repository instructions.

### Checkpoint: Complete

- [ ] All shell scripts pass `bash -n`.
- [ ] Integration tests pass.
- [ ] Repository verification passes.
- [ ] Git history is split into reviewable commits.

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
