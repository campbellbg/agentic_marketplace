# Pattern: `app-serving`

A single-page app (static build output) served from a private S3 bucket through
CloudFront. No server-side code; anything that needs one is a different pattern.

## Bounds

What a project on this pattern can and cannot have (see Environment bounds in
the `agentic-conventions` skill).

**Within bounds:**
- A client-side app, built to static files and served from the bucket.
- Data and state kept in the browser (e.g. memory, `localStorage`, IndexedDB).
- Static files shipped with the build (e.g. JSON content, images).
- Calls from the browser to an existing public API that needs no secret, with
  its origin added to the CSP `connect-src`.

**Out of bounds:**
- Any server-side code: an API, Lambda, Lambda@Edge, server-side rendering, or
  CloudFront Function logic beyond the routing function.
- Any data stored outside the browser: a database, user uploads, or writes to
  the bucket from the app.
- Sign-in or user accounts that need a backend or an identity service (e.g.
  Cognito).
- Any secret the app needs at runtime. Everything in the build is public.
- Any AWS resource the template does not have, or any change to it beyond what
  Files and placeholders allows. That includes custom domains and certificates.
- Any deploy-role permission beyond Deploy role permissions below.

## Resources

One CloudFormation template, `infra/app-serving.cfn.yaml`, deployed twice with
different parameters:

| | Production | Non-production (shared) |
|---|---|---|
| Stack (`ResourceName`) | `<env>` | `<env>-nonprod` |
| `EnvironmentType` | `prod` | `nonprod` |
| S3 bucket | `<env>-<account-id>` (dedicated) | `<env>-nonprod-<account-id>` (shared) |
| Bucket layout | the build at the root | one directory per PR: `pr-<number>/` |
| CloudFront distribution | dedicated, comment `<env>` | shared, comment `<env>-nonprod` |
| CloudFront Function | `<env>-spa-routing` | `<env>-nonprod-spa-routing` |
| URL | `https://<prod-domain>/` | `https://<nonprod-domain>/pr-<number>/` |
| Deployed by | `deploy-production.yml`, push to `<base-branch>` | `pr-preview.yml`, PR to `<base-branch>` |

The account ID suffix keeps bucket names globally unique. Domains are the
distributions' default `*.cloudfront.net` names (stack output
`DistributionDomainName`); custom domains are not part of this pattern yet.

Both environments share these, from the template:

- Bucket: private (all public access blocked, bucket-owner-enforced), SSE-S3
  encryption, policy that lets only its own distribution read (Origin Access
  Control, `AWS:SourceArn` condition) and denies non-TLS access. Retained if the
  stack is deleted.
- Distribution: HTTPS only (redirect), HTTP/2 and 3, GET/HEAD only,
  `Managed-CachingOptimized` cache policy, a response headers policy with CSP,
  HSTS, `nosniff`, `X-Frame-Options: DENY` and `Referrer-Policy`. Non-production
  also sends `X-Robots-Tag: noindex, nofollow`.
- Routing function (viewer request):
  - Production: a path with no file extension (a client-side route) is served
    `/index.html`.
  - Non-production: only `/pr-<number>/...` is served; anything else is 404.
    `/pr-<n>` redirects to `/pr-<n>/`, and an extensionless path under it is
    served `/pr-<n>/index.html`.

## The app must build for a base path

A preview lives under `/pr-<number>/`, so asset URLs and the router must use a
base path. The workflows pass it as the `BASE_PATH` environment variable at build
time (`/pr-<number>/` for previews, `/` for production). The builder makes the
app honour it, e.g.:

- Vite: `base: process.env.BASE_PATH ?? '/'` in `vite.config.*`; routers use
  `import.meta.env.BASE_URL` as their basename.
- Create React App: `PUBLIC_URL` from `BASE_PATH` in the build script.
- Angular: `ng build --base-href "$BASE_PATH"`.

No absolute `/...` URLs to the app's own assets or routes in source; they would
escape the PR slot. Hash routing is not needed.

## Deploy steps (what the workflows do)

1. Build with `BASE_PATH` set.
2. `aws cloudformation deploy` the stack (`--no-fail-on-empty-changeset`). The
   preview workflow first waits for the shared stack to leave any
   `*_IN_PROGRESS` state, since another PR may be updating it, and retries the
   deploy up to three times if another PR started an update at the same moment.
3. Read the stack outputs `BucketName`, `DistributionId`,
   `DistributionDomainName`.
4. Upload: the hashed assets directory with
   `Cache-Control: public,max-age=31536000,immutable`; everything else with
   `Cache-Control: no-cache` and `--delete` (excluding the hashed assets, so
   clients still on an old `index.html` keep working).
5. Invalidate (`/pr-<number>/*` or `/*`) and wait for it to finish.
6. Previews: publish the URL; then the `test-preview` job runs the project's test
   command with `PREVIEW_URL` set.
7. On PR close: `aws s3 rm s3://<bucket>/pr-<number>/ --recursive` and invalidate
   `/pr-<number>/*`.

## Files and placeholders

Copy from `assets/app-serving/` in this skill's directory:

| Asset | Copy to |
|-------|---------|
| `app-serving.cfn.yaml` | `infra/app-serving.cfn.yaml` |
| `pr-preview.yml` | `.github/workflows/pr-preview.yml` |
| `deploy-production.yml` | `.github/workflows/deploy-production.yml` |

Fill in every `<...>` placeholder:

| Placeholder | Value |
|-------------|-------|
| `<production-environment-name>` | Production environment name setting |
| `<base-branch>` | Base branch setting |

Adapt only these, to the project:

- Build steps (`setup-node`, install, build) to the project's package manager
  and Node version; the build must still read `BASE_PATH`.
- `BUILD_DIR` (e.g. `dist`, `build`) and `HASHED_ASSETS_DIR` (e.g. `assets`,
  `static`), relative to the build output.
- The test command in `test-preview`, if it is not `npm test`.
- `ContentSecurityPolicy` parameter, only as far as the app needs (e.g. an API
  origin in `connect-src`). Never add `'unsafe-eval'`; add `'unsafe-inline'`
  only with a reason in a template comment.

## Deploy role permissions (user prerequisite)

The role needs, scoped to these resources where the service allows:
CloudFormation on stacks `<env>` and `<env>-nonprod`; S3 create/configure and
object read/write/delete/list on buckets `<env>-*`; CloudFront distributions,
functions, origin access controls, response headers policies and invalidations.

## Review checklist

- Template is the asset's structure: bucket private with OAC and the
  `AWS:SourceArn` condition, TLS-only deny, encryption, no public ACLs or
  website hosting, HTTPS-only viewer policy, security headers policy attached.
- Non-production routing function serves only `/pr-<number>/` paths.
- Preview workflow: `pull_request` (not `_target`), same-repo guard, per-PR
  concurrency, PR number (not branch name) in every path and name, values passed
  through `env:`, minimal `permissions:`, actions pinned to SHAs.
- Teardown removes only `pr-<number>/` and runs on every close.
- Production workflow runs only on push to `<base-branch>`, with no manual or
  other-branch trigger.
- App builds honour `BASE_PATH`; no absolute self-URLs.

## Known limits

- Default CloudFront domains only; no custom domain or ACM certificate yet.
- The first preview or production deploy creates a distribution, which takes
  several minutes.
- A PR that changes the template changes the shared non-production stack for
  every open preview.
- The retained bucket must be emptied and deleted by hand before a deleted
  stack can be recreated with the same name.
