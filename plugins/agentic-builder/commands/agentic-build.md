---
description: Run the agentic build loop for a feature (review/decompose, build, review, commit per iteration, then ship)
argument-hint: <feature name, e.g. feat_0002>
---

# Agentic build: `$ARGUMENTS`

Build the feature **`$ARGUMENTS`** using the agentic build loop below.

## Pre-flight: build environment

Before anything else, check that the project's `CLAUDE.md` (at the repository root) exists and has a `## Agentic build environment` section.

- **Present:** continue.
- **Missing** (no `CLAUDE.md`, no section, or only an older `## Agentic build` section): tell me it is missing, then use the `agentic-build-environment` skill to set it up with me. When the section is written, re-read `CLAUDE.md` and continue with the build. If I decline or the section still is not there, stop and build nothing.

**Project settings.** Read `CLAUDE.md`, including its `## Agentic build environment` section. This loop uses:
- **Requirements dir** (`<requirements-dir>`): from that section, otherwise `requirements/`.
- **Dev server**: the command and port to restart after each build, from CLAUDE.md. If none is given, skip the restart.

The agents and the git process skill read their own settings (test commands, base branch, remote and so on) the same way, so pass them only the feature and iteration.

If no feature name was given (`$ARGUMENTS` is empty), list the directories under `<requirements-dir>/` and ask me which feature to build. Otherwise, confirm `<requirements-dir>/$ARGUMENTS/requirement.md` exists; if it does not, stop and tell me.

From here on, `<feat>` means `$ARGUMENTS`. Run the loop **without stopping to ask between rounds or iterations**; only stop where the steps below say to.

## Agents and files

- **`review-and-decompose-requirement`** runs first. It checks that `requirement.md` is fit to build. If not, it returns suggested changes and writes nothing. If it is, it saves `requirement-decomposed.md`, which splits the requirement into iterations that are each built, reviewed and committed on their own, each with its own acceptance criteria and Definition of Done. The last iteration's Definition of Done includes everything in the requirement's, so meeting it means the feature is done. `requirement-decomposed.md` is the input to the build; `requirement.md` stays the record of what was asked for. Neither changes during a build.
- **`code-builder`** writes code and tests, one iteration at a time. To fix findings, run it again on the same feature and iteration; it reads `requirement-decomposed.md`, the latest `review_consolidated_NNN.md`, and only the findings those directions point to.
- **Review agents** (run each round, in parallel):
  - `review-code`: correctness, requirement coverage
  - `review-security`: security of the app, dependencies, infrastructure-as-code and CI/CD workflows
  - `review-tester`: runs the tests locally. A test that cannot run locally because of a missing dependency, or a `CI only` test, is a **warning**, not a failure. Warnings do not count towards the verdict or Definition of Done, but they appear in the consolidated review and must be included in the final summary.
  - Any other `review-<name>` agent available in this plugin or project also runs in this step.
- **`review-consolidate`** writes brief build directions pointing the builder at the findings to fix, in order.
- Pass every agent the feature name and iteration (e.g. `<feat>`, iteration 1).
- The feature directory `<requirements-dir>/<feat>/` holds `requirement.md`, `requirement-decomposed.md` and the review reports.
- Each review agent saves its own report under the next number for that feature (zero-padded, starting at `001`, continuing across iterations): `review_code_NNN.md`, `review_security_NNN.md`, `review_tester_NNN.md`, and `review-consolidate` saves `review_consolidated_NNN.md`. Do not save them again. If an agent says its save failed, save its report under the next free number yourself.
- Use the plugin's git process skill (`gitprocess`) for all branch, commit, push, PR and merge work.

## Build loop

0. **Branch.** Use the git process skill to create (or switch to) the feature branch for `<feat>` from an up-to-date base branch.

1. **Review and decompose the requirement.**
   - If `<requirements-dir>/<feat>/requirement-decomposed.md` exists and its `Source hash` matches `sha256sum` of `<requirements-dir>/<feat>/requirement.md`, reuse it and go to step 2.
   - If the hash differs and the branch already has iteration commits, **stop and ask me**: the requirement changed part-way through the build.
   - Otherwise run `review-and-decompose-requirement` on `<feat>`. If it returns `Verdict: CHANGES NEEDED`, **stop and show me its suggested changes**. Build nothing and do not edit `requirement.md` yourself.

2. **For each iteration** in `requirement-decomposed.md`, in order, skipping any that already has a non-WIP `<feat>: iteration <k>/<n>` commit on the branch:
   a. Run `code-builder` on `<feat>` and the iteration, then restart the dev server, if the project has one, so it serves the new code.
   b. Run all review agents on `<feat>` and the iteration **in parallel**.
   c. Run `review-consolidate` on `<feat>` and the iteration.
   d. Read the `Summary` line of the new `review_consolidated_NNN.md` (`Verdict: ... | Critical n | High n | Medium n | Low n`) and its `Definition of Done` section, and check them against this iteration's Definition of Done in `requirement-decomposed.md`. If the line is missing or malformed, or the iteration has no Definition of Done, treat it as **not met** and say so.
   e. If it **is met**, use the git process skill to commit and push the iteration (no PR), then start the next iteration.
   f. If it **is not met**, run `code-builder` again on the same feature and iteration (it reads the latest build directions) and go back to step b.
   g. **Stop after 3 build rounds** on one iteration even if its Definition of Done is not met: commit and push it as WIP with the git process skill (no PR), report what is still open, and do not start the next iteration.

3. **Ship.** After the last iteration, use the git process skill to ship the feature (open the PR, wait for the CI checks, merge on green). If a CI check fails, do not merge: report the failure and leave the PR open.

4. **Summarise** for me: each iteration, its number of rounds, any warnings, and the ship result.

## Stop conditions

- If the builder or any review agent raises an open question that changes the requirement, **stop and ask me** instead of guessing.
- Otherwise, stop only at the points named in steps 1, 2g and 3.
