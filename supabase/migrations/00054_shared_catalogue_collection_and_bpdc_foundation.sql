-- Bimal Pathology shared catalogue, collection and BPDC Lab No foundation.
-- Forward-only from production head 00053. No historical clinical row is rewritten.

CREATE TYPE public.clinical_workflow_type_enum AS ENUM (
  'Routine','MicrobiologyCulture','MicrobiologyMicroscopy','Cytology',
  'Histopathology','Molecular','Outsource','NoClinicalReport'
);
CREATE TYPE public.analyzer_lifecycle_enum AS ENUM ('Draft','Active','Archived');

ALTER TABLE public.tests
  ADD COLUMN billing_enabled BOOLEAN,
  ADD COLUMN clinical_reporting_enabled BOOLEAN,
  ADD COLUMN collection_required BOOLEAN,
  ADD COLUMN workflow_type public.clinical_workflow_type_enum,
  ADD COLUMN analyzer_configuration_required BOOLEAN;

-- Preserve effective 00053 billing behaviour. Draft/unsupported identities remain disabled.
UPDATE public.tests SET
  billing_enabled = lifecycle_status='Active' AND is_active AND workflow_supported
    AND clinical_configuration_status IN ('Configured','Ready for Activation'),
  clinical_reporting_enabled = reporting_type IN ('InHouse','OutsourceWithBimalReport')
    AND lifecycle_status='Active' AND is_active AND workflow_supported
    AND clinical_configuration_status IN ('Configured','Ready for Activation'),
  collection_required = reporting_type IN ('InHouse','OutsourceWithBimalReport')
    OR COALESCE(requires_sample_tracking,FALSE),
  workflow_type = CASE
    WHEN code='IHC' OR COALESCE(requires_sample_tracking,FALSE) THEN 'Outsource'::public.clinical_workflow_type_enum
    WHEN reporting_type='NoReporting' THEN 'NoClinicalReport'::public.clinical_workflow_type_enum
    ELSE 'Routine'::public.clinical_workflow_type_enum END,
  analyzer_configuration_required = FALSE;

ALTER TABLE public.tests
  ALTER COLUMN billing_enabled SET DEFAULT FALSE,
  ALTER COLUMN billing_enabled SET NOT NULL,
  ALTER COLUMN clinical_reporting_enabled SET DEFAULT FALSE,
  ALTER COLUMN clinical_reporting_enabled SET NOT NULL,
  ALTER COLUMN collection_required SET DEFAULT FALSE,
  ALTER COLUMN collection_required SET NOT NULL,
  ALTER COLUMN workflow_type SET DEFAULT 'Routine',
  ALTER COLUMN workflow_type SET NOT NULL,
  ALTER COLUMN analyzer_configuration_required SET DEFAULT FALSE,
  ALTER COLUMN analyzer_configuration_required SET NOT NULL;

ALTER TABLE public.clinical_order_items
  ADD COLUMN workflow_type public.clinical_workflow_type_enum,
  ADD COLUMN clinical_reporting_enabled BOOLEAN,
  ADD COLUMN collection_required BOOLEAN;

UPDATE public.clinical_order_items oi SET
  workflow_type=CASE WHEN oi.reporting_type='OutsourceWithBimalReport' THEN 'Outsource'::public.clinical_workflow_type_enum ELSE 'Routine'::public.clinical_workflow_type_enum END,
  clinical_reporting_enabled=oi.reporting_type IN ('InHouse','OutsourceWithBimalReport'),
  collection_required=TRUE;

ALTER TABLE public.clinical_order_items
  ALTER COLUMN workflow_type SET DEFAULT 'Routine',
  ALTER COLUMN workflow_type SET NOT NULL,
  ALTER COLUMN clinical_reporting_enabled SET DEFAULT TRUE,
  ALTER COLUMN clinical_reporting_enabled SET NOT NULL,
  ALTER COLUMN collection_required SET DEFAULT TRUE,
  ALTER COLUMN collection_required SET NOT NULL;

-- NoReporting rows may now exist for collection traceability, without results/reports.
ALTER TABLE public.clinical_order_items DROP CONSTRAINT IF EXISTS clinical_order_items_reporting_type_check;
ALTER TABLE public.clinical_order_items ADD CONSTRAINT clinical_order_items_reporting_type_check
  CHECK (reporting_type IN ('InHouse','OutsourceWithBimalReport','NoReporting'));

CREATE INDEX tests_operational_gates_idx ON public.tests(billing_enabled,clinical_reporting_enabled,collection_required,workflow_type);
CREATE INDEX clinical_order_items_workflow_queue_idx ON public.clinical_order_items(workflow_type,status,created_at DESC);

CREATE TABLE public.analyzers (
  id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  code VARCHAR(50) NOT NULL UNIQUE,
  name VARCHAR(255) NOT NULL,
  manufacturer VARCHAR(255), model VARCHAR(255), serial_number VARCHAR(255),
  laboratory_location VARCHAR(255),
  lifecycle_status public.analyzer_lifecycle_enum NOT NULL DEFAULT 'Draft',
  row_version BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT analyzers_identity_not_blank CHECK (btrim(code)<>'' AND btrim(name)<>'')
);

CREATE TABLE public.test_analyzer_configurations (
  id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
  parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  analyzer_id UUID NOT NULL REFERENCES public.analyzers(id) ON DELETE RESTRICT,
  method VARCHAR(255) NOT NULL,
  assay_identifier VARCHAR(255), configuration_version VARCHAR(100) NOT NULL,
  effective_from DATE NOT NULL DEFAULT CURRENT_DATE, effective_to DATE,
  validation_state public.reference_range_validation_state_enum NOT NULL DEFAULT 'Unclassified',
  validation_source TEXT, is_clinically_approved BOOLEAN NOT NULL DEFAULT FALSE,
  approved_by UUID REFERENCES public.user_profiles(id), approved_at TIMESTAMPTZ,
  lifecycle_status public.analyzer_lifecycle_enum NOT NULL DEFAULT 'Draft',
  row_version BIGINT NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(), updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT test_analyzer_method_not_blank CHECK (btrim(method)<>''),
  CONSTRAINT test_analyzer_version_not_blank CHECK (btrim(configuration_version)<>''),
  CONSTRAINT test_analyzer_dates_valid CHECK (effective_to IS NULL OR effective_to>=effective_from),
  CONSTRAINT test_analyzer_approval_valid CHECK (NOT is_clinically_approved OR (validation_state='ClinicallyValidated' AND approved_by IS NOT NULL AND approved_at IS NOT NULL)),
  UNIQUE(test_id,parameter_id,analyzer_id,configuration_version)
);
CREATE INDEX test_analyzer_active_idx ON public.test_analyzer_configurations(test_id,lifecycle_status,is_clinically_approved);

ALTER TABLE public.analyzers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.test_analyzer_configurations ENABLE ROW LEVEL SECURITY;
CREATE POLICY analyzers_read ON public.analyzers FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY test_analyzer_config_read ON public.test_analyzer_configurations FOR SELECT TO authenticated USING (public.is_active_user());
REVOKE INSERT,UPDATE,DELETE ON public.analyzers,public.test_analyzer_configurations FROM authenticated,anon;

-- Permanent patient-facing number reservation. Existing LAB-* rows are not touched.
CREATE TABLE public.lab_number_registry (
  lab_no VARCHAR(13) PRIMARY KEY,
  order_id UUID UNIQUE,
  reserved_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  assigned_at TIMESTAMPTZ,
  CONSTRAINT lab_number_registry_format CHECK (lab_no ~ '^BPDC-[0-9]{8}$')
);
ALTER TABLE public.lab_number_registry ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.lab_number_registry FROM PUBLIC,anon,authenticated;

CREATE FUNCTION public.guard_lab_number_registry() RETURNS TRIGGER
LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  IF TG_OP='DELETE' THEN RAISE EXCEPTION 'BPDC Lab No reservations are permanent.' USING ERRCODE='55000'; END IF;
  IF OLD.lab_no<>NEW.lab_no OR OLD.reserved_at<>NEW.reserved_at OR OLD.order_id IS NOT NULL
     OR NEW.order_id IS NULL OR NEW.assigned_at IS NULL THEN
    RAISE EXCEPTION 'BPDC Lab No registry is append-only.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER guard_lab_number_registry_trigger BEFORE UPDATE OR DELETE ON public.lab_number_registry
FOR EACH ROW EXECUTE FUNCTION public.guard_lab_number_registry();

CREATE FUNCTION public.assign_bpdc_lab_no() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE candidate VARCHAR(13); reserved_count INT; attempt INT; random_number BIGINT;
BEGIN
  FOR attempt IN 1..100 LOOP
    random_number := 10000000 + ((('x'||encode(extensions.gen_random_bytes(4),'hex'))::bit(32)::BIGINT) % 90000000);
    candidate := 'BPDC-'||lpad(random_number::TEXT,8,'0');
    INSERT INTO public.lab_number_registry(lab_no) VALUES(candidate) ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS reserved_count=ROW_COUNT;
    IF reserved_count=1 THEN NEW.order_number:=candidate; RETURN NEW; END IF;
  END LOOP;
  RAISE EXCEPTION 'Unable to allocate a unique BPDC Lab No after 100 attempts.' USING ERRCODE='23505';
END $$;
CREATE FUNCTION public.bind_bpdc_lab_no() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  UPDATE public.lab_number_registry SET order_id=NEW.id,assigned_at=NOW() WHERE lab_no=NEW.order_number AND order_id IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'BPDC Lab No reservation is missing.' USING ERRCODE='23503'; END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER assign_bpdc_lab_no_trigger BEFORE INSERT ON public.clinical_orders
FOR EACH ROW EXECUTE FUNCTION public.assign_bpdc_lab_no();
CREATE TRIGGER bind_bpdc_lab_no_trigger AFTER INSERT ON public.clinical_orders
FOR EACH ROW EXECUTE FUNCTION public.bind_bpdc_lab_no();

REVOKE ALL ON FUNCTION public.assign_bpdc_lab_no(),public.bind_bpdc_lab_no(),public.guard_lab_number_registry() FROM PUBLIC,anon,authenticated;
COMMENT ON TABLE public.lab_number_registry IS 'Permanent append-only BPDC Lab No reservation ledger; never a patient or clinical identity table.';
