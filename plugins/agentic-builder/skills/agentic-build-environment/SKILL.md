---
name: agentic-build-environment
description: Use this skill to set up, seed, review or change the `## Agentic build environment` section of the project's CLAUDE.md - the settings the agentic-build command, its agents and the gitprocess skill read (requirements directory, source and test dirs, check and test commands, local test setup, test conventions, CI-only skip form, dev server, stack and deployment, git remote, base branch, branch name rules, branch protection). Trigger on phrases like "set up the agentic environment", "set up the agentic build environment", "agentic environment variables", "configure agentic build", "agentic settings", "change the agentic base branch", and whenever the agentic-build command finds the section missing.
---

# Agentic Build Environment

Seed or update the `## Agentic build environment` section of the project's
`CLAUDE.md`. The agentic-build command, its agents and the gitprocess skill
read their project settings from this section. Every value comes from the user:
you detect a suggestion for each one, but the user confirms or replaces it.
Never write a value the user has not confirmed.

## 1. Find the current state

- Find the project's `CLAUDE.md` at the repository root
  (`git rev-parse --show-toplevel`, or the working directory if not a git repo).
  If it does not exist, you will create it.
- If it already has a `## Agentic build environment` section (or an older
  `## Agentic build` section), read it. Its values are the suggestions in step 3,
  and you are updating it, not adding a second one.
- If you were invoked because the user asked to change one or two settings, ask
  only about those, then go to step 4.

## 2. Detect suggestions

Look at the repo, read-only, to suggest a value for each setting. Do not install,
run tests, or change anything.

| Setting | How to suggest a value |
|---------|------------------------|
| Requirements dir | An existing `requirements/` or similar directory holding `feat_*` folders; else `requirements/` |
| Source and test dirs | Top-level dirs such as `src/`, `lib/`, `app/`, `test/`, `tests/`, `spec/` |
| Check command | Typecheck, lint or build scripts in `package.json`, `Makefile`, `pyproject.toml` etc. |
| Test command | The test script or tool (e.g. `npm test`, `pytest`, `go test ./...`) |
| Local test setup | Env vars, ports or flags the test config uses (e.g. a `baseURL`/`BASE_URL` in a Playwright config, a `webServer` port) |
| Test conventions | Patterns in existing tests and test config worth enforcing |
| CI-only skip form | Existing skips in the tests that mention CI; else the framework's skip with a `CI only: <dependency>` reason |
| Dev server | A `start`/`dev`/`serve` script and the port it uses |
| Stack and deployment | Manifests, infrastructure-as-code (CloudFormation, Terraform, Kubernetes, Docker) and CI workflows (`.github/workflows/`) |
| Git remote | `git remote -v`: `origin`, or the only remote |
| Base branch | `git symbolic-ref --short refs/remotes/<remote>/HEAD` (minus the `<remote>/` prefix), else `main` or `master`, whichever exists |
| Branch name rules | Anything the CI workflows do with the branch name (paths, environment names); else `a-z`, `0-9`, `_`, `-` |
| Branch protection | `gh api repos/{owner}/{repo}/rules/branches/<base>` (rulesets) and `.../branches/<base>/protection`, if `gh` is authenticated; else unknown |

## 3. Ask the user for every setting

Ask about **all thirteen settings**, in this order, so nothing is skipped:

1. Requirements dir
2. Source and test dirs
3. Check command
4. Test command
5. Local test setup
6. Test conventions
7. CI-only skip form
8. Dev server (command and port, or none)
9. Stack and deployment
10. Git remote
11. Base branch
12. Branch name rules
13. Branch protection

Use the AskUserQuestion tool, up to four settings per call, so four rounds cover
everything. For each setting:

- Make the question stand alone: name the setting, say in a few words what the
  agents use it for, and show what you detected.
- Offer the detected value as the first option, marked `(Recommended)`, plus one
  or two real alternatives where there are any (e.g. `main` and `master`), and
  `None` where a setting can be empty (check command, local test setup, test
  conventions, dev server, branch protection). The user types any other value
  through the "Other" option.
- For long free-text settings (test conventions, stack and deployment, branch
  protection), put a short summary of what you detected in the option and the
  full text in its description.

If an answer is unclear or contradicts the repo (e.g. a remote that `git remote`
does not list), say so and ask again for that setting only.

## 4. Confirm and write

Show the user the full section you are about to write and ask once to confirm
it (AskUserQuestion: "Write it" / "Change something"). On a change, ask about
those settings again and show it once more.

Then write it to `CLAUDE.md` in exactly this format, one line per setting, values
in backticks where they are commands or paths, `None` where the user chose none:

```markdown
## Agentic build environment
- Requirements dir: `<dir>/`
- Source and test dirs: `<dir>/`, `<dir>/`
- Check command: `<command>` | None
- Test command: `<command>`
- Local test setup: <how to run the tests locally, or None>
- Test conventions: <rules, as sub-bullets if more than one, or None>
- CI-only skip form: <the skip line(s) to use>
- Dev server: `<command>` on port <port> | None
- Stack and deployment: <one or two lines>
- Git remote: `<remote>`
- Base branch: `<branch>`
- Branch name rules: <allowed characters, and why if CI depends on it>
- Branch protection: <rules and required checks, or None known>
```

- **Existing section:** replace it in place (from its heading to the next `## `
  heading or the end of the file), renaming an old `## Agentic build` heading.
  Leave the rest of `CLAUDE.md` unchanged.
- **No section:** append it to the end of `CLAUDE.md`, after a blank line.
- **No `CLAUDE.md`:** create it with a `# <project name>` heading and the section.

Do not commit the change; the gitprocess skill or the user does that. Report the
path you wrote and any settings left as `None`.
