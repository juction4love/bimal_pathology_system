# Authoritative report PDF artifacts

`REPORT_PDFS` binds to a private R2 bucket with no public domain. Supabase access
uses a dedicated non-staff Auth identity and the guarded report-artifact RPC
boundary. `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
`REPORT_ARTIFACT_WORKER_EMAIL`, `REPORT_ARTIFACT_WORKER_PASSWORD`, and
`ARTIFACT_CONTROL_SECRET` are Worker secrets, never vars. A project-wide
service-role key is forbidden.

The Wrangler account is pinned to `c0032014d8ed600a4451ed6b7063db76`.
The existing production bucket is `bimal-pathology-private-reports`. It is reused
through the native `REPORT_PDFS` binding; no duplicate bucket is provisioned.
The S3 API endpoint and S3 access keys are not needed by this Worker.

The generator consumes only the frozen clinical snapshot and minimum immutable
report identity returned by a dedicated-worker-only leased RPC. It uploads an immutable SHA-addressed PDF and
then records matching evidence in Supabase. `/r/<opaque-token>` hashes the
token, asks Supabase to authorize the exact ready artifact, verifies the stored
bytes against the database SHA-256, and streams it with `Cache-Control: private,
no-store`; raw R2 URLs and keys are never returned.

Historical patient URLs remain `https://lis.bimalpathology.com.np/r/<token>`.
New accepted patient URLs use:

`dashboard.bimalpathology.com.np/r/<token>`

The compatibility endpoint `/api/reports/<opaque-token>/pdf` remains available.
This small Worker is the complete controlled origin for the dedicated dashboard
hostname, including a non-sensitive root health response and fail-closed 404s.

Production authorization uses migrations `00081` and `00082`: one registered,
enabled `ReportArtifactWorker` Auth identity may execute only the three artifact
RPCs. The identity must remain inactive in `user_profiles`, have no role or
direct-permission rows, and its password must exist only as a Worker secret.
Migration `00082` removes legacy `service_role` execution from those RPCs.

`GENERATION_ENABLED` remains an independent operational control. Migrations
`00083` and `00084` preserve old LIS URLs while gating only new dashboard-hosted
ReportReady notifications on immutable artifact readiness. Migration 00070 and
cloud SMS remain deferred; Clean Gateway remains unchanged.

Production database and LIS release identity are aligned at migration head
`00085`. Migration `00085` adds the dedicated-worker-only, safe-metadata
acceptance probe. `POST /internal/generate` runs one bounded generation cycle and
`POST /internal/verify` verifies an existing Ready artifact; both fail closed and
require the operational Bearer secret. The scheduled trigger remains a fallback.

Domain responsibilities remain deliberately separate: `www.bimalpathology.com.np`
is the public website, `lis.bimalpathology.com.np` is the laboratory application,
and `dashboard.bimalpathology.com.np` is the patient PDF delivery origin.

The final live SMS recipient test is operator-owned and remains manual acceptance;
it does not change the immutable-PDF, guarded-RPC, private-R2, or readiness-gate
release contracts.
