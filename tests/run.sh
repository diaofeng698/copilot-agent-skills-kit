#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly installer="$project_root/scripts/install.sh"
readonly upstream="$project_root/vendor/agent-skills"
readonly original_upstream_commit="$(git -C "$upstream" rev-parse HEAD)"

temp_root="$(mktemp -d)"
cleanup() {
  rm -f -- "$upstream/.DS_Store" "$upstream/.agent-skills-kit-test-dirty"
  git -C "$upstream" checkout --detach "$original_upstream_commit" >/dev/null 2>&1 || true
  rm -rf -- "$temp_root"
}
trap cleanup EXIT

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

assert_fails() {
  if "$@" >/dev/null 2>&1; then
    fail "expected command to fail: $*"
  fi
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
"$project_root/scripts/verify.sh" --target "$fresh_target" >/dev/null

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

printf 'TEST: unowned same-name content is never overwritten\n'
collision_target="$temp_root/collision-target"
mkdir -p "$collision_target/.agents/skills/api-and-interface-design"
printf '%s\n' 'local same-name skill' > \
  "$collision_target/.agents/skills/api-and-interface-design/SKILL.md"
assert_fails "$installer" --target "$collision_target"
grep -Fqx 'local same-name skill' \
  "$collision_target/.agents/skills/api-and-interface-design/SKILL.md" || \
  fail 'same-name local skill was changed'

printf 'TEST: explicit managed-content force replaces collisions\n'
"$installer" --target "$collision_target" --force-managed >/dev/null
assert_same_tree \
  "$upstream/skills/api-and-interface-design" \
  "$collision_target/.agents/skills/api-and-interface-design"

printf 'TEST: symlinked managed paths are rejected without outside writes\n'
symlink_target="$temp_root/symlink-target"
outside_target="$temp_root/outside-target"
mkdir -p "$symlink_target/.agents" "$outside_target/api-and-interface-design"
printf '%s\n' 'outside sentinel' > "$outside_target/api-and-interface-design/sentinel"
ln -s "$outside_target" "$symlink_target/.agents/skills"
assert_fails "$installer" --target "$symlink_target"
grep -Fqx 'outside sentinel' "$outside_target/api-and-interface-design/sentinel" || \
  fail 'installer modified content outside the target through a symlink'

printf 'TEST: malformed ownership lock is rejected\n'
malformed_target="$temp_root/malformed-target"
mkdir -p "$malformed_target"
printf 'upstream_commit=%s\n' "$original_upstream_commit" > \
  "$malformed_target/.agent-skills-kit.lock"
assert_fails "$installer" --target "$malformed_target"
assert_fails "$project_root/scripts/verify.sh" --target "$malformed_target"

printf 'TEST: stale content previously owned by the kit is removed\n'
stale_target="$temp_root/stale-target"
mkdir -p "$stale_target"
"$installer" --target "$stale_target" >/dev/null
mkdir -p "$stale_target/.agents/skills/retired-upstream-skill"
printf '%s\n' 'retired' > "$stale_target/.agents/skills/retired-upstream-skill/SKILL.md"
printf '%s\n' 'skill=retired-upstream-skill' >> "$stale_target/.agent-skills-kit.lock"
"$installer" --target "$stale_target" >/dev/null
[[ ! -e "$stale_target/.agents/skills/retired-upstream-skill" ]] || \
  fail 'retired managed skill was not removed'

printf 'TEST: force-instructions is required to replace project instructions\n'
printf '%s\n' '# Existing project instructions' > \
  "$stale_target/.github/copilot-instructions.md"
"$installer" --target "$stale_target" >/dev/null
grep -Fqx '# Existing project instructions' \
  "$stale_target/.github/copilot-instructions.md" || \
  fail 'instructions changed without force'
"$installer" --target "$stale_target" --force-instructions >/dev/null
assert_same_file \
  "$project_root/templates/copilot-instructions.md" \
  "$stale_target/.github/copilot-instructions.md"

printf 'TEST: dirty and ignored upstream files block installation\n'
dirty_target="$temp_root/dirty-target"
mkdir -p "$dirty_target"
printf '%s\n' 'dirty' > "$upstream/.agent-skills-kit-test-dirty"
assert_fails "$installer" --target "$dirty_target"
rm -f -- "$upstream/.agent-skills-kit-test-dirty"
printf '%s\n' 'ignored' > "$upstream/.DS_Store"
assert_fails "$installer" --target "$dirty_target"
rm -f -- "$upstream/.DS_Store"

printf 'TEST: submodule checkout must match the pinned Git link\n'
previous_commit="$(git -C "$upstream" rev-parse "$original_upstream_commit^")"
git -C "$upstream" checkout --detach "$previous_commit" >/dev/null
assert_fails "$installer" --target "$dirty_target"
git -C "$upstream" checkout --detach "$original_upstream_commit" >/dev/null

printf 'TEST: invalid target fails without creating it\n'
missing_target="$temp_root/missing/target"
if "$installer" --target "$missing_target" >/dev/null 2>&1; then
  fail 'installer accepted a missing target directory'
fi
[[ ! -e "$missing_target" ]] || fail 'installer created an invalid target'

printf 'TEST: maintenance commands are available and repository verifies\n'
"$project_root/scripts/update-upstream.sh" --help >/dev/null
"$project_root/scripts/verify.sh" >/dev/null

printf 'PASS: all integration tests\n'
