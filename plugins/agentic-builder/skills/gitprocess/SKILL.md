---
name: gitprocess
description: Use this skill whenever there is a need to create/make a feature branch or worktree, commit or push work, create/open a PR, merge to the base branch (main/master), or ship a finished feature. The request can come from the user or from an agent loop (the `agentic-build` command calls it). It derives branch names, commit messages and PR text from the feature's requirement, so it runs without asking for input. It enforces a strict git workflow. It never commits or pushes to the base branch directly, builds each feature in its own git worktree, and merges only when the PR's CI checks are green on the latest base branch, holding a local merge lock so parallel builds merge one at a time. Trigger on phrases like "create a feature branch", "commit this", "push my work", "create a PR", "merge to master", "merge to main", "merge this in", "ship feat_0002".
---

# Branch, PR, and Merge Workflow

There are five actions. Actions 1-4 can be asked for on their own. Action 5
(Ship) runs 2 -> 3 -> 4 in one go and is what the build loop uses. Work out
names and messages yourself from the rules below; do not ask the user for them.
Tell the user what you chose in your report.

**Golden rule across all actions: never commit, push, or merge while on
the base branch.** Always check the current branch first with
`git branch --show-current`.

## Worktrees and scripts

Each feature is built in its own git worktree, so several builds can run at
once. The **main checkout** (the first entry of `git worktree list`) stays on
`<base-branch>`: builds start there and `/agentic-requirement` writes drafts
there, but nothing is built or committed in it. A feature's worktree is
`<main-checkout>/.claude/worktrees/<branch>`, and `.claude/worktrees/` must be
git-ignored.

The scripts are in this skill's `scripts/` directory (its base directory is
shown when the skill loads). Run them with Bash and read their exit codes:

- `prepare-worktree.sh`: creates or reuses a feature's worktree (action 1).
- `wait-pr-checks.sh`: waits for a PR's checks in foreground chunks (action 4).
- `merge-lock.sh`: the local merge lock (action 4). The lock lives in the git
  common directory, so every worktree shares it. It only coordinates builds on
  this machine.

## Repo settings

Read the Requirements dir, Git remote, Base branch, Hosting pattern and Secrets
settings as the `agentic-conventions` skill describes (load it), with its
defaults. Work them out once at the start and tell the user which you used.
PRs get a preview environment and merges deploy production (see the
`deploy-environments` skill).

## Deriving names and messages

The feature is the `<requirements-dir>/<feat>/` directory being worked on, e.g.
`feat_0002`. Its `requirement.md` starts with a heading `# <feat>: <Title>`
and has a `## Summary` section.

- **Branch name:** `<feat>-<title-slug>`, e.g. `# feat_0002: Dark Mode Toggle`
  -> `feat_0002-dark-mode-toggle`. To make the slug:
  - lowercase the title;
  - replace every run of characters other than `a-z0-9` with `-`;
  - trim leading and trailing `-`;
  - cut it to 40 characters.

  Only `a-z`, `0-9`, `_` and `-` may appear, because CI pipelines often use the
  branch name in paths or environment names.
- **Commit subject:** `<feat>: <what the change does>`, imperative, at most 72
  characters, written from the requirement's Summary and title (e.g.
  `feat_0002: add a dark mode toggle to the header`). Match the existing
  history (`git log --oneline -10`).
- **Iteration commit subject:** the build loop commits each iteration of
  `requirement-decomposed.md` separately, as
  `<feat>: iteration <k>/<n> - <what it does>`, at most 72 characters. If the
  round limit stopped the iteration before its Definition of Done was met, use
  `<feat>: WIP iteration <k>/<n> - <what it does>`. The build loop reads these
  subjects to find where to resume, so keep the format exact.
- **Commit body**, in this order:
  - 1-4 short lines on what changed, from the diff (`git diff --cached --stat`
    and the diff itself);
  - if a consolidated review exists, a line
    `Review: <requirements-dir>/<feat>/review_consolidated_<NNN>.md - <its Summary line>`;
  - a blank line, then the commit attribution trailer from the system reminder
    (`Co-Authored-By: ...`).
- **PR title:** the commit subject for the feature as a whole, not an iteration's.
  It becomes the squash commit on `<base-branch>`.
- **PR body**, in this order:
  - `## Summary`: 2-3 lines from the requirement;
  - `## Changes`: bullets from `git diff <remote>/<base-branch>...HEAD --stat`
    and `git log`, listing the iterations;
  - `## Review`: the latest consolidated review's Summary line and path;
  - the PR attribution line from the system reminder.

**No feature directory** (e.g. the user asks to commit tooling or docs
changes): derive the branch name as `chore-<slug>` and the commit subject from
the diff itself, in the same styles. Only ask the user if the diff is too
mixed to describe in one subject line.

## 1. Create a feature worktree

- **Check the environment is committed** (feature branches only). In the main
  checkout, `git status --porcelain -- CLAUDE.md` must be empty: a worktree
  starts from `<remote>/<base-branch>`, so uncommitted settings would not reach
  it. If it is not empty, stop and tell the caller. (The build loop offers to
  ship it as a `chore-` PR first.)
- **`chore-` branches** (no feature directory) take the uncommitted files they
  are for with them: pass each with `--carry <path>` (e.g. `--carry CLAUDE.md
  --carry .gitignore`). If the main checkout has other uncommitted files apart
  from requirement drafts, ask which belong to the chore.
- If `<base-branch>` does not exist on `<remote>`
  (`git ls-remote --heads <remote> <base-branch>` is empty), stop and tell the
  user. The base branch needs an initial commit pushed first, and this skill
  never commits to it.
- If the session is already in this feature's worktree
  (`git branch --show-current` is `<branch>` and
  `git rev-parse --show-toplevel` ends in `.claude/worktrees/<branch>`), stop
  here: it is ready.
- Otherwise run:
  ```bash
  <scripts>/prepare-worktree.sh --branch <branch> --remote <remote> \
    --base <base-branch> --feat <feat> --req-dir <requirements-dir>
  ```
  (omit `--feat` and `--req-dir` with no feature directory). It fetches, then
  reuses the worktree if it exists, or adds one for the existing local or
  remote branch, or for a new branch from `<remote>/<base-branch>`. It moves
  this feature's uncommitted requirement directory from the main checkout into
  the worktree (other features' drafts stay where they are) and installs
  dependencies. It prints `WORKTREE=<path>`. Give it a Bash timeout of 600000 ms.
  - Exit `4`: `.claude/worktrees/` is not git-ignored. Stop and tell the user
    to add it to `.gitignore` and commit it (the `agentic-build-environment`
    skill adds it).
  - Exit `5`: a path to move has changes in both places. Stop and tell the
    user; do not choose for them.
  - Any other failure: stop and show the error.
- **Enter it** with the EnterWorktree tool, `path: <WORKTREE>` (load it with
  ToolSearch if it is deferred). From here on every command, and every
  subagent started afterwards, works in the worktree. Report its path, and
  which requirement files were moved.
  - **No EnterWorktree** (some headless runs do not have it): `cd <WORKTREE>`
    in Bash instead and say so. Subagents may then start in the main checkout,
    so the build loop passes `<WORKTREE>` to every agent, and the agents move
    into it themselves (see the conventions' Worktrees section).

## 2. Commit and/or push

- If on `<base-branch>`, **stop**. Run action 1 first if a feature is known;
  otherwise tell the user.
- Look before staging with `git status --porcelain`. **Stop and tell the user**
  if anything looks like a secret or credential:
  - `.env*`, `*.pem`, `*.key` or `*credentials*` files;
  - cloud or API keys in a diff;
  - anything under the Secrets setting's directory (`secrets/` by default).

  Also stop if a large or binary file appears that you did not expect, or if that
  secrets directory exists and `git check-ignore -q secrets/` says it is not
  ignored. Other features' requirement directories are not a reason to stop:
  they are never staged. Otherwise:
  ```bash
  # everything except other features' requirement dirs, then this feature's dir
  # (<req-dir> is the Requirements dir without its trailing /, e.g. requirements)
  git add -A -- . ':(exclude)<req-dir>/feat_*'
  git add -A -- '<req-dir>/<feat>/'
  git commit -F <message-file>     # subject, body, trailer as derived above
  git push -u <remote> <current-branch>
  ```
  With no feature directory (a `chore-` branch), run only the first `git add`,
  so no requirement drafts are swept in. Check what was staged
  (`git diff --cached --stat`) before committing.
  Write the message to a file in the scratchpad directory and pass it with
  `-F`, so quotes and newlines survive.
- If only a commit was asked for, stop after the commit. If there is nothing
  to commit, say so and continue with the push if one was asked for.

## 3. Create a PR

- If on `<base-branch>`, **stop** and tell the user.
- Make sure everything is committed and pushed (`git status`; run action 2 if
  not).
- If an open PR already exists for the branch
  (`gh pr list --head <current-branch> --state open`), report it instead of
  creating another.
- Otherwise, record the base the PR's CI will test, then open it:
  ```bash
  git fetch <remote>
  git rev-parse <remote>/<base-branch> > "$(git rev-parse --git-dir)/agentic-ci-base"
  gh pr create --base <base-branch> --head <current-branch> --title "<title>" --body-file <body-file>
  ```
  Do not merge `<base-branch>` into the branch first: the PR workflows check out
  GitHub's merge of the branch with the latest `<base-branch>`, so the first CI
  run already tests the feature on top of it. Record the base again the same
  way before every later push to a branch that has an open PR.
- Report the PR URL.

## 4. Merge to the base branch (on green CI, under the merge lock)

Merging needs no confirmation from the user, but **only when every CI check on
the PR has passed, on a run that tested the latest `<base-branch>`**. Branch
protection may require only some checks, so this skill always waits for every
check on the PR; never skip this. If GitHub refuses a merge, stop and show the
error. Do not try to get round the rules.

Never merge `<base-branch>` into the branch locally: local tests cannot reach
AWS, and the PR's preview environment tests it properly.

- If on `<base-branch>`, **stop**: you need the feature branch with the PR.
- Find the open PR: `gh pr list --head <current-branch> --state open`. If
  there is none, run action 3 first.

**a. Wait for CI (no lock).** Take the head commit
(`gh pr view <number> --json headRefOid -q .headRefOid`) and when it was pushed
(now, if you just pushed; otherwise its commit time), then run in the
foreground, with a Bash timeout of 600000 ms:
```bash
<scripts>/wait-pr-checks.sh --pr <number> --sha <head> --since <epoch>
```
Exit `3` means still pending: run it again, up to 60 minutes in all for one
commit, then stop and report the checks still pending. Exit `0`: all passed, go
to b. Exit `2`: go to **Red**. Exit `4` (head moved): start a again with the new
head. Exit `5` (no checks appeared): **stop and tell the user**; do not merge a
PR with no checks. Exit `1` (the script already retried `gh` itself): run it
once more, then stop and show the error.

**b. Acquire the merge lock.** In the foreground, timeout 600000 ms:
```bash
<scripts>/merge-lock.sh acquire --branch <branch> --pr <number> --worktree "$(git rev-parse --show-toplevel)"
```
It prints `TOKEN=<token>`; keep it. Exit `3` means another feature holds the
lock: run it again, up to 2 hours in all, then stop and report who holds it
(`merge-lock.sh status`). It breaks a stale lock itself (no heartbeat for 10
minutes, its PR merged or closed, or its worktree gone) and says so on stderr:
report it. **From here on, every way out of action 4 releases the lock
first** (`merge-lock.sh release --token <token>`): green, red, conflict,
refusal or error. If release exits `6`, another build already broke the lock
(normally because this PR had merged): report it, but it is not an error.

**c. Is the base current?** `git fetch <remote>`, then compare
`git rev-parse <remote>/<base-branch>` with the recorded
`$(git rev-parse --git-dir)/agentic-ci-base` (missing counts as different, e.g.
an earlier run opened the PR).
- **Same:** the green run tested this base. Go to d.
- **Different, but the head already contains it**
  (`git merge-base --is-ancestor <remote>/<base-branch> <head>` succeeds):
  GitHub's merge of the head with this base is the head itself, so the green
  run tested it. Record the base (as in action 3) and go to d.
- **Different:** another merge moved `<base-branch>` after the run started.
  Record the new base (as in action 3), then have GitHub merge it into the PR
  branch: `gh pr update-branch <number>`. If it fails because of a conflict, go
  to **Conflict**. Wait for the PR's head to move, then for CI on the new head,
  passing `--token <token>` both times so the lock's heartbeat stays fresh
  (foreground, timeout 600000 ms):
  ```bash
  <scripts>/wait-pr-checks.sh --pr <number> --moved-from <head> --token <token>   # prints HEAD=<new-head>
  <scripts>/wait-pr-checks.sh --pr <number> --sha <new-head> --since <epoch> --token <token>
  ```
  For `--moved-from`, exit `3` means the head has not moved yet: run it again,
  up to 10 minutes in all, then stop and report. Both share the exit codes in
  a, plus `6`: the lock was lost (another build broke it as stale). Stop and
  report; do not merge. Green: take the new head as `<head>` and go back to c.

**d. Merge.** First confirm the lock is still yours; if this exits `6`, another
build broke it: stop and report, do not merge.
```bash
<scripts>/merge-lock.sh heartbeat --token <token>
gh pr merge <number> --squash --match-head-commit <head>
git push <remote> --delete <branch>
```
Do not use `--delete-branch`: it tries to check out `<base-branch>` in this
worktree, which the main checkout already has. Then update the main checkout,
still holding the lock: if `git -C <main-checkout> branch --show-current` is
`<base-branch>`, run `git -C <main-checkout> pull --ff-only <remote> <base-branch>`.
If that fails, report it and go on: the merge stands. Then release the lock.

**e. Clean up.** If this session entered the worktree with EnterWorktree,
leave it with the ExitWorktree tool (`action: keep`), which returns the session
to the main checkout, then remove it. If it entered with `cd` instead (no
EnterWorktree), `cd <main-checkout>` first, then remove it. If the session was
started inside the worktree, skip the removal and tell the user the two
commands to run from the main checkout.
```bash
git worktree remove .claude/worktrees/<branch>
git branch -D <branch>
```
If `git worktree remove` refuses (untracked files), report the path and leave
it; do not force it. Confirm the merge, and that the remote branch is gone.

**Red:** release the lock if held. Do not merge. Show the failing check and its
log (`gh run view <run-id> --log-failed`, trimmed to the error), and stop. The
PR and the worktree stay for a fix.

**Conflict:** release the lock. Stop and tell the user which files conflict
(`gh pr view <number> --json mergeable`). The PR and the worktree stay.

**Preview and production:** the PR's checks include deploying and testing its
preview, so a green PR has been proved on the preview. Report the preview URL
(the `Preview:` PR comment, or the deploy job's summary). After the merge, find
the runs it triggered on `<base-branch>` and the closed PR:
```bash
gh run list --branch <base-branch> --event push --limit 5
gh run list --event pull_request --limit 5
```
Watch the production deploy and the preview teardown with
`gh run watch <run-id> --exit-status` in the foreground (timeout 600000 ms, run
again if it times out), and report both. A failure is reported, not fixed: the
merge stands and the user decides what next.

## 5. Ship a feature

Trigger: the Definition of Done of the build loop's last iteration is met, or
the user says "ship <feat>". Run action 2 (commit and push), action 3 (PR), then
action 4 (merge on green). Report:
- the branch, commit subject and PR URL;
- the check results, whether the base moved and CI re-ran, and the merge result;
- any lock wait, and any stale lock broken;
- the preview URL, production deploy and preview teardown results.

## Edge cases

- **`gh` not authenticated / not a git repo**: stop and surface the exact
  error rather than retrying blindly.
- **Push or merge refused by branch protection**: read the rules with
  `gh api repos/{owner}/{repo}/rules/branches/<base-branch>` (rulesets) or
  `.../branches/<base-branch>/protection`, report them, and stop. Do not try
  to get round them.
- **Push rejected (diverged branch)**: stop and tell the user rather than
  force-pushing. Never use `--force` or `--no-verify`.
- **`git pull --ff-only` fails in the main checkout after a merge**: report
  it; the merge stands. Do not merge or rebase to make it fit.
- **`git fetch` fails with "cannot lock ref"**: another build is fetching. Run
  it once more before treating it as an error.
- **A lock that will not clear**: `merge-lock.sh status` shows the owner and
  heartbeat age. Only the user runs `merge-lock.sh break`.
- **Deployments run in CI.** Opening or updating a PR deploys its preview; merging
  deploys production. Never deploy, run
  a secrets script, or change AWS resources to make a check pass. A failing
  deploy check is reported like any other failure.
- **Merge conflicts on the PR** (`gh pr view <number> --json mergeable`
  reports `CONFLICTING`, or `gh pr update-branch` fails): release the lock if
  held, stop and tell the user.
