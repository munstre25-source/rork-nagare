# Jojo deployment

## Separate release paths

| Service | Release path |
| --- | --- |
| Web | Existing Vercel GitHub integration and root `vercel.json` |
| Edge Functions | GitHub Actions workflow `deploy-supabase-edge.yml` on relevant pushes to `main` |
| iOS | Revyl remote release build and App Store Connect upload |

The Edge workflow type-checks the pinned Deno dependencies, runs the Edge tests, and identifies affected functions before it requests production approval. It checks direct function changes and follows shared imports transitively. Changes to an established shared dependency lock may require deploying every dependent bundle. A documentation or test-only change cannot deploy a function. Production runs queue without canceling an in-progress deployment.

## Credentials and approval

The `supabase-production` GitHub environment restricts deployment to `main` and requires the GitHub repository owner to approve the job. Admin bypass is disabled. The environment variable `SUPABASE_PROJECT_REF` holds the nonsecret target reference. Its `SUPABASE_ACCESS_TOKEN` secret should be scoped to that project with Project Settings read and Edge Functions read/write. Replace the token in the same environment when it expires.

Maintain runtime secrets in Supabase. The build token authenticates the deployment and has separate permissions from the runtime credentials. The workflow does not sync runtime secrets or apply database migrations.

## Validate and review

From `ios-nagare`, use Deno 2.9.6 to run the same checks as GitHub.

```bash
mapfile -t entries < <(find supabase/functions -type f \( -name index.ts -o -name '*_test.ts' -o -name '*.test.ts' \) | sort)
deno check --config supabase/functions/deno.json --frozen-lockfile "${entries[@]}"
deno test --config supabase/functions/deno.json --frozen-lockfile --allow-env supabase/functions
python3 supabase/tools/plan-edge-deploy.py <before-sha> <head-sha>
```

When a dependency intentionally changes, run both Deno commands without `--frozen-lockfile`, review the lockfile diff, then repeat the frozen checks.

Before approving in GitHub Actions, verify the selected functions and commit in the validation job summary. For a function that differs from the initial production audit, use the saved bundle to review the full production-to-Git change, including shared files. If a live version changed since the audit or last reviewed run, download the new version using the read-only Supabase CLI into a separate directory and compare again before approval.

Check request and response compatibility against the installed App Store app. Preserve gateway JWT verification and the function-level checks for public, admin, and user routes. Test changed requests on a nonproduction project before approving. After deployment, check Supabase logs and exercise an affected read-only app flow on the currently shipping version. Review the result of each target before rerunning a partial deployment. Use a new revert commit if a later deployment has already succeeded.

## Production audit on 28 November 2026

- All 25 deployed functions had local entry points. Nine downloaded bundles matched the worktree and 16 differed, including shared modules. The [manifest](audit/production-2026-11-28/manifest.json) records exact gateway settings, versions, full source manifests and file-level differences.
- `review-catalog` and `catalog-inventory` had gateway JWT verification disabled. Both keep their existing function-level authorization. All other listed routes use the gateway verification mode recorded in the manifest.
- Two deployed entry point versions were absent from the public main history. The audit stores those exact source files and references the remaining production blobs by Git object ID and SHA-256.
- Production recorded 43 applied migrations. Four are absent from the active local sequence and overlap existing local files with different timestamps. Twelve local versions were absent from the production history. The recovered [applied SQL](audit/applied-migrations/) is for review. Resolve the differences before enabling any database migration pipeline.
- Redacted Gitleaks found no credentials in the downloaded Edge bundles. The Git history scan flagged a legacy Supabase JWT in the admin HTML. Its role claim is `anon`, a client credential. No signing material or production environment values were included in the audit.

## Roll back

For a GitHub deployment, open a revert pull request targeting the reviewed function changes. Validate and approve the resulting deployment as usual. Keep a record of the last deployed Git revision and the resulting Supabase function versions.

For the initial audited production state, recover one exact bundle into an empty local directory. Use a full clone so the referenced Git objects are available.

```bash
python3 supabase/tools/restore-edge-baseline.py <function> <empty-directory>
```

The recovery includes that function's exact shared files and gateway mode. Review the recovered bundle before an emergency redeploy. Use only the scoped token and an explicit function name and project reference. Never use the prune option for a rollback. A database rollback requires a separately reviewed SQL plan.
