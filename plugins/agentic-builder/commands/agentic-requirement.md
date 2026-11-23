---
description: Create, review and plan a feature requirement before it is built. Use when the user says "make a new requirement", "new requirement file", "write up a requirement", "new feature request", or asks to review or re-plan an existing feat_NNNN requirement. Takes free text, a file holding the text, or an existing feature name. Writes <requirements-dir>/feat_NNNN/requirement.md, has decompose-requirement review it and plan the build, and leaves it ready for /agentic-build.
argument-hint: <free-text description | path to a file holding it | feat_NNNN to revise>
---

# Agentic requirement: `$ARGUMENTS`

Turn my description into an approved requirement and build plan for the
agentic build loop. First load the `agentic-conventions` skill: it defines the
settings, the feature directory and the requirement template this command uses.

This is the conversational half of the workflow: ask me whenever you need a
decision. `/agentic-build` is the unattended half and starts only from a
requirement this command has approved.

**Never** create branches, commit, push, or write code here. The only files you
write are `requirement.md` (only as described below) and, through
`decompose-requirement`, `requirement-decomposed.md`.

## 1. Settings

Read the settings as the conventions describe. If the root `CLAUDE.md` has no
`## Agentic build environment` section, tell me and offer to set it up with the
`agentic-build-environment` skill, because the review checks the requirement
against the technology stack and Hosting pattern. If I decline, carry on with
the defaults and say that the plan may need re-running once the settings exist.

## 2. Work out the input

Look at `$ARGUMENTS`:

- **Empty:** ask me to describe the feature.
- **A feature name** (`feat_` followed by four digits) whose directory exists
  under `<requirements-dir>/`: **revise** it. Skip to step 4. If I also gave
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
   to the review. I approve the requirement and the plan together in step 5.

## 4. Review and plan

Run the `decompose-requirement` agent on the feature. Pass it only the feature
name, plus any planning guidance I gave in step 5.

- **`Verdict: CHANGES NEEDED`:** show me its Suggested Changes table and
  Questions for the User. Ask which changes to accept and get my answers to the
  questions. Apply what I accepted to `requirement.md`, and only that. If I
  reject everything and want it built as written, tell me the build cannot start
  until a review approves it, and stop. Then run the agent again. After 3 review
  passes without approval, stop and tell me what is still open, so I can edit
  the requirement myself and run `/agentic-requirement <feat>` again.
- **`Verdict: NOT FIT TO BUILD`:** show me its Reasons and What Could Be Built
  Instead, then stop. Do not edit `requirement.md` to get it past the review,
  and do not reword the flagged parts so they read differently with the same
  effect. If I want to go ahead with the safe alternative, draft it as a fresh
  change to `requirement.md` that drops the flagged parts, and go back to the
  start of this step. Being rejected does not count towards the 3 review passes.
- **`Blocked: ...`:** show me and stop.
- **`Save failed: ...`:** save the decomposition it returned at
  `<requirements-dir>/<feat>/requirement-decomposed.md` yourself, then go on.
- **`Saved to: ... | Verdict: APPROVED ...`:** go to step 5.

## 5. Approve

Read `requirement-decomposed.md` and show me:

- the plan: **single build** or **<n> iterations**, with the agent's reason;
- the Iteration Overview table;
- the review notes, and every Prerequisite for the User.

Ask me to choose:

- **Accept:** go to step 6.
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
- that both stay uncommitted on the current branch, and that `/agentic-build`
  carries them onto the feature branch and commits them with the feature;
- the next step: `/agentic-build <feat>`.

If the feature already has a branch with iteration commits
(`git log --all --oneline --grep '^<feat>: .*iteration'`), warn me that the requirement has
changed part-way through a build, and that `/agentic-build` will ask what to do.
