#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
# shellcheck source=common.sh
source "$project_root/scripts/common.sh"
target=""
gitlink_source=head

usage() {
  cat <<'EOF'
Usage: ./scripts/verify.sh [--target PATH] [--staged]

Verify this kit. With --target, also verify all managed content installed in an
existing target project. --staged verifies a submodule Git-link staged by the
upstream updater and cannot be combined with --target.
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

normalize_target_argument() {
  local path="$1"
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  printf '%s\n' "$path"
}

validate_skill_frontmatter() {
  local skill_file="$1"
  local expected_name="$2"
  local declared_name=""
  local description=""
  local first_line=""
  local line=""
  local closed=false

  IFS= read -r first_line < "$skill_file" || true
  [[ "$first_line" == '---' ]] || kit_fail "Skill frontmatter is missing: $skill_file"
  while IFS= read -r line; do
    if [[ "$line" == '---' ]]; then
      closed=true
      break
    fi
    case "$line" in
      name:*)
        [[ -z "$declared_name" ]] || kit_fail "duplicate Skill name: $skill_file"
        declared_name="${line#name:}"
        declared_name="${declared_name#${declared_name%%[![:space:]]*}}"
        ;;
      description:*)
        [[ -z "$description" ]] || kit_fail "duplicate Skill description: $skill_file"
        description="${line#description:}"
        description="${description#${description%%[![:space:]]*}}"
        ;;
    esac
  done < <(tail -n +2 "$skill_file")
  [[ "$closed" == true ]] || kit_fail "Skill frontmatter is not closed: $skill_file"
  [[ "$declared_name" == "$expected_name" ]] || \
    kit_fail "Skill directory/frontmatter mismatch: $expected_name != $declared_name"
  [[ -n "$description" ]] || kit_fail "Skill description is missing: $skill_file"
}

validate_persona_frontmatter() {
  local persona_file="$1"
  local expected_name="$2"
  local declared_name=""
  local description=""
  local first_line=""
  local line=""
  local closed=false

  IFS= read -r first_line < "$persona_file" || true
  [[ "$first_line" == '---' ]] || kit_fail "Persona frontmatter is missing: $persona_file"
  while IFS= read -r line; do
    if [[ "$line" == '---' ]]; then
      closed=true
      break
    fi
    case "$line" in
      name:*)
        [[ -z "$declared_name" ]] || kit_fail "duplicate Persona name: $persona_file"
        declared_name="${line#name:}"
        declared_name="${declared_name#${declared_name%%[![:space:]]*}}"
        ;;
      description:*)
        [[ -z "$description" ]] || \
          kit_fail "duplicate Persona description: $persona_file"
        description="${line#description:}"
        description="${description#${description%%[![:space:]]*}}"
        ;;
    esac
  done < <(tail -n +2 "$persona_file")
  [[ "$closed" == true ]] || kit_fail "Persona frontmatter is not closed: $persona_file"
  [[ "$declared_name" == "$expected_name" ]] || \
    kit_fail "Persona filename/frontmatter mismatch: $expected_name != $declared_name"
  [[ -n "$description" ]] || kit_fail "Persona description is missing: $persona_file"
}

while (($# > 0)); do
  case "$1" in
    --target)
      (($# >= 2)) || kit_fail '--target requires a path'
      target="$2"
      shift 2
      ;;
    --staged)
      gitlink_source=index
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

[[ "$gitlink_source" == head || -z "$target" ]] || \
  kit_fail '--staged cannot be combined with --target'

kit_require_commands git find diff cmp awk grep sha256sum sort tail stat cat
kit_assert_upstream_integrity "$project_root" "$upstream" "$gitlink_source"

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
for tracked_asset in \
  README.md \
  SPEC.md \
  docs/GITHUB_COPILOT_AGENT_SKILLS_GUIDE_ZH.md \
  templates/copilot-instructions.md
do
  git -C "$project_root" ls-files --error-unmatch "$tracked_asset" >/dev/null 2>&1 || \
    kit_fail "required repository asset is not tracked by Git: $tracked_asset"
done

skill_names=()
for skill_dir in "$upstream"/skills/*; do
  [[ -d "$skill_dir" && ! -L "$skill_dir" ]] || kit_fail "invalid upstream Skill path: $skill_dir"
  skill_name="${skill_dir##*/}"
  kit_validate_managed_name skill "$skill_name"
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || kit_fail "missing SKILL.md for $skill_name"
  validate_skill_frontmatter "$skill_file" "$skill_name"
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
  validate_persona_frontmatter "$persona_file" "$persona_name"
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
  target="$(normalize_target_argument "$target")"
  [[ -d "$target" && ! -L "$target" ]] || \
    kit_fail "target must be an existing real directory: $target"
  target="$(cd -- "$target" && pwd -P)"
  upstream_url="$(kit_configured_upstream_url "$project_root")"

  kit_assert_safe_directory "$target/.agents"
  kit_assert_safe_directory "$target/.agents/skills"
  kit_assert_safe_directory "$target/.agents/references"
  kit_assert_safe_directory "$target/.github"
  kit_assert_safe_directory "$target/.github/agents"
  kit_assert_safe_file "$target/.agent-skills-kit.lock"
  kit_load_lock "$target/.agent-skills-kit.lock" "$upstream_url"
  kit_validate_lock_manifest "$upstream"

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
    [[ "$(kit_hash_directory "$target/.agents/skills/$name")" == \
      "${lock_skill_digest[$name]}" ]] || kit_fail "installed Skill digest differs: $name"
  done
  for name in "${reference_names[@]}"; do
    contains_name "$name" "${lock_references[@]}" || \
      kit_fail "target lock omits reference: $name"
    kit_assert_safe_file "$target/.agents/references/$name"
    cmp -s "$upstream/references/$name" "$target/.agents/references/$name" || \
      kit_fail "installed reference differs: $name"
    [[ "$(kit_hash_file "$target/.agents/references/$name")" == \
      "${lock_reference_digest[$name]}" ]] || \
      kit_fail "installed reference digest differs: $name"
  done
  for name in "${persona_names[@]}"; do
    contains_name "$name" "${lock_personas[@]}" || kit_fail "target lock omits Persona: $name"
    kit_assert_safe_file "$target/.github/agents/$name.agent.md"
    cmp -s "$upstream/agents/$name.md" "$target/.github/agents/$name.agent.md" || \
      kit_fail "installed Persona differs: $name"
    [[ "$(kit_hash_file "$target/.github/agents/$name.agent.md")" == \
      "${lock_persona_digest[$name]}" ]] || \
      kit_fail "installed Persona digest differs: $name"
  done
fi

printf 'PASS: verified %s upstream skills at %s\n' \
  "${#skill_names[@]}" "$(git -C "$upstream" rev-parse --short HEAD)"
if [[ -n "$target" ]]; then
  printf 'PASS: verified managed installation in %s\n' "$target"
fi
