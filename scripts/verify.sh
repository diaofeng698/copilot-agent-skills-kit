#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
# shellcheck source=common.sh
source "$project_root/scripts/common.sh"
target=""

usage() {
  cat <<'EOF'
Usage: ./scripts/verify.sh [--target PATH]

Verify this kit. With --target, also verify all managed content installed in an
existing target project.
EOF
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

while (($# > 0)); do
  case "$1" in
    --target)
      (($# >= 2)) || kit_fail '--target requires a path'
      target="$2"
      shift 2
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

kit_require_commands git find diff cmp awk grep
kit_assert_upstream_integrity "$project_root" "$upstream"

for script in "$project_root"/scripts/*.sh "$project_root"/tests/*.sh; do
  [[ -f "$script" && ! -L "$script" ]] || kit_fail "invalid shell script path: $script"
  bash -n "$script" || kit_fail "invalid shell syntax: $script"
done

[[ -d "$upstream/skills" ]] || kit_fail 'upstream skills directory is missing'
[[ -d "$upstream/references" ]] || kit_fail 'upstream references directory is missing'
[[ -f "$project_root/templates/copilot-instructions.md" ]] || \
  kit_fail 'Copilot instructions template is missing'
[[ -f "$project_root/README.md" ]] || kit_fail 'README.md is missing'
[[ -f "$project_root/SPEC.md" ]] || kit_fail 'SPEC.md is missing'
[[ -f "$project_root/docs/GITHUB_COPILOT_AGENT_SKILLS_GUIDE_ZH.md" ]] || \
  kit_fail 'Chinese setup guide is missing'

skill_names=()
for skill_dir in "$upstream"/skills/*; do
  [[ -d "$skill_dir" && ! -L "$skill_dir" ]] || kit_fail "invalid upstream Skill path: $skill_dir"
  skill_name="${skill_dir##*/}"
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || kit_fail "missing SKILL.md for $skill_name"
  declared_name="$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$skill_file")"
  [[ "$declared_name" == "$skill_name" ]] || \
    kit_fail "Skill directory/frontmatter mismatch: $skill_name != $declared_name"
  skill_names+=("$skill_name")
done
((${#skill_names[@]} > 0)) || kit_fail 'no upstream Skills found'

reference_names=()
for reference_path in "$upstream"/references/*; do
  [[ -f "$reference_path" && ! -L "$reference_path" ]] || \
    kit_fail "upstream reference must be a regular file: $reference_path"
  reference_name="${reference_path##*/}"
  kit_validate_managed_name reference "$reference_name"
  reference_names+=("$reference_name")
done
((${#reference_names[@]} > 0)) || kit_fail 'no upstream references found'

persona_names=()
for persona_file in "$upstream"/agents/*.md; do
  [[ -f "$persona_file" && ! -L "$persona_file" ]] || \
    kit_fail "upstream Persona must be a regular file: $persona_file"
  persona_name="${persona_file##*/}"
  persona_name="${persona_name%.md}"
  kit_validate_managed_name persona "$persona_name"
  persona_names+=("$persona_name")
done
for persona_name in \
  code-reviewer \
  test-engineer \
  security-auditor \
  web-performance-auditor
do
  contains_name "$persona_name" "${persona_names[@]}" || \
    kit_fail "required upstream Persona is missing: $persona_name"
done

if [[ -n "$target" ]]; then
  [[ -d "$target" && ! -L "$target" ]] || \
    kit_fail "target must be an existing real directory: $target"
  target="$(cd -- "$target" && pwd -P)"
  upstream_url="$(git -C "$upstream" remote get-url origin)"

  kit_assert_safe_directory "$target/.agents"
  kit_assert_safe_directory "$target/.agents/skills"
  kit_assert_safe_directory "$target/.agents/references"
  kit_assert_safe_directory "$target/.github"
  kit_assert_safe_directory "$target/.github/agents"
  kit_assert_safe_file "$target/.agent-skills-kit.lock"
  kit_load_lock "$target/.agent-skills-kit.lock" "$upstream_url"

  [[ "$lock_upstream_commit" == "$(git -C "$upstream" rev-parse HEAD)" ]] || \
    kit_fail 'target lock does not match the pinned upstream commit'

  ((${#lock_skills[@]} == ${#skill_names[@]})) || \
    kit_fail 'target lock Skill manifest is incomplete or contains extras'
  ((${#lock_references[@]} == ${#reference_names[@]})) || \
    kit_fail 'target lock reference manifest is incomplete or contains extras'
  ((${#lock_personas[@]} == ${#persona_names[@]})) || \
    kit_fail 'target lock Persona manifest is incomplete or contains extras'

  for name in "${skill_names[@]}"; do
    contains_name "$name" "${lock_skills[@]}" || kit_fail "target lock omits Skill: $name"
    kit_reject_symlinks "$target/.agents/skills/$name" "installed Skill $name"
    diff -qr "$upstream/skills/$name" "$target/.agents/skills/$name" >/dev/null || \
      kit_fail "installed Skill differs: $name"
  done
  for name in "${reference_names[@]}"; do
    contains_name "$name" "${lock_references[@]}" || \
      kit_fail "target lock omits reference: $name"
    kit_assert_safe_file "$target/.agents/references/$name"
    cmp -s "$upstream/references/$name" "$target/.agents/references/$name" || \
      kit_fail "installed reference differs: $name"
  done
  for name in "${persona_names[@]}"; do
    contains_name "$name" "${lock_personas[@]}" || kit_fail "target lock omits Persona: $name"
    kit_assert_safe_file "$target/.github/agents/$name.agent.md"
    cmp -s "$upstream/agents/$name.md" "$target/.github/agents/$name.agent.md" || \
      kit_fail "installed Persona differs: $name"
  done
fi

printf 'PASS: verified %s upstream skills at %s\n' \
  "${#skill_names[@]}" "$(git -C "$upstream" rev-parse --short HEAD)"
if [[ -n "$target" ]]; then
  printf 'PASS: verified managed installation in %s\n' "$target"
fi
