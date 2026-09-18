#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
target=""

usage() {
  cat <<'EOF'
Usage: ./scripts/verify.sh [--target PATH]

Verify this kit. With --target, also verify all managed content installed in an
existing target project.
EOF
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --target)
      (($# >= 2)) || fail '--target requires a path'
      target="$2"
      shift 2
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

for script in "$project_root"/scripts/*.sh "$project_root"/tests/*.sh; do
  [[ -f "$script" ]] || continue
  bash -n "$script" || fail "invalid shell syntax: $script"
done

submodule_status="$(git -C "$project_root" submodule status -- vendor/agent-skills)"
case "${submodule_status:0:1}" in
  -) fail 'agent-skills submodule is not initialized' ;;
  +) fail 'agent-skills checkout does not match the pinned Git link' ;;
  U) fail 'agent-skills submodule has unresolved conflicts' ;;
esac

[[ -z "$(git -C "$upstream" status --porcelain)" ]] || \
  fail 'agent-skills submodule contains local modifications'
[[ -d "$upstream/skills" ]] || fail 'upstream skills directory is missing'
[[ -d "$upstream/references" ]] || fail 'upstream references directory is missing'
[[ -f "$project_root/templates/copilot-instructions.md" ]] || \
  fail 'Copilot instructions template is missing'

skill_count=0
for skill_dir in "$upstream"/skills/*; do
  [[ -d "$skill_dir" ]] || continue
  skill_name="${skill_dir##*/}"
  skill_file="$skill_dir/SKILL.md"
  [[ -f "$skill_file" ]] || fail "missing SKILL.md for $skill_name"
  declared_name="$(awk '/^name:[[:space:]]*/ { sub(/^name:[[:space:]]*/, ""); print; exit }' "$skill_file")"
  [[ "$declared_name" == "$skill_name" ]] || \
    fail "skill directory/frontmatter mismatch: $skill_name != $declared_name"
  ((skill_count += 1))
done
((skill_count > 0)) || fail 'no upstream skills found'

for persona_name in \
  code-reviewer \
  test-engineer \
  security-auditor \
  web-performance-auditor
do
  [[ -f "$upstream/agents/$persona_name.md" ]] || \
    fail "required upstream persona is missing: $persona_name"
done

if [[ -n "$target" ]]; then
  [[ -d "$target" ]] || fail "target directory does not exist: $target"
  target="$(cd -- "$target" && pwd -P)"

  for skill_dir in "$upstream"/skills/*; do
    [[ -d "$skill_dir" ]] || continue
    skill_name="${skill_dir##*/}"
    diff -qr "$skill_dir" "$target/.agents/skills/$skill_name" >/dev/null || \
      fail "installed skill differs: $skill_name"
  done

  for reference in "$upstream"/references/*; do
    [[ -e "$reference" ]] || continue
    reference_name="${reference##*/}"
    diff -qr "$reference" "$target/.agents/references/$reference_name" >/dev/null || \
      fail "installed reference differs: $reference_name"
  done

  for persona_file in "$upstream"/agents/*.md; do
    [[ -f "$persona_file" ]] || continue
    persona_name="${persona_file##*/}"
    persona_name="${persona_name%.md}"
    cmp -s "$persona_file" "$target/.github/agents/$persona_name.agent.md" || \
      fail "installed persona differs: $persona_name"
  done

  lock_file="$target/.agent-skills-kit.lock"
  [[ -f "$lock_file" ]] || fail 'target lock file is missing'
  grep -Fqx "upstream_commit=$(git -C "$upstream" rev-parse HEAD)" "$lock_file" || \
    fail 'target lock does not match the pinned upstream commit'
fi

printf 'PASS: verified %s upstream skills at %s\n' \
  "$skill_count" "$(git -C "$upstream" rev-parse --short HEAD)"
if [[ -n "$target" ]]; then
  printf 'PASS: verified managed installation in %s\n' "$target"
fi
