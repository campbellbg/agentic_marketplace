# agentic-builder

An agentic build loop for Claude Code. It reviews and decomposes a feature's
requirement into iterations, then for each iteration builds the code and tests,
runs code, security and test reviews in parallel, consolidates the findings,
reworks until the iteration's Definition of Done is met, and commits. When every
iteration is done it opens a PR, waits for CI and merges on green.

## Install

```
/plugin marketplace add <path or git URL of this marketplace>
/plugin install agentic-builder@bryan_agentic_marketplace
```

## Usage

```
/agentic-build <feature name>
```

For example `/agentic-build feat_0002`. The feature's requirement must exist at
`<requirements-dir>/<feature>/requirement.md`.

## What's included

| Type | Name | Role |
|------|------|------|
| Command | `agentic-build` | Runs the build loop |
| Agent | `review-and-decompose-requirement` | Checks the requirement and splits it into iterations |
| Agent | `code-builder` | Builds one iteration, and reworks it from review findings |
| Agent | `review-code` | Correctness and requirement coverage |
| Agent | `review-security` | App, dependency, infrastructure and CI/CD security |
| Agent | `review-tester` | Runs the tests locally and checks they will work in CI |
| Agent | `review-consolidate` | Turns the reviews into build directions and a verdict |
| Skill | `gitprocess` | Feature branches, commits, PRs and merge on green CI |
| Skill | `agentic-build-environment` | Asks you for each project setting and writes the `## Agentic build environment` section of CLAUDE.md |

## Requirement format

`requirement.md` starts with `# <feature>: <Title>` and has a `## Summary`,
Acceptance Criteria with IDs, Out of Scope, and a Definition of Done.

## Project settings

Nothing in the plugin is tied to one project. Each agent, the command and the
skill read `CLAUDE.md` for the project layout and technology, plus its
`## Agentic build environment` section. `/agentic-build` checks for that section
first and, if it is missing, runs the `agentic-build-environment` skill to set it
up with you. You can also run that skill any time by asking to "set up the agentic
environment". Anything the section leaves out falls back to the default below.

| Setting | Default |
|---------|---------|
| Requirements dir | `requirements/` |
| Source and test dirs | Worked out from the repo layout |
| Check command | The project's typecheck, lint or build script, if any |
| Test command | The project's standard test command (e.g. `npm test`, `pytest`) |
| Local test setup | Run the test command as is |
| Test conventions | None beyond the agents' general rules |
| CI-only skip form | The framework's skip, with a reason starting `CI only:` or `Local only:` |
| Dev server | None (the restart step is skipped) |
| Stack and deployment | Worked out from the repo |
| Git remote | `origin`, or the only remote |
| Base branch | The remote's default branch, else `main`, else `master` |
| Branch name rules | `a-z`, `0-9`, `_`, `-` |
| Branch protection | Not described; read from GitHub if a push or merge is refused |

### Example `CLAUDE.md` section

```markdown
## Agentic build environment
- Requirements dir: `requirements/`
- Source and test dirs: `src/`, `test/`
- Check command: `npm run typecheck`
- Test command: `npm test`
- Local test setup: `env -u BASE_URL -u CI PORT=<free port> npm test`
- Test conventions: navigate relative to `BASE_URL` with `page.goto('./')`
- CI-only skip form: `test.skip(!process.env.BASE_URL, 'CI only: <dependency>')`
- Dev server: `npm start` on port 3000
- Stack and deployment: static TypeScript site on S3 + CloudFront, GitHub Actions
- Git remote: `origin`
- Base branch: `main`
```

## Requirements

- `git` and an authenticated `gh` CLI for the commit, PR and merge steps.
- A CI workflow that runs on pull requests, so the merge step has checks to wait for.
