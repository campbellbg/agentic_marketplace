#!/usr/bin/env bash
# Local merge lock shared by every worktree of this repository.
# Only one build at a time may take a PR from "CI green" to "merged".
#
#   merge-lock.sh acquire --branch <b> --pr <n> --worktree <path> [--wait <secs>]
#       0  acquired (prints TOKEN=<token>)       3  still held by someone else after --wait
#       1  error
#   merge-lock.sh heartbeat --token <t>   0 ok | 6 lock lost (not the owner any more)
#   merge-lock.sh release   --token <t>   0 released (or already gone) | 6 not the owner
#   merge-lock.sh status                  prints the owner and heartbeat age, or "free"
#   merge-lock.sh break                   removes the lock whoever owns it (for the user)
#
# A lock is stale, and any waiter breaks it, when its heartbeat is older than
# AGENTIC_LOCK_STALE_SECS (default 600), its PR is merged or closed, or its
# worktree no longer exists. Breaking is an atomic rename, so two waiters can
# never both break it and then delete each other's fresh lock.
set -euo pipefail

STALE_SECS="${AGENTIC_LOCK_STALE_SECS:-600}"
common_dir=$(git rev-parse --path-format=absolute --git-common-dir)
LOCK="$common_dir/agentic-merge.lock"

die() { echo "merge-lock: $*" >&2; exit 1; }
now() { date +%s; }
field() { sed -n "s/^$1=//p" "$LOCK/owner" 2>/dev/null | head -1; }

heartbeat_age() {
  local hb
  hb=$(cat "$LOCK/heartbeat" 2>/dev/null || echo 0)
  echo $(( $(now) - hb ))
}

# Prints a reason and returns 0 if the current lock is stale.
stale_reason() {
  [ -d "$LOCK" ] || return 1
  local age pr wt state
  age=$(heartbeat_age)
  if [ "$age" -gt "$STALE_SECS" ]; then echo "no heartbeat for ${age}s"; return 0; fi
  wt=$(field worktree)
  if [ -n "$wt" ] && [ ! -d "$wt" ]; then echo "worktree $wt no longer exists"; return 0; fi
  pr=$(field pr)
  if [ -n "$pr" ] && [ "$pr" != "none" ]; then
    state=$(gh pr view "$pr" --json state -q .state 2>/dev/null || echo UNKNOWN)
    case "$state" in MERGED|CLOSED) echo "PR #$pr is $state"; return 0 ;; esac
  fi
  return 1
}

break_lock() {
  local reason="$1" grave="$LOCK.stale.$(now).$$"
  if mv "$LOCK" "$grave" 2>/dev/null; then
    echo "merge-lock: broke lock held by $(sed -n 's/^branch=//p' "$grave/owner" 2>/dev/null) (PR #$(sed -n 's/^pr=//p' "$grave/owner" 2>/dev/null)): $reason" >&2
    rm -rf "$grave"
  fi
}

try_take() {
  local branch="$1" pr="$2" wt="$3" token
  mkdir "$LOCK" 2>/dev/null || return 1
  token="$(now)-$$-$RANDOM$RANDOM"
  printf 'token=%s\nbranch=%s\npr=%s\nworktree=%s\nhost=%s\nacquired=%s\n' \
    "$token" "$branch" "$pr" "$wt" "$(hostname)" "$(date -u +%FT%TZ)" > "$LOCK/owner"
  now > "$LOCK/heartbeat"
  echo "TOKEN=$token"
}

cmd="${1:-}"; shift || true
branch=""; pr="none"; wt=""; wait_secs=540; token=""
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    --pr) pr="$2"; shift 2 ;;
    --worktree) wt="$2"; shift 2 ;;
    --wait) wait_secs="$2"; shift 2 ;;
    --token) token="$2"; shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

case "$cmd" in
  acquire)
    [ -n "$branch" ] || die "acquire needs --branch"
    deadline=$(( $(now) + wait_secs ))
    while :; do
      # Re-entry: a resumed build of the same branch takes its own lock back.
      if [ -d "$LOCK" ] && [ "$(field branch)" = "$branch" ]; then
        now > "$LOCK/heartbeat"
        sed -i "s/^pr=.*/pr=$pr/; s|^worktree=.*|worktree=$wt|" "$LOCK/owner"
        echo "TOKEN=$(field token)"; exit 0
      fi
      try_take "$branch" "$pr" "$wt" && exit 0
      if reason=$(stale_reason); then break_lock "$reason"; continue; fi
      if [ "$(now)" -ge "$deadline" ]; then
        echo "merge-lock: still held by $(field branch) (PR #$(field pr)), heartbeat $(heartbeat_age)s ago" >&2
        exit 3
      fi
      pause=$(( 15 + RANDOM % 16 )); left=$(( deadline - $(now) ))
      [ "$pause" -gt "$left" ] && pause=$left
      sleep "$pause"
    done ;;
  heartbeat)
    [ -n "$token" ] || die "heartbeat needs --token"
    [ "$(field token)" = "$token" ] || { echo "merge-lock: lock lost" >&2; exit 6; }
    now > "$LOCK/heartbeat" ;;
  release)
    [ -n "$token" ] || die "release needs --token"
    [ -d "$LOCK" ] || exit 0
    [ "$(field token)" = "$token" ] || { echo "merge-lock: not the owner; left in place" >&2; exit 6; }
    rm -rf "$LOCK" ;;
  status)
    if [ -d "$LOCK" ]; then
      cat "$LOCK/owner" | grep -v '^token='
      echo "heartbeat_age=$(heartbeat_age)s"
      if reason=$(stale_reason); then echo "stale=$reason"; fi
    else
      echo free
    fi ;;
  break)
    [ -d "$LOCK" ] && break_lock "broken by hand" || echo free ;;
  *) die "usage: merge-lock.sh acquire|heartbeat|release|status|break [...]" ;;
esac
