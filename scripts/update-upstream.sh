#!/usr/bin/env bash
set -Eeuo pipefail

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
check_only=false
requested_ref=""

usage() {
  cat <<'EOF'
Usage: ./scripts/update-upstream.sh [--check] [REF]

Fetch upstream tags and compare or update the pinned agent-skills submodule.
Without REF, the newest numeric release tag is selected.

Options:
  --check  Report the current and available revision without changing the pin.
  --help   Show this help.

Examples:
  ./scripts/update-upstream.sh --check
  ./scripts/update-upstream.sh
  ./scripts/update-upstream.sh 0.6.10
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

while (($# > 0)); do
  case "$1" in
    --check)
      check_only=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -* )
      fail "unknown option: $1"
      ;;
    *)
      [[ -z "$requested_ref" ]] || fail 'only one REF may be specified'
      requested_ref="$1"
      shift
      ;;
  esac
done

for command_name in git sort head; do
  command -v "$command_name" >/dev/null 2>&1 || \
    fail "required command not found: $command_name"
done

if ! git -C "$upstream" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Initializing the agent-skills submodule...\n'
  git -C "$project_root" submodule update --init --recursive
fi

[[ -z "$(git -C "$upstream" status --porcelain)" ]] || \
  fail 'agent-skills submodule has local modifications; preserve or discard them first'

printf 'Fetching agent-skills tags...\n'
git -C "$upstream" fetch --prune --tags origin

if [[ -z "$requested_ref" ]]; then
  requested_ref="$(git -C "$upstream" tag -l '[0-9]*' --sort=-v:refname | head -n 1)"
  [[ -n "$requested_ref" ]] || fail 'no numeric release tags found upstream'
fi

desired_commit="$(git -C "$upstream" rev-parse --verify "$requested_ref^{commit}" 2>/dev/null)" || \
  fail "upstream ref does not exist: $requested_ref"
current_commit="$(git -C "$upstream" rev-parse HEAD)"
current_name="$(git -C "$upstream" describe --tags --always)"
desired_name="$(git -C "$upstream" describe --tags --always "$desired_commit")"

printf 'Current: %s (%s)\n' "$current_name" "${current_commit:0:12}"
printf 'Target:  %s (%s)\n' "$desired_name" "${desired_commit:0:12}"

if [[ "$check_only" == true ]]; then
  if [[ "$current_commit" == "$desired_commit" ]]; then
    printf 'Status: already up to date\n'
  else
    printf 'Status: update available\n'
    git -C "$upstream" --no-pager log --oneline "$current_commit..$desired_commit"
  fi
  exit 0
fi

[[ -z "$(git -C "$project_root" status --porcelain --ignore-submodules=dirty)" ]] || \
  fail 'maintenance repository has uncommitted changes; commit or stash them first'

if [[ "$current_commit" == "$desired_commit" ]]; then
  printf 'No Git-link change required.\n'
  exit 0
fi

rollback() {
  git -C "$upstream" checkout --detach "$current_commit" >/dev/null 2>&1 || true
}
trap rollback ERR

git -C "$upstream" checkout --detach "$desired_commit"
"$project_root/scripts/verify.sh"
trap - ERR

printf '\nUpdated the submodule checkout. Review before committing:\n'
printf '  git diff --submodule=log -- vendor/agent-skills\n'
printf '  ./tests/run.sh\n'
printf '  git add vendor/agent-skills\n'
printf '  git commit -m "chore: update agent-skills to %s"\n' "$desired_name"
