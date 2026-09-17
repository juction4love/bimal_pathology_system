-- Emergency forward compatibility for the production frontend r20260824a.
--
-- The deployed frontend still invokes the original five-argument billing RPC.
-- Migration 00050 revoked authenticated execution while introducing its guarded
-- package-aware successor. Restore only the authenticated EXECUTE privilege on
-- the existing transactional RPC; its auth.uid(), can_create_bill, validation,
-- idempotency, and atomic transaction behavior remain unchanged.
--
-- Do not add catalogue or administrative direct-write privileges here. Retire
-- this temporary grant in a later forward migration after the replacement
-- frontend is deployed and production-verified.

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(
    JSONB,
    JSONB,
    JSONB[],
    JSONB,
    TEXT
) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(
    JSONB,
    JSONB,
    JSONB[],
    JSONB,
    TEXT
) TO authenticated;

COMMENT ON FUNCTION public.create_patient_bill_and_order(
    JSONB,
    JSONB,
    JSONB[],
    JSONB,
    TEXT
) IS
    'Temporary authenticated compatibility for deployed frontend r20260824a. Internal can_create_bill authorization, transactionality, and idempotency remain authoritative. Revoke in a later forward migration after the replacement frontend is verified.';
