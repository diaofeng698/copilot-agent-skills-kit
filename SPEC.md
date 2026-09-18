# Spec: Portable GitHub Copilot Agent Skills Kit

## Objective

Create a small, version-controlled maintenance repository that lets one user or a team reproduce the same GitHub Copilot Agent Skills setup on another computer or in another project.

The repository owns the Chinese setup guide, installation/update/verification scripts, and a project instructions template. The third-party `addyosmani/agent-skills` repository remains an independent Git submodule so its upstream history, license, and pinned revision stay explicit.

## Assumptions

1. The maintenance repository is standalone and can be cloned to any writable path.
2. The default branch is `main`; no remote is configured until the user chooses a hosting URL.
3. Linux Bash, Git, and `rsync` are available on target machines.
4. A stable, reviewed upstream revision is preferred over silently following the moving `main` branch.
5. Existing project-specific `.github/copilot-instructions.md` files must not be overwritten.

## Tech Stack

- Git and Git submodules
- Bash 4.2+
- Standard Unix tools plus `rsync`
- Markdown documentation
- No npm, Python, package manager, or production dependency

## Commands

```bash
# Clone on a new computer
git clone --recurse-submodules <repository-url>

# Install into a project
./scripts/install.sh --target /path/to/project

# Preview installation
./scripts/install.sh --target /path/to/project --dry-run

# Update the pinned third-party revision
./scripts/update-upstream.sh

# Verify this maintenance repository
./scripts/verify.sh

# Run behavioral tests
./tests/run.sh
```

## Project Structure

```text
copilot-agent-skills-kit/
├── .github/                   Repository-specific Copilot instructions
├── .vscode/                   Safe shell editing defaults
├── docs/                      Chinese setup guide
├── scripts/                   Install, upstream update, and verification tools
├── templates/                 Files copied only when absent in a target project
├── tests/                     Bash integration tests
├── tasks/                     Implementation plan and checklist
├── vendor/agent-skills/       Pinned upstream Git submodule
├── .gitmodules                Submodule URL and path
├── README.md                  Quick start and maintenance workflow
└── SPEC.md                    Requirements and boundaries
```

## Code Style

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
```

- Quote every path expansion.
- Use lowercase local variable names and uppercase exported variables only.
- Prefer explicit long options and fail with actionable messages.
- Run `bash -n` on every shell script.
- Do not pass project paths through `eval` or an extra shell.

## Testing Strategy

- Integration tests create temporary target projects and call the real installer.
- Tests verify Skill, Persona, reference, lock, and instructions behavior.
- Tests prove existing instructions and unrelated local Skills are preserved.
- Tests prove locally modified managed content is rejected unless explicitly forced.
- Tests prove failed installations restore the prior target state.
- Tests prove dry-run mode does not modify the target.
- Verification checks submodule state, required upstream assets, shell syntax, and documentation.

## Boundaries

### Always

- Pin the upstream repository through a Git submodule commit.
- Preserve unrelated target-project Skills and existing Copilot instructions.
- Record content digests for managed entries and stage changes before replacement.
- Verify scripts before committing an update.
- Keep third-party licensing and history inside the submodule.

### Ask first

- Add a remote or push this repository.
- Change the upstream repository URL.
- Add production dependencies.
- Replace an existing target-project Copilot instructions file.

### Never

- Commit secrets or credentials.
- Copy the upstream repository into normal tracked files.
- Run destructive Git resets in a target project.
- Automatically merge or commit unreviewed upstream changes.
- Edit files inside the third-party submodule as local product code.

## Success Criteria

- A fresh clone with `--recurse-submodules` can install all upstream Skills, references, and four Personas into an arbitrary project.
- Installation is idempotent and preserves unrelated local Skills.
- Interrupted or failed installation does not leave a partial managed configuration.
- Existing project Copilot instructions are never overwritten by default.
- Upstream updates are explicit, reviewable Git-link changes.
- Automated tests and verification pass.
- The Chinese guide and README explain first install, routine updates, rollback, and troubleshooting.

## Open Questions

- Remote hosting URL and repository visibility are intentionally deferred.
- A license for this wrapper repository is intentionally deferred; the upstream submodule retains its MIT license.
