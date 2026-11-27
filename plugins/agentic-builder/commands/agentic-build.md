---
description: Run the agentic build loop for a feature whose requirement /agentic-requirement has approved - build, review and commit each iteration in the feature's own git worktree, then open the PR and merge on green CI under a local merge lock. Several builds can run at once, in separate terminals or headless. Use when the user says "build feat_NNNN", "implement feat_NNNN", "start the build", "run the agentic build", "kick off the build loop", or asks to build or implement an approved requirement. Takes the feature name; with none, lists the features and asks which to build.
argument-hint: <feature name, e.g. feat_0002>
---

# Agentic build: `$ARGUMENTS`

Build the feature **`$ARGUMENTS`** using the agentic build loop below. First
load the `agentic-conventions` skill: it defines the settings, the feature
directory, rounds, the report protocol and the verdict rule this loop uses.

## Pre-flight

Check these in order. At each **stop**, tell me exactly what is wrong and the
command that would fix it, and build nothing. Do not fix these yourself.

1. **Repository.** `git rev-parse --show-toplevel` succeeds (otherwise stop:
   suggest `git init`), and `gh auth status` succeeds (otherwise stop: suggest
   `! gh auth login`). Start from the main checkout (the first entry of
   `git worktree list`) or from this feature's own worktree. If the session is
   in any other worktree, stop and say which one.
2. **Build environment.** The root `CLAUDE.md` has a `## Agentic build
   environment` section. If it does not (no `CLAUDE.md`, no section, or only an
   older `## Agentic build` section), tell me, then use the
   `agentic-build-environment` skill to set it up with me. Re-read `CLAUDE.md`
   when it is written. If I decline, or the section is still missing, stop.
   The section must also set Hosting pattern to a pattern the
   `deploy-environments` skill lists, and Production environment name. If
   either is missing or `None`, stop and suggest the `agentic-build-environment`
   skill to set them.
   - **`CLAUDE.md` must be committed** in the main checkout
     (`git status --porcelain -- CLAUDE.md` is empty), because the feature's
     worktree starts from `<remote>/<base-branch>`. If it is not, tell me and
     ask whether to ship it now as a `chore-agentic-environment` PR with
     `gitprocess` (action 5, carrying `CLAUDE.md` and, if it has changes,
     `.gitignore`). On yes, ship it, then carry on from the updated base
     branch. On no, or if no one can answer (a headless run), stop.
   - **`.claude/worktrees/` must be git-ignored**
     (`git check-ignore -q .claude/worktrees/`). If it is not, stop and suggest
     adding it to `.gitignore` and committing it (or include it in the chore PR
     above).
3. **Remote and base branch.** Read the settings as the conventions describe.
   The Git remote exists (`git remote`), otherwise stop (e.g.
   `gh repo create --source . --private --push`). The base branch exists on it
   (`git ls-remote --heads <remote> <base-branch>`), otherwise stop: the base
   branch needs an initial commit pushed before a feature branch can start from it.
4. **Feature.** If no feature was given (`$ARGUMENTS` is empty), list the
   directories under `<requirements-dir>/`, plus the features that have a build
   worktree, and ask me which to build. If no one can answer (a headless run),
   stop and say the feature name must be passed.

   **Feature directory** (`<feature-dir>`): if `git worktree list` shows a
   worktree at `.claude/worktrees/$ARGUMENTS-*`, the build has started before
   and its requirement files moved there, so it is
   `<that worktree>/<requirements-dir>/$ARGUMENTS/`. Otherwise it is
   `<requirements-dir>/$ARGUMENTS/` in the current checkout.
   `<feature-dir>/requirement.md` must exist. If it does not, stop and suggest
   `/agentic-requirement <description>` to create it.
5. **Approved plan.** The requirement stage (`/agentic-requirement`) reviews and
   plans the requirement; this loop does not. In
   `<feature-dir>`, `requirement-decomposed.md` must exist,
   read `Verdict: APPROVED`, and its `Source hash` must equal the hex digest
   (first field) of `sha256sum requirement.md`.
   - Missing or not approved: stop and suggest `/agentic-requirement $ARGUMENTS`.
   - Hash differs: the requirement changed after it was approved. If the
     feature branch already has iteration commits
     (`git log --all --oneline --grep '^$ARGUMENTS: .*iteration'`), **stop and
     ask me**: it changed part-way through the build. Otherwise stop and suggest
     `/agentic-requirement $ARGUMENTS` to re-review it.

From here on, `<feat>` means `$ARGUMENTS`. Run the loop **without stopping to ask
between rounds or iterations**. Only stop where the steps below say to.

## Agents

The plan comes from `requirement-decomposed.md`, which `decompose-requirement`
wrote during `/agentic-requirement`: one iteration (a single build) or several,
each built, reviewed and committed on its own, with its own Definition of Done.
Meeting the last iteration's Definition of Done means the feature is done. This
loop never runs `decompose-requirement` and never edits either requirement file.

- **`code-builder`** writes code and tests for one iteration. Run it again on the
  same iteration to fix the latest round's findings.
- **Review agents:** every agent named `review-<name>` in this plugin or the
  project's `.claude/agents/`. They run in parallel, one report each per round.
  This plugin ships these three:
  - `review-code`: correctness and requirement coverage.
  - `review-security`: the app, dependencies, infrastructure-as-code and CI/CD.
  - `review-tester`: runs the tests locally. A test that cannot run locally
    (missing dependency, or `CI only`) is a **warning**, not a failure.
    Warnings do not count towards the verdict or the Definition of Done, but
    the final summary must include them.
- **`consolidate-reviews`** turns a round's reports into build directions and
  judges the iteration's Definition of Done.

Pass each agent only `<feat>`, the iteration, the round and the worktree path
(the `WORKTREE` from step 0). They read their own settings.

**Round** (`<NNN>`): before each `code-builder` run, take one more than the
highest `<NNN>` of any round file in `<requirements-dir>/<feat>/`
(`build_<NNN>.md`, `review_*_<NNN>.md` or `review_consolidated_<NNN>.md`; `001`
if there are none). A round that stopped part-way is never reused, so no saved
report is overwritten. The builder's `build_<NNN>.md` and the reviews of its
work share that number.

**Agent results.** `Save failed: ...`: save the report it returned at the path
it names yourself, then continue. `Blocked: ...`: stop and show me.

Use the `gitprocess` skill for all branch, commit, push, PR and merge work.

## Build loop

0. **Worktree.** Use `gitprocess` action 1 to create (or reuse) the feature's
   worktree and enter it. It moves this feature's requirement files out of the
   main checkout into the worktree; other features' drafts stay behind. Every
   step below, and every agent, runs in the worktree.

1. **For each iteration** in `requirement-decomposed.md`, in order. Skip any
   iteration that already has a non-WIP `<feat>: iteration <k>/<n>` commit on
   the branch.
   a. Work out the round, then run `code-builder` on `<feat>`, the iteration
      and the round.
   b. Run all review agents on `<feat>`, the iteration and the same round, **in
      parallel**. Then check that every review agent you ran has saved its
      `review_<reviewer>_<NNN>.md`. Run any agent whose report is missing once
      more; if it is still missing, **stop and show me** which one. Never
      consolidate a round with a report missing.
   c. Run `consolidate-reviews` on `<feat>`, the iteration and the round.
   d. Read the `## Definition of Done` and `## Summary` sections of the new
      `review_consolidated_<NNN>.md`. The iteration is **met** only if the
      Definition of Done reads `Met` and the Summary line is present and
      well-formed. Otherwise it is **not met**: say why if either is missing.
   e. **Met:** use `gitprocess` to commit and push the iteration (no PR), then
      start the next iteration.
   f. **Not met:** go back to step a for the same iteration. The builder reads
      the latest directions and reworks.
   g. **Stop after 3 build rounds** on one iteration **in this run** even if it
      is not met. Only rounds started by this run count: rounds from an earlier
      run (e.g. one that stopped with a WIP commit) do not, so a resumed
      iteration gets 3 fresh rounds and the builder starts from the latest
      consolidated directions. Commit and push it as WIP with `gitprocess` (no
      PR), report what is still open, and do not start the next iteration.

2. **Ship.** After the last iteration, use `gitprocess` to ship the feature:
   open the PR, wait for its CI checks, take the merge lock, re-run CI if
   another feature merged in the meantime, and merge if green. If a check
   fails, do not merge: report the failure and leave the PR open. After a merge,
   `gitprocess` returns the session to the main checkout and removes the
   worktree. If the build stops anywhere else (WIP, red CI, a question for me),
   the worktree stays: report its path. Running `/agentic-build <feat>` again
   picks it up.

3. **Summarise** for me:
   - each iteration and its number of rounds;
   - any warnings;
   - the ship result, including the preview URL, production deploy and preview
     teardown;
   - any one-time prerequisites I need to do, from the Prerequisites for the
     User section of every `build_<NNN>.md` of this feature;
   - any finding still listed under Conflicts in the last consolidated review.

## Stop conditions

- If the builder or a review agent raises an open question that changes the
  requirement, **stop and ask me** instead of guessing.
- If the builder returns `Blocked:` because the iteration cannot be met within
  the environment bounds (see the conventions), or a review finds the code
  outside them and the builder cannot fix it without leaving them, **stop and
  show me** which part does not fit and which bound it breaks. Do not commit
  it as WIP. The requirement needs changing, or I need to add a hosting
  pattern first.
- Otherwise, stop only at the points named in pre-flight and in steps 1b, 1g
  and 2.
