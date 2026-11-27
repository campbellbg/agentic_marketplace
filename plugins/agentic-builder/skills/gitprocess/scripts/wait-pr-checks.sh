#!/usr/bin/env bash
# Wait on a PR in foreground chunks: for every CI check on its head commit, or
# (with --moved-from) for its head to move off a commit.
#
#   wait-pr-checks.sh --pr <n> --sha <head-sha> --since <epoch> [--wait <secs>] [--token <lock-token>]
#   wait-pr-checks.sh --pr <n> --moved-from <old-sha> [--wait <secs>] [--token <lock-token>]
#
#   --sha         the commit CI must have run on; checks for any other head are not counted
#   --since       when that commit was pushed; no checks 5 minutes after it is an error
#   --moved-from  wait until the PR head is no longer this commit (after gh pr update-branch);
#                 prints HEAD=<new-sha>
#   --token       if the merge lock is held, heartbeat it on every poll
#
# Green needs the same set of checks, all passed, for AGENTIC_CHECKS_SETTLE_SECS
# (default 60): a fast check can pass before a slower workflow has registered
# its own, so a first all-pass reading is not trusted on its own.
#
# Exit: 0 all passed (with --moved-from: the head moved) | 2 a check failed or was cancelled
#       3 still pending (call again) | 4 head moved off --sha | 5 no checks appeared within 5 minutes
#       6 merge lock lost | 1 error (bad arguments, or gh failed on 3 polls in a row)
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
pr=""; sha=""; since=""; moved_from=""; wait_secs=540; token=""
while [ $# -gt 0 ]; do
  case "$1" in
    --pr) pr="$2"; shift 2 ;;
    --sha) sha="$2"; shift 2 ;;
    --since) since="$2"; shift 2 ;;
    --moved-from) moved_from="$2"; shift 2 ;;
    --wait) wait_secs="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$pr" ] || { echo "needs --pr" >&2; exit 1; }
if [ -z "$moved_from" ]; then
  [ -n "$sha" ] && [ -n "$since" ] || { echo "needs --sha and --since, or --moved-from" >&2; exit 1; }
fi

# A failing gh call (network, rate limit) is retried on the next poll, up to 3 in a row.
gh_fails=0
gh_failed() {
  gh_fails=$(( gh_fails + 1 ))
  if [ "$gh_fails" -ge 3 ]; then echo "gh failed 3 polls in a row: $1" >&2; exit 1; fi
}

settle_secs="${AGENTIC_CHECKS_SETTLE_SECS:-60}"
deadline=$(( $(date +%s) + wait_secs ))
buckets=""
green_set=""; green_since=""   # the all-passed check names, and when that set was first seen
while :; do
  if [ -n "$token" ]; then "$here/merge-lock.sh" heartbeat --token "$token" || exit 6; fi

  if head=$(gh pr view "$pr" --json headRefOid -q .headRefOid 2>&1); then
    gh_fails=0
    if [ -n "$moved_from" ]; then
      if [ "$head" != "$moved_from" ]; then echo "HEAD=$head"; exit 0; fi
    else
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
        if grep -q '^pending' <<<"$buckets"; then
          green_set=""; green_since=""
        else
          names=$(cut -f2 <<<"$buckets" | sort)
          if [ "$names" != "$green_set" ]; then green_set=$names; green_since=$(date +%s); fi
          if [ $(( $(date +%s) - green_since )) -ge "$settle_secs" ]; then echo "$buckets"; exit 0; fi
        fi
      fi
    fi
  else
    gh_failed "$head"
  fi

  if [ "$(date +%s)" -ge "$deadline" ]; then
    if [ -n "$moved_from" ]; then
      echo "PR #$pr head is still $moved_from" >&2
    else
      if [ -n "$green_since" ]; then echo "all checks passed; waiting for them to settle" >&2
      else grep '^pending' <<<"$buckets" >&2 || echo "waiting for checks to appear" >&2; fi
    fi
    exit 3
  fi
  if [ -n "$moved_from" ]; then sleep 10; else sleep 30; fi
done
