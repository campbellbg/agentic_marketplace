---
name: agentic-conventions
description: Shared conventions of the agentic-builder plugin - project settings and their defaults, fixed AWS access, how to find what a feature changed, the feature directory and its files (including the requirement template), the review report protocol (round numbers, Summary line, verdict and severity rules) and the rules every test follows. Preloaded into the agentic-builder agents; load it whenever you work on the agentic-requirement or agentic-build commands, their agents or their files outside them.
user-invocable: false
---

# Agentic build conventions

The single source for what the `agentic-requirement` and `agentic-build`
commands, their agents and the
`gitprocess`, `agentic-build-environment` and `deploy-environments` skills share.
Where one of them says "see the conventions", it means this file.

## Project settings

Read the `## Agentic build environment` section of `CLAUDE.md` at the repository
root (`git rev-parse --show-toplevel`). Use the default for any setting it does
not set. The `agentic-build-environment` skill writes the section.

| Setting | Default if the section does not set it |
|---------|----------------------------------------|
| Requirements dir (`<requirements-dir>`) | `requirements/` |
| Source and test dirs | Work them out from the repo layout (e.g. `src/`, `test/`, `tests/`) |
| Technology stack | Work it out from the repo: manifests and source |
| Deployment | All deployments except secrets run through GitHub Actions workflows; never deploy from a local machine. AWS resources are deployed with CloudFormation. |
| Hosting pattern | `None`. When set (e.g. `app-serving`), load the `deploy-environments` skill and follow it for production and per-PR preview environments. |
| Production environment name (`<env>`) | `None`. Required when Hosting pattern is set; the base of every resource name. |
| Secrets | Created manually, never by CI. The scripts that create or update them live in a git-ignored `secrets/` directory; templates and workflows reference secrets by name or ARN only, never by value. |
| Git remote (`<remote>`) | `origin`, or the only remote if there is just one. If neither applies, stop and say so. |
| Base branch (`<base-branch>`) | The remote's default branch (`git symbolic-ref --short refs/remotes/<remote>/HEAD`, minus the `<remote>/` prefix); if the remote has none, `main`. |

**Worked out from the repo, not settings.** These are never written to the
section; work them out each time. If `CLAUDE.md` states one elsewhere (e.g. a
`## Build and test notes` section), that wins.

- **Check command:** the project's typecheck, lint or build script (e.g.
  `npm run typecheck`); otherwise none.
- **Test command:** the project's standard test command, from its manifest or
  build files (e.g. `npm test`, `pytest`, `go test ./...`).
- **Test conventions:** the patterns the existing tests follow.

## AWS access (fixed, not a setting)

Workflows authenticate to AWS through GitHub OIDC with
`aws-actions/configure-aws-credentials`,
`role-to-assume: ${{ secrets.AWS_DEPLOY_ARN }}` and
`aws-region: ${{ secrets.AWS_DEPLOY_REGION }}`, with `permissions: id-token: write`
only on jobs that assume the role. Both repo secrets exist before any work; never
create, rename or ask for them, never hard-code a region or account, and never use
long-lived AWS keys. Never run `aws`, `sam`, `cdk` or any other deploy command
yourself.

## What a feature has changed

Everything on the feature branch since it left the base branch, committed or not:

```bash
base=$(git merge-base <base-branch> HEAD)
git diff --stat "$base"          # committed and uncommitted changes to tracked files
git diff "$base" -- <path>       # one file's change
git status --porcelain -uall     # plus new, untracked files
```

## The feature directory

`<requirements-dir>/<feat>/`, e.g. `requirements/feat_0002/`, holds:

| File | Written by | Notes |
|------|-----------|-------|
| `requirement.md` | the user, or drafted from their description by the `agentic-requirement` command | What was asked for. Only the user, or `agentic-requirement` with the user's explicit approval, changes it; no agent ever edits it. Format: [assets/requirement-template.md](assets/requirement-template.md). |
| `requirement-decomposed.md` | `decompose-requirement` only, run by `agentic-requirement` | The approved plan: a single build or iterations, each with its acceptance criteria, Tests table and Definition of Done. The build's input. One file with no round number, replaced in full each time the requirement is re-reviewed. |

**Two stages.** The requirement stage (`/agentic-requirement`) is interactive:
it writes `requirement.md`, has `decompose-requirement` review it and plan the
build, and ends when the user approves the plan. The build stage
(`/agentic-build`) runs unattended and starts only from an approved
`requirement-decomposed.md` whose `Source hash` matches `requirement.md`. Rounds
belong to the build stage only.
| `build_<NNN>.md` | `code-builder` | Its report for the round: what changed, coverage by AC ID, and the reason for any finding it did not fix. |
| `review_<reviewer>_<NNN>.md` | each review agent | `<reviewer>` is the agent name without `review-` (`review-code` -> `review_code_004.md`). |
| `review_consolidated_<NNN>.md` | `consolidate-reviews` | The round's build directions for `code-builder`. |

**Rounds.** `<NNN>` is the round: one run of `code-builder`, then every review
agent, then `consolidate-reviews`, numbered from `001`, zero-padded to three
digits and continuing across iterations. Every file of a round shares its
number. The `agentic-build` command passes the round to `code-builder`, each
review agent and `consolidate-reviews`. The command starts each round at one
more than the highest `<NNN>` of any round file in the feature directory
(`build_*`, `review_*`, `review_consolidated_*`), so a round that stopped
part-way is never reused. If you are run on your own without a round: as
`code-builder`, use one more than that highest `<NNN>` (`001` if there are none);
as a review agent or `consolidate-reviews`, use the highest `build_<NNN>.md`,
the round you are reviewing. Nobody modifies a report once it is saved.

## Review reports (every `review-*` agent)

**Inputs:** the feature, the iteration and the round. Read `requirement.md` and
`requirement-decomposed.md`. Review the code as it stands against this
iteration's section plus all earlier iterations. Work planned for a later
iteration being absent is not a finding, and neither is a criterion marked
`(verified by CI at ship)`. On a re-review, read your own report from the
latest earlier round, if there is one, and say whether each of its findings has
been fixed. Read the Review Findings table of this round's `build_<NNN>.md` too.
Where the builder marked one of your earlier findings `Not fixed` with a reason,
check the reason against the code and the requirement:
- if it holds, drop the finding and say so under Questions / Ambiguities;
- if it does not, raise the finding again, name its earlier ID (e.g. `was SEC-2
  in round 003`), and say in the finding why the builder's reason does not hold.

Acceptance criteria are always referred to by their AC IDs from
`requirement-decomposed.md`, never renumbered or reworded.

**You are a reviewer only.** Never modify code or tests. The only file you
write is your report. Do not run git commands that change the repo (commit,
push, checkout, switch, stash, reset, restore, clean); read-only ones such as
`git diff`, `git log` and `git status` are fine.

**Report layout.** Your agent file gives the sections between Verdict and
Findings. Every report has these:

```
# <Kind> Review: <feat> - iteration <k> - round <NNN>

## Verdict
PASS | PASS WITH CHANGES | FAIL - <one sentence why>

...agent-specific sections...

## Findings
### [Critical|High|Medium|Low] <PREFIX>-<n> <title>
- **Location:** path/to/file:line
- ...agent-specific fields...

(Most severe first, numbered <PREFIX>-1, <PREFIX>-2, ... in that order.
consolidate-reviews points the builder at findings by these IDs. Write "None"
if there are none.)

## Questions / Ambiguities
- ... (Write "None" if there are none.)

## Summary
Verdict: <PASS|PASS WITH CHANGES|FAIL> | Critical <n> | High <n> | Medium <n> | Low <n>
```

**Summary line.** It is read by the next step, so it is the last section,
appears exactly once, uses exactly this format with every count present (write
0, never omit one), and agrees with the Findings. Warnings are not counted.

**Verdict rule** (every report and the consolidated directions): `FAIL` if there
is any Critical or High finding, `PASS WITH CHANGES` if there are only Medium or
Low findings, `PASS` if there are none. The verdict follows from the counts.

**Severity scale.** Agent files may add examples for their own field.

- **Critical** - exploitable security hole, data loss, or the requirement
  fundamentally not met.
- **High** - a bug that will occur in normal use, a failing check or test, or
  a missing control that leaves a serious weakness open.
- **Medium** - a bug in edge cases, a flaky test, a missing defence-in-depth
  control, or a significant maintainability risk.
- **Low** - a minor improvement; non-blocking.

**Verify before reporting.** Re-read the code for each finding and confirm it is
real. Give a concrete scenario (input or actor -> wrong result or gain). Drop
findings you cannot justify; put unproven concerns under Questions. Fewer,
accurate findings beat many speculative ones. Cite `file:line`. Do not praise,
pad or summarise the code, and do not nitpick what a linter would catch.

**Save and return.**

1. Save the full report with the Write tool to
   `<requirements-dir>/<feat>/review_<reviewer>_<NNN>.md`. Write to no other path.
   If the file already exists, do not overwrite it: treat that as a failed save.
2. Return exactly one line: `Saved to: <path> | <your Summary line>`. Do not
   return the report itself.
3. If the save failed, return `Save failed: <error>` followed by the full report,
   so the caller can save it.

Always finish by saving, even if you found nothing or could not finish every
step. If you were blocked part-way, save what you did verify and say in the
report what you could not check and why.

## Blocked

You run as a subagent and cannot ask the user anything. If the inputs are
missing or unclear (no feature or iteration, no `requirement-decomposed.md`, the
two requirement files disagree), do not guess and do not invent requirements.
Finish with a final message that starts `Blocked: <what is missing>`. The caller
stops and asks the user.

## Tests (code-builder writes them, review-tester checks them)

- Tests live in the test dir, follow the test conventions and run through the
  test command. Treat that as the only command CI runs: a test it does not pick
  up never runs in CI.
- **The same test passes locally and in CI** by default. Do not hard-code hosts,
  ports or environment-specific paths; take them from the configuration the
  tests already use. Keep each test independent of test order and of other
  tests' state. Wait on conditions, not fixed sleeps. If the suite also runs
  against a deployed environment, keep every test safe to run there.
- Never leave a focused test (`test.only`, `it.only`, `fit`, ...).
- **Skip form:** the framework's skip, as the test's first line, with a reason
  starting `CI only: <dependency>` or `Local only: <reason>`. Use it only where
  the iteration's Tests table plans it, or where a test truly cannot run in one
  environment. Never skip a test because it fails or is awkward.
- **Hosting pattern set:** a test of the deployed site takes its base URL from
  `PREVIEW_URL` and uses the CI-only skip form when it is unset.
- **Running the suite:** run the check command, if there is one, then the whole
  suite with the test command, without `PREVIEW_URL` or cloud credentials, so
  nothing touches a deployed environment. Give it a Bash timeout of 600000 ms; a
  run cut off by your own timeout is not a test result. If the runner starts its
  own server, first check that nothing already listens on its port
  (`ss -ltn`). If something does, the run could test a stale server, so report
  it rather than stopping that process.
- **Who runs what:** review-tester runs the whole suite every round; its run is
  the gate that proves the whole suite passes. code-builder runs only a
  **targeted run**: the check command, if there is one, then just this
  iteration's planned tests plus the tests in any test file it created or
  changed, selected with the runner's filter or file arguments (e.g.
  `npx playwright test <files>`, `pytest <files> -k <name>`,
  `npx vitest run <files>`). It follows the rest of these rules (no
  `PREVIEW_URL`, timeout, port check). If the runner cannot select tests, it runs
  the whole suite instead.
- Test output directories (e.g. `test-results/`, `playwright-report/`,
  `coverage/`) belong in `.gitignore`, because iteration commits stage
  everything.
