-- ====================================================================
-- Pre-Production Transactional Demo Data Cleanup
-- ====================================================================
-- Safely purges demo/test transactional data prior to production go-live.
-- Preserves all system users, roles, permissions, analyzers, settings,
-- catalogue definitions, and reference ranges.
-- Respects strict Foreign Key cascade ordering.
-- ====================================================================

BEGIN;

-- Disable immutability triggers for pre-production transactional cleanup
ALTER TABLE public.report_pdf_artifacts DISABLE TRIGGER enforce_report_pdf_artifact_immutability_trigger;
ALTER TABLE public.payment_transactions DISABLE TRIGGER trg_payment_transactions_immutable;
ALTER TABLE public.report_calculation_provenance DISABLE TRIGGER report_calculation_provenance_immutable;
ALTER TABLE public.lab_number_registry DISABLE TRIGGER guard_lab_number_registry_trigger;

-- Clean demo transactional records in strict FK order
DELETE FROM public.sms_queue_items;
DELETE FROM public.report_pdf_delivery_intents;
DELETE FROM public.order_report_delivery_entitlements;
DELETE FROM public.order_report_delivery_tokens;
DELETE FROM public.order_report_notification_generations;
DELETE FROM public.report_secure_link_presentations;
DELETE FROM public.public_report_tokens;
DELETE FROM public.patient_app_pdf_tokens;
DELETE FROM public.patient_app_identities;
DELETE FROM public.report_calculation_provenance;
DELETE FROM public.report_pdf_artifacts;
DELETE FROM public.critical_alert_events;
DELETE FROM public.test_results;
DELETE FROM public.diagnostic_reports;
DELETE FROM public.clinical_report_group_items;
DELETE FROM public.clinical_report_groups;
DELETE FROM public.outsource_sample_events;
DELETE FROM public.outsource_samples;
DELETE FROM public.sample_lifecycle_events;
DELETE FROM public.samples;
DELETE FROM public.clinical_order_items;
DELETE FROM public.clinical_orders;
DELETE FROM public.payment_idempotency_requests;
DELETE FROM public.payment_transactions;
DELETE FROM public.bill_panel_selections;
DELETE FROM public.bill_panel_components;
DELETE FROM public.bill_package_selections;
DELETE FROM public.bill_package_components;
DELETE FROM public.bill_items;
DELETE FROM public.billing_idempotency_requests;
DELETE FROM public.bills;
DELETE FROM public.lab_number_registry;
DELETE FROM public.patients;

-- Re-enable immutability triggers
ALTER TABLE public.report_pdf_artifacts ENABLE TRIGGER enforce_report_pdf_artifact_immutability_trigger;
ALTER TABLE public.payment_transactions ENABLE TRIGGER trg_payment_transactions_immutable;
ALTER TABLE public.report_calculation_provenance ENABLE TRIGGER report_calculation_provenance_immutable;
ALTER TABLE public.lab_number_registry ENABLE TRIGGER guard_lab_number_registry_trigger;

COMMIT;
