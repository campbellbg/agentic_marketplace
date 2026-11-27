#!/usr/bin/env bash
# Create or reuse a feature's worktree at <main-checkout>/.claude/worktrees/<branch>,
# move the feature's uncommitted requirement directory (and any --carry paths)
# into it, and install dependencies. Run from the main checkout or any worktree.
#
#   prepare-worktree.sh --branch <b> --remote <r> --base <base>
#                       [--feat <feat> --req-dir <dir>] [--carry <path>]...
#
# Moving means: copy the uncommitted files into the worktree, then return the
# main checkout's copy to its committed state (new files are removed there).
#
# Prints WORKTREE=<absolute path> on success.
# Exit: 0 ok | 1 error | 4 .claude/worktrees/ is not git-ignored
#       5 a path to move has uncommitted changes in both the main checkout and the worktree
set -euo pipefail

branch=""; remote=""; base=""; feat=""; req_dir=""; carry=()
while [ $# -gt 0 ]; do
  case "$1" in
    --branch) branch="$2"; shift 2 ;;
    --remote) remote="$2"; shift 2 ;;
    --base) base="$2"; shift 2 ;;
    --feat) feat="$2"; shift 2 ;;
    --req-dir) req_dir="${2%/}"; shift 2 ;;
    --carry) carry+=("${2%/}"); shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done
[ -n "$branch" ] && [ -n "$remote" ] && [ -n "$base" ] || { echo "needs --branch, --remote and --base" >&2; exit 1; }

main=$(git worktree list --porcelain | sed -n '1s/^worktree //p')
wt="$main/.claude/worktrees/$branch"
cd "$main"

git check-ignore -q .claude/worktrees/ || { echo ".claude/worktrees/ is not in .gitignore" >&2; exit 4; }

fetch() { git fetch --quiet "$remote" || { sleep 5; git fetch --quiet "$remote"; }; }

if git worktree list --porcelain | grep -qxF "worktree $wt"; then
  echo "reusing worktree $wt" >&2
else
  fetch
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    git worktree add "$wt" "$branch" >&2
  elif git show-ref --verify --quiet "refs/remotes/$remote/$branch"; then
    git worktree add --track -b "$branch" "$wt" "$remote/$branch" >&2
  else
    git worktree add --no-track -b "$branch" "$wt" "$remote/$base" >&2
  fi
fi

# Move uncommitted files out of the main checkout into the worktree.
move() {
  local path="$1"
  [ -n "$(git status --porcelain -uall -- "$path")" ] || return 0
  if [ -n "$(git -C "$wt" status --porcelain -uall -- "$path")" ]; then
    echo "$path has uncommitted changes in both $main and $wt; not moving it" >&2; exit 5
  fi
  if [ -d "$path" ]; then
    mkdir -p "$wt/$path"; cp -a "$path/." "$wt/$path/"
  else
    mkdir -p "$wt/$(dirname "$path")"; cp -a "$path" "$wt/$path"
  fi
  git checkout -- "$path" 2>/dev/null || true   # tracked files back to their committed state
  git clean -fdq -- "$path"                      # new files removed (now in the worktree)
  echo "moved $path into $wt" >&2
}
[ -n "$feat" ] && move "$req_dir/$feat"
for path in "${carry[@]}"; do move "$path"; done

# Install dependencies once per worktree.
cd "$wt"
if [ -f package.json ] && [ ! -d node_modules ]; then
  if   [ -f pnpm-lock.yaml ]; then pnpm install --frozen-lockfile >&2
  elif [ -f yarn.lock ];      then yarn install --frozen-lockfile >&2
  elif [ -f package-lock.json ]; then npm ci >&2
  else npm install >&2
  fi
fi

echo "WORKTREE=$wt"
