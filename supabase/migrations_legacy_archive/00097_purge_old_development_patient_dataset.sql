-- Migration: 00097_purge_old_development_patient_dataset.sql
-- Description: Clean all old/development/test patient-related transactional records from production database
-- Safety: Preserves all master data, catalogue, reference ranges, user accounts, roles, auth, and audit infrastructure.

DO $$
BEGIN
  -- 1. Temporarily disable immutability triggers on patient-dependent transactional tables
  ALTER TABLE public.payment_transactions DISABLE TRIGGER trg_payment_transactions_immutable;
  ALTER TABLE public.clinical_calculation_runs DISABLE TRIGGER clinical_calculation_runs_immutable;
  ALTER TABLE public.clinical_calculation_consistency_checks DISABLE TRIGGER clinical_calculation_checks_immutable;
  ALTER TABLE public.report_calculation_provenance DISABLE TRIGGER report_calculation_provenance_immutable;
  ALTER TABLE public.report_pdf_artifacts DISABLE TRIGGER enforce_report_pdf_artifact_immutability_trigger;

  -- 2. FK Topological deletion: Leaves to root (37 patient-dependent tables)
  -- 2.1. Patient app identities and tokens
  DELETE FROM public.patient_app_identities;
  DELETE FROM public.patient_app_pdf_tokens;

  -- 2.2. Bill package and panel breakdown components
  DELETE FROM public.bill_package_components;
  DELETE FROM public.bill_package_selections;
  DELETE FROM public.bill_panel_components;
  DELETE FROM public.bill_panel_selections;

  -- 2.3. Financial payment transactions and request idempotency cache
  DELETE FROM public.payment_transactions;
  DELETE FROM public.billing_idempotency_requests;
  DELETE FROM public.payment_idempotency_requests;

  -- 2.4. Sample tracking and lifecycle events
  DELETE FROM public.sample_lifecycle_events;
  DELETE FROM public.outsource_sample_events;
  DELETE FROM public.outsource_samples;

  -- 2.5. Microbiology worksheets, isolates, and AST observations
  DELETE FROM public.pus_culture_worksheets;
  DELETE FROM public.ast_observation_audit;
  DELETE FROM public.ast_observations;
  DELETE FROM public.ast_isolates;

  -- 2.6. Clinical calculation runs, consistency checks, and provenance evidence
  DELETE FROM public.clinical_calculation_consistency_checks;
  DELETE FROM public.report_calculation_provenance;
  DELETE FROM public.clinical_calculation_runs;

  -- 2.7. Test results
  DELETE FROM public.test_results;

  -- 2.8. Order items, group items, and bill items
  DELETE FROM public.clinical_report_group_items;
  DELETE FROM public.clinical_order_items;
  DELETE FROM public.bill_items;

  -- 2.9. Samples
  DELETE FROM public.samples;

  -- 2.10. Report delivery tokens, entitlements, notification generations, artifacts, links, and SMS queue
  DELETE FROM public.order_report_delivery_entitlements;
  DELETE FROM public.order_report_notification_generations;
  DELETE FROM public.report_pdf_artifacts;
  DELETE FROM public.report_pdf_delivery_intents;
  DELETE FROM public.order_report_delivery_tokens;
  DELETE FROM public.report_secure_link_presentations;
  DELETE FROM public.public_report_tokens;
  DELETE FROM public.sms_queue_items;

  -- 2.11. Diagnostic reports and Clinical report groups
  DELETE FROM public.diagnostic_reports;
  DELETE FROM public.clinical_report_groups;

  -- 2.12. Clinical orders and Bills
  DELETE FROM public.clinical_orders;
  DELETE FROM public.bills;

  -- 2.13. Root Patients
  DELETE FROM public.patients;

  -- 3. Re-enable immutability triggers on patient-dependent transactional tables
  ALTER TABLE public.payment_transactions ENABLE TRIGGER trg_payment_transactions_immutable;
  ALTER TABLE public.clinical_calculation_runs ENABLE TRIGGER clinical_calculation_runs_immutable;
  ALTER TABLE public.clinical_calculation_consistency_checks ENABLE TRIGGER clinical_calculation_checks_immutable;
  ALTER TABLE public.report_calculation_provenance ENABLE TRIGGER report_calculation_provenance_immutable;
  ALTER TABLE public.report_pdf_artifacts ENABLE TRIGGER enforce_report_pdf_artifact_immutability_trigger;

END $$;
