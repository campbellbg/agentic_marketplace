---
description: Create, review and plan a feature requirement before it is built. Use when the user says "make a new requirement", "new requirement file", "write up a requirement", "new feature request", or asks to review or re-plan an existing feat_NNNN requirement. Takes free text, a file holding the text, or an existing feature name. Writes <requirements-dir>/feat_NNNN/requirement.md, has decompose-requirement review it and plan the build, and leaves it ready for /agentic-build.
argument-hint: <free-text description | path to a file holding it | feat_NNNN to revise>
---

# Agentic requirement: `$ARGUMENTS`

Turn my description into an approved requirement and build plan for the
agentic build loop. First load the `agentic-conventions` skill: it defines the
settings, the feature directory and the requirement template this command uses.

This is the conversational half of the workflow, but only where I am needed:
ask me when you need a decision only I can make, or when the review does not
approve the requirement. I trust `decompose-requirement` to review and plan
well, so its `APPROVED` verdict is the approval: do not ask me to approve the
requirement or the plan. `/agentic-build` is the unattended half and starts only
from a requirement the review has approved.

**Never** create branches, commit, push, or write code here. The only files you
write are `requirement.md` (only as described below) and, through
`decompose-requirement`, `requirement-decomposed.md`.

## 1. Settings

Read the settings as the conventions describe. The review checks the
requirement against the environment bounds (see the conventions), so the
environment must be set up first. If the root `CLAUDE.md` has no
`## Agentic build environment` section, or it does not set a supported Hosting
pattern and a Production environment name, tell me and offer to set it up with
the `agentic-build-environment` skill. If I decline, stop.

## 2. Work out the input

Look at `$ARGUMENTS`:

- **Empty:** ask me to describe the feature.
- **A feature name** (`feat_` followed by four digits) with a build worktree
  (`git worktree list` shows `.claude/worktrees/<feat>-*`): **stop**. Its
  requirement moved into that worktree when the build started. Tell me the
  path, and that changing it part-way through a build stops `/agentic-build`
  and asks me what to do.
- **A feature name** whose directory exists under `<requirements-dir>/`:
  **revise** it. Skip to step 4. If I also gave
  text after the name, treat it as the changes I want and draft them as in
  step 3, editing the existing `requirement.md`.
- **A path to a readable file:** read it; its contents are the description. If
  it already follows the requirement template, use it as the draft.
- **Anything else:** the text itself is the description.

## 3. Draft a new requirement

1. **Number.** Take one more than the highest `NNNN` found in either:
   - the directories `<requirements-dir>/feat_NNNN/`;
   - branch names, local and remote (`git branch -a --list '*feat_*'`), because a
     feature still on an unmerged branch has no directory on this one.

   Zero-pad to four digits (`feat_0001` if there are none). Never reuse a number.
   **Claim it** before writing anything, because another session may be
   drafting at the same time: `mkdir -p <requirements-dir>`, then a plain
   `mkdir <requirements-dir>/feat_NNNN` (no `-p`, so it fails if the directory
   exists). If it fails, another session took that number: take the next one
   and claim again.
2. **Gaps.** If something essential is unclear (who uses it, what counts as
   success, an obvious boundary), ask me at most 3 short questions in one go
   before writing. Do not invent scope: anything else unclear goes in an
   `## Open Questions` section, not into an acceptance criterion.
3. **Write** `<requirements-dir>/feat_NNNN/requirement.md` from the conventions'
   requirement template (`assets/requirement-template.md` in the
   `agentic-conventions` skill): the heading `# feat_NNNN: <Short Title>`,
   Summary, Background (only if I gave context), Acceptance Criteria as
   `**AC-n** Given / when / then`, each one observable and testable, Out of
   Scope, and Definition of Done. Remove the template's HTML comments.
4. Show me the path, the title and the AC list in a few lines, then go straight
   to the review without waiting for me.

## 4. Review and plan

Run the `decompose-requirement` agent on the feature. Pass it only the feature
name, plus any planning guidance I gave (with the description, or after a
step 5 report).

- **`Verdict: CHANGES NEEDED`:** show me its Suggested Changes table and
  Questions for the User. Ask which changes to accept and get my answers to the
  questions. Apply what I accepted to `requirement.md`, and only that. If I
  reject everything and want it built as written, tell me the build cannot start
  until a review approves it, and stop. Then run the agent again. After 3 review
  passes without approval, stop and tell me what is still open, so I can edit
  the requirement myself and run `/agentic-requirement <feat>` again.
- **`Verdict: NOT FIT TO BUILD`:** show me its Reasons and What Could Be Built
  Instead, then stop. Where a reason is `environment`, say plainly that the
  requirement cannot be met within the current build environment, and that
  it needs changing to fit or a new hosting pattern (which I add myself). Do not edit `requirement.md` to get it past the review,
  and do not reword the flagged parts so they read differently with the same
  effect. If I want to go ahead with the safe alternative, draft it as a fresh
  change to `requirement.md` that drops the flagged parts, and go back to the
  start of this step. Being rejected does not count towards the 3 review passes.
- **`Blocked: ...`:** show me and stop.
- **`Save failed: ...`:** save the decomposition it returned at
  `<requirements-dir>/<feat>/requirement-decomposed.md` yourself, then go on.
- **`Saved to: ... | Verdict: APPROVED ...`:** go to step 5.

## 5. Report the approved plan

The review's `APPROVED` verdict approves the requirement and the plan. Do not
ask me to accept them. Read `requirement-decomposed.md` and show me, briefly:

- the plan: **single build** or **<n> iterations**, with the agent's reason;
- the Iteration Overview table;
- the review notes, and every Prerequisite for the User, flagged clearly as
  things I must do myself.

Then go straight to step 6. If I later reply asking for a change, handle it:

- **Change the requirement:** draft my changes into `requirement.md` and go back
  to step 4.
- **Change the plan only** (e.g. "build it in one go", "split the API from the
  UI"): go back to step 4 and pass my words as planning guidance. The agent may
  change the split, but never the requirement.

Never edit `requirement-decomposed.md` yourself. It is rewritten in full each
time the agent runs, so no older versions are kept beside it.

## 6. Finish

Tell me:

- the paths of `requirement.md` and `requirement-decomposed.md`;
- that both stay uncommitted in this checkout, and that `/agentic-build` moves
  them into the feature's worktree and commits them with the feature;
- the next step: `/agentic-build <feat>`.

If the feature already has a branch with iteration commits
(`git log --all --oneline --grep '^<feat>: .*iteration'`), warn me that the requirement has
changed part-way through a build, and that `/agentic-build` will ask what to do.
