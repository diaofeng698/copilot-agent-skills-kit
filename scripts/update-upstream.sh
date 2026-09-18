#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

readonly project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
readonly upstream="$project_root/vendor/agent-skills"
# shellcheck source=common.sh
source "$project_root/scripts/common.sh"
check_only=false
requested_ref=""

usage() {
  cat <<'EOF'
Usage: ./scripts/update-upstream.sh [--check] [REF]

Fetch upstream tags and compare or update the pinned agent-skills submodule.
Without REF, the newest stable numeric release tag (X.Y.Z) is selected.

Options:
  --check  Report the current and available revision without changing the pin.
  --help   Show this help.

Examples:
  ./scripts/update-upstream.sh --check
  ./scripts/update-upstream.sh
  ./scripts/update-upstream.sh 0.6.10
EOF
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
      kit_fail "unknown option: $1"
      ;;
    *)
      [[ -z "$requested_ref" ]] || kit_fail 'only one REF may be specified'
      requested_ref="$1"
      shift
      ;;
  esac
done

kit_require_commands git find sort sed
if ! git -C "$upstream" rev-parse --git-dir >/dev/null 2>&1; then
  printf 'Initializing the agent-skills submodule...\n'
  git -C "$project_root" submodule update --init --recursive
fi
kit_assert_upstream_integrity "$project_root" "$upstream"

configured_url="$(kit_configured_upstream_url "$project_root")"
actual_url="$(git -C "$upstream" config --get remote.origin.url)"
[[ "$actual_url" == "$configured_url" ]] || \
  kit_fail "agent-skills origin does not match .gitmodules: $actual_url"

printf 'Fetching agent-skills tags...\n'
git -C "$upstream" fetch --prune --tags origin

if [[ -z "$requested_ref" ]]; then
  while IFS= read -r candidate; do
    if [[ "$candidate" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      requested_ref="$candidate"
      break
    fi
  done < <(
    git -C "$upstream" ls-remote --tags --refs origin 'refs/tags/*' | \
      sed 's#^[^[:space:]]*[[:space:]]refs/tags/##' | \
      sort -Vr
  )
  [[ -n "$requested_ref" ]] || kit_fail 'no stable X.Y.Z release tags found upstream'
fi

if [[ "$requested_ref" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  remote_ref="$(
    git -C "$upstream" ls-remote --tags --refs origin "refs/tags/$requested_ref" | \
      awk 'NR == 1 { print $2 }'
  )"
  [[ "$remote_ref" == "refs/tags/$requested_ref" ]] || \
    kit_fail "release tag is not advertised by origin: $requested_ref"
fi

desired_commit="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream" rev-parse --verify "$requested_ref^{commit}" 2>/dev/null)" || \
  kit_fail "upstream ref does not exist: $requested_ref"
remote_contains="$(
  GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream" for-each-ref \
    --format='%(refname)' --contains "$desired_commit" refs/remotes/origin/ | \
    head -n 1
)"
[[ -n "$remote_contains" ]] || \
  kit_fail "upstream ref is not reachable from an origin branch: $requested_ref"
current_commit="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream" rev-parse HEAD)"
current_name="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream" describe --tags --always)"
desired_name="$(GIT_NO_REPLACE_OBJECTS=1 git -C "$upstream" describe --tags --always "$desired_commit")"

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
  kit_fail 'maintenance repository has uncommitted changes; commit or stash them first'

if [[ "$current_commit" == "$desired_commit" ]]; then
  printf 'No Git-link change required.\n'
  exit 0
fi

rollback() {
  git -C "$project_root" reset -q HEAD -- vendor/agent-skills \
    >/dev/null 2>&1 || true
  git -C "$upstream" checkout --detach "$current_commit" >/dev/null 2>&1 || true
}
rollback_and_exit() {
  local status="$1"
  trap - ERR INT TERM HUP
  rollback
  exit "$status"
}
trap 'rollback_and_exit $?' ERR
trap 'rollback_and_exit 130' INT
trap 'rollback_and_exit 143' TERM
trap 'rollback_and_exit 129' HUP

git -C "$upstream" checkout --detach "$desired_commit"
git -C "$project_root" add vendor/agent-skills
"$project_root/scripts/verify.sh" --staged
trap - ERR INT TERM HUP

printf '\nUpdated and staged the submodule Git link. Review before committing:\n'
printf '  git diff --cached --submodule=log -- vendor/agent-skills\n'
printf '  ./tests/run.sh\n'
printf '  ./scripts/verify.sh --staged\n'
printf '  git commit -m %q\n' "chore: update agent-skills to $desired_name"
