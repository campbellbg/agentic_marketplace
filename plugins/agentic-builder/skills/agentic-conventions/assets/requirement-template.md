# feat_0001: <Short Title>

<!--
Save as <requirements-dir>/feat_NNNN/requirement.md, where the directory name
matches the heading. The heading and Summary feed the branch name, commit
subjects and PR text. Delete these comments when you write the requirement.
-->

## Summary

<Two or three sentences: what the user can do after this feature that they
cannot do now, and why it matters.>

## Background

<Optional. Context the builder needs: related features, constraints, links.>

## Acceptance Criteria

<!--
One observable outcome per criterion, each with an ID. Each must be something
a test can check. Say what happens, not how to build it.
-->

- **AC-1** Given <starting state>, when <action>, then <observable result>.
- **AC-2** ...

## Out of Scope

- <Nearby work this feature must not do.>

## Definition of Done

- All acceptance criteria are met and covered by tests that run through the
  project's test command.
- The whole test suite passes.
- Reviews: no Critical or High findings.
<!-- Add anything else, e.g. "tests pass in the PR's CI run against the preview". -->
