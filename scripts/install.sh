#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
readonly template="$project_root/templates/copilot-instructions.md"
# shellcheck source=common.sh
source "$project_root/scripts/common.sh"

target=""
dry_run=false
force_instructions=false
force_managed=false

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh --target PATH [OPTIONS]

Install the pinned agent-skills content into an existing project directory.

Options:
  --target PATH          Existing target project directory (required).
  --dry-run              Validate and print actions without modifying the target.
  --force-instructions   Replace an existing Copilot instructions file.
  --force-managed        Replace unowned same-name Skills, references, or Personas.
  --help                 Show this help.
EOF
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

contains_name() {
  local wanted="$1"
  shift
  local candidate
  for candidate in "$@"; do
    [[ "$candidate" == "$wanted" ]] && return 0
  done
  return 1
}

assert_owned_or_compatible_directory() {
  local source_path="$1"
  local target_path="$2"
  local kind="$3"
  local name="$4"
  shift 4
  local owned_names=("$@")

  kit_assert_safe_directory "$target_path"
  [[ -e "$target_path" ]] || return 0
  kit_reject_symlinks "$target_path" "target $kind $name"
  contains_name "$name" "${owned_names[@]}" && return 0
  diff -qr "$source_path" "$target_path" >/dev/null && return 0
  [[ "$force_managed" == true ]] || \
    kit_fail "unowned $kind collides with upstream name '$name': $target_path; rerun with --force-managed only after review"
}

assert_owned_or_compatible_file() {
  local source_path="$1"
  local target_path="$2"
  local kind="$3"
  local name="$4"
  shift 4
  local owned_names=("$@")

  kit_assert_safe_file "$target_path"
  [[ -e "$target_path" ]] || return 0
  contains_name "$name" "${owned_names[@]}" && return 0
  cmp -s "$source_path" "$target_path" && return 0
  [[ "$force_managed" == true ]] || \
    kit_fail "unowned $kind collides with upstream name '$name': $target_path; rerun with --force-managed only after review"
}

while (($# > 0)); do
  case "$1" in
    --target)
      (($# >= 2)) || kit_fail '--target requires a path'
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
    --force-managed)
      force_managed=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      kit_fail "unknown option: $1"
      ;;
  esac
done

[[ -n "$target" ]] || kit_fail '--target is required'
[[ -d "$target" && ! -L "$target" ]] || \
  kit_fail "target must be an existing real directory: $target"
target="$(cd -- "$target" && pwd -P)"

kit_require_commands git rsync find diff cmp
kit_assert_upstream_integrity "$project_root" "$upstream"

[[ -d "$upstream/skills" ]] || kit_fail "upstream skills directory not found: $upstream/skills"
[[ -d "$upstream/references" ]] || \
  kit_fail "upstream references directory not found: $upstream/references"
[[ -d "$upstream/agents" ]] || kit_fail "upstream agents directory not found: $upstream/agents"
[[ -f "$template" && ! -L "$template" ]] || \
  kit_fail "Copilot instructions template is not a regular file: $template"

readonly skills_target="$target/.agents/skills"
readonly references_target="$target/.agents/references"
readonly personas_target="$target/.github/agents"
readonly instructions_target="$target/.github/copilot-instructions.md"
readonly lock_file="$target/.agent-skills-kit.lock"
readonly upstream_url="$(git -C "$upstream" remote get-url origin)"

skill_names=()
for skill_dir in "$upstream"/skills/*; do
  [[ -d "$skill_dir" && ! -L "$skill_dir" ]] || kit_fail "invalid upstream Skill path: $skill_dir"
  skill_name="${skill_dir##*/}"
  kit_validate_managed_name skill "$skill_name"
  [[ -f "$skill_dir/SKILL.md" ]] || kit_fail "missing SKILL.md for $skill_name"
  skill_names+=("$skill_name")
done

reference_names=()
for reference_path in "$upstream"/references/*; do
  [[ -f "$reference_path" && ! -L "$reference_path" ]] || \
    kit_fail "upstream reference must be a regular file: $reference_path"
  reference_name="${reference_path##*/}"
  kit_validate_managed_name reference "$reference_name"
  reference_names+=("$reference_name")
done

persona_names=()
for persona_file in "$upstream"/agents/*.md; do
  [[ -f "$persona_file" && ! -L "$persona_file" ]] || \
    kit_fail "upstream Persona must be a regular file: $persona_file"
  persona_name="${persona_file##*/}"
  persona_name="${persona_name%.md}"
  kit_validate_managed_name persona "$persona_name"
  persona_names+=("$persona_name")
done

((${#skill_names[@]} > 0)) || kit_fail 'upstream contains no Skills'
((${#reference_names[@]} > 0)) || kit_fail 'upstream contains no references'
((${#persona_names[@]} > 0)) || kit_fail 'upstream contains no Personas'

old_skills=()
old_references=()
old_personas=()
if [[ -e "$lock_file" || -L "$lock_file" ]]; then
  kit_load_lock "$lock_file" "$upstream_url"
  old_skills=("${lock_skills[@]}")
  old_references=("${lock_references[@]}")
  old_personas=("${lock_personas[@]}")
fi

# Complete all destination safety and ownership checks before the first write.
kit_assert_safe_directory "$target/.agents"
kit_assert_safe_directory "$skills_target"
kit_assert_safe_directory "$references_target"
kit_assert_safe_directory "$target/.github"
kit_assert_safe_directory "$personas_target"
kit_assert_safe_file "$instructions_target"
kit_assert_safe_file "$lock_file"

for name in "${skill_names[@]}"; do
  assert_owned_or_compatible_directory \
    "$upstream/skills/$name" "$skills_target/$name" Skill "$name" \
    "${old_skills[@]}"
done
for name in "${reference_names[@]}"; do
  assert_owned_or_compatible_file \
    "$upstream/references/$name" "$references_target/$name" reference "$name" \
    "${old_references[@]}"
done
for name in "${persona_names[@]}"; do
  assert_owned_or_compatible_file \
    "$upstream/agents/$name.md" "$personas_target/$name.agent.md" Persona "$name" \
    "${old_personas[@]}"
done
for name in "${old_skills[@]}"; do
  kit_assert_safe_directory "$skills_target/$name"
  kit_reject_symlinks "$skills_target/$name" "previously managed Skill $name"
done
for name in "${old_references[@]}"; do
  kit_assert_safe_file "$references_target/$name"
done
for name in "${old_personas[@]}"; do
  kit_assert_safe_file "$personas_target/$name.agent.md"
done

run mkdir -p "$skills_target" "$references_target" "$personas_target"

for name in "${skill_names[@]}"; do
  run mkdir -p "$skills_target/$name"
  run rsync -a --delete "$upstream/skills/$name/" "$skills_target/$name/"
done
for name in "${reference_names[@]}"; do
  run cp "$upstream/references/$name" "$references_target/$name"
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
  if [[ ! -f "$upstream/references/$name" ]]; then
    run rm -f -- "$references_target/$name"
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
  lock_tmp="$(mktemp "$target/.agent-skills-kit.lock.tmp.XXXXXX")"
  trap 'rm -f -- "${lock_tmp:-}"' EXIT
  {
    printf 'format=1\n'
    printf 'upstream_url=%s\n' "$upstream_url"
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
