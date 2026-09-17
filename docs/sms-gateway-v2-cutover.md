# SMS Gateway 2.0 controlled rollout

1. Apply migration 00076 through the normal reviewed migration process.
2. Create a dedicated Supabase Auth user with no LIS staff profile; register its UID and the stable local instance ID through `register_sms_gateway_v2_instance` as Super Admin.
3. Provision the publishable key, dedicated Auth credentials, and existing Sparrow configuration into the machine-scope DPAPI store. Keep claiming disabled and local mode `shadow`.
4. Verify heartbeat and preflight, then prove the principal cannot read patient, bill, report, result, or queue tables directly.
5. At cutover, confirm no `Processing` jobs, stop `BimalPathologySMSGateway`, enable v2 claiming using the exact guarded confirmation, switch local mode to `active`, and start `BimalPathologySMSGatewayV2`.
6. Observe one genuine Payment Confirmation and one genuine Report Ready job. Confirm one provider acceptance and guarded `Sent` completion per row. Do not generate synthetic production SMS.
7. Roll back by disabling/stopping v2, confirming no active `Processing` rows, and restarting Gateway 1.x. No queue migration is involved.

Do not revoke the 1.x service-role RPC path or uninstall 1.x until a separately approved stability period completes.
