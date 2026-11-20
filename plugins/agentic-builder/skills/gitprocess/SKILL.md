---
name: gitprocess
description: Use this skill whenever there is a need to create/make a feature branch, commit or push work, create/open a PR, merge to the base branch (main/master), or ship a finished feature. This need could come from me or from an agent loop (the `agentic-build` command calls it). It derives branch names, commit messages and PR text from the feature's requirement, so it runs without asking for input, and it enforces a strict git workflow — never commits or pushes to the base branch directly, always works on a feature branch, and merges only when the PR's CI checks are green. Trigger on phrases like "create a feature branch", "commit this", "push my work", "create a PR", "merge to master", "merge to main", "merge this in", "ship feat_0002".
---

# Branch, PR, and Merge Workflow

Five actions. Actions 1-4 can be asked for on their own; action 5 (Ship) runs
2 -> 3 -> 4 in one go and is what the build loop uses. Work out names and
messages yourself from the rules below - do not ask the user for them. Tell
the user what you chose in your report.

**Golden rule across all actions: never commit, push, or merge while on
the base branch.** Always check the current branch first with
`git branch --show-current`.

## Repo settings

This skill is used across projects. Read the `## Agentic build environment` section of
`CLAUDE.md` for these values, and use the default for any it does not set.
Work them out once at the start and tell the user which you used.

| Setting | Default if CLAUDE.md does not set it |
|---------|---------------------------------------|
| Requirements dir (`<requirements-dir>`) | `requirements/` |
| Git remote (`<remote>`) | `origin`, or the only remote if there is just one (`git remote`). If neither applies, stop and ask - do not guess. |
| Base branch (`<base-branch>`) | The remote's default branch (`git symbolic-ref --short refs/remotes/<remote>/HEAD`, minus the `<remote>/` prefix), else `main` if it exists, else `master` |
| Branch name rules | Only `a-z`, `0-9`, `_` and `-` |
| Branch protection | Not described. If a push or merge is refused, read the rules with `gh api repos/{owner}/{repo}/rules/branches/<base-branch>` (rulesets) or `.../branches/<base-branch>/protection`, report them, and do not try to get round them. |

## Deriving names and messages


The feature is the `<requirements-dir>/<feat>/` directory being worked on, e.g.
`feat_0002`. Its `requirement.md` starts with a heading `# <feat>: <Title>`
and has a `## Summary` section.

- **Branch name:** `<feat>-<title-slug>`, e.g. `# feat_0002: Dark Mode Toggle`
  -> `feat_0002-dark-mode-toggle`. The slug is the title in lowercase, with
  every run of characters other than `a-z0-9` replaced by `-`, trimmed of
  leading/trailing `-`, and cut to 40 characters. Only characters the branch name rules allow may
  appear, because CI pipelines often use the branch name in paths or
  environment names.
- **Commit subject:** `<feat>: <what the change does>`, imperative, at most 72
  characters, written from the requirement's Summary and title (e.g.
  `feat_0002: add a dark mode toggle to the header`). Match the existing
  history (`git log --oneline -10`).
- **Iteration commit subject:** the build loop commits each iteration of
  `requirement-decomposed.md` separately, as `<feat>: iteration <k>/<n> - <what it
  does>`, at most 72 characters. If the round limit stopped the iteration before
  its Definition of Done was met, use `<feat>: WIP iteration <k>/<n> - <what it
  does>`. The build loop reads these subjects to find where to resume, so keep the
  format exact.
- **Commit body:** 1-4 short lines on what changed, from the diff
  (`git diff --cached --stat` and the diff itself), then a line
  `Review: <requirements-dir>/<feat>/review_consolidated_NNN.md - <its Summary line>`
  if a consolidated review exists, then a blank line and the commit
  attribution trailer from the system reminder (`Co-Authored-By: ...`).
- **PR title:** the commit subject for the feature as a whole, not an iteration's.
  It becomes the squash commit on `<base-branch>`.
- **PR body:** a `## Summary` (2-3 lines from the requirement), `## Changes`
  (bullets from `git diff <remote>/<base-branch>...HEAD --stat` and `git log`, listing the
  iterations),
  `## Review` (the latest consolidated review's Summary line and path), then
  the PR attribution line from the system reminder.

**No feature directory** (e.g. the user asks to commit tooling or docs
changes): derive the branch name as `chore-<slug>` and the commit subject from
the diff itself, in the same styles. Only ask the user if the diff is too
mixed to describe in one subject line.

## 1. Create a feature branch

- If a branch for this feature already exists (`git branch --list '<feat>-*'`,
  `git ls-remote --heads <remote> '<feat>-*'`), switch to it and stop. An
  uncommitted `<requirements-dir>/<feat>/requirement.md` comes along as below; if
  the switch is refused because the branch has its own changes to that file,
  stop and tell the user.
- Check for uncommitted changes on `<base-branch>` with
  `git status --porcelain -uall`:
  - **Only `<requirements-dir>/<feat>/requirement.md`, optionally with its
    `requirement-decomposed.md`** (modified or new, for this
    feature): this is expected - the requirement is usually written on
    `<base-branch>` just before a build. Carry it onto the feature branch
    automatically; `git checkout -b` keeps it in the working tree, and it is
    committed with the feature. Tell the user in your report that it was
    carried over.
  - **Anything else**: **stop and tell the user** - it would be swept into
    the feature's commit.
- Start from an up-to-date `<base-branch>`:
  ```bash
  git checkout <base-branch>
  git pull --ff-only <remote> <base-branch>
  git checkout -b <branch>
  ```
  If the pull or checkout fails because it would overwrite the carried
  `requirement.md`, stop and tell the user; do not stash, reset or discard it.

## 2. Commit and/or push

- If on `<base-branch>`, **stop** - run action 1 first if a feature is known,
  otherwise tell the user.
- Look before staging: `git status --porcelain`. **Stop and tell the user**
  if anything looks like a secret or credential (`.env*`, `*.pem`, `*.key`,
  `*credentials*`, cloud or API keys in a diff) or is a large or binary file you did
  not expect. Otherwise:
  ```bash
  git add -A
  git commit -F <message-file>     # subject, body, trailer as derived above
  git push -u <remote> <current-branch>
  ```
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
- Otherwise:
  ```bash
  gh pr create --base <base-branch> --head <current-branch> --title "<title>" --body-file <body-file>
  ```
- Report the PR URL.

## 4. Merge to the base branch (on green CI)

Merging needs no confirmation from the user, but **only when every CI check
on the PR has passed**. Branch protection may enforce part of this, but it may
require only some checks, so this skill always waits for every check on the PR -
never skip it. If GitHub refuses a merge, stop and show the
error; do not try to get round the rules.

- If on `<base-branch>`, **stop** - you need the feature branch with the PR.
- Find the open PR: `gh pr list --head <current-branch> --state open`. If
  there is none, run action 3 first.
- Wait for checks to appear (they can take a minute after the PR opens):
  poll `gh pr checks <number>` every 30 seconds for up to 5 minutes. If no
  checks appear, **stop and tell the user** - do not merge a PR with no checks.
- Wait for them to finish:
  ```bash
  gh pr checks <number> --watch --interval 30
  ```
  Run it in the background and wait for the completion notification; a
  deploy and test run can take longer than a foreground command's timeout.
- **Any check failed or was cancelled:** do not merge. Show the failing check
  and its log (`gh run view <run-id> --log-failed`, trimmed to the error),
  and stop. The PR stays open for a fix.
- **All checks passed:**
  ```bash
  gh pr merge <number> --squash --delete-branch
  git checkout <base-branch>
  git pull --ff-only <remote> <base-branch>
  git branch -D <branch>   # if --delete-branch did not already remove it
  ```
  Confirm the merge, and that the remote and local branches are gone.

## 5. Ship a feature

Trigger: the Definition of Done of the build loop's last iteration is met, or the user says "ship
<feat>". Run action 2 (commit and push), action 3 (PR), then action 4 (merge
on green). Report the branch, commit subject, PR URL, check results and merge
result.

## Edge cases

- **`gh` not authenticated / not a git repo**: stop and surface the exact
  error rather than retrying blindly.
- **Push rejected (diverged branch)**: stop and tell the user rather than
  force-pushing. Never use `--force` or `--no-verify`.
- **`git pull --ff-only` fails on `<base-branch>`**: stop and tell the user; do not
  merge or rebase to make it fit.
- **Merge conflicts on the PR** (`gh pr view <number> --json mergeable`
  reports `CONFLICTING`): stop and tell the user.
