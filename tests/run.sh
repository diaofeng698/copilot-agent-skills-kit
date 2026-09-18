#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly installer="$project_root/scripts/install.sh"
readonly upstream="$project_root/vendor/agent-skills"

temp_root="$(mktemp -d)"
cleanup() {
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
assert_fails "$installer" --target "$preserved_target"
grep -Fq 'local corruption' \
  "$preserved_target/.agents/skills/api-and-interface-design/SKILL.md" || \
  fail 'installer changed a locally modified managed Skill without force'
"$installer" --target "$preserved_target" --force-managed >/dev/null
assert_same_tree \
  "$upstream/skills/api-and-interface-design" \
  "$preserved_target/.agents/skills/api-and-interface-design"
assert_file "$preserved_target/.agents/skills/local-only/SKILL.md"

printf 'TEST: reinstall repairs same-size same-mtime corruption\n'
managed_skill_file="$preserved_target/.agents/skills/api-and-interface-design/SKILL.md"
source_skill_file="$upstream/skills/api-and-interface-design/SKILL.md"
first_byte="$(LC_ALL=C head -c 1 "$managed_skill_file")"
replacement_byte=x
[[ "$first_byte" != x ]] || replacement_byte=y
printf '%s' "$replacement_byte" | dd of="$managed_skill_file" bs=1 count=1 conv=notrunc \
  status=none
touch -r "$source_skill_file" "$managed_skill_file"
[[ "$(stat -c %s "$managed_skill_file")" == "$(stat -c %s "$source_skill_file")" ]] || \
  fail 'test setup changed the managed file size'
assert_fails "$installer" --target "$preserved_target"
"$installer" --target "$preserved_target" --force-managed >/dev/null
assert_same_file "$source_skill_file" "$managed_skill_file"

printf 'TEST: managed Skill digest detects mode-only changes\n'
mode_skill_file="$preserved_target/.agents/skills/idea-refine/scripts/idea-refine.sh"
original_mode="$(stat -c %a "$mode_skill_file")"
chmod -x "$mode_skill_file"
assert_fails "$project_root/scripts/verify.sh" --target "$preserved_target"
chmod "$original_mode" "$mode_skill_file"
"$project_root/scripts/verify.sh" --target "$preserved_target" >/dev/null

printf 'TEST: directory digest has unambiguous path/content framing\n'
digest_tree_a="$temp_root/digest-tree-a"
digest_tree_b="$temp_root/digest-tree-b"
mkdir -p "$digest_tree_a" "$digest_tree_b"
printf '%s' 'bc' > "$digest_tree_a/a"
printf '%s' 'c' > "$digest_tree_b/ab"
source "$project_root/scripts/common.sh"
[[ "$(kit_hash_directory "$digest_tree_a")" != \
  "$(kit_hash_directory "$digest_tree_b")" ]] || \
  fail 'different directory trees produced the same managed digest'

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

skill_link_target="$temp_root/skill-link-target"
skill_link_outside="$temp_root/skill-link-outside"
mkdir -p "$skill_link_target/.agents/skills" "$skill_link_outside"
ln -s "$skill_link_outside" \
  "$skill_link_target/.agents/skills/api-and-interface-design"
assert_fails "$installer" --target "$skill_link_target"
[[ -z "$(find "$skill_link_outside" -mindepth 1 -print)" ]] || \
  fail 'installer wrote through a managed Skill symlink'

instructions_link_target="$temp_root/instructions-link-target"
mkdir -p "$instructions_link_target/.github"
ln -s "$temp_root/nonexistent-instructions" \
  "$instructions_link_target/.github/copilot-instructions.md"
assert_fails "$installer" --target "$instructions_link_target"
[[ ! -e "$temp_root/nonexistent-instructions" ]] || \
  fail 'installer followed a dangling instructions symlink'

trailing_link_real="$temp_root/trailing-link-real"
trailing_link_target="$temp_root/trailing-link-target"
mkdir -p "$trailing_link_real"
ln -s "$trailing_link_real" "$trailing_link_target"
assert_fails "$installer" --target "$trailing_link_target/"
[[ ! -e "$trailing_link_real/.agents" ]] || \
  fail 'installer accepted a target symlink with a trailing slash'

printf 'TEST: forced file replacement does not modify outside hard links\n'
hardlink_target="$temp_root/hardlink-target"
hardlink_outside="$temp_root/hardlink-outside"
mkdir -p "$hardlink_target/.agents/references" "$hardlink_target/.github"
printf '%s\n' 'outside reference sentinel' > "$hardlink_outside"
ln "$hardlink_outside" "$hardlink_target/.agents/references/security-checklist.md"
assert_fails "$installer" --target "$hardlink_target" --force-managed
grep -Fqx 'outside reference sentinel' "$hardlink_outside" || \
  fail 'forced reference replacement modified an outside hard link'
grep -Fqx 'outside reference sentinel' \
  "$hardlink_target/.agents/references/security-checklist.md" || \
  fail 'rejected hard-linked reference was changed'

instructions_hardlink_target="$temp_root/instructions-hardlink-target"
instructions_hardlink_outside="$temp_root/instructions-hardlink-outside"
mkdir -p "$instructions_hardlink_target/.github"
printf '%s\n' 'outside instructions sentinel' > "$instructions_hardlink_outside"
ln "$instructions_hardlink_outside" \
  "$instructions_hardlink_target/.github/copilot-instructions.md"
assert_fails "$installer" --target "$instructions_hardlink_target" \
  --force-instructions
grep -Fqx 'outside instructions sentinel' "$instructions_hardlink_outside" || \
  fail 'forced instructions replacement modified an outside hard link'

printf 'TEST: malformed ownership lock is rejected\n'
malformed_target="$temp_root/malformed-target"
mkdir -p "$malformed_target"
printf 'upstream_commit=%s\n' "$(git -C "$upstream" rev-parse HEAD)" > \
  "$malformed_target/.agent-skills-kit.lock"
assert_fails "$installer" --target "$malformed_target"
assert_fails "$project_root/scripts/verify.sh" --target "$malformed_target"

truncated_target="$temp_root/truncated-target"
mkdir -p "$truncated_target"
"$installer" --target "$truncated_target" >/dev/null
grep -v '^skill=api-and-interface-design|' \
  "$truncated_target/.agent-skills-kit.lock" > "$truncated_target/lock.tmp"
mv "$truncated_target/lock.tmp" "$truncated_target/.agent-skills-kit.lock"
assert_fails "$installer" --target "$truncated_target"
assert_fails "$project_root/scripts/verify.sh" --target "$truncated_target"

printf 'TEST: malicious historical Git names are rejected as data\n'
malicious_upstream="$temp_root/malicious-upstream"
malicious_marker="$temp_root/malicious-name-executed"
malicious_name='$(touch${IFS}${MALICIOUS_MARKER})'
git init -q "$malicious_upstream"
git -C "$malicious_upstream" config user.name 'Agent Skills Kit Test'
git -C "$malicious_upstream" config user.email 'test@example.invalid'
mkdir -p \
  "$malicious_upstream/skills/$malicious_name" \
  "$malicious_upstream/references" \
  "$malicious_upstream/agents"
printf '%s\n' 'malicious fixture' > \
  "$malicious_upstream/skills/$malicious_name/SKILL.md"
printf '%s\n' 'reference' > "$malicious_upstream/references/checklist.md"
printf '%s\n' 'persona' > "$malicious_upstream/agents/code-reviewer.md"
git -C "$malicious_upstream" add .
git -C "$malicious_upstream" commit -q -m 'fixture: malicious historical name'
malicious_commit="$(git -C "$malicious_upstream" rev-parse HEAD)"
if MALICIOUS_MARKER="$malicious_marker" bash -c '
  set -Eeuo pipefail
  source "$1"
  kit_lock_reset
  lock_upstream_commit="$2"
  lock_skills=(safe)
  lock_references=(checklist.md)
  lock_personas=(code-reviewer)
  lock_skill_set[safe]=1
  lock_reference_set[checklist.md]=1
  lock_persona_set[code-reviewer]=1
  kit_validate_lock_manifest "$3"
' _ "$project_root/scripts/common.sh" "$malicious_commit" "$malicious_upstream" \
  >/dev/null 2>&1; then
  fail 'malicious historical Git name was accepted'
fi
[[ ! -e "$malicious_marker" ]] || fail 'historical Git name executed a command'

printf 'TEST: force-instructions is required to replace project instructions\n'
stale_target="$temp_root/stale-target"
mkdir -p "$stale_target"
"$installer" --target "$stale_target" >/dev/null
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

printf 'TEST: invalid target fails without creating it\n'
missing_target="$temp_root/missing/target"
if "$installer" --target "$missing_target" >/dev/null 2>&1; then
  fail 'installer accepted a missing target directory'
fi
[[ ! -e "$missing_target" ]] || fail 'installer created an invalid target'

printf 'TEST: upstream update stages a valid pin and rolls back an invalid pin\n'
fixture_upstream="$temp_root/fixture-upstream"
fixture_kit="$temp_root/fixture-kit"
git init -q "$fixture_upstream"
git -C "$fixture_upstream" symbolic-ref HEAD refs/heads/main
git -C "$fixture_upstream" config user.name 'Agent Skills Kit Test'
git -C "$fixture_upstream" config user.email 'test@example.invalid'
mkdir -p \
  "$fixture_upstream/skills/example-skill" \
  "$fixture_upstream/skills/retired-skill" \
  "$fixture_upstream/references" \
  "$fixture_upstream/agents"
cat > "$fixture_upstream/skills/example-skill/SKILL.md" <<'EOF'
---
name: example-skill
description: Fixture skill
---
EOF
cat > "$fixture_upstream/skills/retired-skill/SKILL.md" <<'EOF'
---
name: retired-skill
description: Removed in the next fixture release
---
EOF
printf '%s\n' 'fixture reference' > "$fixture_upstream/references/checklist.md"
for name in code-reviewer test-engineer security-auditor web-performance-auditor; do
  cat > "$fixture_upstream/agents/$name.md" <<EOF
---
name: $name
description: Fixture $name persona
---

# $name
EOF
done
git -C "$fixture_upstream" add .
git -C "$fixture_upstream" commit -q -m 'fixture: version 1.0.0'
git -C "$fixture_upstream" tag 1.0.0
fixture_v1="$(git -C "$fixture_upstream" rev-parse HEAD)"
printf '%s\n' 'fixture reference v1.1' > "$fixture_upstream/references/checklist.md"
rm -rf "$fixture_upstream/skills/retired-skill"
git -C "$fixture_upstream" add .
git -C "$fixture_upstream" commit -q -m 'fixture: version 1.1.0'
git -C "$fixture_upstream" tag 1.1.0
fixture_v11="$(git -C "$fixture_upstream" rev-parse HEAD)"
printf '%s\n' '# Missing frontmatter' > \
  "$fixture_upstream/agents/web-performance-auditor.md"
git -C "$fixture_upstream" add .
git -C "$fixture_upstream" commit -q -m 'fixture: invalid version 2.0.0'
git -C "$fixture_upstream" tag 2.0.0
fixture_v2="$(git -C "$fixture_upstream" rev-parse HEAD)"

git init -q "$fixture_kit"
git -C "$fixture_kit" symbolic-ref HEAD refs/heads/main
git -C "$fixture_kit" config user.name 'Agent Skills Kit Test'
git -C "$fixture_kit" config user.email 'test@example.invalid'
mkdir -p "$fixture_kit/scripts" "$fixture_kit/tests" "$fixture_kit/templates" "$fixture_kit/docs"
cp "$project_root/scripts/common.sh" "$fixture_kit/scripts/common.sh"
cp "$project_root/scripts/install.sh" "$fixture_kit/scripts/install.sh"
cp "$project_root/scripts/update-upstream.sh" "$fixture_kit/scripts/update-upstream.sh"
cp "$project_root/scripts/verify.sh" "$fixture_kit/scripts/verify.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fixture_kit/tests/run.sh"
printf '%s\n' '# Fixture instructions' > "$fixture_kit/templates/copilot-instructions.md"
printf '%s\n' '# Fixture README' > "$fixture_kit/README.md"
printf '%s\n' '# Fixture spec' > "$fixture_kit/SPEC.md"
printf '%s\n' '# Fixture guide' > \
  "$fixture_kit/docs/GITHUB_COPILOT_AGENT_SKILLS_GUIDE_ZH.md"
git -C "$fixture_kit" -c protocol.file.allow=always submodule add -q \
  "$fixture_upstream" vendor/agent-skills
git -C "$fixture_kit/vendor/agent-skills" checkout -q --detach "$fixture_v1"
git -C "$fixture_kit" add .
git -C "$fixture_kit" commit -q -m 'fixture: pin 1.0.0'

printf 'TEST: dirty and mismatched fixture submodules block installation\n'
dirty_target="$temp_root/dirty-target"
mkdir -p "$dirty_target"
printf '%s\n' 'dirty' > "$fixture_kit/vendor/agent-skills/.agent-skills-kit-test-dirty"
assert_fails "$fixture_kit/scripts/install.sh" --target "$dirty_target"
rm -f -- "$fixture_kit/vendor/agent-skills/.agent-skills-kit-test-dirty"
printf '%s\n' 'ignored' > "$fixture_kit/vendor/agent-skills/.DS_Store"
assert_fails "$fixture_kit/scripts/install.sh" --target "$dirty_target"
rm -f -- "$fixture_kit/vendor/agent-skills/.DS_Store"
git -C "$fixture_kit/vendor/agent-skills" checkout -q --detach "$fixture_v11"
assert_fails "$fixture_kit/scripts/install.sh" --target "$dirty_target"
git -C "$fixture_kit/vendor/agent-skills" checkout -q --detach "$fixture_v1"

fixture_install_target="$temp_root/fixture-install-target"
mkdir -p "$fixture_install_target"
"$fixture_kit/scripts/install.sh" --target "$fixture_install_target" >/dev/null
assert_dir "$fixture_install_target/.agents/skills/retired-skill"

printf 'TEST: failed installation restores the prior target state\n'
rollback_target="$temp_root/rollback-target"
rollback_bin="$temp_root/rollback-bin"
mkdir -p "$rollback_target" "$rollback_bin"
cat > "$rollback_bin/rsync" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
real_rsync=/usr/bin/rsync
source_path="${@: -2:1}"
"$real_rsync" "$@"
if [[ "$source_path" == */example-skill/ ]]; then
  printf '%s\n' 'injected rsync failure' >&2
  exit 99
fi
EOF
chmod 0755 "$rollback_bin/rsync"
if PATH="$rollback_bin:$PATH" \
  "$fixture_kit/scripts/install.sh" --target "$rollback_target" >/dev/null 2>&1; then
  fail 'fault-injected installation unexpectedly succeeded'
fi
[[ ! -e "$rollback_target/.agents" ]] || fail 'failed installation left .agents content'
[[ ! -e "$rollback_target/.github" ]] || fail 'failed installation left .github content'
[[ ! -e "$rollback_target/.agent-skills-kit.lock" ]] || \
  fail 'failed installation left a lock file'

printf 'TEST: transaction signals restore a populated target byte-for-byte\n'
transaction_target="$temp_root/transaction-target"
transaction_baseline="$temp_root/transaction-baseline"
transaction_bin="$temp_root/transaction-bin"
mkdir -p "$transaction_target" "$transaction_bin"
"$fixture_kit/scripts/install.sh" --target "$transaction_target" >/dev/null
printf '%s\n' 'project-owned content' > "$transaction_target/.github/project-owned.md"
cp -a "$transaction_target" "$transaction_baseline"
cat > "$transaction_bin/mv" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
real_mv=/usr/bin/mv
count=0
[[ ! -f "$MV_STATE" ]] || read -r count < "$MV_STATE"
"$real_mv" "$@"
((count += 1))
printf '%s\n' "$count" > "$MV_STATE"
if [[ "$count" == "$MV_FAIL_AT" ]]; then
  kill -TERM "$PPID"
fi
EOF
chmod 0755 "$transaction_bin/mv"
for fail_at in 1 2 3 4 5 6; do
  rm -rf -- "$transaction_target"
  cp -a "$transaction_baseline" "$transaction_target"
  transaction_state="$temp_root/mv-state-$fail_at"
  if MV_STATE="$transaction_state" MV_FAIL_AT="$fail_at" \
    PATH="$transaction_bin:$PATH" \
    "$fixture_kit/scripts/install.sh" --target "$transaction_target" \
    >/dev/null 2>&1; then
    fail "signal after transaction move $fail_at returned success"
  fi
  assert_same_tree "$transaction_baseline" "$transaction_target"
done

"$fixture_kit/scripts/update-upstream.sh" --check 1.1.0 >/dev/null
"$fixture_kit/scripts/update-upstream.sh" 1.1.0 >/dev/null
[[ "$(git -C "$fixture_kit/vendor/agent-skills" rev-parse HEAD)" == "$fixture_v11" ]] || \
  fail 'valid update did not change the submodule checkout'
[[ "$(git -C "$fixture_kit" ls-files --stage vendor/agent-skills | awk '{print $2}')" == \
  "$fixture_v11" ]] || fail 'valid update did not stage the new Git link'
"$fixture_kit/scripts/verify.sh" --staged >/dev/null
git -C "$fixture_kit" commit -q -m 'fixture: pin 1.1.0'
"$fixture_kit/scripts/install.sh" --target "$fixture_install_target" >/dev/null
[[ ! -e "$fixture_install_target/.agents/skills/retired-skill" ]] || \
  fail 'retired Skill from the previous valid lock was not removed'
"$fixture_kit/scripts/verify.sh" --target "$fixture_install_target" >/dev/null

git -C "$fixture_kit/vendor/agent-skills" tag 9.9.9 "$fixture_v2"
"$fixture_kit/scripts/update-upstream.sh" --check > "$temp_root/update-check.out"
grep -Fq 'Target:  2.0.0' "$temp_root/update-check.out" || \
  fail 'automatic update selected a local-only tag'

assert_fails "$fixture_kit/scripts/update-upstream.sh" 2.0.0
[[ "$(git -C "$fixture_kit/vendor/agent-skills" rev-parse HEAD)" == "$fixture_v11" ]] || \
  fail 'failed update did not restore the previous submodule checkout'
[[ "$(git -C "$fixture_kit" ls-files --stage vendor/agent-skills | awk '{print $2}')" == \
  "$fixture_v11" ]] || fail 'failed update did not restore the previous Git link'

printf 'TEST: updater signals roll back and return failure\n'
git -C "$fixture_kit/vendor/agent-skills" tag -d 9.9.9 >/dev/null
update_signal_bin="$temp_root/update-signal-bin"
mkdir -p "$update_signal_bin"
cat > "$update_signal_bin/git" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
real_git=/usr/bin/git
"$real_git" "$@"
if [[ " $* " == *' checkout --detach '* && -n "${UPDATE_SIGNAL_MARKER:-}" && \
  ! -e "$UPDATE_SIGNAL_MARKER" ]]; then
  : > "$UPDATE_SIGNAL_MARKER"
  kill -TERM "$PPID"
fi
EOF
chmod 0755 "$update_signal_bin/git"
update_signal_marker="$temp_root/update-signal-marker"
if UPDATE_SIGNAL_MARKER="$update_signal_marker" PATH="$update_signal_bin:$PATH" \
  "$fixture_kit/scripts/update-upstream.sh" 2.0.0 >/dev/null 2>&1; then
  fail 'signal-interrupted upstream update returned success'
fi
[[ "$(git -C "$fixture_kit/vendor/agent-skills" rev-parse HEAD)" == "$fixture_v11" ]] || \
  fail 'signal-interrupted update did not restore the previous checkout'
[[ "$(git -C "$fixture_kit" ls-files --stage vendor/agent-skills | awk '{print $2}')" == \
  "$fixture_v11" ]] || fail 'signal-interrupted update did not restore the Git link'

printf 'TEST: maintenance commands are available and repository verifies\n'
"$project_root/scripts/update-upstream.sh" --help >/dev/null
"$project_root/scripts/verify.sh" >/dev/null

printf 'PASS: all integration tests\n'
