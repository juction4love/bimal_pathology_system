# Bimal Pathology SMS Gateway — Clean 2.0

Independent Node.js 24/TypeScript SMS outbox worker. It uses only the guarded
Gateway v2 Supabase RPC boundary, a generic `SmsProvider`, machine-scope DPAPI,
and a minimal native Windows Service host. Tests use mocks and never contact a
Supabase project or SMS provider.

## Production ownership

As of 2026-08-31, the production service is `BimalPathologySMSGatewayClean`,
installed at `C:\Program Files\BimalPathology\SmsGatewayClean` with protected
state under `C:\ProgramData\BimalPathology\SmsGatewayClean`. It runs as
`NT AUTHORITY\LocalService` using the bundled Node.js runtime and the native
service host. Stable production instance identity:
`a7c7e059-0dc9-4594-8d0d-a507d2b19ff1`.

Accepted package SHA-256:
`03d784cf19ef1a39d1d01b312c0c1a24d5fd05c918a6bb197f341fdc461acabd`.

The clean Gateway is the sole active SMS claimant. The historical Gateway 1.x
and experimental Gateway V2 services are stopped and retained as audit and
software rollback artifacts; neither is an immediately operational rollback
until its identity, credentials, and authorization are separately verified.

For rollback, first disable clean instance claiming, stop the clean service if
necessary, and inspect every Processing lease and provider-call fence. Never
resend an ambiguous provider outcome. Enable an older implementation only after
its credentials and runtime are independently proven, and never run two active
claimants concurrently.

DPAPI material is machine/context-bound. Preserve the clean ProgramData folder,
service identity, package, instance ID, and recovery evidence together. Never
copy or decrypt protected secrets into source control or plaintext recovery
notes.
