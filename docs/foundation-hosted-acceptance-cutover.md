# Foundation hosted acceptance and cutover package

This package is intentionally fail-closed. Permanent staging is pinned to `ilcnctiaumrjbnlmnise`. The retired project `qvuidmgddjoircheapzk` is permanently refused and must never be cited as corrected-foundation evidence.

## Authorized disposable acceptance project

The operator must use the authorized empty permanent staging project `ilcnctiaumrjbnlmnise` and set these values in the operator shell. Values are deliberately not stored in the repository:

- `FOUNDATION_PROJECT_REF` — the new 20-letter project ref
- `FOUNDATION_SUPABASE_URL=https://<ref>.supabase.co`
- `FOUNDATION_TARGET_ENVIRONMENT=isolated-acceptance`
- `FOUNDATION_TARGET_CONFIRMATION=I_CONFIRM_SYNTHETIC_ACCEPTANCE_<ref>`
- `FOUNDATION_EXPECTED_START_HEAD=empty` (or `00053` only for a separately proven baseline)
- Supabase CLI authentication/linkage for that exact project

Run `node scripts/verify-foundation-hosted-package.js`, then run `node scripts/prepare-hosted-foundation-apply.js` without `--execute`. Inspect the migration-list and dry-run evidence. Execution is deliberately unavailable until the additional `FOUNDATION_APPLY_CONFIRMATION=APPLY_FOUNDATION_TO_<ref>` is supplied and the same command is rerun with `--execute`.

The resulting head must be `00056`. Run `psql` against the isolated project database with `scripts/hosted-foundation-candidate-proof.sql` to capture authoritative function bodies, signatures, constraints, policies, and grants. The proof fails if cloud-SMS objects exist.

## Synthetic hosted acceptance

Set `STAGING_PROJECT_REF`, `STAGING_SUPABASE_URL`, `STAGING_ANON_KEY`, `STAGING_SERVICE_KEY`, `STAGING_TEST_PASSWORD`, and `STAGING_EXPECTED_MIGRATION_HEAD=00056` to the same isolated project. The service key is operator-shell-only and must never be exposed to the browser. Then set `FOUNDATION_ACCEPTANCE_RUN_CONFIRMATION=RUN_SYNTHETIC_ACCEPTANCE_ON_<ref>` and run `node scripts/run-hosted-foundation-acceptance.js`.

The suite creates only `example.invalid` Auth users and synthetic clinical fixtures. It covers Auth personas, PostgREST RPC shape, direct mutation denial, catalogue/billing, collection readiness, two-JWT revision conflict, critical acknowledgement, verification, sign-off/amendment concurrency, token/version resolution, and ReportReady identity. It does not invoke Sparrow or cloud SMS.

For browser acceptance, provide a local or explicitly isolated frontend connected to the same project plus the `STAGING_ACCEPTANCE_*` variables required by `stagingAcceptanceGuard.js`. Create a fresh synthetic Received result item at revision 0, set its UUID plus distinct Admin/Technician-A/Technician-B `example.invalid` emails, and run `node scripts/staging-browser-fixture-setup.js`. Set both technician passwords to `STAGING_TEST_PASSWORD`, then run `npx playwright test --config playwright.foundation.config.js`. The guard refuses production, the quarantined staging ref, Sparrow, and other Supabase projects.

## Current production promotion preflight (do not execute during acceptance)

The foundation workflow documented above is historical acceptance evidence.
The current production baseline is `00060`, the candidate head is `00069`, and
the exact pending deployable set is `00061` through `00069`. Run
`node scripts/production-foundation-cutover-guard.js` without `--execute`; the
guard verifies the exact project ref, baseline head, candidate checksums,
migration-set identity, and exclusion of deferred cloud-SMS `00070`.

Execution remains a separate controlled change. It additionally requires the
exact `FOUNDATION_PRODUCTION_APPLY_CONFIRMATION` value enforced by the guard,
fresh backup/restore evidence, clean `00060→00069` rehearsal, and explicit
operator authorization. Nothing in this document grants that authorization.

No command in this document deploys Cloudflare, sends Sparrow SMS, applies the deferred cloud-SMS migration, or deploys the accepted frontend release.
