#!/usr/bin/env bash

kit_fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

kit_require_commands() {
  local command_name
  for command_name in "$@"; do
    command -v "$command_name" >/dev/null 2>&1 || \
      kit_fail "required command not found: $command_name"
  done
}

kit_gitlink_commit() {
  local root_dir="$1"
  local mode=""
  local commit=""
  local stage=""
  local path=""

  read -r mode commit stage path < <(
    git -C "$root_dir" ls-files --stage -- vendor/agent-skills
  )
  [[ "$mode" == "160000" && "$stage" == "0" && "$path" == "vendor/agent-skills" ]] || \
    kit_fail 'vendor/agent-skills is not a valid staged Git submodule link'
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || \
    kit_fail 'vendor/agent-skills Git-link commit is invalid'
  printf '%s\n' "$commit"
}

kit_reject_symlinks() {
  local root="$1"
  local label="$2"
  local symlinks=""

  [[ -e "$root" ]] || return 0
  [[ ! -L "$root" ]] || kit_fail "$label is a symbolic link: $root"
  symlinks="$(find "$root" -type l -print)"
  [[ -z "$symlinks" ]] || \
    kit_fail "$label contains symbolic links; first match: ${symlinks%%$'\n'*}"
}

kit_assert_upstream_integrity() {
  local root_dir="$1"
  local upstream_dir="$2"
  local expected_commit=""
  local actual_commit=""
  local status_output=""

  git -C "$upstream_dir" rev-parse --git-dir >/dev/null 2>&1 || \
    kit_fail 'agent-skills submodule is not initialized; run git submodule update --init --recursive'

  expected_commit="$(kit_gitlink_commit "$root_dir")"
  actual_commit="$(git -C "$upstream_dir" rev-parse HEAD)"
  [[ "$actual_commit" == "$expected_commit" ]] || \
    kit_fail "agent-skills checkout $actual_commit does not match pinned Git link $expected_commit"

  status_output="$(
    git -C "$upstream_dir" status \
      --porcelain=v1 \
      --untracked-files=all \
      --ignored=matching
  )"
  [[ -z "$status_output" ]] || \
    kit_fail "agent-skills submodule contains modified, untracked, or ignored files:\n$status_output"

  kit_reject_symlinks "$upstream_dir/skills" 'upstream Skills'
  kit_reject_symlinks "$upstream_dir/references" 'upstream references'
  kit_reject_symlinks "$upstream_dir/agents" 'upstream Personas'
}

kit_validate_managed_name() {
  local kind="$1"
  local name="$2"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
    kit_fail "invalid managed $kind name: $name"
}

kit_lock_reset() {
  lock_format=""
  lock_upstream_url=""
  lock_upstream_commit=""
  lock_upstream_version=""
  lock_skills=()
  lock_references=()
  lock_personas=()
  declare -gA lock_skill_set=()
  declare -gA lock_reference_set=()
  declare -gA lock_persona_set=()
}

kit_load_lock() {
  local lock_path="$1"
  local expected_url="$2"
  local line=""
  local key=""
  local value=""
  local line_number=0

  kit_lock_reset
  [[ -f "$lock_path" && ! -L "$lock_path" ]] || \
    kit_fail "managed lock is not a regular file: $lock_path"

  while IFS= read -r line || [[ -n "$line" ]]; do
    ((line_number += 1))
    [[ "$line" == *=* ]] || kit_fail "malformed lock line $line_number"
    key="${line%%=*}"
    value="${line#*=}"
    [[ -n "$key" && -n "$value" ]] || kit_fail "empty lock field at line $line_number"

    case "$key" in
      format)
        [[ -z "$lock_format" ]] || kit_fail 'duplicate lock format field'
        lock_format="$value"
        ;;
      upstream_url)
        [[ -z "$lock_upstream_url" ]] || kit_fail 'duplicate lock upstream_url field'
        lock_upstream_url="$value"
        ;;
      upstream_commit)
        [[ -z "$lock_upstream_commit" ]] || kit_fail 'duplicate lock upstream_commit field'
        lock_upstream_commit="$value"
        ;;
      upstream_version)
        [[ -z "$lock_upstream_version" ]] || kit_fail 'duplicate lock upstream_version field'
        lock_upstream_version="$value"
        ;;
      skill)
        kit_validate_managed_name skill "$value"
        [[ ! -v "lock_skill_set[$value]" ]] || kit_fail "duplicate lock Skill: $value"
        lock_skill_set["$value"]=1
        lock_skills+=("$value")
        ;;
      reference)
        kit_validate_managed_name reference "$value"
        [[ ! -v "lock_reference_set[$value]" ]] || \
          kit_fail "duplicate lock reference: $value"
        lock_reference_set["$value"]=1
        lock_references+=("$value")
        ;;
      persona)
        kit_validate_managed_name persona "$value"
        [[ ! -v "lock_persona_set[$value]" ]] || kit_fail "duplicate lock Persona: $value"
        lock_persona_set["$value"]=1
        lock_personas+=("$value")
        ;;
      *)
        kit_fail "unknown lock field at line $line_number: $key"
        ;;
    esac
  done < "$lock_path"

  [[ "$lock_format" == "1" ]] || kit_fail 'unsupported or missing lock format'
  [[ "$lock_upstream_url" == "$expected_url" ]] || \
    kit_fail 'lock upstream URL does not match this kit'
  [[ "$lock_upstream_commit" =~ ^[0-9a-f]{40}$ ]] || \
    kit_fail 'lock upstream commit is missing or invalid'
  [[ "$lock_upstream_version" =~ ^[A-Za-z0-9._-]+$ ]] || \
    kit_fail 'lock upstream version is missing or invalid'
  ((${#lock_skills[@]} > 0)) || kit_fail 'lock contains no Skills'
  ((${#lock_references[@]} > 0)) || kit_fail 'lock contains no references'
  ((${#lock_personas[@]} > 0)) || kit_fail 'lock contains no Personas'
}

kit_assert_safe_directory() {
  local path="$1"
  [[ ! -L "$path" ]] || kit_fail "managed directory is a symbolic link: $path"
  [[ ! -e "$path" || -d "$path" ]] || kit_fail "managed directory path is not a directory: $path"
}

kit_assert_safe_file() {
  local path="$1"
  [[ ! -L "$path" ]] || kit_fail "managed file is a symbolic link: $path"
  [[ ! -e "$path" || -f "$path" ]] || kit_fail "managed file path is not a regular file: $path"
}