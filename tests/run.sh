#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly installer="$project_root/scripts/install.sh"
readonly upstream="$project_root/vendor/agent-skills"

temp_root="$(mktemp -d)"
trap 'rm -rf -- "$temp_root"' EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file() {
  [[ -f "$1" ]] || fail "expected file: $1"
}

assert_dir() {
  [[ -d "$1" ]] || fail "expected directory: $1"
}

assert_same_file() {
  cmp -s "$1" "$2" || fail "files differ: $1 and $2"
}

assert_same_tree() {
  diff -qr "$1" "$2" >/dev/null || fail "directories differ: $1 and $2"
}

printf 'TEST: dry-run does not modify target\n'
dry_target="$temp_root/dry-run-target"
mkdir -p "$dry_target"
"$installer" --target "$dry_target" --dry-run >/dev/null
[[ ! -e "$dry_target/.agents" ]] || fail 'dry-run created .agents'
[[ ! -e "$dry_target/.github" ]] || fail 'dry-run created .github'
[[ ! -e "$dry_target/.agent-skills-kit.lock" ]] || fail 'dry-run created lock file'

printf 'TEST: fresh install copies all managed content\n'
fresh_target="$temp_root/fresh-target"
mkdir -p "$fresh_target"
"$installer" --target "$fresh_target" >/dev/null

assert_same_tree "$upstream/skills" "$fresh_target/.agents/skills"
assert_same_tree "$upstream/references" "$fresh_target/.agents/references"
assert_file "$fresh_target/.github/copilot-instructions.md"
assert_file "$fresh_target/.agent-skills-kit.lock"

grep -Fq "upstream_commit=$(git -C "$upstream" rev-parse HEAD)" \
  "$fresh_target/.agent-skills-kit.lock" || fail 'lock file has wrong upstream commit'

for persona_file in "$upstream"/agents/*.md; do
  persona_name="${persona_file##*/}"
  persona_name="${persona_name%.md}"
  assert_same_file "$persona_file" "$fresh_target/.github/agents/$persona_name.agent.md"
done

printf 'TEST: reinstall repairs managed files and preserves project files\n'
preserved_target="$temp_root/preserved-target"
mkdir -p \
  "$preserved_target/.agents/skills/local-only" \
  "$preserved_target/.github"
printf '%s\n' '# Local-only skill' > "$preserved_target/.agents/skills/local-only/SKILL.md"
printf '%s\n' '# Existing project instructions' > "$preserved_target/.github/copilot-instructions.md"

"$installer" --target "$preserved_target" >/dev/null
assert_file "$preserved_target/.agents/skills/local-only/SKILL.md"
grep -Fq '# Existing project instructions' \
  "$preserved_target/.github/copilot-instructions.md" || fail 'existing instructions were overwritten'

printf '%s\n' 'local corruption' >> \
  "$preserved_target/.agents/skills/api-and-interface-design/SKILL.md"
"$installer" --target "$preserved_target" >/dev/null
assert_same_tree \
  "$upstream/skills/api-and-interface-design" \
  "$preserved_target/.agents/skills/api-and-interface-design"
assert_file "$preserved_target/.agents/skills/local-only/SKILL.md"

printf 'TEST: invalid target fails without creating it\n'
missing_target="$temp_root/missing/target"
if "$installer" --target "$missing_target" >/dev/null 2>&1; then
  fail 'installer accepted a missing target directory'
fi
[[ ! -e "$missing_target" ]] || fail 'installer created an invalid target'

printf 'PASS: all installer integration tests\n'
