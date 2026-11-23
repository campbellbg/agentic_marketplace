---
name: gitprocess
description: Use this skill whenever there is a need to create/make a feature branch, commit or push work, create/open a PR, merge to the base branch (main/master), or ship a finished feature. The request can come from the user or from an agent loop (the `agentic-build` command calls it). It derives branch names, commit messages and PR text from the feature's requirement, so it runs without asking for input. It enforces a strict git workflow. It never commits or pushes to the base branch directly, always works on a feature branch, and merges only when the PR's CI checks are green. Trigger on phrases like "create a feature branch", "commit this", "push my work", "create a PR", "merge to master", "merge to main", "merge this in", "ship feat_0002".
---

# Branch, PR, and Merge Workflow

There are five actions. Actions 1-4 can be asked for on their own. Action 5
(Ship) runs 2 -> 3 -> 4 in one go and is what the build loop uses. Work out
names and messages yourself from the rules below; do not ask the user for them.
Tell the user what you chose in your report.

**Golden rule across all actions: never commit, push, or merge while on
the base branch.** Always check the current branch first with
`git branch --show-current`.

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

## 1. Create a feature branch

- **First, check uncommitted changes** with `git status --porcelain -uall`,
  before switching to any branch. Git keeps uncommitted files in the working
  tree across a switch, so this check decides what comes along. Sort each file:
  - **Carried over:** the requirement is written on `<base-branch>` by
    `/agentic-requirement` before a build, and a first build sets up the
    environment there too. These may be modified or new:
    - anything under `<requirements-dir>/<feat>/` (this feature only);
    - `CLAUDE.md`;
    - `.gitignore`.

    They come onto the feature branch and are committed with the feature. Tell
    the user in your report which were carried over.
  - **Left behind:** anything under another feature's directory,
    `<requirements-dir>/feat_*/` other than `<feat>`. These are requirements
    drafted for later builds. They stay in the working tree, uncommitted, and
    action 2 never stages them. List them in your report.
  - **Anything else**: **stop and tell the user**, because it would be swept
    into the feature's commit.
- If a branch for this feature already exists (`git branch --list '<feat>-*'`,
  `git ls-remote --heads <remote> '<feat>-*'`), switch to it and stop. If the
  switch is refused because the branch has its own changes to a carried or
  left-behind file, stop and tell the user.
- If `<base-branch>` does not exist on `<remote>`
  (`git ls-remote --heads <remote> <base-branch>` is empty), stop and tell the
  user. The base branch needs an initial commit pushed first, and this skill
  never commits to it.
- Start from an up-to-date `<base-branch>`:
  ```bash
  git checkout <base-branch>
  git pull --ff-only <remote> <base-branch>
  git checkout -b <branch>
  ```
  If the pull or checkout fails because it would overwrite a carried or
  left-behind file, stop and tell the user. Do not stash, reset or discard it.

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
  git add -A -- . ':(exclude)<requirements-dir>/feat_*'
  git add -A -- '<requirements-dir>/<feat>/'
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
- Otherwise:
  ```bash
  gh pr create --base <base-branch> --head <current-branch> --title "<title>" --body-file <body-file>
  ```
- Report the PR URL.

## 4. Merge to the base branch (on green CI)

Merging needs no confirmation from the user, but **only when every CI check on
the PR has passed**. Branch protection may require only some checks, so this
skill always waits for every check on the PR; never skip this. If GitHub refuses
a merge, stop and show the error. Do not try to get round the rules.

- If on `<base-branch>`, **stop**: you need the feature branch with the PR.
- Find the open PR: `gh pr list --head <current-branch> --state open`. If
  there is none, run action 3 first.
- Wait for checks to appear, since they can take a minute after the PR opens.
  Poll `gh pr checks <number>` every 30 seconds for up to 5 minutes. If no
  checks appear, **stop and tell the user**: do not merge a PR with no checks.
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
- **Preview and production:** the PR's checks include deploying and testing its
  preview, so a green PR has been proved on the preview. Report the preview URL
  (the `Preview:` PR comment, or the deploy job's summary). After the merge,
  find the runs it triggered on `<base-branch>` and the closed PR:
  ```bash
  gh run list --branch <base-branch> --event push --limit 5
  gh run list --event pull_request --limit 5
  ```
  Watch the production deploy and the preview teardown in the background
  (`gh run watch <run-id> --exit-status`) and report both. A failure is
  reported, not fixed: the merge stands and the user decides what next.

## 5. Ship a feature

Trigger: the Definition of Done of the build loop's last iteration is met, or
the user says "ship <feat>". Run action 2 (commit and push), action 3 (PR), then
action 4 (merge on green). Report:
- the branch, commit subject and PR URL;
- the check results and merge result;
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
- **`git pull --ff-only` fails on `<base-branch>`**: stop and tell the user. Do
  not merge or rebase to make it fit.
- **Deployments run in CI.** Opening or updating a PR deploys its preview; merging
  deploys production. Never deploy, run
  a secrets script, or change AWS resources to make a check pass. A failing
  deploy check is reported like any other failure.
- **Merge conflicts on the PR** (`gh pr view <number> --json mergeable`
  reports `CONFLICTING`): stop and tell the user.
