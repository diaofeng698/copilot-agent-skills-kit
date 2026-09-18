#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
readonly template="$project_root/templates/copilot-instructions.md"

target=""
dry_run=false
force_instructions=false

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh --target PATH [--dry-run] [--force-instructions]

Install the pinned agent-skills content into an existing project directory.

Options:
  --target PATH          Existing target project directory (required).
  --dry-run              Print actions without modifying the target.
  --force-instructions   Replace an existing Copilot instructions file.
  --help                 Show this help.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

run() {
  if [[ "$dry_run" == true ]]; then
    printf 'DRY-RUN:'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

while (($# > 0)); do
  case "$1" in
    --target)
      (($# >= 2)) || fail '--target requires a path'
      target="$2"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --force-instructions)
      force_instructions=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$target" ]] || fail '--target is required'
[[ -d "$target" ]] || fail "target directory does not exist: $target"
target="$(cd -- "$target" && pwd -P)"

for command_name in git rsync find sort cmp; do
  command -v "$command_name" >/dev/null 2>&1 || \
    fail "required command not found: $command_name"
done

if ! git -C "$upstream" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Initializing the agent-skills submodule...\n'
  git -C "$project_root" submodule update --init --recursive
fi

[[ -d "$upstream/skills" ]] || fail "upstream skills directory not found: $upstream/skills"
[[ -d "$upstream/references" ]] || fail "upstream references directory not found: $upstream/references"
[[ -d "$upstream/agents" ]] || fail "upstream agents directory not found: $upstream/agents"
[[ -f "$template" ]] || fail "Copilot instructions template not found: $template"

readonly skills_target="$target/.agents/skills"
readonly references_target="$target/.agents/references"
readonly personas_target="$target/.github/agents"
readonly instructions_target="$target/.github/copilot-instructions.md"
readonly lock_file="$target/.agent-skills-kit.lock"

old_skills=()
old_references=()
old_personas=()
if [[ -f "$lock_file" ]]; then
  while IFS='=' read -r key value; do
    [[ "$value" =~ ^[A-Za-z0-9._-]+$ ]] || continue
    case "$key" in
      skill) old_skills+=("$value") ;;
      reference) old_references+=("$value") ;;
      persona) old_personas+=("$value") ;;
    esac
  done < "$lock_file"
fi

mapfile -t skill_names < <(
  find "$upstream/skills" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort
)
mapfile -t reference_names < <(
  find "$upstream/references" -mindepth 1 -maxdepth 1 -printf '%f\n' | sort
)
mapfile -t persona_names < <(
  find "$upstream/agents" -mindepth 1 -maxdepth 1 -type f -name '*.md' \
    -printf '%f\n' | sed 's/\.md$//' | sort
)

((${#skill_names[@]} > 0)) || fail 'upstream contains no skills'
((${#persona_names[@]} > 0)) || fail 'upstream contains no personas'

run mkdir -p "$skills_target" "$references_target" "$personas_target"

for name in "${skill_names[@]}"; do
  run mkdir -p "$skills_target/$name"
  run rsync -a --delete "$upstream/skills/$name/" "$skills_target/$name/"
done

for name in "${reference_names[@]}"; do
  run rsync -a "$upstream/references/$name" "$references_target/"
done

for name in "${persona_names[@]}"; do
  run cp "$upstream/agents/$name.md" "$personas_target/$name.agent.md"
done

for name in "${old_skills[@]}"; do
  if [[ ! -d "$upstream/skills/$name" ]]; then
    run rm -rf -- "$skills_target/$name"
  fi
done
for name in "${old_references[@]}"; do
  if [[ ! -e "$upstream/references/$name" ]]; then
    run rm -rf -- "$references_target/$name"
  fi
done
for name in "${old_personas[@]}"; do
  if [[ ! -f "$upstream/agents/$name.md" ]]; then
    run rm -f -- "$personas_target/$name.agent.md"
  fi
done

if [[ ! -e "$instructions_target" || "$force_instructions" == true ]]; then
  run mkdir -p "$(dirname -- "$instructions_target")"
  run cp "$template" "$instructions_target"
else
  printf 'Preserved existing Copilot instructions: %s\n' "$instructions_target"
fi

if [[ "$dry_run" == false ]]; then
  lock_tmp="$(mktemp)"
  trap 'rm -f -- "${lock_tmp:-}"' EXIT
  {
    printf 'format=1\n'
    printf 'upstream_url=%s\n' "$(git -C "$upstream" remote get-url origin)"
    printf 'upstream_commit=%s\n' "$(git -C "$upstream" rev-parse HEAD)"
    printf 'upstream_version=%s\n' "$(git -C "$upstream" describe --tags --always)"
    printf '%s\n' "${skill_names[@]/#/skill=}"
    printf '%s\n' "${reference_names[@]/#/reference=}"
    printf '%s\n' "${persona_names[@]/#/persona=}"
  } > "$lock_tmp"
  mv "$lock_tmp" "$lock_file"
  trap - EXIT
fi

printf '%s install for %s skills, %s references, and %s personas in %s.\n' \
  "$([[ "$dry_run" == true ]] && printf 'Previewed' || printf 'Completed')" \
  "${#skill_names[@]}" "${#reference_names[@]}" "${#persona_names[@]}" "$target"
if [[ "$dry_run" == false ]]; then
  printf 'Reload the VS Code window and start a new Copilot Chat session.\n'
fi
