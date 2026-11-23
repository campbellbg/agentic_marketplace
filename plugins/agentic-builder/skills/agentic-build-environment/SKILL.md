---
name: agentic-build-environment
description: Use this skill to set up, seed, review or change the `## Agentic build environment` section of the project's CLAUDE.md. That section holds the settings the agentic-build command, its agents and the gitprocess skill read (requirements directory, source and test dirs, technology stack, deployment, hosting pattern, production environment name, secrets, git remote, base branch). Trigger on phrases like "set up the agentic environment", "set up the agentic build environment", "agentic environment variables", "configure agentic build", "agentic settings", "change the agentic base branch", and whenever the agentic-build command finds the section missing.
---

# Agentic Build Environment

Seed or update the `## Agentic build environment` section of the project's
`CLAUDE.md`. The `agentic-conventions` skill (load it) lists these settings
and the defaults agents use when one is not set. Every value comes from the
user: you detect a suggestion for each one, but the user confirms or replaces
it. Never write a value the user has not confirmed.

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
| Technology stack | Manifests and source, grouped by area (e.g. front-end, back-end, infrastructure, tests), each with its languages and frameworks |
| Deployment | Infrastructure-as-code (CloudFormation, Terraform, Kubernetes, Docker) and CI workflows (`.github/workflows/`). Unless the repo clearly does something else, suggest the conventions' default |
| Hosting pattern | Which `deploy-environments` pattern the project's production and per-PR preview environments follow. Only the patterns that skill lists are allowed (currently `app-serving`, for a static single-page app such as a Vite, Create React App or Angular build with no server code). There is no `None` |
| Production environment name | The base name of the project's AWS resources (production uses it as is, non-production adds `-nonprod`). Suggest the repo directory name as a slug: lowercase, every run of characters other than `a-z0-9` replaced by `-`, trimmed, at most 40 characters, prefixed with `app-` if it does not start with a letter |
| Secrets | A `secrets/` directory and whether `.gitignore` covers it (`git check-ignore -q secrets/`). Unless the repo clearly does something else, suggest the conventions' default |
| Git remote | `git remote -v`: `origin`, or the only remote |
| Base branch | The remote's default branch (`git symbolic-ref --short refs/remotes/<remote>/HEAD`, minus the `<remote>/` prefix); if it has none, the current branch (`git branch --show-current`); if that is empty, `main`. Offer `main` or `master`, whichever it is not, as the alternative |

## 3. Ask the user for every setting

**AWS access is not a setting** (see the conventions). Do not ask about AWS
credentials or region, and do not write them to the section.

Ask about **all nine settings**, in this order, so nothing is skipped:

1. Requirements dir
2. Source and test dirs
3. Technology stack
4. Deployment
5. Hosting pattern
6. Production environment name
7. Secrets
8. Git remote
9. Base branch

Use the AskUserQuestion tool, up to four settings per call, so three rounds cover
everything. For each setting:

- Make the question stand alone: name the setting, say in a few words what the
  agents use it for, and show what you detected.
- Offer the detected value as the first option, marked `(Recommended)`. Add one
  or two real alternatives where there are any (e.g. `main` and `master`). The
  user types any other value through the "Other" option. Hosting pattern and
  Production environment name are required: never offer `None` for them.
- For long free-text settings (technology stack, deployment,
  secrets), put a short summary of what you detected in the option and the
  full text in its description.

If an answer is unclear or contradicts the repo (e.g. a remote that `git remote`
does not list), say so and ask again for that setting only. Hosting pattern must
be a pattern `deploy-environments` lists, and Production environment name must
be set. It must match
`^[a-z][a-z0-9-]{1,38}[a-z0-9]$`, because it becomes S3 bucket and CloudFormation
stack names. Ask again until both hold.

If the project does not fit any listed pattern (e.g. it has server code), tell
the user the plugin cannot build it until a matching hosting pattern, with its
own deploy role, has been added. Do not write the section.

## 4. Confirm and write

Show the user the full section you are about to write and ask once to confirm
it (AskUserQuestion: "Write it" / "Change something"). On a change, ask about
those settings again and show it once more.

Then write it to `CLAUDE.md` in exactly this format, one line per setting, values
in backticks where they are commands or paths:

```markdown
## Agentic build environment
- Requirements dir: `<dir>/`
- Source and test dirs: `<dir>/`, `<dir>/`
- Technology stack:
  - <area>: <languages, frameworks>
  - <area>: <languages, frameworks>
- Deployment: <how and where deployments run>
- Hosting pattern: `<pattern>`
- Production environment name: `<name>`
- Secrets: <how secrets are created and referenced>
- Git remote: `<remote>`
- Base branch: `<branch>`
```

- **Existing section:** replace it in place, from its heading to the next `## `
  heading or the end of the file:
  - rename an old `## Agentic build` heading;
  - split an old `Stack and deployment` line into Technology stack, Deployment
    and Secrets;
  - if the section lacks the Hosting pattern and Production environment name
    lines, or either says None, ask about just those two settings and set them;
  - remove lines the format no longer has. AWS credentials and AWS region are
    dropped. Check command, test command, local test setup, test conventions,
    CI-only skip form, dev server, branch name rules and branch protection are
    worked out from the repo (see the conventions). If such a line holds a
    project-specific value, move it unchanged under a `## Build and test notes`
    section after this one, which the agents read and which wins over what they
    would work out.

  In your report, list what you dropped and what you moved. Leave the rest of
  `CLAUDE.md` unchanged.
- **No section:** append it to the end of `CLAUDE.md`, after a blank line.
- **No `CLAUDE.md`:** create it with a `# <project name>` heading and the section.

If Secrets uses a `secrets/` directory that `.gitignore` does not cover, add
`secrets/` to `.gitignore` and say so.

Do not commit the change. The build loop carries `CLAUDE.md` and `.gitignore`
onto the feature branch and commits them with the feature; otherwise the user or
the gitprocess skill commits them. Report the path you wrote.
