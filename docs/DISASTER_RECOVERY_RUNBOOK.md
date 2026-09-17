# Bimal Pathology Cloud disaster-recovery runbook

Status: procedure defined; no successful isolated full restore has yet been recorded. A backup is not accepted as recoverable until the restore rehearsal checklist below passes.

## Recovery scope and ownership

| Asset | Backup mechanism | Restore mechanism | Current recoverability |
|---|---|---|---|
| PostgreSQL schema/data | Supabase CLI `db dump`/PostgreSQL custom-format dump using an approved privileged connection | Restore into a new isolated Supabase project/PostgreSQL instance, then validate migrations and invariants | Procedure available; not yet demonstrated |
| Supabase Auth identities | Authorized Admin API export of identity metadata plus documented provider configuration; never export password hashes into the repository | Provider-supported/admin-mediated recreation; password-reset invitations may be required | Password credentials and sessions cannot be assumed portable |
| Supabase Storage | Enumerate every bucket and download each object with path, size, MIME type and SHA-256 manifest | Recreate private buckets/policies, upload objects to identical paths, verify hashes | Procedure available; no complete inventory/restore demonstrated |
| Supabase project configuration | Redacted inventory of Auth URLs/providers, Edge Function names, schedules, RLS/migration head and Storage policies | Reconfigure through dashboard/CLI and compare against inventory | Secrets must come from the approved secret vault/operator, not backup files |
| Cloudflare Pages | Source/build command, environment-variable names, domains, redirects and release manifest | Create/repair Pages project, restore variables from secret vault, deploy an approved artifact | Deploy history is not a database backup |
| Gateway DPAPI configuration | Copy encrypted Gateway configuration plus service identity, machine name and gateway version | Restore only under the same Windows DPAPI machine/user context, or re-enter secrets and create a new protected configuration | Existing DPAPI blob is not portable by itself |
| Sparrow | Redacted sender/template/endpoint/IP-allowlist inventory | Obtain credentials from authorized operator, restore allowed IP and send controlled acceptance SMS | Provider credentials/balance cannot be recovered from source |

## Backup creation

1. Record UTC time, operator, Supabase project ref, current remote migration ledger and `release-manifest.json`.
2. Put backup output in a new restricted directory outside the web workspace. Never commit dumps or secrets.
3. Create both schema and data dumps using the Supabase CLI/PostgreSQL connection method approved for the linked project. Capture command exit codes, file sizes and SHA-256 hashes.
4. Export an Auth identity inventory using a service-role/Admin API process. Include IDs, email/phone, timestamps and provider metadata; exclude access tokens, refresh tokens and plaintext secrets.
5. Enumerate Storage buckets and objects. Download every object and create a manifest containing bucket, path, byte length and SHA-256.
6. Capture a redacted configuration inventory: variable names and owners only. Store actual secrets in the operational secret manager.
7. Copy the Gateway DPAPI blob, service installation metadata and Gateway binary/version. Record the Windows service account and originating machine because DPAPI recovery depends on them.
8. Encrypt the backup set with an organization-controlled key, copy it to a second failure domain, and verify both copies by hash.

## Isolated restore rehearsal

1. Create a new isolated Supabase project with no production DNS, SMS or Gateway connection.
2. Restore schema/data and verify migration history matches the recorded head.
3. Recreate Auth configuration and import what the provider supports. Issue test-user password resets instead of assuming production credentials are portable.
4. Recreate private Storage buckets/policies, upload objects and compare every object hash.
5. Deploy the recorded frontend artifact to a non-production Cloudflare hostname with SMS disabled.
6. Configure a test Gateway with non-production credentials. If the original DPAPI context is unavailable, re-enter secrets; do not copy an unreadable blob and call it restored.
7. Run patient, bill, payment, sample, result, sign-off, secure report and SMS-queue acceptance using synthetic records.
8. Verify historical snapshot hashes, public-token behavior, object access controls, RLS and last-super-admin protection.
9. Record counts, failures, recovery-point objective and recovery time. Obtain Admin and clinical sign-off.

## Acceptance rule

DR remains **Not Ready** until one isolated rehearsal completes with database invariants, Auth access, Storage hashes, frontend release identity and synthetic end-to-end workflows verified. Production must never be used as the restore target for a rehearsal.

## 2026-08-30 remediation rehearsal record

- A clean disposable PostgreSQL environment was rebuilt successfully through migrations `00000` to `00075`, with deferred `00070` excluded. It contained 247 canonical tests, 31 panels, 206 result-entry-ready tests, zero generic incomplete tests, and the Pus Culture worksheet schema.
- The linked production migration ledger was inspected read-only and confirmed production head `00074`; neither `00070` nor `00075` is applied.
- This was a migration-chain rehearsal, not an accepted production-backup restore. A complete encrypted production backup could not be created because no organization-controlled backup encryption key or approved secrets-recovery package was available in the task context. Auth credential portability, Storage object hash restoration, and machine-bound Gateway DPAPI re-provisioning therefore remain unproved.
- Required next action: provide the approved backup encryption recipient/key, authorized secret-vault recovery procedure, and an isolated restore target. Then create the DB/Auth/Storage/config bundle, encrypt it before persistence, restore it, compare object/count/hash manifests, re-provision Gateway secrets, and record start/end time plus clinical sign-off.

## 2026-08-31 workspace-local technical recovery rehearsal

- Production `public` data and the Supabase migration ledger at head `00075` were streamed from PostgreSQL 17 directly into an authenticated AES-256-GCM archive. The 256-bit content key is protected with Windows LocalMachine DPAPI under the ignored `recovery/keys` path.
- Auth recovery evidence is aggregate-only; password hashes, tokens, email addresses and credentials were not placed in the archive or inventories. Storage contained one private `diagnostic-reports` bucket with zero objects at the recovery point, so no object payload export was required.
- The encrypted archive was decrypted only inside an ACL-restricted `.recovery-work` directory and restored into a loopback-only PostgreSQL 17 cluster. The restored ledger head was `00075`; schema, function, RLS, policy, role/permission, SMS, report snapshot and referential checks passed. The server, decrypted archive and cluster were then removed.
- Machine-readable evidence is generated under ignored `recovery/inventories`, `recovery/restore-tests`, and `recovery/manifests` paths.
- Technical encrypted backup/restore is verified. Independent failure-domain key custody remains unresolved because both the encrypted archive and machine-bound DPAPI key are constrained to this workspace/machine for this pass.

## 2026-08-31 clean SMS Gateway production ownership

- Permanent SMS owner: Windows service `BimalPathologySMSGatewayClean`, running
  as `NT AUTHORITY\LocalService` from
  `C:\Program Files\BimalPathology\SmsGatewayClean` with protected state under
  `C:\ProgramData\BimalPathology\SmsGatewayClean`.
- Stable instance: `a7c7e059-0dc9-4594-8d0d-a507d2b19ff1`; accepted package
  SHA-256: `03d784cf19ef1a39d1d01b312c0c1a24d5fd05c918a6bb197f341fdc461acabd`.
- Gateway 1.x and experimental Gateway V2 are stopped, startup-disabled, and retained for audit.
  They are not immediately operational rollback paths. Before any rollback,
  verify credentials and authorization, disable clean claiming, inspect active
  leases/provider fences, and prevent concurrent claimers.
- Clean Gateway DPAPI state is machine/context-bound and must remain associated
  with the LocalService installation. Do not decrypt it for backup inventory.
- The deployed `bimal-pathology-report-artifacts` Cloudflare Worker now uses a
  dedicated non-staff Auth identity and the guarded artifact RPC boundary from
  migrations `00081`/`00082`. Its legacy service-role secret binding was removed,
  and `service_role` cannot execute the artifact RPCs. Project-wide legacy API
  keys remain enabled pending an authorized Supabase Dashboard/Management API
  deactivation; this control-plane item must be completed before the exposed
  legacy key is considered revoked. The clean Gateway does not consume it.

## 2026-08-31 production report-delivery ownership and release identity

- Production database and LIS frontend are aligned at migration head `00085`.
- Main public website: `https://www.bimalpathology.com.np/`.
- Laboratory operational LIS: `https://lis.bimalpathology.com.np/`.
- Patient SMS report/PDF delivery origin: `https://dashboard.bimalpathology.com.np/`.
- Supabase remains the authoritative backend/database. Finalized report PDFs are
  immutable private objects in Cloudflare R2 and are streamed only after guarded
  token and exact report-version authorization by `bimal-pathology-report-artifacts`.
- Clean Gateway service `BimalPathologySMSGatewayClean` remains the permanent SMS
  owner. It consumes only server-eligible queue work and has no responsibility for
  rendering or storing report PDFs.
- Historical `https://lis.bimalpathology.com.np/r/<token>` links remain supported;
  new dashboard report links use the private PDF delivery Worker.
- ReportReady eligibility is server-gated on an immutable PDF artifact reaching
  `Ready`; the permanent Clean Gateway then delivers the queued notification
  through Sparrow without direct report or R2 access.
- Final live SMS-to-dashboard-PDF recipient acceptance is explicitly assigned to
  the operator and is recorded as `MANUAL OPERATOR ACCEPTANCE PENDING`. This is
  an operational acceptance item, not a software release blocker.
