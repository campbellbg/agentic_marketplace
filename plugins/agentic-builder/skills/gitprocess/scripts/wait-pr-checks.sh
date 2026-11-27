#!/usr/bin/env bash
# Wait for every CI check on a PR's head commit, in foreground chunks.
#
#   wait-pr-checks.sh --pr <n> --sha <head-sha> --since <epoch> [--wait <secs>] [--token <lock-token>]
#
#   --sha    the commit CI must have run on; checks for any other head are not counted
#   --since  when that commit was pushed; no checks 5 minutes after it is an error
#   --token  if the merge lock is held, heartbeat it on every poll
#
# Exit: 0 all passed | 2 a check failed or was cancelled | 3 still pending (call again)
#       4 head moved off --sha | 5 no checks appeared within 5 minutes | 6 merge lock lost | 1 error
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
pr=""; sha=""; since=""; wait_secs=540; token=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) pr="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --wait) wait_secs="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$pr" ] && [ -n "$sha" ] && [ -n "$since" ] || { echo "needs --pr, --sha and --since" >&2; exit 1; }

deadline=$(( $(date +%s) + wait_secs ))
while :; do
  if [ -n "$token" ]; then "$here/merge-lock.sh" heartbeat --token "$token" || exit 6; fi

  head=$(gh pr view "$pr" --json headRefOid -q .headRefOid)
  [ "$head" = "$sha" ] || { echo "PR #$pr head is $head, not $sha" >&2; exit 4; }

  # Piped output is tab-separated: name, state (pass|fail|pending|skipping|cancel), ...
  # gh exits non-zero while checks are pending or failing, so ignore its status.
  buckets=$(gh pr checks "$pr" 2>/dev/null | awk -F'\t' 'NF>=2 {print $2 "\t" $1}' || true)
  if [ -z "$buckets" ]; then
    if [ $(( $(date +%s) - since )) -gt 300 ]; then echo "no checks on PR #$pr after 5 minutes" >&2; exit 5; fi
  else
    if grep -qE '^(fail|cancel)' <<<"$buckets"; then
      grep -E '^(fail|cancel)' <<<"$buckets" >&2; exit 2
    fi
    if ! grep -q '^pending' <<<"$buckets"; then echo "$buckets"; exit 0; fi
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    grep '^pending' <<<"$buckets" >&2 || echo "waiting for checks to appear" >&2
    exit 3
  fi
  sleep 30
done
