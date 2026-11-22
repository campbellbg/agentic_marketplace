---
name: deploy-environments
description: Use this skill whenever work involves a project's production or non-production (ephemeral, per-PR preview) environments - writing, planning, reviewing or shipping the GitHub Actions workflows and CloudFormation that deploy them. It holds the environment model, naming rules and the templates for each hosting pattern (currently `app-serving`). The agentic-build agents and the gitprocess skill load it when the project's `Hosting pattern` setting is not `None`. Trigger on phrases like "ephemeral environment", "PR preview", "preview environment", "deploy to production", "S3 and CloudFront", "hosting pattern".
---

# Deploy Environments

How a project's environments are laid out, named, deployed and torn down. The
runtime work happens in GitHub Actions; this skill tells the agents how to write
those workflows, what to plan and review, and what shipping a PR involves.

## Settings this skill reads

From the `## Agentic build environment` section of `CLAUDE.md`:

| Setting | Use |
|---------|-----|
| Hosting pattern | Which reference below applies. `None` or missing: this skill does not apply. |
| Production environment name (`<env>`) | The base of every resource name (see Naming). Lowercase letters, digits and `-`, starting with a letter, at most 40 characters. |
| Base branch (`<base-branch>`) | PRs to it get a preview; pushes to it deploy production. |

If Hosting pattern is set but `<env>` is missing, stop and say so: use the
`agentic-build-environment` skill to set it. Do not invent names.

AWS access is fixed, not a setting: follow the AWS access rule in the
`agentic-conventions` skill (OIDC, `secrets.AWS_DEPLOY_ARN`,
`secrets.AWS_DEPLOY_REGION`).

## Patterns

| Hosting pattern | Reference | Assets |
|-----------------|-----------|--------|
| `app-serving` | [references/app-serving.md](references/app-serving.md) | `assets/app-serving/` |

Read the reference for the project's pattern before writing, planning or
reviewing anything it covers. A pattern not in this table is not supported yet:
stop and say so rather than improvising one.

## Environment model (all patterns)

- **Production** - dedicated resources, named from `<env>`. Deployed by a
  workflow on push to `<base-branch>` (i.e. on merge), and only from there.
- **Non-production** - one shared set of resources per project, named
  `<env>-nonprod`. Each open PR gets its own slot, `pr-<number>`, inside it.
  - Deployed by a workflow on `pull_request` to `<base-branch>` (opened,
    synchronize, reopened).
  - Removed by the same workflow when the PR closes (merged or not).
  - The PR's version of the shared infrastructure template is deployed to the
    shared stack, so a template change reaches every open preview. Production
    changes only on merge.

## Naming

| Thing | Production | Non-production |
|-------|------------|----------------|
| Resource name / CloudFormation stack | `<env>` | `<env>-nonprod` |
| PR slot | - | `pr-<number>` |

Patterns derive their resource names (buckets, distributions, functions) from
the resource name; the reference lists them. Use the PR **number**, never the
branch name or PR title, in anything that names, paths or deletes a resource.

## Rules for the workflows (all patterns)

- Copy the pattern's asset files and fill in the placeholders; keep their
  structure. Adapt only what the reference marks as adaptable (build steps,
  directories, CSP). Pin each third-party action to the full commit SHA of the
  release tag, with the tag in a trailing comment (look it up with
  `gh api repos/<owner>/<action>/git/ref/tags/<tag>`). If its `object.type` is
  `tag` (an annotated tag), that SHA is the tag object, not the commit: get the
  commit with `gh api repos/<owner>/<action>/git/tags/<sha> --jq .object.sha`.
- `on: pull_request`, never `pull_request_target`. Preview jobs run only for PRs
  from this repository (`github.event.pull_request.head.repo.full_name ==
  github.repository`), because fork PRs get no OIDC token.
- Concurrency group per PR (`pr-preview-<number>`, cancel in progress), and one
  group for production (no cancel), so two deploys never race on the same slot.
- Untrusted event values reach `run:` steps through `env:`, never `${{ }}`
  inside the script.
- `permissions:` default `contents: read`; `id-token: write` only on jobs that
  assume the AWS role; `pull-requests: write` only on the job that comments.
- The preview job publishes its URL as a job output, in the job summary, and as
  a PR comment when the PR opens or reopens.
- The preview workflow runs the project's test command against the preview with
  `PREVIEW_URL` set, so deployed-site tests (see the conventions' test rules) run
  as PR checks before merge.
- The shared non-production stack is updated by every open PR. A deploy waits
  for it to leave any `*_IN_PROGRESS` state and retries if another PR started an
  update at the same moment.
- Teardown must succeed when there is nothing to remove (stack missing, slot
  already empty).
- Never deploy or tear down from a local machine, and never run the workflows'
  commands yourself.

## One-time prerequisites (the user does these, not CI or an agent)

The repo secrets `AWS_DEPLOY_ARN` and `AWS_DEPLOY_REGION` exist, and the
deploy role in `AWS_DEPLOY_ARN` must:

- Trust GitHub OIDC for this repo with the subjects
  `repo:<owner>/<repo>:pull_request` (previews) and
  `repo:<owner>/<repo>:ref:refs/heads/<base-branch>` (production), audience
  `sts.amazonaws.com`.
- Allow what the pattern deploys (the reference lists it).

If a workflow fails because of either, report it as a prerequisite for the user;
do not widen the trust or permissions yourself.

## Who uses this skill

- **decompose-requirement** - plans the hosting workflows and
  template into the first iteration that deploys anything (if the repo does not
  have them yet), and plans deployed-site tests as `CI only: PREVIEW_URL`.
- **code-builder** - writes and maintains the files from the assets.
- **review-security** - checks the files against the reference's checklist.
- **review-tester** - checks deployed-site tests read `PREVIEW_URL` and skip
  locally.
- **gitprocess** - waits for the preview checks before merging, then reports the
  production deploy and the preview teardown.

## Extending

A new pattern (e.g. an app with a database) is a new row in Patterns, a new
reference file and a new assets directory. Keep the environment model, naming
and workflow rules above; put what is specific to the pattern in its reference.
