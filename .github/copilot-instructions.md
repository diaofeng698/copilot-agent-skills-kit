# Repository Instructions

This repository packages a portable GitHub Copilot Agent Skills setup around the pinned `vendor/agent-skills` submodule.

- Treat `vendor/agent-skills/` as read-only third-party code; update its Git link instead of editing it.
- Keep the installer dependency-light: Bash, Git, rsync, and standard Unix tools only.
- Write an integration test before changing installer behavior.
- Never overwrite a target project's existing `.github/copilot-instructions.md` unless the user passes an explicit force option.
- Preserve target-project Skills that are not listed in `.agent-skills-kit.lock`.
- Run `./tests/run.sh` and `./scripts/verify.sh` before committing.
- Keep shell scripts executable and verify them with `bash -n`.
- Do not add a remote or push without explicit user approval.
