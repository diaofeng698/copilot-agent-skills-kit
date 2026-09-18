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

kit_configured_upstream_url() {
  local root_dir="$1"
  local url=""

  url="$(
    git -C "$root_dir" config -f .gitmodules \
      --get submodule.vendor/agent-skills.url
  )"
  [[ -n "$url" ]] || kit_fail 'vendor/agent-skills URL is missing from .gitmodules'
  printf '%s\n' "$url"
}

kit_gitlink_commit() {
  local root_dir="$1"
  local source="${2:-head}"
  local mode=""
  local commit=""
  local stage=""
  local path=""

  case "$source" in
    head)
      read -r mode type commit path < <(
        GIT_NO_REPLACE_OBJECTS=1 git -C "$root_dir" ls-tree HEAD -- vendor/agent-skills
      )
      [[ "$mode" == "160000" && "$type" == "commit" && \
        "$path" == "vendor/agent-skills" ]] || \
        kit_fail 'vendor/agent-skills is not a committed Git submodule link'
      ;;
    index)
      read -r mode commit stage path < <(
        git -C "$root_dir" ls-files --stage -- vendor/agent-skills
      )
      [[ "$mode" == "160000" && "$stage" == "0" && \
        "$path" == "vendor/agent-skills" ]] || \
        kit_fail 'vendor/agent-skills is not a valid staged Git submodule link'
      ;;
    *)
      kit_fail "unknown Git-link source: $source"
      ;;
  esac
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
  local gitlink_source="${3:-head}"
  local expected_commit=""
  local actual_commit=""
  local configured_url=""
  local actual_url=""
  local special_index_entries=""
  local status_output=""

  git -C "$upstream_dir" rev-parse --git-dir >/dev/null 2>&1 || \
    kit_fail 'agent-skills submodule is not initialized; run git submodule update --init --recursive'

  configured_url="$(kit_configured_upstream_url "$root_dir")"
  actual_url="$(git -C "$upstream_dir" config --get remote.origin.url)"
  [[ "$actual_url" == "$configured_url" ]] || \
    kit_fail "agent-skills origin does not match .gitmodules: $actual_url"

  [[ -z "$(git -C "$upstream_dir" for-each-ref --format='%(refname)' refs/replace)" ]] || \
    kit_fail 'agent-skills submodule contains Git replacement refs'

  special_index_entries="$(
    git -C "$upstream_dir" ls-files -v -- skills references agents | \
      awk 'substr($0, 1, 1) ~ /[a-zS]/ { print; exit }'
  )"
  [[ -z "$special_index_entries" ]] || \
    kit_fail "agent-skills submodule contains special index flags: $special_index_entries"

  expected_commit="$(kit_gitlink_commit "$root_dir" "$gitlink_source")"
  actual_commit="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream_dir" rev-parse HEAD)"
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
  case "$kind" in
    skill|persona)
      [[ ${#name} -le 64 && "$name" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || \
        kit_fail "invalid managed $kind name: $name"
      ;;
    reference)
      [[ ${#name} -le 128 && "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || \
        kit_fail "invalid managed $kind name: $name"
      ;;
    *)
      kit_fail "unknown managed name kind: $kind"
      ;;
  esac
}

kit_hash_file() {
  local path="$1"
  sha256sum -- "$path" | awk '{print $1}'
}

kit_hash_directory() {
  local root="$1"
  local relative=""
  local mode=""
  local content_digest=""
  (
    cd -- "$root"
    while IFS= read -r -d '' relative; do
      relative="${relative#./}"
      if [[ -x "$relative" ]]; then
        mode=755
      else
        mode=644
      fi
      content_digest="$(kit_hash_file "$relative")"
      printf '%s\0%s\0%s\0' "$mode" "$relative" "$content_digest"
    done < <(find . -type f -print0 | sort -z)
  ) | sha256sum | awk '{print $1}'
}

kit_hash_git_file() {
  local repository="$1"
  local object_path="$2"
  GIT_NO_REPLACE_OBJECTS=1 git -C "$repository" show "$object_path" | \
    sha256sum | awk '{print $1}'
}

kit_hash_git_tree() {
  local repository="$1"
  local object_path="$2"
  local record=""
  local metadata=""
  local relative=""
  local mode=""
  local type=""
  local object_id=""
  local content_digest=""

  while IFS= read -r -d '' record; do
    metadata="${record%%$'\t'*}"
    relative="${record#*$'\t'}"
    read -r mode type object_id <<<"$metadata"
    [[ "$type" == "blob" && "$object_id" =~ ^[0-9a-f]{40}$ ]] || \
      kit_fail "unexpected Git tree entry: $record"
    case "$mode" in
      100644) mode=644 ;;
      100755) mode=755 ;;
      *) kit_fail "unsupported managed Git file mode: $mode" ;;
    esac
    content_digest="$(
      GIT_NO_REPLACE_OBJECTS=1 git -C "$repository" cat-file blob "$object_id" | \
        sha256sum | awk '{print $1}'
    )"
    printf '%s\0%s\0%s\0' "$mode" "$relative" "$content_digest"
  done < <(
    GIT_NO_REPLACE_OBJECTS=1 git -C "$repository" ls-tree -r -z "$object_path"
  ) | sha256sum | awk '{print $1}'
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
  declare -gA lock_skill_digest=()
  declare -gA lock_reference_digest=()
  declare -gA lock_persona_digest=()
}

kit_load_lock() {
  local lock_path="$1"
  local expected_url="$2"
  local line=""
  local key=""
  local value=""
  local name=""
  local digest=""
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
        [[ "$value" == *'|'* ]] || kit_fail "missing Skill digest at line $line_number"
        name="${value%%|*}"
        digest="${value#*|}"
        kit_validate_managed_name skill "$name"
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || kit_fail "invalid Skill digest: $name"
        [[ ! -v "lock_skill_set[$name]" ]] || kit_fail "duplicate lock Skill: $name"
        lock_skill_set["$name"]=1
        lock_skill_digest["$name"]="$digest"
        lock_skills+=("$name")
        ;;
      reference)
        [[ "$value" == *'|'* ]] || kit_fail "missing reference digest at line $line_number"
        name="${value%%|*}"
        digest="${value#*|}"
        kit_validate_managed_name reference "$name"
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || kit_fail "invalid reference digest: $name"
        [[ ! -v "lock_reference_set[$name]" ]] || \
          kit_fail "duplicate lock reference: $name"
        lock_reference_set["$name"]=1
        lock_reference_digest["$name"]="$digest"
        lock_references+=("$name")
        ;;
      persona)
        [[ "$value" == *'|'* ]] || kit_fail "missing Persona digest at line $line_number"
        name="${value%%|*}"
        digest="${value#*|}"
        kit_validate_managed_name persona "$name"
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || kit_fail "invalid Persona digest: $name"
        [[ ! -v "lock_persona_set[$name]" ]] || kit_fail "duplicate lock Persona: $name"
        lock_persona_set["$name"]=1
        lock_persona_digest["$name"]="$digest"
        lock_personas+=("$name")
        ;;
      *)
        kit_fail "unknown lock field at line $line_number: $key"
        ;;
    esac
  done < "$lock_path"

  [[ "$lock_format" == "2" ]] || kit_fail 'unsupported or missing lock format'
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

kit_validate_lock_manifest() {
  local upstream_dir="$1"
  local expected_skills=()
  local expected_references=()
  local expected_personas=()
  local name=""
  local expected_digest=""

  git -C "$upstream_dir" cat-file -e "$lock_upstream_commit^{commit}" 2>/dev/null || \
    kit_fail "lock refers to unavailable upstream commit: $lock_upstream_commit"

  while IFS= read -r -d '' name; do
    kit_validate_managed_name skill "$name"
    expected_skills+=("$name")
  done < <(
    GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream_dir" \
      ls-tree -d -z --name-only "$lock_upstream_commit:skills"
  )
  while IFS= read -r -d '' name; do
    kit_validate_managed_name reference "$name"
    expected_references+=("$name")
  done < <(
    GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream_dir" \
      ls-tree -z --name-only "$lock_upstream_commit:references"
  )
  while IFS= read -r -d '' name; do
    [[ "$name" == *.md ]] || continue
    name="${name%.md}"
    kit_validate_managed_name persona "$name"
    expected_personas+=("$name")
  done < <(
    GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream_dir" \
      ls-tree -z --name-only "$lock_upstream_commit:agents"
  )

  ((${#lock_skills[@]} == ${#expected_skills[@]})) || \
    kit_fail 'lock Skill manifest does not match its upstream commit'
  ((${#lock_references[@]} == ${#expected_references[@]})) || \
    kit_fail 'lock reference manifest does not match its upstream commit'
  ((${#lock_personas[@]} == ${#expected_personas[@]})) || \
    kit_fail 'lock Persona manifest does not match its upstream commit'

  for name in "${expected_skills[@]}"; do
    [[ -v "lock_skill_set[$name]" ]] || kit_fail "lock omits historical Skill: $name"
    expected_digest="$(
      kit_hash_git_tree "$upstream_dir" "$lock_upstream_commit:skills/$name"
    )"
    [[ "${lock_skill_digest[$name]}" == "$expected_digest" ]] || \
      kit_fail "lock has invalid historical Skill digest: $name"
  done
  for name in "${expected_references[@]}"; do
    [[ -v "lock_reference_set[$name]" ]] || \
      kit_fail "lock omits historical reference: $name"
    expected_digest="$(
      kit_hash_git_file "$upstream_dir" "$lock_upstream_commit:references/$name"
    )"
    [[ "${lock_reference_digest[$name]}" == "$expected_digest" ]] || \
      kit_fail "lock has invalid historical reference digest: $name"
  done
  for name in "${expected_personas[@]}"; do
    [[ -v "lock_persona_set[$name]" ]] || kit_fail "lock omits historical Persona: $name"
    expected_digest="$(
      kit_hash_git_file "$upstream_dir" "$lock_upstream_commit:agents/$name.md"
    )"
    [[ "${lock_persona_digest[$name]}" == "$expected_digest" ]] || \
      kit_fail "lock has invalid historical Persona digest: $name"
  done
}

kit_assert_safe_directory() {
  local path="$1"
  [[ ! -L "$path" ]] || kit_fail "managed directory is a symbolic link: $path"
  [[ ! -e "$path" || -d "$path" ]] || kit_fail "managed directory path is not a directory: $path"
}

kit_assert_safe_file() {
  local path="$1"
  local link_count=""
  [[ ! -L "$path" ]] || kit_fail "managed file is a symbolic link: $path"
  [[ ! -e "$path" || -f "$path" ]] || kit_fail "managed file path is not a regular file: $path"
  if [[ -e "$path" ]]; then
    link_count="$(stat -c %h -- "$path")"
    [[ "$link_count" == "1" ]] || kit_fail "managed file has multiple hard links: $path"
  fi
}