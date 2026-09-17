-- Catalogue readiness and human approval workflow.
-- Forward-only from 00074. No patient, bill, order, result, report, SMS or R2 DML.

CREATE TYPE public.catalogue_readiness_state_enum AS ENUM
  ('Draft','NeedsConfiguration','ReadyForReview','Approved','Suspended');
CREATE TYPE public.catalogue_decision_status_enum AS ENUM
  ('Configured','Reviewed','Approved','Rejected');

-- Final operator category master. Reuse the long-lived category UUIDs wherever
-- a canonical discipline already exists; retain every legacy category row and
-- relationship, and make aliases explicit instead of manufacturing duplicates.
UPDATE public.test_categories SET name='Haematology',display_order=1,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='HEMATOLOGY';
UPDATE public.test_categories SET name='Biochemistry',display_order=2,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='BIOCHEMISTRY';
UPDATE public.test_categories SET name='Serology & Immunology',display_order=3,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='SEROLOGY';
UPDATE public.test_categories SET name='Clinical Pathology',display_order=4,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='CLINICAL_PATHOLOGY';
UPDATE public.test_categories SET name='Cytology',display_order=5,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='CYTOLOGY';
UPDATE public.test_categories SET name='Microbiology',display_order=6,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='MICROBIOLOGY';
UPDATE public.test_categories SET name='Endocrinology',display_order=7,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='ENDOCRINOLOGY';
UPDATE public.test_categories SET name='Histopathology',display_order=8,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='HISTOPATHOLOGY';
UPDATE public.test_categories SET name='Others',display_order=9,lifecycle_status='Active',row_version=row_version+1,updated_at=now() WHERE code='GENERAL';
INSERT INTO public.test_categories(code,name,lifecycle_status,display_order)
VALUES('MISCELLANEOUS','Miscellaneous','Active',10)
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,display_order=EXCLUDED.display_order,lifecycle_status='Active',row_version=public.test_categories.row_version+1,updated_at=now();

CREATE TABLE public.test_category_aliases (
  normalized_alias TEXT PRIMARY KEY CHECK(normalized_alias=btrim(lower(normalized_alias)) AND normalized_alias<>''),
  canonical_category_id UUID NOT NULL REFERENCES public.test_categories(id) ON DELETE RESTRICT,
  legacy_category_id UUID REFERENCES public.test_categories(id) ON DELETE RESTRICT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.test_category_aliases ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.test_category_aliases FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.test_category_aliases TO authenticated;
CREATE POLICY test_category_aliases_staff_read ON public.test_category_aliases FOR SELECT TO authenticated USING(public.is_active_user());

INSERT INTO public.test_category_aliases(normalized_alias,canonical_category_id,legacy_category_id)
SELECT a.alias,c.id,l.id
FROM (VALUES
 ('hematology','HEMATOLOGY','HEMATOLOGY'),('haematology','HEMATOLOGY','HEMATOLOGY'),
 ('biochemistry','BIOCHEMISTRY','BIOCHEMISTRY'),('clinical biochemistry','BIOCHEMISTRY','BIOCHEMISTRY'),('biochemistry & clinical chemistry','BIOCHEMISTRY','BIOCHEMISTRY'),
 ('serology','SEROLOGY','SEROLOGY'),('immunology','SEROLOGY','SEROLOGY'),('serology & immunology','SEROLOGY','SEROLOGY'),
 ('clinical pathology','CLINICAL_PATHOLOGY','CLINICAL_PATHOLOGY'),('cytology','CYTOLOGY','CYTOLOGY'),
 ('microbiology','MICROBIOLOGY','MICROBIOLOGY'),('microbiology & culture','MICROBIOLOGY','MICROBIOLOGY'),
 ('endocrinology','ENDOCRINOLOGY','ENDOCRINOLOGY'),('hormones & endocrinology','ENDOCRINOLOGY','ENDOCRINOLOGY'),
 ('histopathology','HISTOPATHOLOGY','HISTOPATHOLOGY'),('histopathology & biopsy','HISTOPATHOLOGY','HISTOPATHOLOGY'),
 ('others','GENERAL','GENERAL'),('general tests','GENERAL','GENERAL'),('miscellaneous','MISCELLANEOUS','MISCELLANEOUS')
) a(alias,canonical_code,legacy_code)
JOIN public.test_categories c ON c.code=a.canonical_code
JOIN public.test_categories l ON l.code=a.legacy_code;

UPDATE public.test_categories SET lifecycle_status='Archived',row_version=row_version+1,updated_at=now()
WHERE code NOT IN('HEMATOLOGY','BIOCHEMISTRY','SEROLOGY','CLINICAL_PATHOLOGY','CYTOLOGY','MICROBIOLOGY','ENDOCRINOLOGY','HISTOPATHOLOGY','GENERAL','MISCELLANEOUS');

DO $$ BEGIN
 IF (SELECT count(*) FROM public.test_categories WHERE lifecycle_status='Active')<>10 THEN RAISE EXCEPTION 'CANONICAL_CATEGORY_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM (VALUES
  (1,'HEMATOLOGY','Haematology'),(2,'BIOCHEMISTRY','Biochemistry'),(3,'SEROLOGY','Serology & Immunology'),
  (4,'CLINICAL_PATHOLOGY','Clinical Pathology'),(5,'CYTOLOGY','Cytology'),(6,'MICROBIOLOGY','Microbiology'),
  (7,'ENDOCRINOLOGY','Endocrinology'),(8,'HISTOPATHOLOGY','Histopathology'),(9,'GENERAL','Others'),(10,'MISCELLANEOUS','Miscellaneous')
 ) expected(display_order,code,name) LEFT JOIN public.test_categories c USING(code)
 WHERE c.id IS NULL OR c.name<>expected.name OR c.display_order<>expected.display_order OR c.lifecycle_status<>'Active') THEN
   RAISE EXCEPTION 'CANONICAL_CATEGORY_MASTER_INVALID';
 END IF;
END $$;

-- ============================================================================
-- VERSIONED SPECIALIST AST BREAKPOINT ENGINE — PUS CULTURE
-- Provenance is deliberately local and edition-neutral.
-- ============================================================================
CREATE TABLE public.ast_breakpoint_sets(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), name TEXT NOT NULL, version TEXT NOT NULL,
 effective_date DATE NOT NULL, provenance TEXT NOT NULL, status TEXT NOT NULL CHECK(status IN('Draft','Validated','Active','Retired')),
 is_active BOOLEAN NOT NULL DEFAULT FALSE, row_version BIGINT NOT NULL DEFAULT 1,
 created_by UUID REFERENCES public.user_profiles(id) ON DELETE RESTRICT, approved_by UUID REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), approved_at TIMESTAMPTZ, retired_at TIMESTAMPTZ,
 UNIQUE(name,version), CHECK((status='Active')=is_active)
);
CREATE UNIQUE INDEX ast_one_active_breakpoint_set ON public.ast_breakpoint_sets(is_active) WHERE is_active;

CREATE TABLE public.ast_organism_groups(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), code TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL UNIQUE,
 is_active BOOLEAN NOT NULL DEFAULT TRUE, row_version BIGINT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.ast_antibiotics(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), code TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
 is_active BOOLEAN NOT NULL DEFAULT TRUE, row_version BIGINT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.ast_microorganisms(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), code TEXT NOT NULL UNIQUE, display_name TEXT NOT NULL UNIQUE,
 organism_group_id UUID REFERENCES public.ast_organism_groups(id) ON DELETE RESTRICT, is_active BOOLEAN NOT NULL DEFAULT TRUE,
 row_version BIGINT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE TABLE public.ast_breakpoint_rules(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), breakpoint_set_id UUID NOT NULL REFERENCES public.ast_breakpoint_sets(id) ON DELETE RESTRICT,
 organism_group_id UUID NOT NULL REFERENCES public.ast_organism_groups(id) ON DELETE RESTRICT,
 antibiotic_id UUID NOT NULL REFERENCES public.ast_antibiotics(id) ON DELETE RESTRICT,
 method TEXT NOT NULL CHECK(method IN('Disk','MIC')), metric_type TEXT NOT NULL CHECK(metric_type IN('ZoneDiameterMm','MicConcentration')),
 potency TEXT, automatic_interpretation_allowed BOOLEAN NOT NULL DEFAULT TRUE,
 susceptible_min NUMERIC, susceptible_max NUMERIC, susceptible_secondary NUMERIC,
 intermediate_min NUMERIC, intermediate_max NUMERIC, intermediate_secondary_min NUMERIC, intermediate_secondary_max NUMERIC,
 resistant_min NUMERIC, resistant_max NUMERIC, resistant_secondary NUMERIC,
 intermediate_semantics TEXT CHECK(intermediate_semantics IS NULL OR intermediate_semantics IN('I','SDD')),
 interpretation_semantics JSONB NOT NULL DEFAULT '{}'::JSONB, notes TEXT, row_version BIGINT NOT NULL DEFAULT 1,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(breakpoint_set_id,organism_group_id,antibiotic_id,method),
 CHECK((method='Disk' AND metric_type='ZoneDiameterMm') OR (method='MIC' AND metric_type='MicConcentration'))
);

CREATE TABLE public.ast_isolates(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), order_item_id UUID NOT NULL REFERENCES public.clinical_order_items(id) ON DELETE RESTRICT,
 isolate_number INT NOT NULL CHECK(isolate_number>0), microorganism_id UUID REFERENCES public.ast_microorganisms(id) ON DELETE RESTRICT,
 organism_name_snapshot TEXT NOT NULL, organism_group_id UUID REFERENCES public.ast_organism_groups(id) ON DELETE RESTRICT,
 organism_group_snapshot TEXT, growth_state TEXT NOT NULL CHECK(growth_state IN('Positive','NoGrowth')),
 status TEXT NOT NULL DEFAULT 'Draft' CHECK(status IN('Draft','Submitted','Verified','SignedOff')),
 row_version BIGINT NOT NULL DEFAULT 1, created_by UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(), UNIQUE(order_item_id,isolate_number)
);
CREATE TABLE public.ast_observations(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), isolate_id UUID NOT NULL REFERENCES public.ast_isolates(id) ON DELETE RESTRICT,
 antibiotic_id UUID NOT NULL REFERENCES public.ast_antibiotics(id) ON DELETE RESTRICT, antibiotic_code_snapshot TEXT NOT NULL, antibiotic_name_snapshot TEXT NOT NULL,
 method TEXT NOT NULL CHECK(method IN('Disk','MIC')), metric_type TEXT NOT NULL CHECK(metric_type IN('ZoneDiameterMm','MicConcentration')),
 metric_value NUMERIC NOT NULL CHECK(metric_value>=0), metric_secondary_value NUMERIC CHECK(metric_secondary_value>=0),
 automatic_interpretation TEXT CHECK(automatic_interpretation IN('S','I','R','SDD')),
 final_interpretation TEXT NOT NULL CHECK(final_interpretation IN('S','I','R','SDD')),
 breakpoint_set_id UUID REFERENCES public.ast_breakpoint_sets(id) ON DELETE RESTRICT, breakpoint_set_version_snapshot TEXT,
 breakpoint_rule_id UUID REFERENCES public.ast_breakpoint_rules(id) ON DELETE RESTRICT,
 manual_override BOOLEAN NOT NULL DEFAULT FALSE, override_reason TEXT, actor_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 row_version BIGINT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(isolate_id,antibiotic_id,method), CHECK((NOT manual_override) OR btrim(COALESCE(override_reason,''))<>'')
);
CREATE TABLE public.ast_observation_audit(
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), observation_id UUID REFERENCES public.ast_observations(id) ON DELETE RESTRICT,
 isolate_id UUID NOT NULL REFERENCES public.ast_isolates(id) ON DELETE RESTRICT, actor_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 action TEXT NOT NULL, before_state JSONB, after_state JSONB NOT NULL, reason TEXT, created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.ast_breakpoint_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_organism_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_antibiotics ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_microorganisms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_breakpoint_rules ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_isolates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_observations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ast_observation_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY ast_master_staff_read ON public.ast_breakpoint_sets FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY ast_group_staff_read ON public.ast_organism_groups FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY ast_antibiotic_staff_read ON public.ast_antibiotics FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY ast_microorganism_staff_read ON public.ast_microorganisms FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY ast_rule_staff_read ON public.ast_breakpoint_rules FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY ast_isolate_staff_read ON public.ast_isolates FOR SELECT TO authenticated USING(public.is_active_user() AND (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')));
CREATE POLICY ast_observation_staff_read ON public.ast_observations FOR SELECT TO authenticated USING(public.is_active_user() AND (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')));
CREATE POLICY ast_audit_staff_read ON public.ast_observation_audit FOR SELECT TO authenticated USING(public.is_active_user() AND (public.has_permission('can_verify_results') OR public.has_permission('can_view_audit_logs')));

INSERT INTO public.role_permissions(role_id,permission_key)
SELECT id,'can_manage_ast_breakpoints' FROM public.roles WHERE code='admin'
ON CONFLICT(role_id,permission_key) DO NOTHING;

INSERT INTO public.ast_organism_groups(code,display_name) VALUES
('STAPHYLOCOCCUS_SPP','Staphylococcus spp.'),('ENTEROBACTERALES','Enterobacterales'),('PSEUDOMONAS_AERUGINOSA','Pseudomonas aeruginosa')
ON CONFLICT(code) DO UPDATE SET display_name=EXCLUDED.display_name,is_active=TRUE,updated_at=now();
INSERT INTO public.ast_antibiotics(code,name) VALUES
('AB_FOX','Cefoxitin'),('AB_PEN','Penicillin'),('AB_CIP','Ciprofloxacin'),('AB_CLI','Clindamycin'),('AB_ERY','Erythromycin'),
('AB_GEN','Gentamicin'),('AB_LZD','Linezolid'),('AB_COT','Cotrimoxazole'),('AB_DOX','Doxycycline'),('AB_VAN','Vancomycin'),
('AB_AMP','Ampicillin'),('AB_AMC','Amoxicillin-Clavulanate'),('AB_TZP','Piperacillin-Tazobactam'),('AB_CTX','Cefotaxime'),
('AB_CTR','Ceftriaxone'),('AB_CAZ','Ceftazidime'),('AB_FEP','Cefepime'),('AB_MEM','Meropenem'),('AB_IPM','Imipenem'),
('AB_AMK','Amikacin'),('AB_LEV','Levofloxacin'),('AB_TOB','Tobramycin'),('AB_COL','Colistin')
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,is_active=TRUE,updated_at=now();
INSERT INTO public.ast_microorganisms(code,display_name,organism_group_id)
SELECT v.code,v.name,g.id FROM (VALUES
 ('STAPHYLOCOCCUS_AUREUS','Staphylococcus aureus','STAPHYLOCOCCUS_SPP'),
 ('COAGULASE_NEGATIVE_STAPHYLOCOCCUS','Coagulase-negative Staphylococcus','STAPHYLOCOCCUS_SPP'),
 ('ESCHERICHIA_COLI','Escherichia coli','ENTEROBACTERALES'),('KLEBSIELLA_PNEUMONIAE','Klebsiella pneumoniae','ENTEROBACTERALES'),
 ('PROTEUS_SPP','Proteus spp.','ENTEROBACTERALES'),('PSEUDOMONAS_AERUGINOSA','Pseudomonas aeruginosa','PSEUDOMONAS_AERUGINOSA')
)v(code,name,group_code) JOIN public.ast_organism_groups g ON g.code=v.group_code
ON CONFLICT(code) DO UPDATE SET display_name=EXCLUDED.display_name,organism_group_id=EXCLUDED.organism_group_id,is_active=TRUE,updated_at=now();

INSERT INTO public.ast_breakpoint_sets(name,version,effective_date,provenance,status,is_active)
VALUES('Local AST Breakpoint Baseline','1.0','2026-08-30','Operator-approved local breakpoint baseline','Active',TRUE)
ON CONFLICT(name,version) DO UPDATE SET effective_date=EXCLUDED.effective_date,provenance=EXCLUDED.provenance,status='Active',is_active=TRUE;

-- Dedicated least-privilege capability. It does not imply catalogue lifecycle,
-- pricing, reporting-tier, deletion, suspension, or final-approval authority.
INSERT INTO public.role_permissions(role_id,permission_key)
SELECT id,'can_configure_catalogue_technical' FROM public.roles WHERE code='lab_technician'
ON CONFLICT(role_id,permission_key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE entry JSONB; role_row public.roles%ROWTYPE; role_ids UUID[]:=ARRAY[]::UUID[]; permission_count INT:=0;
 allowed_permissions TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints','can_manage_referring_doctors','can_manage_personnel','can_view_financials','can_manage_users','can_manage_roles','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports','can_finalize_hmis_reports'];
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_roles') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF jsonb_typeof(COALESCE(p_matrix,'[]'))<>'array' THEN RAISE EXCEPTION 'Role permission matrix must be an array.' USING ERRCODE='22023'; END IF;
 FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix,'[]')) LOOP
  IF (entry->>'role_id')::UUID=ANY(role_ids) THEN RAISE EXCEPTION 'A role may occur only once.' USING ERRCODE='23505'; END IF;
  SELECT * INTO role_row FROM public.roles WHERE id=(entry->>'role_id')::UUID FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Unknown role.' USING ERRCODE='23503'; END IF;
  IF role_row.code='admin' THEN RAISE EXCEPTION 'The Admin permission set is migration-controlled and cannot be replaced here.' USING ERRCODE='42501'; END IF;
  IF jsonb_typeof(COALESCE(entry->'permissions','[]'))<>'array' OR EXISTS(SELECT 1 FROM jsonb_array_elements_text(COALESCE(entry->'permissions','[]')) p WHERE NOT p=ANY(allowed_permissions)) THEN RAISE EXCEPTION 'Invalid permission payload.' USING ERRCODE='22023'; END IF;
  role_ids:=array_append(role_ids,role_row.id);
 END LOOP;
 FOR entry IN SELECT * FROM jsonb_array_elements(COALESCE(p_matrix,'[]')) LOOP
  DELETE FROM public.role_permissions WHERE role_id=(entry->>'role_id')::UUID;
  INSERT INTO public.role_permissions(role_id,permission_key) SELECT (entry->>'role_id')::UUID,p FROM (SELECT DISTINCT jsonb_array_elements_text(COALESCE(entry->'permissions','[]')) p) x;
  GET DIAGNOSTICS permission_count=ROW_COUNT;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ROLE_PERMISSIONS_REPLACED','Role',(entry->>'role_id'),jsonb_build_object('permission_count',permission_count));
 END LOOP;
 RETURN cardinality(role_ids);
END $$;

CREATE TABLE public.catalogue_service_readiness (
  test_id UUID PRIMARY KEY REFERENCES public.tests(id) ON DELETE RESTRICT,
  state public.catalogue_readiness_state_enum NOT NULL DEFAULT 'NeedsConfiguration',
  configuration_version BIGINT NOT NULL DEFAULT 1 CHECK (configuration_version > 0),
  submitted_by UUID REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  submitted_at TIMESTAMPTZ,
  approved_by UUID REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  approved_at TIMESTAMPTZ,
  suspended_by UUID REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  suspended_at TIMESTAMPTZ,
  decision_reason TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT catalogue_readiness_reason_not_blank CHECK (decision_reason IS NULL OR btrim(decision_reason) <> '')
);

CREATE TABLE public.catalogue_configuration_evidence (
  id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
  configuration_version BIGINT NOT NULL CHECK (configuration_version > 0),
  category TEXT NOT NULL CHECK (category IN
    ('Identity','Specimen','ParameterStructure','ReferenceRanges','Calculations',
     'CriticalLimits','MethodAnalyzer','SourceConflicts','Pricing','Workflow','FinalApproval')),
  status public.catalogue_decision_status_enum NOT NULL,
  previous_state JSONB,
  new_state JSONB NOT NULL DEFAULT '{}'::JSONB,
  source_metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
  reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
  actor_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  actor_role TEXT NOT NULL CHECK (btrim(actor_role) <> ''),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Operator-supplied clinical panels are first-class catalogue composition.
-- They are deliberately separate from commercial ratelist/package rows.
CREATE TABLE public.catalogue_panels (
  id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  code TEXT NOT NULL UNIQUE CHECK (code = upper(code) AND btrim(code) <> ''),
  name TEXT NOT NULL UNIQUE CHECK (btrim(name) <> ''),
  category_id UUID NOT NULL REFERENCES public.test_categories(id) ON DELETE RESTRICT,
  clinical_notes TEXT,
  interpretation_rows JSONB NOT NULL DEFAULT '[]'::JSONB CHECK (jsonb_typeof(interpretation_rows)='array'),
  interpretation_notes TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
  hide_component_interpretation BOOLEAN NOT NULL DEFAULT TRUE,
  show_component_method_instrument BOOLEAN NOT NULL DEFAULT TRUE,
  reporting_type public.reporting_type_enum NOT NULL DEFAULT 'InHouse',
  workflow_supported BOOLEAN NOT NULL DEFAULT TRUE,
  clinical_reporting_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Draft',
  display_order INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE public.catalogue_panel_components (
  panel_id UUID NOT NULL REFERENCES public.catalogue_panels(id) ON DELETE RESTRICT,
  component_test_id UUID REFERENCES public.tests(id) ON DELETE RESTRICT,
  component_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  display_name TEXT NOT NULL CHECK (btrim(display_name) <> ''),
  display_order INT NOT NULL CHECK (display_order > 0),
  unresolved_reason TEXT,
  PRIMARY KEY(panel_id, display_order),
  CHECK (
    (((component_test_id IS NOT NULL)::INT + (component_parameter_id IS NOT NULL)::INT = 1) AND unresolved_reason IS NULL)
    OR
    (component_test_id IS NULL AND component_parameter_id IS NULL AND btrim(unresolved_reason) <> '')
  ),
  UNIQUE(panel_id, component_test_id),
  UNIQUE(panel_id, component_parameter_id)
);

CREATE TABLE public.catalogue_panel_ratelist_links (
  panel_id UUID NOT NULL REFERENCES public.catalogue_panels(id) ON DELETE RESTRICT,
  ratelist_name TEXT NOT NULL CHECK (btrim(ratelist_name) <> ''),
  operator_rate_npr NUMERIC(12,2) CHECK (operator_rate_npr IS NULL OR operator_rate_npr >= 0),
  health_package_id UUID REFERENCES public.health_packages(id) ON DELETE RESTRICT,
  PRIMARY KEY(panel_id, ratelist_name)
);

CREATE INDEX catalogue_panels_category_order_idx ON public.catalogue_panels(category_id, display_order, id);
CREATE INDEX catalogue_panel_ratelist_package_idx ON public.catalogue_panel_ratelist_links(health_package_id) WHERE health_package_id IS NOT NULL;

-- Clean operator-facing 256-row Test Database projection. A source entry may
-- resolve to a whole canonical test or to a parameter owned by a canonical
-- multi-parameter test; it never creates a duplicate standalone test.
CREATE TABLE public.catalogue_test_database_entries (
  source_order INT PRIMARY KEY CHECK(source_order BETWEEN 1 AND 256),
  test_name TEXT NOT NULL CHECK(btrim(test_name)<>''),
  test_type TEXT NOT NULL CHECK(test_type IN ('Single parameter','Multi parameter','Multi parameter nested','Document')),
  short_name TEXT,
  operator_category TEXT NOT NULL CHECK(operator_category IN ('Haematology','Biochemistry','Serology & Immunology','Clinical Pathology','Cytology','Microbiology','Endocrinology','Histopathology','Others','Miscellaneous')),
  category_id UUID NOT NULL REFERENCES public.test_categories(id) ON DELETE RESTRICT,
  configuration_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
  canonical_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  is_operator_approved BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(test_name,source_order)
);
CREATE INDEX catalogue_test_database_category_order_idx ON public.catalogue_test_database_entries(category_id,source_order);
CREATE INDEX catalogue_test_database_type_order_idx ON public.catalogue_test_database_entries(test_type,source_order);

-- Operator-approved authoring library. Templates point back to the canonical
-- Test Database projection; they are not clinical tests and panels never refer
-- to them. Copying creates a private editable draft, not a test or service.
CREATE TABLE public.catalogue_test_templates (
  source_order INT PRIMARY KEY CHECK(source_order BETWEEN 1 AND 111),
  supplied_name TEXT NOT NULL CHECK(btrim(supplied_name)<>''),
  test_database_source_order INT NOT NULL REFERENCES public.catalogue_test_database_entries(source_order) ON DELETE RESTRICT,
  configuration_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
  canonical_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,
  is_operator_approved BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(test_database_source_order)
);
CREATE TABLE public.catalogue_test_template_drafts (
  id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
  template_source_order INT NOT NULL REFERENCES public.catalogue_test_templates(source_order) ON DELETE RESTRICT,
  created_by UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
  proposed_code TEXT,
  proposed_name TEXT,
  technical_configuration JSONB NOT NULL DEFAULT '{}'::JSONB CHECK(jsonb_typeof(technical_configuration)='object'),
  revision BIGINT NOT NULL DEFAULT 1 CHECK(revision>0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK(proposed_code IS NULL OR btrim(proposed_code)<>''),
  CHECK(proposed_name IS NULL OR btrim(proposed_name)<>'')
);
CREATE INDEX catalogue_template_canonical_idx ON public.catalogue_test_templates(configuration_test_id,source_order);
CREATE INDEX catalogue_template_draft_owner_idx ON public.catalogue_test_template_drafts(created_by,updated_at DESC,id);

ALTER TABLE public.catalogue_panels ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_ratelist_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_test_database_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_test_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_test_template_drafts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.catalogue_panels, public.catalogue_panel_components, public.catalogue_panel_ratelist_links FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.catalogue_test_database_entries FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON public.catalogue_test_templates,public.catalogue_test_template_drafts FROM PUBLIC, anon, authenticated, service_role;
GRANT SELECT ON public.catalogue_panels, public.catalogue_panel_components, public.catalogue_panel_ratelist_links TO authenticated;
GRANT SELECT ON public.catalogue_test_database_entries TO authenticated;
GRANT SELECT ON public.catalogue_test_templates TO authenticated;
CREATE POLICY catalogue_panels_staff_read ON public.catalogue_panels FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_panel_components_staff_read ON public.catalogue_panel_components FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_panel_ratelist_staff_read ON public.catalogue_panel_ratelist_links FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_test_database_staff_read ON public.catalogue_test_database_entries FOR SELECT TO authenticated USING (public.is_active_user());
CREATE POLICY catalogue_test_templates_staff_read ON public.catalogue_test_templates FOR SELECT TO authenticated USING (public.is_active_user());

CREATE INDEX catalogue_readiness_state_idx
  ON public.catalogue_service_readiness(state, updated_at DESC, test_id);
CREATE INDEX catalogue_evidence_test_category_idx
  ON public.catalogue_configuration_evidence(test_id, category, configuration_version DESC, created_at DESC);

ALTER TABLE public.catalogue_service_readiness ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_configuration_evidence ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.catalogue_service_readiness, public.catalogue_configuration_evidence FROM PUBLIC, anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.catalogue_readiness_actor_role()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
  SELECT COALESCE(string_agg(DISTINCT r.name, ', ' ORDER BY r.name), 'Authenticated user')
  FROM public.user_profiles up
  LEFT JOIN public.user_roles ur ON ur.user_id=up.id
  LEFT JOIN public.roles r ON r.id=ur.role_id
  WHERE up.id=auth.uid() AND up.is_active;
$$;

CREATE OR REPLACE FUNCTION public.catalogue_require_readiness_staff()
RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
  IF auth.uid() IS NULL OR NOT (public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue')) THEN
    RAISE EXCEPTION 'CATALOGUE_READINESS_ACCESS_DENIED' USING ERRCODE='42501';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_classification(p_test public.tests)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path=public,pg_temp AS $$
 SELECT CASE
   WHEN p_test.workflow_type IN
     ('MicrobiologyCulture','MicrobiologyMicroscopy','Cytology','Histopathology','Molecular') THEN 'SpecialistWorkflow'
   WHEN NOT p_test.workflow_supported AND p_test.workflow_type<>'NoClinicalReport' THEN 'SpecialistWorkflow'
   WHEN p_test.reporting_type='NoReporting' OR p_test.workflow_type='NoClinicalReport' THEN 'BillingOnly'
   WHEN p_test.reporting_type='OutsourceWithBimalReport' THEN 'OutsourceWithBimalReport'
   ELSE 'InHouse'
 END;
$$;

CREATE OR REPLACE FUNCTION public.catalogue_service_readiness_checklist(p_test_id UUID)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE
 t public.tests%ROWTYPE; classification TEXT; missing TEXT[]:=ARRAY[]::TEXT[];
 parameter_count INT:=0; range_ready BOOLEAN:=TRUE; calculation_ready BOOLEAN:=TRUE;
 critical_ready BOOLEAN:=TRUE; method_ready BOOLEAN:=TRUE; conflict_ready BOOLEAN:=TRUE;
 latest_categories JSONB:='{}'::JSONB; category TEXT; reviewed BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 classification:=public.catalogue_classification(t);

 SELECT count(*) INTO parameter_count FROM public.parameters p
 WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';

 SELECT COALESCE(jsonb_object_agg(x.category,x.status), '{}'::JSONB) INTO latest_categories
 FROM (
   SELECT DISTINCT ON (e.category) e.category,e.status::TEXT status
   FROM public.catalogue_configuration_evidence e
   WHERE e.test_id=t.id
   ORDER BY e.category,e.configuration_version DESC,e.created_at DESC,e.id DESC
 ) x;

 IF btrim(COALESCE(t.code,''))='' OR btrim(COALESCE(t.name,''))='' OR t.category_id IS NULL
 THEN missing:=array_append(missing,'Canonical identity/category is incomplete'); END IF;
 IF NOT t.is_active OR t.lifecycle_status<>'Active' THEN missing:=array_append(missing,'Service lifecycle is not Active'); END IF;
 IF NOT t.billing_enabled THEN missing:=array_append(missing,'Service is not enabled for billing'); END IF;
 IF NOT t.price_configured AND t.pricing_policy='Fixed' THEN missing:=array_append(missing,'Fixed production price is not configured'); END IF;

 IF classification='SpecialistWorkflow' THEN
   missing:=array_append(missing,'Specialist workflow implementation is required; generic Result Entry is not supported');
 ELSIF classification NOT IN ('BillingOnly') THEN
   IF t.reporting_type NOT IN ('InHouse','OutsourceWithBimalReport') THEN missing:=array_append(missing,'Reporting type must be InHouse or OutsourceWithBimalReport'); END IF;
   IF t.collection_required AND (btrim(COALESCE(t.sample_type,''))='' OR btrim(COALESCE(t.container,''))='')
     THEN missing:=array_append(missing,'Specimen and container are required'); END IF;
   IF parameter_count=0 THEN missing:=array_append(missing,'At least one active parameter/component is required'); END IF;

   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'
      AND p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='') THEN
     missing:=array_append(missing,'Every active numeric/calculated parameter requires a unit');
   END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'
      AND p.range_validation_required AND NOT EXISTS(
        SELECT 1 FROM public.reference_ranges rr WHERE rr.parameter_id=p.id AND rr.is_active
          AND rr.lifecycle_status='Active' AND rr.is_approved AND rr.validation_state='ClinicallyValidated')) THEN
     range_ready:=FALSE; missing:=array_append(missing,'Clinically validated reference ranges are missing');
   END IF;
   IF EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'
      AND p.value_type='Calculated' AND (p.calculation_identifier IS NULL OR NOT EXISTS(
        SELECT 1 FROM public.clinical_calculation_formula_versions f
        WHERE f.formula_identifier=p.calculation_identifier AND f.lifecycle_status='Approved'
          AND f.rounding_scale IS NOT NULL))) THEN
     calculation_ready:=FALSE; missing:=array_append(missing,'Approved calculation formula/rounding configuration is missing');
   END IF;

   -- A blank method is not a clinical-range rejection. It becomes actionable
   -- only where this service/parameter explicitly requires analyzer/method setup.
   IF t.analyzer_configuration_required OR EXISTS(
      SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active
        AND p.lifecycle_status='Active' AND p.method_validation_required) THEN
     method_ready:=EXISTS(SELECT 1 FROM public.test_analyzer_configurations c
       WHERE c.test_id=t.id AND c.lifecycle_status='Active' AND c.is_clinically_approved);
     IF NOT method_ready THEN missing:=array_append(missing,'Method not configured'); END IF;
   END IF;
   -- Critical limits are optional unless configured; approved baseline intervals
   -- remain valid without manufactured critical values.
   critical_ready:=TRUE;
 END IF;

 RETURN jsonb_build_object(
   'test_id',t.id,'code',t.code,'name',t.name,'classification',classification,
   'active',t.is_active AND t.lifecycle_status='Active','billable',t.billing_enabled,
   'reporting_type',t.reporting_type,'reporting_model',t.reporting_model,'workflow_type',t.workflow_type,
   'workflow_supported',t.workflow_supported,'clinical_reporting_enabled',t.clinical_reporting_enabled,
   'collection_required',t.collection_required,'specimen',t.sample_type,'container',t.container,'method',t.method,'test_row_version',t.row_version,
   'parameter_count',parameter_count,'range_ready',range_ready,'calculation_ready',calculation_ready,
   'critical_limit_ready',critical_ready,'method_analyzer_ready',method_ready,
   'conflict_ready',conflict_ready,'pricing_ready',t.price_configured OR t.pricing_policy<>'Fixed',
   'category_decisions',latest_categories,'missing_requirements',to_jsonb(missing),
   'ready_for_review',cardinality(missing)=0,
   'operational_status',CASE WHEN NOT t.is_active OR t.lifecycle_status<>'Active' THEN 'Inactive'
     WHEN classification='BillingOnly' THEN 'Billing only · No Worklist'
     WHEN classification='SpecialistWorkflow' THEN 'Specialist workflow'
     WHEN t.clinical_reporting_enabled THEN 'Reportable' ELSE 'Needs configuration' END
 );
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_readiness_inventory(p_state TEXT DEFAULT NULL,p_query TEXT DEFAULT NULL)
RETURNS SETOF JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE row RECORD; checklist JSONB; term TEXT:=lower(btrim(COALESCE(p_query,'')));
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 FOR row IN
   SELECT t.id,r.state,r.configuration_version,r.decision_reason
   FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id
   WHERE t.lifecycle_status<>'Archived'
     AND (p_state IS NULL OR p_state='' OR r.state::TEXT=p_state)
     AND (term='' OR lower(t.code) LIKE '%'||term||'%' OR lower(t.name) LIKE '%'||term||'%')
   ORDER BY t.is_active DESC,t.display_order,t.code,t.id LIMIT 500
 LOOP
   checklist:=public.catalogue_service_readiness_checklist(row.id);
   RETURN NEXT checklist||jsonb_build_object('service_kind','Test','approval_state',row.state,
     'configuration_version',row.configuration_version,'decision_reason',row.decision_reason);
 END LOOP;
 FOR row IN
   SELECT p.id,p.code,p.name,p.lifecycle_status,p.price_paisa,count(c.test_id) component_count
   FROM public.health_packages p LEFT JOIN public.health_package_components c ON c.package_id=p.id
   WHERE p.lifecycle_status<>'Archived' AND (term='' OR lower(p.code) LIKE '%'||term||'%' OR lower(p.name) LIKE '%'||term||'%')
   GROUP BY p.id,p.code,p.name,p.lifecycle_status,p.price_paisa ORDER BY p.code LIMIT 500
 LOOP
   RETURN NEXT jsonb_build_object('service_kind','Package','test_id',row.id,'code',row.code,'name',row.name,
     'classification','CommercialPackage','approval_state',CASE WHEN row.lifecycle_status='Active' THEN 'Approved' ELSE 'Draft' END,
     'clinical_reporting_enabled',FALSE,'parameter_count',row.component_count,
     'missing_requirements',CASE WHEN row.component_count=0 THEN jsonb_build_array('Package requires components') ELSE '[]'::JSONB END);
 END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_record_configuration_review(
 p_test_id UUID,p_category TEXT,p_reason TEXT,p_source_metadata JSONB,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; next_version BIGINT; previous JSONB;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF p_category NOT IN ('Identity','Specimen','ParameterStructure','ReferenceRanges','Calculations','CriticalLimits','MethodAnalyzer','SourceConflicts','Pricing','Workflow')
   THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_CATEGORY_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'A review reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 SELECT new_state INTO previous FROM public.catalogue_configuration_evidence WHERE test_id=p_test_id AND category=p_category ORDER BY configuration_version DESC,created_at DESC LIMIT 1;
 next_version:=r.configuration_version+1;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,source_metadata,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,p_category,'Reviewed',previous,jsonb_build_object('reviewed',TRUE),COALESCE(p_source_metadata,'{}'),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=next_version,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now()
 WHERE test_id=p_test_id;
 RETURN next_version;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_booking_readiness(p_test_ids UUID[])
RETURNS TABLE(test_id UUID,approval_state TEXT,classification TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_create_bill') OR public.has_permission('can_manage_catalogue')) THEN
   RAISE EXCEPTION 'CATALOGUE_BOOKING_READINESS_ACCESS_DENIED' USING ERRCODE='42501';
 END IF;
 RETURN QUERY SELECT t.id,r.state::TEXT,public.catalogue_classification(t)
 FROM public.tests t JOIN public.catalogue_service_readiness r ON r.test_id=t.id
 WHERE t.id=ANY(COALESCE(p_test_ids,ARRAY[]::UUID[]));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_technical_update_test(
 p_test_id UUID,p_patch JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; next_version BIGINT; forbidden TEXT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_patch,'{}')) key
 WHERE key NOT IN ('sample_type','container','collection_required','method','configuration_notes') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_CATALOGUE_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_SERVICE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF t.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 UPDATE public.tests SET
   sample_type=CASE WHEN p_patch?'sample_type' THEN COALESCE(p_patch->>'sample_type','') ELSE sample_type END,
   container=CASE WHEN p_patch?'container' THEN COALESCE(p_patch->>'container','') ELSE container END,
   collection_required=CASE WHEN p_patch?'collection_required' THEN (p_patch->>'collection_required')::BOOLEAN ELSE collection_required END,
   method=CASE WHEN p_patch?'method' THEN NULLIF(btrim(p_patch->>'method'),'') ELSE method END,
   configuration_notes=CASE WHEN p_patch?'configuration_notes' THEN NULLIF(btrim(p_patch->>'configuration_notes'),'') ELSE configuration_notes END,
   row_version=row_version+1,updated_at=now() WHERE id=p_test_id RETURNING row_version INTO next_version;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT p_test_id,r.configuration_version+1,'Specimen','Configured',
   jsonb_build_object('sample_type',t.sample_type,'container',t.container,'collection_required',t.collection_required,'method',t.method),
   p_patch,btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness r WHERE r.test_id=p_test_id;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 RETURN next_version;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_technical_update_parameter(
 p_parameter_id UUID,p_patch JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE; next_version BIGINT; forbidden TEXT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_patch,'{}')) key
 WHERE key NOT IN ('unit','display_order','is_mandatory','range_validation_required','method_validation_required') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_PARAMETER_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'CATALOGUE_PARAMETER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 UPDATE public.parameters SET
   unit=CASE WHEN p_patch?'unit' THEN NULLIF(btrim(p_patch->>'unit'),'') ELSE unit END,
   display_order=CASE WHEN p_patch?'display_order' THEN (p_patch->>'display_order')::INT ELSE display_order END,
   is_mandatory=CASE WHEN p_patch?'is_mandatory' THEN (p_patch->>'is_mandatory')::BOOLEAN ELSE is_mandatory END,
   range_validation_required=CASE WHEN p_patch?'range_validation_required' THEN (p_patch->>'range_validation_required')::BOOLEAN ELSE range_validation_required END,
   method_validation_required=CASE WHEN p_patch?'method_validation_required' THEN (p_patch->>'method_validation_required')::BOOLEAN ELSE method_validation_required END,
   row_version=row_version+1,updated_at=now() WHERE id=p_parameter_id RETURNING row_version INTO next_version;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT p.test_id,r.configuration_version+1,'ParameterStructure','Configured',to_jsonb(p),p_patch,btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness r WHERE r.test_id=p.test_id;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,
   submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p.test_id;
 RETURN next_version;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_configuration_history(p_test_id UUID)
RETURNS TABLE(configuration_version BIGINT,category TEXT,status TEXT,actor_role TEXT,action_at TIMESTAMPTZ,reason TEXT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 RETURN QUERY SELECT e.configuration_version,e.category,e.status::TEXT,e.actor_role,e.created_at,e.reason
 FROM public.catalogue_configuration_evidence e WHERE e.test_id=p_test_id
 ORDER BY e.configuration_version DESC,e.created_at DESC,e.id DESC LIMIT 100;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_technical_save_range(
 p_range JSONB,p_expected_version BIGINT,p_reason TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.reference_ranges%ROWTYPE; result_id UUID; test_uuid UUID; old_row JSONB; forbidden TEXT;
 min_age INT:=COALESCE((p_range->>'age_min_days')::INT,0); max_age INT:=COALESCE((p_range->>'age_max_days')::INT,43800);
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT key INTO forbidden FROM jsonb_object_keys(COALESCE(p_range,'{}')) key WHERE key NOT IN
  ('id','parameter_id','gender','age_min_days','age_max_days','normal_min','normal_max','critical_low','critical_high','normal_text','reference_text','method','unit','effective_from','effective_to') LIMIT 1;
 IF forbidden IS NOT NULL THEN RAISE EXCEPTION 'PROTECTED_REFERENCE_RANGE_FIELD: %',forbidden USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Technical change reason is required.' USING ERRCODE='23514'; END IF;
 SELECT p.test_id INTO test_uuid FROM public.parameters p WHERE p.id=(p_range->>'parameter_id')::UUID AND p.lifecycle_status='Active';
 IF test_uuid IS NULL THEN RAISE EXCEPTION 'CATALOGUE_PARAMETER_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges x WHERE x.parameter_id=(p_range->>'parameter_id')::UUID
   AND x.id<>COALESCE(NULLIF(p_range->>'id','')::UUID,'00000000-0000-0000-0000-000000000000'::UUID)
   AND x.lifecycle_status='Active' AND x.is_active AND x.gender=COALESCE(p_range->>'gender','All')
   AND int4range(x.age_min_days,x.age_max_days,'[]')&&int4range(min_age,max_age,'[]')
   AND COALESCE(x.method,'')=COALESCE(NULLIF(btrim(p_range->>'method'),''),'')) THEN
   RAISE EXCEPTION 'Overlapping active reference range for the same sex and method.' USING ERRCODE='23505';
 END IF;
 IF NULLIF(p_range->>'id','') IS NOT NULL THEN
   SELECT * INTO r FROM public.reference_ranges WHERE id=(p_range->>'id')::UUID FOR UPDATE;
   IF NOT FOUND OR r.parameter_id<>(p_range->>'parameter_id')::UUID THEN RAISE EXCEPTION 'REFERENCE_RANGE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
   IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
   old_row:=to_jsonb(r);
   UPDATE public.reference_ranges SET gender=COALESCE(p_range->>'gender','All'),age_min_days=min_age,age_max_days=max_age,
    normal_min=(p_range->>'normal_min')::NUMERIC,normal_max=(p_range->>'normal_max')::NUMERIC,critical_low=(p_range->>'critical_low')::NUMERIC,critical_high=(p_range->>'critical_high')::NUMERIC,
    normal_text=NULLIF(btrim(p_range->>'normal_text'),''),reference_text=NULLIF(btrim(p_range->>'reference_text'),''),method=NULLIF(btrim(p_range->>'method'),''),unit=NULLIF(btrim(p_range->>'unit'),''),
    effective_from=COALESCE((p_range->>'effective_from')::DATE,effective_from),effective_to=NULLIF(p_range->>'effective_to','')::DATE,
    is_approved=FALSE,approved_by=NULL,approved_at=NULL,validation_state='Unclassified',validation_source='Technician configuration; final approval required',row_version=row_version+1,updated_at=now()
   WHERE id=r.id RETURNING id INTO result_id;
 ELSE
   INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source,effective_from,effective_to)
   VALUES((p_range->>'parameter_id')::UUID,COALESCE(p_range->>'gender','All'),min_age,max_age,(p_range->>'normal_min')::NUMERIC,(p_range->>'normal_max')::NUMERIC,(p_range->>'critical_low')::NUMERIC,(p_range->>'critical_high')::NUMERIC,NULLIF(btrim(p_range->>'normal_text'),''),NULLIF(btrim(p_range->>'reference_text'),''),NULLIF(btrim(p_range->>'method'),''),NULLIF(btrim(p_range->>'unit'),''),TRUE,FALSE,'Active','Unclassified','Technician configuration; final approval required',COALESCE((p_range->>'effective_from')::DATE,CURRENT_DATE),NULLIF(p_range->>'effective_to','')::DATE) RETURNING id INTO result_id;
 END IF;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,previous_state,new_state,reason,actor_id,actor_role)
 SELECT test_uuid,cr.configuration_version+1,'ReferenceRanges','Configured',old_row,
   jsonb_build_object('range_id',result_id,'approval','Final Super Admin approval required'),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role()
 FROM public.catalogue_service_readiness cr WHERE cr.test_id=test_uuid;
 UPDATE public.catalogue_service_readiness SET state='NeedsConfiguration',configuration_version=configuration_version+1,submitted_by=NULL,submitted_at=NULL,approved_by=NULL,approved_at=NULL,decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=test_uuid;
 RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_submit_for_review(p_test_id UUID,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; checklist JSONB; next_version BIGINT;
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 checklist:=public.catalogue_service_readiness_checklist(p_test_id);
 IF NOT COALESCE((checklist->>'ready_for_review')::BOOLEAN,FALSE) THEN
   RAISE EXCEPTION 'CATALOGUE_NOT_READY: %',checklist->'missing_requirements' USING ERRCODE='23514';
 END IF;
 next_version:=r.configuration_version+1;
 UPDATE public.catalogue_service_readiness SET state='ReadyForReview',configuration_version=next_version,
   submitted_by=auth.uid(),submitted_at=now(),decision_reason=NULLIF(btrim(p_reason),''),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'Workflow','Reviewed',checklist,COALESCE(NULLIF(btrim(p_reason),''),'Submitted for final review'),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_decide_readiness(
 p_test_id UUID,p_decision TEXT,p_reason TEXT,p_expected_version BIGINT)
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_service_readiness%ROWTYPE; t public.tests%ROWTYPE; checklist JSONB; next_version BIGINT; target public.catalogue_readiness_state_enum;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_super_admin() THEN RAISE EXCEPTION 'SUPER_ADMIN_APPROVAL_REQUIRED' USING ERRCODE='42501'; END IF;
 IF p_decision NOT IN ('Approve','Reject','Suspend','Reactivate') THEN RAISE EXCEPTION 'CATALOGUE_DECISION_INVALID' USING ERRCODE='22023'; END IF;
 IF btrim(COALESCE(p_reason,''))='' THEN RAISE EXCEPTION 'Approval, rejection, and suspension require a reason.' USING ERRCODE='23514'; END IF;
 SELECT * INTO r FROM public.catalogue_service_readiness WHERE test_id=p_test_id FOR UPDATE;
 SELECT * INTO t FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF r.configuration_version<>p_expected_version THEN RAISE EXCEPTION 'CATALOGUE_CONFIGURATION_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 checklist:=public.catalogue_service_readiness_checklist(p_test_id);
 next_version:=r.configuration_version+1;
 IF p_decision IN ('Approve','Reactivate') THEN
   IF r.state NOT IN ('ReadyForReview','Suspended') THEN RAISE EXCEPTION 'Service must be ReadyForReview or Suspended.' USING ERRCODE='23514'; END IF;
   IF NOT COALESCE((checklist->>'ready_for_review')::BOOLEAN,FALSE) THEN RAISE EXCEPTION 'CATALOGUE_NOT_READY: %',checklist->'missing_requirements' USING ERRCODE='23514'; END IF;
   IF checklist->>'classification' NOT IN ('InHouse','OutsourceWithBimalReport') THEN RAISE EXCEPTION 'Only supported clinical tests may be activated.' USING ERRCODE='23514'; END IF;
   target:='Approved';
   UPDATE public.tests SET clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSIF p_decision='Suspend' THEN
   target:='Suspended'; UPDATE public.tests SET clinical_reporting_enabled=FALSE,row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 ELSE
   target:='NeedsConfiguration'; UPDATE public.tests SET clinical_reporting_enabled=FALSE,clinical_configuration_status='Requires Clinical Validation',row_version=row_version+1,updated_at=now() WHERE id=p_test_id;
 END IF;
 UPDATE public.catalogue_service_readiness SET state=target,configuration_version=next_version,
   approved_by=CASE WHEN target='Approved' THEN auth.uid() END,approved_at=CASE WHEN target='Approved' THEN now() END,
   suspended_by=CASE WHEN target='Suspended' THEN auth.uid() END,suspended_at=CASE WHEN target='Suspended' THEN now() END,
   decision_reason=btrim(p_reason),updated_at=now() WHERE test_id=p_test_id;
 INSERT INTO public.catalogue_configuration_evidence(test_id,configuration_version,category,status,new_state,reason,actor_id,actor_role)
 VALUES(p_test_id,next_version,'FinalApproval',CASE WHEN target='Approved' THEN 'Approved'::public.catalogue_decision_status_enum ELSE 'Rejected'::public.catalogue_decision_status_enum END,
   checklist||jsonb_build_object('decision',p_decision,'resulting_state',target),btrim(p_reason),auth.uid(),public.catalogue_readiness_actor_role());
 RETURN next_version;
END $$;

CREATE OR REPLACE FUNCTION public.prevent_catalogue_evidence_mutation()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN RAISE EXCEPTION 'CATALOGUE_APPROVAL_EVIDENCE_IS_IMMUTABLE' USING ERRCODE='23514'; END $$;
CREATE TRIGGER catalogue_configuration_evidence_immutable
BEFORE UPDATE OR DELETE ON public.catalogue_configuration_evidence
FOR EACH ROW EXECUTE FUNCTION public.prevent_catalogue_evidence_mutation();

CREATE OR REPLACE FUNCTION public.catalogue_test_template_detail(p_source_order INT)
RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'TEST_TEMPLATE_ACCESS_DENIED' USING ERRCODE='42501'; END IF;
 SELECT jsonb_build_object(
   'source_order',ct.source_order,'name',ct.supplied_name,
   'basic',jsonb_build_object('test_name',t.name,'code',t.code,'category',tc.name,'test_type',d.test_type,'short_name',d.short_name),
   'parameters',COALESCE((SELECT jsonb_agg(jsonb_build_object('name',p.name,'unit',p.unit,'result_type',p.value_type,'display_order',p.display_order) ORDER BY p.display_order,p.id) FROM public.parameters p WHERE p.test_id=t.id AND p.is_active),'[]'::JSONB),
   'reference_ranges',COALESCE((SELECT jsonb_agg(jsonb_build_object('parameter',p.name,'sex',r.gender,'age_min_days',r.age_min_days,'age_max_days',r.age_max_days,'normal_min',r.normal_min,'normal_max',r.normal_max,'normal_text',r.normal_text,'critical_low',r.critical_low,'critical_high',r.critical_high,'method',NULLIF(r.method,'')) ORDER BY p.display_order,r.gender,r.age_min_days) FROM public.parameters p JOIN public.reference_ranges r ON r.parameter_id=p.id WHERE p.test_id=t.id AND p.is_active AND r.lifecycle_status='Active'),'[]'::JSONB),
   'workflow',jsonb_build_object('specimen',t.sample_type,'container',t.container,'reporting_model',t.reporting_model,'reporting_type',t.reporting_type,'collection_required',t.collection_required),
   'notes',jsonb_build_object('interpretation',t.interpretation_template,'technical_notes',NULL)
 ) INTO result
 FROM public.catalogue_test_templates ct
 JOIN public.catalogue_test_database_entries d ON d.source_order=ct.test_database_source_order
 JOIN public.tests t ON t.id=ct.configuration_test_id
 JOIN public.test_categories tc ON tc.id=d.category_id
 WHERE ct.source_order=p_source_order;
 IF result IS NULL THEN RAISE EXCEPTION 'TEST_TEMPLATE_NOT_FOUND' USING ERRCODE='P0002'; END IF;
 RETURN result;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_start_template_copy(p_source_order INT,p_proposed_code TEXT,p_proposed_name TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE draft_id UUID; normalized_code TEXT:=upper(btrim(COALESCE(p_proposed_code,''))); normalized_name TEXT:=regexp_replace(lower(btrim(COALESCE(p_proposed_name,''))),'[^a-z0-9]+','','g');
BEGIN
 PERFORM public.catalogue_require_readiness_staff();
 IF normalized_code='' OR normalized_name='' THEN RAISE EXCEPTION 'A distinct code and name are required for a copied draft.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.tests WHERE upper(code)=normalized_code OR regexp_replace(lower(name),'[^a-z0-9]+','','g')=normalized_name OR normalized_code=ANY(SELECT upper(x) FROM unnest(COALESCE(search_aliases,ARRAY[]::TEXT[])) x)) THEN
   RAISE EXCEPTION 'CATALOGUE_TEMPLATE_DESTINATION_COLLISION' USING ERRCODE='23505';
 END IF;
 INSERT INTO public.catalogue_test_template_drafts(template_source_order,created_by,proposed_code,proposed_name,technical_configuration)
 VALUES(p_source_order,auth.uid(),normalized_code,btrim(p_proposed_name),public.catalogue_test_template_detail(p_source_order)) RETURNING id INTO draft_id;
 RETURN draft_id;
END $$;

-- Conservative initial state: retain accepted active reportable services, surface every
-- other identity for human review, and never auto-enable a test.
INSERT INTO public.catalogue_service_readiness(test_id,state,decision_reason)
SELECT id,CASE
  WHEN clinical_reporting_enabled AND reporting_type IN ('InHouse','OutsourceWithBimalReport') AND workflow_supported THEN 'Approved'::public.catalogue_readiness_state_enum
  WHEN lifecycle_status='Draft' THEN 'Draft'::public.catalogue_readiness_state_enum
  ELSE 'NeedsConfiguration'::public.catalogue_readiness_state_enum END,
  CASE WHEN clinical_reporting_enabled THEN 'Accepted pre-00075 production configuration retained.'
       ELSE 'Initial conservative readiness audit required; no automatic approval.' END
FROM public.tests ON CONFLICT(test_id) DO NOTHING;

REVOKE ALL ON FUNCTION public.catalogue_readiness_actor_role(),public.catalogue_require_readiness_staff(),
 public.catalogue_classification(public.tests),public.catalogue_service_readiness_checklist(UUID),
 public.catalogue_readiness_inventory(TEXT,TEXT),public.catalogue_record_configuration_review(UUID,TEXT,TEXT,JSONB,BIGINT),
 public.catalogue_booking_readiness(UUID[]),
 public.catalogue_technical_update_test(UUID,JSONB,BIGINT,TEXT),
 public.catalogue_technical_update_parameter(UUID,JSONB,BIGINT,TEXT),public.catalogue_configuration_history(UUID),
 public.catalogue_technical_save_range(JSONB,BIGINT,TEXT),
 public.catalogue_submit_for_review(UUID,TEXT,BIGINT),public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT),
 public.prevent_catalogue_evidence_mutation(),public.catalogue_test_template_detail(INT),
 public.catalogue_start_template_copy(INT,TEXT,TEXT) FROM PUBLIC,anon,authenticated,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_service_readiness_checklist(UUID),public.catalogue_readiness_inventory(TEXT,TEXT),
 public.catalogue_record_configuration_review(UUID,TEXT,TEXT,JSONB,BIGINT),public.catalogue_submit_for_review(UUID,TEXT,BIGINT),
 public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT),public.catalogue_booking_readiness(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_technical_update_test(UUID,JSONB,BIGINT,TEXT),
 public.catalogue_technical_update_parameter(UUID,JSONB,BIGINT,TEXT),public.catalogue_configuration_history(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_technical_save_range(JSONB,BIGINT,TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_test_template_detail(INT),public.catalogue_start_template_copy(INT,TEXT,TEXT) TO authenticated;

COMMENT ON TABLE public.catalogue_configuration_evidence IS 'Append-only, actor-attributed clinical catalogue configuration and approval evidence.';
COMMENT ON FUNCTION public.catalogue_decide_readiness(UUID,TEXT,TEXT,BIGINT) IS 'Super-Admin-only final activation/suspension. Updates future-booking catalogue gates only.';

-- BEGIN GENERATED OPERATOR-APPROVED DATA RECONCILIATION
-- Inputs (SHA-256): catalogue e0fe28aef2c66ab07dc837dc142dab3085070e8ce6b0465edfd89c5672e43aa8;
-- ranges 3a9d9b4a06cba85ca963ef1b86c0a2f58d4ec6249fc2f056a55700c9e7d08806.
-- Existing canonical UUIDs are retained. BETA HCG aliases to BETA_HCG and is not inserted.
CREATE TEMP TABLE approved_catalogue_00075(code TEXT PRIMARY KEY,name TEXT,short_name TEXT,department TEXT,category TEXT,reporting_type TEXT,price_paisa BIGINT,sample_type TEXT,container TEXT,method TEXT,test_kind TEXT,pricing_policy TEXT,workflow_supported BOOLEAN,billing_enabled BOOLEAN,collection_required BOOLEAN,workflow_type TEXT,analyzer_configuration_required BOOLEAN,reporting_model TEXT) ON COMMIT DROP;
INSERT INTO approved_catalogue_00075 VALUES
('VITAMIN_D','25-Hydroxy Vitamin D (Total)','Vit D','Clinical Biochemistry','Vitamins','InHouse',300000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('AFP','Alfa Feto Protein',NULL,'Clinical Biochemistry','ECLIA','InHouse',150000,'Blood / Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,FALSE,TRUE,'Routine',FALSE,'NumericSingle'),
('ANTI_HCV','Anti-Hepatitis C Virus (Anti-HCV)','Anti-HCV','Serology & Immunology','Viral Serology','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('ASO','Anti-Streptolysin O (ASO Titer)','ASO','Serology & Immunology','Infectious Serology','InHouse',30000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('BETA_HCG','Beta-hCG Quantitative','Beta-hCG','Serology & Immunology','Hormones & Fertility','InHouse',160000,'Serum','Yellow Top (SST)','ECLIA / CLIA / CMIA','Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('UREA','Blood Urea','Urea','Clinical Biochemistry','Renal Function','InHouse',20000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('CRP','C-Reactive Protein (CRP, Quantitative)','CRP','Serology & Immunology','Inflammatory Markers','InHouse',80000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('CBC','Complete Blood Count (CBC / Hemogram)',NULL,'Hematology','Routine Hematology','InHouse',40000,'Whole Blood (EDTA)','Lavender Top (EDTA)',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('DENGUE_IGG','Dengue IgG Antibody (Rapid)','Dengue IgG','Serology & Immunology','Vector-Borne','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('DENGUE_IGM','Dengue IgM Antibody (Rapid)','Dengue IgM','Serology & Immunology','Vector-Borne','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('DENGUE_NS1','Dengue NS1 Antigen (Rapid)','Dengue NS1','Serology & Immunology','Vector-Borne','InHouse',100000,'Serum / Whole Blood','Yellow Top (SST) / EDTA',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('DLC','Differential Leukocyte Count (DLC)','DLC','Hematology','Routine Hematology','InHouse',10000,'Whole Blood','EDTA / Lavender Top',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('ESR','Erythrocyte Sedimentation Rate (ESR)','ESR','Hematology','Routine Hematology','InHouse',10000,'Whole Blood','Sodium Citrate / Black Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('FBS','Fasting Blood Sugar (FBS)','FBS','Clinical Biochemistry','Glucose & Diabetes','InHouse',5000,'Fluoride Plasma / Serum','Grey Top / Yellow Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('FT4','Free Thyroxine (FT4)','FT4','Immunology & Endocrinology','Endocrinology','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('FT3','Free Triiodothyronine (FT3)','FT3','Immunology & Endocrinology','Endocrinology','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('HBA1C','Glycated Hemoglobin (HbA1c)','HbA1c','Clinical Biochemistry','Glucose & Diabetes','InHouse',100000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericMultiParameter'),
('HB','Hemoglobin (Hb)','Hb','Hematology','Routine Hematology','InHouse',30000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('HBSAG','Hepatitis B Surface Antigen (HBsAg)','HBsAg','Serology & Immunology','Viral Serology','InHouse',40000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('HIV','HIV 1 & 2 Antibody / Antigen','HIV','Serology & Immunology','Viral Serology','InHouse',60000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('IHC','Immunohistochemistry (IHC)','IHC','Histopathology','Outsourced Histopathology','NoReporting',0,'Paraffin Block / Biopsy','Slide / Block','Immunoperoxidase Staining','Individual','Manual',TRUE,TRUE,TRUE,'Outsource',FALSE,'NarrativeDocument'),
('KFT','Kidney Function Test (KFT / RFT Profile)','KFT','Clinical Biochemistry','Renal Function','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Profile','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('LIPID_PROFILE','Lipid Profile','Lipid','Clinical Biochemistry','Lipid Metabolism','InHouse',100000,'Serum (Fasting)','Yellow Top (SST)',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('LIPID','Lipid Profile',NULL,'Clinical Biochemistry','Biochemistry Profiles','InHouse',75000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,FALSE,TRUE,'Routine',FALSE,'NumericSingle'),
('LFT','Liver Function Test (LFT)',NULL,'Clinical Biochemistry','Biochemistry Profiles','InHouse',90000,'Serum','Yellow Top (SST)',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('PCV','Packed Cell Volume (PCV / Hematocrit)','PCV','Hematology','Routine Hematology','InHouse',20000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('PBS','Peripheral Blood Smear Examination (PBS)','PBS','Hematology','Morphology','InHouse',80000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericMultiParameter'),
('PLT','Platelet Count','Platelets','Hematology','Routine Hematology','InHouse',20000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('PPBS','Post Prandial Blood Sugar (PPBS)','PPBS','Clinical Biochemistry','Glucose & Diabetes','InHouse',5000,'Fluoride Plasma / Serum','Grey Top / Yellow Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('PSA','Prostate Specific Antigen (PSA, Total)','PSA','Serology & Immunology','Tumor Markers','InHouse',150000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('RBS','Random Blood Sugar (RBS)','RBS','Clinical Biochemistry','Glucose & Diabetes','InHouse',10000,'Fluoride Plasma / Serum','Grey Top / Yellow Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('RBC_COUNT','Red Blood Cell Count (RBC Count)','RBC','Hematology','Routine Hematology','InHouse',20000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('RFT','Renal Function Test (RFT)',NULL,'Clinical Biochemistry','Biochemistry Profiles','InHouse',85000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,FALSE,TRUE,'Routine',FALSE,'NumericSingle'),
('RA_FACTOR','Rheumatoid Factor (RA Factor, Quantitative)','RA Factor','Serology & Immunology','Autoimmune','InHouse',80000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('CALCIUM','Serum Calcium (Total)','Calcium','Clinical Biochemistry','Minerals & Electrolytes','InHouse',45000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('CHLORIDE','Serum Chloride (Cl-)','Chloride','Clinical Biochemistry','Electrolytes','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('CREATININE','Serum Creatinine','Creatinine','Clinical Biochemistry','Renal Function','InHouse',35000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('FERRITIN','Serum Ferritin','Ferritin','Clinical Biochemistry','Iron Studies','InHouse',130000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('IRON','Serum Iron','Iron','Clinical Biochemistry','Iron Studies','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('MAGNESIUM','Serum Magnesium','Magnesium','Clinical Biochemistry','Minerals & Electrolytes','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('PHOSPHORUS','Serum Phosphorus (Inorganic)','Phosphorus','Clinical Biochemistry','Minerals & Electrolytes','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('POTASSIUM','Serum Potassium (K+)','Potassium','Clinical Biochemistry','Electrolytes','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('SODIUM','Serum Sodium (Na+)','Sodium','Clinical Biochemistry','Electrolytes','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('URIC_ACID','Serum Uric Acid','Uric Acid','Clinical Biochemistry','Renal Function','InHouse',25000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('STOOL_OB','Stool for Occult Blood (FOBT)','FOBT','Clinical Pathology','Clinical Pathology','InHouse',20000,'Fresh Stool Specimen','Stool Container',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('STOOL_RE','Stool Routine & Microscopic Examination (Stool R/E)','Stool R/E','Clinical Pathology','Clinical Pathology','InHouse',15000,'Fresh Stool Specimen','Stool Container with Spoon',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericMultiParameter'),
('THYROID_ECLIA','Thyroid Function Panel (FT3, FT4, Sensitive TSH)',NULL,'Immunology & Serology','Endocrinology','OutsourceWithBimalReport',120000,'Serum','Yellow Top (SST)',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('THYROID_PROFILE','Thyroid Profile (T3, T4, TSH)','TFT','Immunology & Endocrinology','Endocrinology','InHouse',120000,'Serum','Yellow Top (SST)',NULL,'Profile','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'Profile'),
('TSH','Thyroid Stimulating Hormone (TSH, Ultrasensitive)','TSH','Immunology & Endocrinology','Endocrinology','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('T4','Thyroxine Total (T4)','T4','Immunology & Endocrinology','Endocrinology','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('TIBC','Total Iron Binding Capacity (TIBC)','TIBC','Clinical Biochemistry','Iron Studies','InHouse',70000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('TLC','Total Leukocyte Count (TLC / WBC)','TLC','Hematology','Routine Hematology','InHouse',10000,'Whole Blood','EDTA / Lavender Top',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('T3','Triiodothyronine Total (T3)','T3','Immunology & Endocrinology','Endocrinology','InHouse',50000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('URINE_RE','Urine Routine & Microscopic Examination (Urine R/E)','Urine R/E','Clinical Pathology','Clinical Pathology','InHouse',15000,'Clean Catch Midstream Urine','Sterile Urine Container',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericMultiParameter'),
('VDRL','VDRL / RPR (Syphilis Serology)','VDRL','Serology & Immunology','Infectious Serology','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('VITAMIN_B12','Vitamin B12 (Cyanocobalamin)','Vit B12','Clinical Biochemistry','Vitamins','InHouse',180000,'Serum','Yellow Top (SST)',NULL,'Individual','Fixed',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericSingle'),
('WIDAL','Widal Agglutination Test (Typhoid)','Widal','Serology & Immunology','Infectious Serology','InHouse',0,'Serum','Yellow Top (SST)',NULL,'Individual','PricePending',TRUE,TRUE,TRUE,'Routine',FALSE,'NumericMultiParameter');

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM approved_catalogue_00075 a LEFT JOIN public.tests t ON t.code=a.code WHERE t.id IS NULL) THEN
   RAISE EXCEPTION 'APPROVED_CATALOGUE_CANONICAL_IDENTITY_MISSING';
 END IF;
 IF (SELECT count(*) FROM public.tests WHERE code='CBC')<>1 OR (SELECT count(*) FROM public.tests WHERE code='BETA_HCG')<>1 THEN
   RAISE EXCEPTION 'CANONICAL_IDENTITY_ASSERTION_FAILED';
 END IF;
END $$;

UPDATE public.tests t SET
 name=a.name, short_name=NULLIF(a.short_name,''), reporting_type=a.reporting_type::public.reporting_type_enum,
 price_paisa=a.price_paisa, sample_type=NULLIF(a.sample_type,''), container=NULLIF(a.container,''), method=NULLIF(a.method,''),
 test_kind=a.test_kind::public.catalogue_test_kind_enum, pricing_policy=a.pricing_policy::public.catalogue_pricing_policy_enum,
 workflow_supported=a.workflow_supported, billing_enabled=(a.billing_enabled AND a.price_paisa>0), collection_required=a.collection_required,
 workflow_type=a.workflow_type::public.clinical_workflow_type_enum, analyzer_configuration_required=a.analyzer_configuration_required,
 reporting_model=a.reporting_model::public.catalogue_reporting_model_enum, lifecycle_status='Active', is_active=TRUE,
 price_configured=(a.price_paisa>0), row_version=t.row_version+1, updated_at=now()
FROM approved_catalogue_00075 a WHERE t.code=a.code;

-- The final approved CBC set reuses fourteen canonical identities and adds only genuinely absent MPV/PDW.
DO $$ DECLARE c UUID; BEGIN
 SELECT id INTO c FROM public.tests WHERE code='CBC';
 IF (SELECT count(*) FROM public.parameters WHERE test_id=c AND code IN ('RBC','HB','PCV','MCV','MCH','MCHC','RDW','TLC','NEUT','LYMPH','MONO','EOSIN','BASO','PLT') AND lifecycle_status='Active')<>14 THEN
   RAISE EXCEPTION 'CBC_CANONICAL_PARAMETER_ASSERTION_FAILED';
 END IF;
 INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
 VALUES (c,'MPV','Mean Platelet Volume','Numeric','fL',15,TRUE,TRUE,'Active','Configured',TRUE,TRUE,FALSE),
        (c,'PDW','Platelet Distribution Width','Numeric','%',16,TRUE,TRUE,'Active','Configured',TRUE,TRUE,FALSE)
 ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,is_active=TRUE,lifecycle_status='Active',range_validation_required=TRUE,row_version=public.parameters.row_version+1,updated_at=now();
END $$;

-- Approved operator panel Blood Sugar Fasting & PP. Its diagnostic table is
-- panel-level interpretation only and is never promoted into parameter ranges,
-- flags, critical limits, or calculation definitions.
DO $$
DECLARE
  v_panel CONSTANT UUID := '75000000-0000-0000-0000-000000000076';
  v_package CONSTANT UUID := '75000000-0000-0000-0000-000000000176';
  v_category UUID;
  v_fbs UUID;
  v_ppbs UUID;
BEGIN
  SELECT id INTO STRICT v_category FROM public.test_categories WHERE code='BIOCHEMISTRY';
  SELECT id INTO STRICT v_fbs FROM public.tests WHERE code='FBS';
  SELECT id INTO STRICT v_ppbs FROM public.tests WHERE code='PPBS';

  INSERT INTO public.catalogue_panels(
    id,code,name,category_id,clinical_notes,interpretation_rows,interpretation_notes,
    hide_component_interpretation,show_component_method_instrument,
    reporting_type,workflow_supported,clinical_reporting_enabled,lifecycle_status,display_order
  ) VALUES (
    v_panel,'BLOOD_SUGAR_FASTING_PP','Blood Sugar Fasting & PP',v_category,
    $note$Elevated glucose levels (hyperglycemia) are most often encountered clinically in
the setting of diabetes mellitus, but they may also occur with pancreatic
neoplasms, hyperthyroidism, and adrenocortical dysfunction.

Decreased glucose levels (hypoglycemia) may result from endogenous or exogenous
insulin excess, prolonged starvation, or liver disease.$note$,
    jsonb_build_array(
      jsonb_build_object('fasting_glucose','<100','pp_glucose_2h','<140','diagnosis','Normal'),
      jsonb_build_object('fasting_glucose','100 to 125','pp_glucose_2h','140 to 199','diagnosis','Pre Diabetes'),
      jsonb_build_object('fasting_glucose','>126','pp_glucose_2h','>200','diagnosis','Diabetes')
    ),
    ARRAY[
      'A level of 126 mg/dL or above, confirmed by repeating the test on another day, means a person has diabetes.',
      'IGT (2 hrs Post meal) means a person has an increased risk of developing type 2 diabetes but does not have it yet.',
      'A 2-hour glucose level of 200 mg/dL or above, confirmed by repeating the test on another day, means a person has diabetes.'
    ]::TEXT[],
    TRUE,TRUE,'InHouse',TRUE,TRUE,'Active',6
  )
  ON CONFLICT(code) DO UPDATE SET
    name=EXCLUDED.name,category_id=EXCLUDED.category_id,
    clinical_notes=EXCLUDED.clinical_notes,
    interpretation_rows=EXCLUDED.interpretation_rows,
    interpretation_notes=EXCLUDED.interpretation_notes,
    hide_component_interpretation=TRUE,show_component_method_instrument=TRUE,
    reporting_type='InHouse',workflow_supported=TRUE,
    clinical_reporting_enabled=TRUE,lifecycle_status='Active',display_order=6,updated_at=now();

  DELETE FROM public.catalogue_panel_components WHERE panel_id=v_panel;
  INSERT INTO public.catalogue_panel_components(panel_id,component_test_id,display_name,display_order)
  VALUES
    (v_panel,v_fbs,'Fasting Blood Sugar',1),
    (v_panel,v_ppbs,'Blood Sugar PP',2);

  INSERT INTO public.health_packages(id,code,name,description,price_paisa,pricing_policy,lifecycle_status,search_aliases)
  VALUES(v_package,'BLOOD_SUGAR_FASTING_PP','Blood Sugar Fasting & PP','Commercial ratelist entry for the canonical Blood Sugar Fasting & PP clinical panel.',10000,'Fixed','Active',ARRAY['fbs pp','blood sugar fasting pp']::TEXT[])
  ON CONFLICT(code) DO UPDATE SET
    name=EXCLUDED.name,description=EXCLUDED.description,price_paisa=EXCLUDED.price_paisa,
    pricing_policy='Fixed',lifecycle_status='Active',search_aliases=EXCLUDED.search_aliases,
    row_version=public.health_packages.row_version+1,updated_at=now();

  DELETE FROM public.health_package_components WHERE package_id=v_package;
  INSERT INTO public.health_package_components(package_id,test_id,display_order)
  VALUES(v_package,v_fbs,1),(v_package,v_ppbs,2);

  INSERT INTO public.catalogue_panel_ratelist_links(panel_id,ratelist_name,operator_rate_npr,health_package_id)
  VALUES
    (v_panel,'Blood Sugar Fasting & PP',100,v_package),
    (v_panel,'Diabetic package',100,NULL)
  ON CONFLICT(panel_id,ratelist_name) DO UPDATE SET
    operator_rate_npr=EXCLUDED.operator_rate_npr,
    health_package_id=EXCLUDED.health_package_id;
END $$;

-- Final operator-approved Liver Function Test panel. The clinical panel reuses
-- the canonical LFT test UUID; commercial/package names remain separate links.
-- Existing accepted calculation evidence is deliberately not rewritten. The
-- SGOT/SGPT identity is added because it is genuinely absent, but no formula is
-- manufactured by this migration.
DO $$
DECLARE
  v_panel UUID;
  v_category UUID;
BEGIN
  SELECT id INTO STRICT v_panel FROM public.tests WHERE code='LFT';
  SELECT id INTO STRICT v_category FROM public.test_categories WHERE code='BIOCHEMISTRY';

  IF (SELECT count(*) FROM public.tests WHERE code='LFT')<>1 THEN
    RAISE EXCEPTION 'LFT_CANONICAL_IDENTITY_ASSERTION_FAILED';
  END IF;

  INSERT INTO public.parameters(
    test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,
    lifecycle_status,clinical_configuration_status,unit_validation_required,
    range_validation_required,method_validation_required
  ) VALUES (
    v_panel,'SGOT_SGPT_RATIO','SGOT/SGPT','Calculated','ratio',6,FALSE,TRUE,
    'Active','Configured',TRUE,FALSE,FALSE
  )
  ON CONFLICT(test_id,code) DO UPDATE SET
    name=EXCLUDED.name,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,
    is_active=TRUE,lifecycle_status='Active',row_version=public.parameters.row_version+1,
    updated_at=now();

  UPDATE public.parameters SET display_order=1,updated_at=now() WHERE test_id=v_panel AND code='TBIL';
  UPDATE public.parameters SET display_order=2,updated_at=now() WHERE test_id=v_panel AND code='DBIL';
  UPDATE public.parameters SET display_order=3,updated_at=now() WHERE test_id=v_panel AND code='IBIL';
  UPDATE public.parameters SET display_order=4,updated_at=now() WHERE test_id=v_panel AND code='SGOT';
  UPDATE public.parameters SET display_order=5,updated_at=now() WHERE test_id=v_panel AND code='SGPT';
  UPDATE public.parameters SET display_order=7,updated_at=now() WHERE test_id=v_panel AND code='ALP';
  UPDATE public.parameters SET display_order=8,updated_at=now() WHERE test_id=v_panel AND code='TP';
  UPDATE public.parameters SET display_order=9,updated_at=now() WHERE test_id=v_panel AND code='ALB';
  UPDATE public.parameters SET display_order=10,updated_at=now() WHERE test_id=v_panel AND code='GLOB';
  UPDATE public.parameters SET display_order=11,updated_at=now() WHERE test_id=v_panel AND code='AG_RATIO';

  IF (SELECT count(*) FROM public.parameters WHERE test_id=v_panel AND code IN
      ('TBIL','DBIL','IBIL','SGOT','SGPT','SGOT_SGPT_RATIO','ALP','TP','ALB','GLOB','AG_RATIO'))<>11 THEN
    RAISE EXCEPTION 'LFT_CANONICAL_COMPONENT_ASSERTION_FAILED';
  END IF;

  INSERT INTO public.catalogue_panels(
    id,code,name,category_id,clinical_notes,
    hide_component_interpretation,show_component_method_instrument,
    reporting_type,workflow_supported,clinical_reporting_enabled,lifecycle_status,display_order
  ) VALUES (
    v_panel,'LFT','Liver Function Test (LFT)',v_category,
    $note$LFT Interpretation

Liver Function Blood Test gives an insight into your liver health and helps identify problems like hepatitis, cirrhosis, and fatty liver disease, which may cause similar symptoms but require different treatments to recover.

Test Significance

Besides diagnosing liver problems, LFT’s also monitor overall liver functioning. Monitoring helps people with liver disease or taking medication, as it helps screen whether the treatment works fine or requires adjustments. Moreover, Liver Function Tests help determine if someone is at risk of developing liver diseases. Apart from assessing your chances, this test also checks the severity of the liver damage to help the doctor plan and prescribe appropriate treatment.

Increased in

Acute or chronic hepatitis, cirrhosis, biliary tract obstruction, toxic hepatitis, neonatal jaundice (neonatal hyperbilirubinemia), congenital liver enzyme abnormalities (Dubin-Johnson, Rotor, Gilbert, Crigler-Najjar syndromes), fasting, hemolytic disorders. Hepatotoxic drugs.$note$,
    TRUE,TRUE,'InHouse',TRUE,TRUE,'Active',7
  )
  ON CONFLICT(code) DO UPDATE SET
    name=EXCLUDED.name,category_id=EXCLUDED.category_id,clinical_notes=EXCLUDED.clinical_notes,
    hide_component_interpretation=TRUE,show_component_method_instrument=TRUE,
    reporting_type='InHouse',workflow_supported=TRUE,clinical_reporting_enabled=TRUE,
    lifecycle_status='Active',display_order=7,updated_at=now();

  DELETE FROM public.catalogue_panel_components WHERE panel_id=v_panel;
  INSERT INTO public.catalogue_panel_components(panel_id,component_parameter_id,display_name,display_order)
  SELECT v_panel,p.id,x.display_name,x.display_order
  FROM (VALUES
    ('TBIL','Serum Bilirubin (Total)',1),
    ('DBIL','Serum Bilirubin (Direct)',2),
    ('IBIL','Serum Bilirubin (Indirect)',3),
    ('SGOT','SGOT (AST)',4),
    ('SGPT','SGPT (ALT)',5),
    ('SGOT_SGPT_RATIO','SGOT/SGPT',6),
    ('ALP','Serum Alkaline Phosphatase',7),
    ('TP','Serum Protein',8),
    ('ALB','Serum Albumin',9),
    ('GLOB','Globulin',10),
    ('AG_RATIO','A/G Ratio',11)
  ) AS x(code,display_name,display_order)
  JOIN public.parameters p ON p.test_id=v_panel AND p.code=x.code;

  IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=v_panel)<>11 OR
     (SELECT count(DISTINCT component_parameter_id) FROM public.catalogue_panel_components WHERE panel_id=v_panel)<>11 THEN
    RAISE EXCEPTION 'LFT_PANEL_COMPOSITION_ASSERTION_FAILED';
  END IF;

  DELETE FROM public.catalogue_profile_components WHERE profile_test_id=v_panel;
  INSERT INTO public.catalogue_profile_components(
    profile_test_id,component_parameter_id,component_role,display_order,source_numbers
  )
  SELECT v_panel,c.component_parameter_id,
         CASE WHEN p.value_type='Calculated' THEN 'Calculated' ELSE 'Measured' END,
         c.display_order,ARRAY[]::INT[]
  FROM public.catalogue_panel_components c
  JOIN public.parameters p ON p.id=c.component_parameter_id
  WHERE c.panel_id=v_panel
  ORDER BY c.display_order;

  UPDATE public.tests SET price_paisa=100000,price_configured=TRUE,billing_enabled=TRUE,
    reporting_type='InHouse',workflow_supported=TRUE,clinical_reporting_enabled=TRUE,
    lifecycle_status='Active',is_active=TRUE,row_version=row_version+1,updated_at=now()
  WHERE id=v_panel;

  INSERT INTO public.catalogue_panel_ratelist_links(panel_id,ratelist_name,operator_rate_npr)
  VALUES
    (v_panel,'Liver Function Test (LFT)',1000),
    (v_panel,'Fitness Package',100),
    (v_panel,'Full body checkup (Female)',100),
    (v_panel,'Full body checkup (Male)',100)
  ON CONFLICT(panel_id,ratelist_name) DO UPDATE SET operator_rate_npr=EXCLUDED.operator_rate_npr;
END $$;

-- Approved operator panel BT & CT reuses the existing BT_CT profile UUID and
-- its two canonical parameter UUIDs. Operator approval changes the intended
-- reporting classification to InHouse, while technical readiness remains
-- fail-closed until units/specimen and other mandatory configuration pass.
DO $$
DECLARE
  v_panel UUID;
  v_category UUID;
BEGIN
  SELECT id INTO STRICT v_panel FROM public.tests WHERE code='BT_CT';
  SELECT id INTO STRICT v_category FROM public.test_categories WHERE code='HEMATOLOGY';

  UPDATE public.tests
  SET name='BT & CT',
      reporting_type='InHouse',
      workflow_type='Routine',
      reporting_model='Profile',
      test_kind='Profile',
      workflow_supported=TRUE,
      clinical_reporting_enabled=FALSE,
      billing_enabled=FALSE,
      clinical_configuration_status='Requires Clinical Validation',
      row_version=row_version+1,
      updated_at=now()
  WHERE id=v_panel;

  INSERT INTO public.catalogue_panels(
    id,code,name,category_id,clinical_notes,
    hide_component_interpretation,show_component_method_instrument,
    reporting_type,workflow_supported,clinical_reporting_enabled,
    lifecycle_status,display_order
  ) VALUES (
    v_panel,'BT_CT','BT & CT',v_category,
    $note$Bleeding Time:
The bleeding time test assesses primary hemostasis (vascular and platelet components) and is dependent on adequate functioning of platelets and blood vessels.

Causes of prolongation of bleeding time:

1. Thrombocytopenia
2. Disorders of platelet function
3. Von Willebrand disease
4. Disorders of blood vessels

Clotting Time:
Clotting time measures the time required for the blood to clot in a glass test tube kept at 37°C. Prolongation of clotting time only occurs in severe deficiency of a clotting factor and is normal in mild or moderate deficiency.

Note:
Recommended test is Prothrombin Time (PT) and Activated Partial Thromboplastin time (APTT).$note$,
    TRUE,TRUE,'InHouse',TRUE,FALSE,'Draft',4
  )
  ON CONFLICT(code) DO UPDATE SET
    name=EXCLUDED.name,
    category_id=EXCLUDED.category_id,
    clinical_notes=EXCLUDED.clinical_notes,
    hide_component_interpretation=TRUE,
    show_component_method_instrument=TRUE,
    reporting_type='InHouse',
    workflow_supported=TRUE,
    display_order=4,
    updated_at=now();

  DELETE FROM public.catalogue_panel_components WHERE panel_id=v_panel;
  INSERT INTO public.catalogue_panel_components(
    panel_id,component_parameter_id,display_name,display_order
  ) VALUES
    (v_panel,(SELECT id FROM public.parameters WHERE test_id=v_panel AND code='BLEEDING_TIME'),'Bleeding Time',1),
    (v_panel,(SELECT id FROM public.parameters WHERE test_id=v_panel AND code='CLOTTING_TIME'),'Clotting Time',2);

  IF (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=v_panel)<>2 THEN
    RAISE EXCEPTION 'BT_CT_CANONICAL_COMPONENT_ASSERTION_FAILED';
  END IF;

  INSERT INTO public.catalogue_panel_ratelist_links(panel_id,ratelist_name,operator_rate_npr)
  VALUES(v_panel,'BT & CT',200)
  ON CONFLICT(panel_id,ratelist_name) DO UPDATE SET operator_rate_npr=EXCLUDED.operator_rate_npr;
END $$;

-- Approved operator panel: one clinical identity, fifteen canonical component
-- references, and four commercial/source link records. The numeric source
-- values are commercial rates attached to each ratelist name; they never alter
-- the clinical panel composition.
DO $$
DECLARE
  v_panel CONSTANT UUID := '75000000-0000-0000-0000-000000000075';
  v_category UUID;
  v_cbc UUID;
BEGIN
  SELECT id INTO STRICT v_category FROM public.test_categories WHERE code = 'HEMATOLOGY';
  SELECT id INTO STRICT v_cbc FROM public.tests WHERE code = 'CBC';

  INSERT INTO public.catalogue_panels(
    id, code, name, category_id, clinical_notes,
    hide_component_interpretation, show_component_method_instrument,
    reporting_type, workflow_supported, clinical_reporting_enabled,
    lifecycle_status, display_order
  ) VALUES (
    v_panel, 'CBC_WITH_ESR', 'CBC with ESR', v_category, NULL,
    TRUE, TRUE, 'InHouse', TRUE, FALSE, 'Draft', 3
  )
  ON CONFLICT (code) DO UPDATE SET
    name = EXCLUDED.name,
    category_id = EXCLUDED.category_id,
    hide_component_interpretation = TRUE,
    show_component_method_instrument = TRUE,
    reporting_type = 'InHouse',
    workflow_supported = TRUE,
    display_order = 3,
    updated_at = now();

  DELETE FROM public.catalogue_panel_components WHERE panel_id = v_panel;
  INSERT INTO public.catalogue_panel_components(
    panel_id, component_test_id, component_parameter_id, display_name, display_order
  ) VALUES
    (v_panel, (SELECT id FROM public.tests WHERE code='HB'), NULL, 'Hemoglobin', 1),
    (v_panel, (SELECT id FROM public.tests WHERE code='TLC'), NULL, 'Total Leukocyte Count', 2),
    (v_panel, (SELECT id FROM public.tests WHERE code='DLC'), NULL, 'Differential Leucocyte Count', 3),
    (v_panel, (SELECT id FROM public.tests WHERE code='PLT'), NULL, 'Platelet Count', 4),
    (v_panel, (SELECT id FROM public.tests WHERE code='RBC_COUNT'), NULL, 'Total RBC Count', 5),
    (v_panel, (SELECT id FROM public.tests WHERE code='PCV'), NULL, 'Hematocrit Value, Hct', 6),
    (v_panel, NULL, (SELECT id FROM public.parameters WHERE test_id=v_cbc AND code='MCV'), 'Mean Corpuscular Volume, MCV', 7),
    (v_panel, NULL, (SELECT id FROM public.parameters WHERE test_id=v_cbc AND code='MCH'), 'Mean Cell Haemoglobin, MCH', 8),
    (v_panel, NULL, (SELECT id FROM public.parameters WHERE test_id=v_cbc AND code='MCHC'), 'Mean Cell Haemoglobin CON, MCHC', 9),
    (v_panel, (SELECT id FROM public.tests WHERE code='MPV'), NULL, 'Mean Platelet Volume, MPV', 10),
    (v_panel, (SELECT id FROM public.tests WHERE code='R_D_W_SD'), NULL, 'R.D.W. - SD', 11),
    (v_panel, (SELECT id FROM public.tests WHERE code='R_D_W_CV'), NULL, 'R.D.W. - CV', 12),
    (v_panel, (SELECT id FROM public.tests WHERE code='P_LCR'), NULL, 'P-LCR', 13),
    (v_panel, (SELECT id FROM public.tests WHERE code='P_D_W'), NULL, 'P.D.W.', 14),
    (v_panel, (SELECT id FROM public.tests WHERE code='ESR_WINTROBE'), NULL, 'Erythrocyte Sedimentation Rate (Wintrobe)', 15);

  IF EXISTS (
    SELECT 1 FROM public.catalogue_panel_components
    WHERE panel_id=v_panel AND component_test_id IS NULL AND component_parameter_id IS NULL
  ) OR (SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=v_panel) <> 15 THEN
    RAISE EXCEPTION 'CBC_WITH_ESR_CANONICAL_COMPONENT_ASSERTION_FAILED';
  END IF;

  INSERT INTO public.catalogue_panel_ratelist_links(panel_id,ratelist_name,operator_rate_npr)
  VALUES
    (v_panel,'CBC with ESR',500),
    (v_panel,'Anemia package',100),
    (v_panel,'Arthritis Package',100),
    (v_panel,'Fever package',1550)
  ON CONFLICT (panel_id,ratelist_name) DO UPDATE
    SET operator_rate_npr=EXCLUDED.operator_rate_npr;
END $$;

-- Operator master catalogue presentation: keep CBC as the existing canonical
-- profile and extend its ordered composition only with the two genuinely new
-- approved parameters. Differential cells remain canonical CBC parameters;
-- no duplicate Hb/Hgb, Hct/PCV, WBC/TLC or PLT identities are introduced.
DO $$
DECLARE
  v_cbc UUID;
  v_mpv UUID;
  v_pdw UUID;
BEGIN
  SELECT id INTO STRICT v_cbc FROM public.tests WHERE code = 'CBC';
  SELECT id INTO STRICT v_mpv FROM public.parameters WHERE test_id = v_cbc AND code = 'MPV';
  SELECT id INTO STRICT v_pdw FROM public.parameters WHERE test_id = v_cbc AND code = 'PDW';

  INSERT INTO public.catalogue_profile_components(
    profile_test_id, component_parameter_id, component_role, display_order,
    is_required, source_numbers
  ) VALUES
    (v_cbc, v_mpv, 'Measured', 15, TRUE, '{}'::INT[]),
    (v_cbc, v_pdw, 'Measured', 16, TRUE, '{}'::INT[])
  ON CONFLICT (profile_test_id, component_parameter_id) DO UPDATE
    SET component_role = EXCLUDED.component_role,
        display_order = EXCLUDED.display_order,
        is_required = EXCLUDED.is_required;

  UPDATE public.tests
  SET description = 'Complete Blood Count (CBC) panel. Used to evaluate overall health and detect disorders including anemia, infection, and leukemia. Individual component methods, instruments, approved reference ranges and interpretations remain attached to their canonical test/parameter definitions.',
      row_version = row_version + 1,
      updated_at = now()
  WHERE id = v_cbc;
END $$;

-- Operator-approved Test Database identities that are genuine profile-derived
-- components but were absent as canonical parameters. They remain calculation
-- configuration identities only; 00075 does not manufacture formulas.
DO $$
DECLARE v_lipid UUID; v_kft UUID;
BEGIN
 SELECT id INTO STRICT v_lipid FROM public.tests WHERE code='LIPID_PROFILE';
 SELECT id INTO STRICT v_kft FROM public.tests WHERE code='KFT';
 INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
 VALUES
 (v_lipid,'LDL_HDL_RATIO','LDL / HDL','Calculated','ratio',6,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_lipid,'TC_HDL_RATIO','Total Cholesterol / HDL','Calculated','ratio',7,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_lipid,'TG_HDL_RATIO','TG / HDL','Calculated','ratio',8,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_lipid,'NON_HDL','Non-HDL cholesterol','Calculated','mg/dL',9,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_kft,'EGFR','eGFR','Calculated','mL/min/1.73m²',6,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_kft,'EGFR_CATEGORY','eGFR Category','Calculated',NULL,7,FALSE,TRUE,'Active','Configured',FALSE,FALSE,FALSE),
 (v_kft,'UREA_CREAT_RATIO','Urea / Creatinine Ratio','Calculated','ratio',8,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE),
 (v_kft,'BUN_CREAT_RATIO','BUN / Creatinine Ratio','Calculated','ratio',9,FALSE,TRUE,'Active','Configured',TRUE,FALSE,FALSE)
 ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,is_active=TRUE,lifecycle_status='Active',row_version=public.parameters.row_version+1,updated_at=now();
END $$;

-- The final panel list supplies one genuinely new structural identity that is
-- absent from TM256. It is deliberately non-reportable until the specialist
-- workflow is configured; no method, analyzer, range, price or result schema is
-- inferred from the service name.
INSERT INTO public.tests(
 id,code,name,short_name,department,category,category_id,test_kind,reporting_type,
 price_paisa,price_configured,pricing_policy,sample_type,container,is_active,
 lifecycle_status,clinical_configuration_status,workflow_supported,billing_enabled,
 clinical_reporting_enabled,collection_required,workflow_type,reporting_model,
 configuration_notes,search_aliases
)
SELECT '75000000-0000-0000-0000-000000000228','SERUM_PROTEIN_ELECTROPHORESIS',
 'Serum Protein Electrophoresis','SPE','Biochemistry','Biochemistry',c.id,
 'Individual','InHouse',0,FALSE,'PricePending','','',TRUE,'Active','Workflow Not Supported',
 FALSE,FALSE,FALSE,FALSE,'Routine','NarrativeDocument',
 'Final operator-approved structural identity. Specialist workflow, specimen, method, analyzer, price and report structure are not configured.',
 ARRAY['protein electrophoresis','spe']::TEXT[]
FROM public.test_categories c WHERE c.code='BIOCHEMISTRY'
ON CONFLICT(code) DO UPDATE SET
 name=EXCLUDED.name,short_name=EXCLUDED.short_name,category_id=EXCLUDED.category_id,
 category=EXCLUDED.category,department=EXCLUDED.department,is_active=TRUE,lifecycle_status='Active',
 workflow_supported=FALSE,billing_enabled=FALSE,clinical_reporting_enabled=FALSE,
 clinical_configuration_status='Workflow Not Supported',reporting_model='NarrativeDocument',
 configuration_notes=EXCLUDED.configuration_notes,search_aliases=EXCLUDED.search_aliases,
 row_version=public.tests.row_version+1,updated_at=now();

-- Consolidated operator Test Panels master. Panel composition is authoritative;
-- commercial ratelist names remain separate and every component resolves to a
-- canonical test or canonical parameter.
CREATE TEMP TABLE operator_panel_master_00075(
  display_order INT PRIMARY KEY, code TEXT UNIQUE, name TEXT UNIQUE,
  category_code TEXT, canonical_test_code TEXT, fallback_id UUID,
  workflow_supported BOOLEAN, clinical_reporting_enabled BOOLEAN
) ON COMMIT DROP;
INSERT INTO operator_panel_master_00075 VALUES
(1,'CBC','Complete Blood Count (CBC)','HEMATOLOGY','CBC',NULL,TRUE,TRUE),
(2,'CBC_WITH_ABSOLUTE_COUNTS','CBC (with absolute counts)','HEMATOLOGY',NULL,'75000000-0000-0000-0000-000000000202',TRUE,TRUE),
(3,'CBC_WITH_ESR','CBC with ESR','HEMATOLOGY',NULL,'75000000-0000-0000-0000-000000000075',TRUE,TRUE),
(4,'BT_CT','BT & CT','HEMATOLOGY','BT_CT',NULL,TRUE,TRUE),
(5,'COAG_PROFILE','Coagulation Profile','HEMATOLOGY','COAG_PROFILE',NULL,TRUE,TRUE),
(6,'BLOOD_SUGAR_FASTING_PP','Blood Sugar Fasting & PP','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000076',TRUE,TRUE),
(7,'LFT','Liver Function Test (LFT)','BIOCHEMISTRY','LFT',NULL,TRUE,TRUE),
(8,'BILIRUBIN_TD','Bilirubin Total, Direct & Indirect','BIOCHEMISTRY','BILIRUBIN_TD',NULL,TRUE,TRUE),
(9,'KFT','Kidney Function Test (KFT)','BIOCHEMISTRY','KFT',NULL,TRUE,TRUE),
(10,'KFT_WITHOUT_EGFR','KFT without eGFR','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000210',TRUE,TRUE),
(11,'LIPID_PROFILE','Lipid Profile','BIOCHEMISTRY','LIPID_PROFILE',NULL,TRUE,TRUE),
(12,'ELECTROLYTES_PANEL','Electrolytes Panel','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000212',TRUE,TRUE),
(13,'ARTHRITIS_PROFILE','Arthritis Profile','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000213',TRUE,TRUE),
(14,'PROTEIN_FRACTION','Protein Fraction','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000214',TRUE,TRUE),
(15,'TORCH_PROFILE','Torch Profile','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000215',TRUE,TRUE),
(16,'IRON_PROFILE','Iron Studies','BIOCHEMISTRY','IRON_PROFILE',NULL,TRUE,TRUE),
(17,'AMH_PANEL','AMH Panel','BIOCHEMISTRY',NULL,'75000000-0000-0000-0000-000000000217',TRUE,TRUE),
(18,'VIRAL_MARKER','Viral Marker','SEROLOGY',NULL,'75000000-0000-0000-0000-000000000218',TRUE,TRUE),
(19,'THYROID_PROFILE','Thyroid Function Test (TFT)','ENDOCRINOLOGY','THYROID_PROFILE',NULL,TRUE,TRUE),
(20,'THYROID_ECLIA','Free Thyroid Function Test (FTFT)','ENDOCRINOLOGY','THYROID_ECLIA',NULL,TRUE,TRUE),
(21,'PCOD_PANEL','Pcod','ENDOCRINOLOGY',NULL,'75000000-0000-0000-0000-000000000221',TRUE,TRUE),
(22,'UPCR','Urine Protein/Creatinine Ratio (UPCR)','BIOCHEMISTRY','UPCR',NULL,TRUE,TRUE),
(23,'EGFR','Estimated Glomerular Filtration Rate (eGFR)','BIOCHEMISTRY','EGFR',NULL,TRUE,TRUE),
(24,'CBC_WITH_MORPHOLOGY','CBC with Morphology','HEMATOLOGY',NULL,'75000000-0000-0000-0000-000000000224',TRUE,TRUE),
(25,'CCP','Anti-ccp','BIOCHEMISTRY','CCP',NULL,TRUE,TRUE),
(26,'PUS_CULTURE_AND_SENSITIVITY','Pus Culture and Sensitivity','MICROBIOLOGY','PUS_CULTURE_AND_SENSITIVITY',NULL,FALSE,FALSE),
(27,'ADA','Serum ADA','BIOCHEMISTRY','ADA',NULL,TRUE,TRUE),
(28,'SERUM_PROTEIN_ELECTROPHORESIS','Serum Protein Electrophoresis','BIOCHEMISTRY','SERUM_PROTEIN_ELECTROPHORESIS','75000000-0000-0000-0000-000000000228',FALSE,FALSE),
(29,'GENETIC_TEST','BRCA1 BRCA2','SEROLOGY','GENETIC_TEST',NULL,FALSE,FALSE),
(30,'PRL','Prolactin','SEROLOGY','PRL',NULL,TRUE,TRUE),
(31,'CEA_CARCINOEMBRYONIC_ANTIGEN','CEA','SEROLOGY','CEA_CARCINOEMBRYONIC_ANTIGEN',NULL,TRUE,TRUE);

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM operator_panel_master_00075 m LEFT JOIN public.test_categories c ON c.code=m.category_code WHERE c.id IS NULL) THEN
   RAISE EXCEPTION 'OPERATOR_PANEL_CATEGORY_UNRESOLVED';
 END IF;
 IF EXISTS(SELECT 1 FROM operator_panel_master_00075 m LEFT JOIN public.tests t ON t.code=m.canonical_test_code WHERE m.canonical_test_code IS NOT NULL AND t.id IS NULL) THEN
   RAISE EXCEPTION 'OPERATOR_PANEL_CANONICAL_IDENTITY_UNRESOLVED';
 END IF;
END $$;

INSERT INTO public.catalogue_panels(
 id,code,name,category_id,hide_component_interpretation,show_component_method_instrument,
 reporting_type,workflow_supported,clinical_reporting_enabled,lifecycle_status,display_order
)
SELECT COALESCE(t.id,m.fallback_id),m.code,m.name,c.id,TRUE,TRUE,
 CASE WHEN m.workflow_supported THEN 'InHouse' ELSE 'NoReporting' END::public.reporting_type_enum,
 m.workflow_supported,m.clinical_reporting_enabled,
 'Active'::public.catalogue_lifecycle_enum,m.display_order
FROM operator_panel_master_00075 m
JOIN public.test_categories c ON c.code=m.category_code
LEFT JOIN public.tests t ON t.code=m.canonical_test_code
ON CONFLICT(code) DO UPDATE SET
 name=EXCLUDED.name,category_id=EXCLUDED.category_id,
 hide_component_interpretation=TRUE,show_component_method_instrument=TRUE,
 reporting_type=EXCLUDED.reporting_type,workflow_supported=EXCLUDED.workflow_supported,
 clinical_reporting_enabled=EXCLUDED.clinical_reporting_enabled,
 lifecycle_status=EXCLUDED.lifecycle_status,display_order=EXCLUDED.display_order,updated_at=now();

CREATE TEMP TABLE operator_panel_components_00075(
 panel_code TEXT,display_order INT,display_name TEXT,
 component_test_code TEXT,parameter_test_code TEXT,parameter_code TEXT,
 unresolved_reason TEXT,PRIMARY KEY(panel_code,display_order)
) ON COMMIT DROP;
INSERT INTO operator_panel_components_00075 VALUES
('CBC',1,'Hemoglobin','HB',NULL,NULL,NULL),('CBC',2,'Total Leukocyte Count','TLC',NULL,NULL,NULL),('CBC',3,'Differential Leucocyte Count','DLC',NULL,NULL,NULL),('CBC',4,'Platelet Count','PLT',NULL,NULL,NULL),('CBC',5,'Total RBC Count','RBC_COUNT',NULL,NULL,NULL),('CBC',6,'Hematocrit Value, Hct','PCV',NULL,NULL,NULL),('CBC',7,'Mean Corpuscular Volume, MCV',NULL,'CBC','MCV',NULL),('CBC',8,'Mean Cell Haemoglobin, MCH',NULL,'CBC','MCH',NULL),('CBC',9,'Mean Cell Haemoglobin CON, MCHC',NULL,'CBC','MCHC',NULL),('CBC',10,'Mean Platelet Volume, MPV','MPV',NULL,NULL,NULL),('CBC',11,'R.D.W. - SD','R_D_W_SD',NULL,NULL,NULL),('CBC',12,'R.D.W. - CV','R_D_W_CV',NULL,NULL,NULL),('CBC',13,'P-LCR','P_LCR',NULL,NULL,NULL),('CBC',14,'P.D.W.','P_D_W',NULL,NULL,NULL),
('CBC_WITH_ABSOLUTE_COUNTS',1,'Hemoglobin','HB',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',2,'Total Leukocyte Count','TLC',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',3,'Differential Leucocyte Count','DLC',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',4,'Differential Leukocyte Count (Absolute count)','ABS_DLC',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',5,'Neutrophil Lymphocyte Ratio','NLR',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',6,'Platelet Count','PLT',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',7,'Total RBC Count','RBC_COUNT',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',8,'Hematocrit Value, Hct','PCV',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',9,'Mean Corpuscular Volume, MCV',NULL,'CBC','MCV',NULL),('CBC_WITH_ABSOLUTE_COUNTS',10,'Mean Cell Haemoglobin, MCH',NULL,'CBC','MCH',NULL),('CBC_WITH_ABSOLUTE_COUNTS',11,'Mean Cell Haemoglobin CON, MCHC',NULL,'CBC','MCHC',NULL),('CBC_WITH_ABSOLUTE_COUNTS',12,'Mean Platelet Volume, MPV','MPV',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',13,'R.D.W. - CV','R_D_W_CV',NULL,NULL,NULL),('CBC_WITH_ABSOLUTE_COUNTS',14,'R.D.W. - SD','R_D_W_SD',NULL,NULL,NULL),
('CBC_WITH_ESR',1,'Hemoglobin','HB',NULL,NULL,NULL),('CBC_WITH_ESR',2,'Total Leukocyte Count','TLC',NULL,NULL,NULL),('CBC_WITH_ESR',3,'Differential Leucocyte Count','DLC',NULL,NULL,NULL),('CBC_WITH_ESR',4,'Platelet Count','PLT',NULL,NULL,NULL),('CBC_WITH_ESR',5,'Total RBC Count','RBC_COUNT',NULL,NULL,NULL),('CBC_WITH_ESR',6,'Hematocrit Value, Hct','PCV',NULL,NULL,NULL),('CBC_WITH_ESR',7,'Mean Corpuscular Volume, MCV',NULL,'CBC','MCV',NULL),('CBC_WITH_ESR',8,'Mean Cell Haemoglobin, MCH',NULL,'CBC','MCH',NULL),('CBC_WITH_ESR',9,'Mean Cell Haemoglobin CON, MCHC',NULL,'CBC','MCHC',NULL),('CBC_WITH_ESR',10,'Mean Platelet Volume, MPV','MPV',NULL,NULL,NULL),('CBC_WITH_ESR',11,'R.D.W. - SD','R_D_W_SD',NULL,NULL,NULL),('CBC_WITH_ESR',12,'R.D.W. - CV','R_D_W_CV',NULL,NULL,NULL),('CBC_WITH_ESR',13,'P-LCR','P_LCR',NULL,NULL,NULL),('CBC_WITH_ESR',14,'P.D.W.','P_D_W',NULL,NULL,NULL),('CBC_WITH_ESR',15,'Erythrocyte Sedimentation Rate (Wintrobe)','ESR_WINTROBE',NULL,NULL,NULL),
('BT_CT',1,'Bleeding Time',NULL,'BT_CT','BLEEDING_TIME',NULL),('BT_CT',2,'Clotting Time',NULL,'BT_CT','CLOTTING_TIME',NULL),
('COAG_PROFILE',1,'Bleeding Time',NULL,'BT_CT','BLEEDING_TIME',NULL),('COAG_PROFILE',2,'Clotting Time',NULL,'BT_CT','CLOTTING_TIME',NULL),('COAG_PROFILE',3,'Prothrombin time, PT/INR','PT_INR',NULL,NULL,NULL),('COAG_PROFILE',4,'Activated partial thromboplastin time, APTT','APTT',NULL,NULL,NULL),
('BLOOD_SUGAR_FASTING_PP',1,'Fasting Blood Sugar','FBS',NULL,NULL,NULL),('BLOOD_SUGAR_FASTING_PP',2,'Blood Sugar PP','PPBS',NULL,NULL,NULL),
('LFT',1,'Serum Bilirubin (Total)',NULL,'LFT','TBIL',NULL),('LFT',2,'Serum Bilirubin (Direct)',NULL,'LFT','DBIL',NULL),('LFT',3,'Serum Bilirubin (Indirect)',NULL,'LFT','IBIL',NULL),('LFT',4,'SGOT (AST)',NULL,'LFT','SGOT',NULL),('LFT',5,'SGPT (ALT)',NULL,'LFT','SGPT',NULL),('LFT',6,'SGOT/SGPT',NULL,'LFT','SGOT_SGPT_RATIO',NULL),('LFT',7,'Serum Alkaline Phosphatase',NULL,'LFT','ALP',NULL),('LFT',8,'Serum Protein',NULL,'LFT','TP',NULL),('LFT',9,'Serum Albumin',NULL,'LFT','ALB',NULL),('LFT',10,'Globulin',NULL,'LFT','GLOB',NULL),('LFT',11,'A/G Ratio',NULL,'LFT','AG_RATIO',NULL),
('BILIRUBIN_TD',1,'Serum Bilirubin (Total)',NULL,'LFT','TBIL',NULL),('BILIRUBIN_TD',2,'Serum Bilirubin (Direct)',NULL,'LFT','DBIL',NULL),('BILIRUBIN_TD',3,'Serum Bilirubin (Indirect)',NULL,'LFT','IBIL',NULL),
('KFT',1,'BUN','BUN',NULL,NULL,NULL),('KFT',2,'Serum Urea','UREA',NULL,NULL,NULL),('KFT',3,'Serum Creatinine','CREATININE',NULL,NULL,NULL),('KFT',4,'eGFR',NULL,'KFT','EGFR',NULL),('KFT',5,'eGFR Category',NULL,'KFT','EGFR_CATEGORY',NULL),('KFT',6,'Serum Calcium','CALCIUM',NULL,NULL,NULL),('KFT',7,'Serum Potassium','POTASSIUM',NULL,NULL,NULL),('KFT',8,'Serum Sodium','SODIUM',NULL,NULL,NULL),('KFT',9,'Serum Uric Acid','URIC_ACID',NULL,NULL,NULL),('KFT',10,'Urea / Creatinine Ratio',NULL,'KFT','UREA_CREAT_RATIO',NULL),('KFT',11,'BUN / Creatinine Ratio',NULL,'KFT','BUN_CREAT_RATIO',NULL),
('KFT_WITHOUT_EGFR',1,'BUN','BUN',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',2,'Serum Urea','UREA',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',3,'Serum Creatinine','CREATININE',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',4,'Serum Calcium','CALCIUM',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',5,'Serum Potassium','POTASSIUM',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',6,'Serum Sodium','SODIUM',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',7,'Serum Uric Acid','URIC_ACID',NULL,NULL,NULL),('KFT_WITHOUT_EGFR',8,'Urea / Creatinine Ratio',NULL,'KFT','UREA_CREAT_RATIO',NULL),('KFT_WITHOUT_EGFR',9,'BUN / Creatinine Ratio',NULL,'KFT','BUN_CREAT_RATIO',NULL),
('LIPID_PROFILE',1,'Total Cholesterol',NULL,'LIPID_PROFILE','CHOL',NULL),('LIPID_PROFILE',2,'Triglycerides',NULL,'LIPID_PROFILE','TRIG',NULL),('LIPID_PROFILE',3,'HDL Cholesterol',NULL,'LIPID_PROFILE','HDL',NULL),('LIPID_PROFILE',4,'LDL Cholesterol',NULL,'LIPID_PROFILE','LDL',NULL),('LIPID_PROFILE',5,'VLDL Cholesterol',NULL,'LIPID_PROFILE','VLDL',NULL),('LIPID_PROFILE',6,'LDL / HDL',NULL,'LIPID_PROFILE','LDL_HDL_RATIO',NULL),('LIPID_PROFILE',7,'Total Cholesterol / HDL',NULL,'LIPID_PROFILE','TC_HDL_RATIO',NULL),('LIPID_PROFILE',8,'TG / HDL',NULL,'LIPID_PROFILE','TG_HDL_RATIO',NULL),('LIPID_PROFILE',9,'Non-HDL cholesterol',NULL,'LIPID_PROFILE','NON_HDL',NULL),
('ELECTROLYTES_PANEL',1,'Serum Sodium','SODIUM',NULL,NULL,NULL),('ELECTROLYTES_PANEL',2,'Serum Potassium','POTASSIUM',NULL,NULL,NULL),('ELECTROLYTES_PANEL',3,'Serum Chloride','CHLORIDE',NULL,NULL,NULL),('ELECTROLYTES_PANEL',4,'Serum Calcium','CALCIUM',NULL,NULL,NULL),('ELECTROLYTES_PANEL',5,'iCalcium','ICALCIUM',NULL,NULL,NULL),
('ARTHRITIS_PROFILE',1,'Serum Uric Acid','URIC_ACID',NULL,NULL,NULL),('ARTHRITIS_PROFILE',2,'Rheumatoid Factor, RA (Quantitative)','RA_FACTOR',NULL,NULL,NULL),('ARTHRITIS_PROFILE',3,'C-Reactive Protein, CRP (Quantitative)','CRP',NULL,NULL,NULL),('ARTHRITIS_PROFILE',4,'Antistreptolysin O, ASO Titer','ASO',NULL,NULL,NULL),('ARTHRITIS_PROFILE',5,'iCalcium','ICALCIUM',NULL,NULL,NULL),('ARTHRITIS_PROFILE',6,'Total Calcium','CALCIUM',NULL,NULL,NULL),('ARTHRITIS_PROFILE',7,'Serum Phosphorus','PHOSPHORUS',NULL,NULL,NULL),
('PROTEIN_FRACTION',1,'Serum Protein',NULL,'LFT','TP',NULL),('PROTEIN_FRACTION',2,'Serum Albumin',NULL,'LFT','ALB',NULL),('PROTEIN_FRACTION',3,'Globulin',NULL,'LFT','GLOB',NULL),('PROTEIN_FRACTION',4,'A/G Ratio',NULL,'LFT','AG_RATIO',NULL),
('TORCH_PROFILE',1,'Toxo IgG','TOXO_IGG',NULL,NULL,NULL),('TORCH_PROFILE',2,'Toxo IgM','TOXO_IGM',NULL,NULL,NULL),('TORCH_PROFILE',3,'Rubella IgG','RUBELLA_IGG',NULL,NULL,NULL),('TORCH_PROFILE',4,'Rubella IgM','RUBELLA_IGM',NULL,NULL,NULL),('TORCH_PROFILE',5,'CMV IgG','CMV_IGG',NULL,NULL,NULL),('TORCH_PROFILE',6,'CMV IgM','CMV_IGM',NULL,NULL,NULL),('TORCH_PROFILE',7,'HSV-1/2 IgG','HSV_1_2_IGG',NULL,NULL,NULL),('TORCH_PROFILE',8,'HSV-1/2 IgM','HSV_1_2_IGM',NULL,NULL,NULL),('TORCH_PROFILE',9,'HSV-2 IgG','HSV_2_IGG',NULL,NULL,NULL),
('IRON_PROFILE',1,'Iron','IRON',NULL,NULL,NULL),('IRON_PROFILE',2,'UIBC',NULL,'IRON_PROFILE','UIBC',NULL),('IRON_PROFILE',3,'Total Iron Binding Capacity (TIBC)','TIBC',NULL,NULL,NULL),('IRON_PROFILE',4,'Transferrin Saturation',NULL,'IRON_PROFILE','TRANSFERRIN_SAT',NULL),
('AMH_PANEL',1,'ANTI MULLERIAN HORMONE','AMH',NULL,NULL,NULL),('AMH_PANEL',2,'Serum thyroxine, T4','T4',NULL,NULL,NULL),('AMH_PANEL',3,'Thyroid-Stimulating Hormone, TSH','TSH',NULL,NULL,NULL),('AMH_PANEL',4,'Prolactin','PRL',NULL,NULL,NULL),('AMH_PANEL',5,'Luteinising Hormone, LH','LH',NULL,NULL,NULL),('AMH_PANEL',6,'Follicle Stimulating Hormone, FSH','FSH',NULL,NULL,NULL),('AMH_PANEL',7,'Estradiol','ESTRADIOL',NULL,NULL,NULL),
('VIRAL_MARKER',1,'HIV (Card Test)','HIV_CARD_TEST',NULL,NULL,NULL),('VIRAL_MARKER',2,'VDRL','VDRL',NULL,NULL,NULL),('VIRAL_MARKER',3,'Hepatitis C Virus, HCV','HCV',NULL,NULL,NULL),('VIRAL_MARKER',4,'HBsAg','HBSAG',NULL,NULL,NULL),
('THYROID_PROFILE',1,'Serum Triiodothyronine, T3','T3',NULL,NULL,NULL),('THYROID_PROFILE',2,'Serum thyroxine, T4','T4',NULL,NULL,NULL),('THYROID_PROFILE',3,'Thyroid-Stimulating Hormone, TSH','TSH',NULL,NULL,NULL),
('THYROID_ECLIA',1,'Free Triiodothyronine l, FT3','FT3',NULL,NULL,NULL),('THYROID_ECLIA',2,'Free Thyroxine, FT4','FT4',NULL,NULL,NULL),('THYROID_ECLIA',3,'Thyroid-Stimulating Hormone, TSH','TSH',NULL,NULL,NULL),
('PCOD_PANEL',1,'Progesterone','PROGESTERONE',NULL,NULL,NULL),('PCOD_PANEL',2,'Prolactin','PRL',NULL,NULL,NULL),('PCOD_PANEL',3,'Luteinising Hormone, LH','LH',NULL,NULL,NULL),('PCOD_PANEL',4,'Follicle Stimulating Hormone, FSH','FSH',NULL,NULL,NULL),('PCOD_PANEL',5,'Random Blood Sugar','RBS',NULL,NULL,NULL),('PCOD_PANEL',6,'Estradiol','ESTRADIOL',NULL,NULL,NULL),
('UPCR',1,'Urine for creatinine','URINE_FOR_CREATININE',NULL,NULL,NULL),('UPCR',2,'Urine for Protein','URINE_FOR_PROTEIN',NULL,NULL,NULL),('UPCR',3,'Urine Protein Creatinine Ratio','UPCR',NULL,NULL,NULL),
('EGFR',1,'Serum Creatinine','CREATININE',NULL,NULL,NULL),('EGFR',2,'eGFR',NULL,'KFT','EGFR',NULL),('EGFR',3,'eGFR Category',NULL,'KFT','EGFR_CATEGORY',NULL),
('CBC_WITH_MORPHOLOGY',1,'Differential Leucocyte Count','DLC',NULL,NULL,NULL),('CBC_WITH_MORPHOLOGY',2,'Differential Leukocyte Count (Absolute count)','ABS_DLC',NULL,NULL,NULL),('CBC_WITH_MORPHOLOGY',3,'WBC Count','TLC',NULL,NULL,NULL),('CBC_WITH_MORPHOLOGY',4,'RBC Indices','RBC_INDICES',NULL,NULL,NULL),('CBC_WITH_MORPHOLOGY',5,'Platelet Indices','PLATELET_INDICES',NULL,NULL,NULL),('CBC_WITH_MORPHOLOGY',6,'Morphology','PBS',NULL,NULL,NULL),
('CCP',1,'Anti-ccp','CCP',NULL,NULL,NULL),('PUS_CULTURE_AND_SENSITIVITY',1,'Pus Culture and Sensitivity','PUS_CULTURE_AND_SENSITIVITY',NULL,NULL,NULL),('ADA',1,'Serum ADA','ADA',NULL,NULL,NULL),('SERUM_PROTEIN_ELECTROPHORESIS',1,'Serum Protein Electrophoresis','SERUM_PROTEIN_ELECTROPHORESIS',NULL,NULL,NULL),('GENETIC_TEST',1,'BRCA1 BRCA2','GENETIC_TEST',NULL,NULL,NULL),('PRL',1,'Prolactin','PRL',NULL,NULL,NULL),('CEA_CARCINOEMBRYONIC_ANTIGEN',1,'CEA','CEA_CARCINOEMBRYONIC_ANTIGEN',NULL,NULL,NULL);

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM operator_panel_components_00075 c LEFT JOIN public.catalogue_panels p ON p.code=c.panel_code WHERE p.id IS NULL) THEN RAISE EXCEPTION 'PANEL_COMPONENT_PANEL_UNRESOLVED'; END IF;
 IF EXISTS(SELECT 1 FROM operator_panel_components_00075 c LEFT JOIN public.tests t ON t.code=c.component_test_code WHERE c.component_test_code IS NOT NULL AND t.id IS NULL) THEN RAISE EXCEPTION 'PANEL_COMPONENT_TEST_UNRESOLVED'; END IF;
 IF EXISTS(SELECT 1 FROM operator_panel_components_00075 c LEFT JOIN public.tests t ON t.code=c.parameter_test_code LEFT JOIN public.parameters p ON p.test_id=t.id AND p.code=c.parameter_code WHERE c.parameter_code IS NOT NULL AND p.id IS NULL) THEN RAISE EXCEPTION 'PANEL_COMPONENT_PARAMETER_UNRESOLVED'; END IF;
END $$;

DELETE FROM public.catalogue_panel_components WHERE panel_id IN (SELECT p.id FROM public.catalogue_panels p JOIN operator_panel_master_00075 m ON m.code=p.code);
INSERT INTO public.catalogue_panel_components(panel_id,component_test_id,component_parameter_id,display_name,display_order,unresolved_reason)
SELECT pnl.id,t.id,prm.id,c.display_name,c.display_order,c.unresolved_reason
FROM operator_panel_components_00075 c
JOIN public.catalogue_panels pnl ON pnl.code=c.panel_code
LEFT JOIN public.tests t ON t.code=c.component_test_code
LEFT JOIN public.tests pt ON pt.code=c.parameter_test_code
LEFT JOIN public.parameters prm ON prm.test_id=pt.id AND prm.code=c.parameter_code;

UPDATE public.catalogue_panels p SET clinical_reporting_enabled=FALSE,lifecycle_status='Draft',updated_at=now()
WHERE EXISTS(SELECT 1 FROM public.catalogue_panel_components c WHERE c.panel_id=p.id AND c.unresolved_reason IS NOT NULL);

CREATE TEMP TABLE operator_panel_rates_00075(panel_code TEXT,ratelist_name TEXT,operator_rate_npr NUMERIC,PRIMARY KEY(panel_code,ratelist_name)) ON COMMIT DROP;
INSERT INTO operator_panel_rates_00075(panel_code,ratelist_name) VALUES
('CBC','CBC with GBP'),('CBC','Complete Blood Count (CBC)'),
('CBC_WITH_ABSOLUTE_COUNTS','Antenatal Package'),('CBC_WITH_ABSOLUTE_COUNTS','Cardiac package'),('CBC_WITH_ABSOLUTE_COUNTS','CBC (with absolute counts)'),('CBC_WITH_ABSOLUTE_COUNTS','Dialysis package'),('CBC_WITH_ABSOLUTE_COUNTS','Fitness Package'),('CBC_WITH_ABSOLUTE_COUNTS','Full body checkup (Female)'),('CBC_WITH_ABSOLUTE_COUNTS','Full body checkup (Male)'),('CBC_WITH_ABSOLUTE_COUNTS','Preoperative'),('CBC_WITH_ABSOLUTE_COUNTS','Thyroid package'),
('CBC_WITH_ESR','Anemia package'),('CBC_WITH_ESR','Arthritis Package'),('CBC_WITH_ESR','CBC with ESR'),('CBC_WITH_ESR','Fever package'),('BT_CT','BT & CT'),('COAG_PROFILE','Coagulation Profile'),
('BLOOD_SUGAR_FASTING_PP','Blood Sugar Fasting & PP'),('BLOOD_SUGAR_FASTING_PP','Diabetic package'),
('LFT','Fitness Package'),('LFT','Full body checkup (Female)'),('LFT','Full body checkup (Male)'),('LFT','Liver Function Test (LFT)'),
('BILIRUBIN_TD','Bilirubin Total, Direct & Indirect'),('KFT','Fitness Package'),('KFT','Full body checkup (Female)'),('KFT','Full body checkup (Male)'),('KFT','Kidney Function Test (KFT)'),('KFT_WITHOUT_EGFR','KFT without eGFR'),
('LIPID_PROFILE','Cardiac package'),('LIPID_PROFILE','Diabetic package'),('LIPID_PROFILE','Fitness Package'),('LIPID_PROFILE','Full body checkup (Female)'),('LIPID_PROFILE','Full body checkup (Male)'),('LIPID_PROFILE','Lipid Profile'),
('ELECTROLYTES_PANEL','Electrolytes Panel'),('ARTHRITIS_PROFILE','Arthritis Profile'),('PROTEIN_FRACTION','Protein Fraction'),('TORCH_PROFILE','Bad Obstetric History (BOH) Package'),('TORCH_PROFILE','Torch Profile'),('IRON_PROFILE','Fitness Package'),('IRON_PROFILE','Iron Studies'),('AMH_PANEL','AMH Panel'),('VIRAL_MARKER','Antenatal Package'),('VIRAL_MARKER','Viral Marker'),
('THYROID_PROFILE','Fitness Package'),('THYROID_PROFILE','Full body checkup (Female)'),('THYROID_PROFILE','Full body checkup (Male)'),('THYROID_PROFILE','Thyroid Function Test (TFT)'),('THYROID_PROFILE','Thyroid package'),('THYROID_ECLIA','Free Thyroid Function Test (FTFT)'),('PCOD_PANEL','Pcod'),('UPCR','Urine Protein/Creatinine Ratio (UPCR)'),('EGFR','Estimated Glomerular Filtration Rate (eGFR)'),('CBC_WITH_MORPHOLOGY','CBC with Morphology'),('CCP','Anti-ccp'),('PUS_CULTURE_AND_SENSITIVITY','Pus Culture and Sensitivity'),('ADA','Serum ADA'),('SERUM_PROTEIN_ELECTROPHORESIS','Serum Protein Electrophoresis'),('GENETIC_TEST','BRCA1 BRCA2'),('PRL','Prolactin'),('CEA_CARCINOEMBRYONIC_ANTIGEN','CEA');

INSERT INTO public.catalogue_panel_ratelist_links(panel_id,ratelist_name,operator_rate_npr)
SELECT p.id,r.ratelist_name,r.operator_rate_npr FROM operator_panel_rates_00075 r JOIN public.catalogue_panels p ON p.code=r.panel_code
ON CONFLICT(panel_id,ratelist_name) DO UPDATE SET operator_rate_npr=COALESCE(EXCLUDED.operator_rate_npr,public.catalogue_panel_ratelist_links.operator_rate_npr);

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_panels p JOIN operator_panel_master_00075 m ON m.code=p.code)<>31 THEN RAISE EXCEPTION 'OPERATOR_PANEL_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT panel_id,component_test_id FROM public.catalogue_panel_components WHERE component_test_id IS NOT NULL GROUP BY panel_id,component_test_id HAVING count(*)>1) OR EXISTS(SELECT panel_id,component_parameter_id FROM public.catalogue_panel_components WHERE component_parameter_id IS NOT NULL GROUP BY panel_id,component_parameter_id HAVING count(*)>1) THEN RAISE EXCEPTION 'OPERATOR_PANEL_COMPONENT_DUPLICATE'; END IF;
END $$;

-- Reconcile the complete ordered TM256 Test Database into its clean
-- operational projection. The supplied operator source is the authority for
-- order, label, type, short name, and category; canonical IDs remain stable.
INSERT INTO public.catalogue_test_database_entries(
 source_order,test_name,test_type,short_name,operator_category,category_id,configuration_test_id,canonical_parameter_id
)
SELECT s.source_number,s.source_name,s.source_type,NULLIF(btrim(s.source_alias),''),s.source_department,cat.id,
 COALESCE(owner_test.id,s.canonical_test_id),COALESCE(owner_parameter.id,s.canonical_parameter_id)
FROM public.catalogue_master_source_rows s
JOIN public.test_categories cat ON cat.code=CASE s.source_department
 WHEN 'Haematology' THEN 'HEMATOLOGY' WHEN 'Biochemistry' THEN 'BIOCHEMISTRY'
 WHEN 'Serology & Immunology' THEN 'SEROLOGY' WHEN 'Clinical Pathology' THEN 'CLINICAL_PATHOLOGY'
 WHEN 'Cytology' THEN 'CYTOLOGY' WHEN 'Microbiology' THEN 'MICROBIOLOGY'
 WHEN 'Endocrinology' THEN 'ENDOCRINOLOGY' WHEN 'Others' THEN 'GENERAL'
 WHEN 'Histopathology' THEN 'HISTOPATHOLOGY' WHEN 'Miscellaneous' THEN 'MISCELLANEOUS' END
LEFT JOIN LATERAL(
 SELECT x.owner_code,x.parameter_code FROM (VALUES
  (10,'BT_CT','BLEEDING_TIME'),(11,'BT_CT','CLOTTING_TIME'),
  (18,'CBC','MCV'),(19,'CBC','MCH'),(20,'CBC','MCHC'),
  (49,'LFT','TBIL'),(50,'LFT','DBIL'),(51,'LFT','IBIL'),
  (55,'LFT','TP'),(56,'LFT','ALB'),(62,'LIPID_PROFILE','VLDL'),
  (63,'LIPID_PROFILE','LDL_HDL_RATIO'),(64,'LIPID_PROFILE','TC_HDL_RATIO'),
  (65,'LIPID_PROFILE','TG_HDL_RATIO'),(69,'KFT','BUN_CREAT_RATIO'),
  (70,'KFT','UREA_CREAT_RATIO'),(80,'LFT','AG_RATIO'),
  (127,'LIPID_PROFILE','NON_HDL'),(129,'KFT','EGFR'),
  (130,'KFT','EGFR_CATEGORY'),(137,'LFT','SGOT_SGPT_RATIO')
 ) x(source_number,owner_code,parameter_code) WHERE x.source_number=s.source_number
) override ON TRUE
LEFT JOIN public.tests owner_test ON owner_test.code=COALESCE(override.owner_code,CASE WHEN s.source_number=165 THEN 'ASO' END)
LEFT JOIN public.parameters owner_parameter ON owner_parameter.test_id=owner_test.id AND owner_parameter.code=override.parameter_code
WHERE s.source_id='25600000-0000-0000-0000-000000000001'
ON CONFLICT(source_order) DO UPDATE SET
 test_name=EXCLUDED.test_name,test_type=EXCLUDED.test_type,short_name=EXCLUDED.short_name,operator_category=EXCLUDED.operator_category,
 category_id=EXCLUDED.category_id,configuration_test_id=EXCLUDED.configuration_test_id,
 canonical_parameter_id=EXCLUDED.canonical_parameter_id,is_operator_approved=TRUE;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_test_database_entries)<>256 OR
    (SELECT min(source_order) FROM public.catalogue_test_database_entries)<>1 OR
    (SELECT max(source_order) FROM public.catalogue_test_database_entries)<>256 THEN
   RAISE EXCEPTION 'TEST_DATABASE_256_ORDER_ASSERTION_FAILED';
 END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_test_database_entries WHERE configuration_test_id IS NULL) THEN
   RAISE EXCEPTION 'TEST_DATABASE_CANONICAL_IDENTITY_UNRESOLVED';
 END IF;
 IF (SELECT count(DISTINCT source_order) FROM public.catalogue_test_database_entries)<>256 THEN
   RAISE EXCEPTION 'TEST_DATABASE_ORDER_DUPLICATE';
 END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_test_database_entries WHERE test_type NOT IN ('Single parameter','Multi parameter','Multi parameter nested','Document')) THEN
   RAISE EXCEPTION 'TEST_DATABASE_TYPE_MAPPING_INVALID';
 END IF;
END $$;

-- Exact operator-supplied 111-entry View & Copy library. Name reconciliation
-- happens only against the already resolved 256-row Test Database.
CREATE TEMP TABLE operator_test_templates_00075(source_order INT PRIMARY KEY,supplied_name TEXT NOT NULL) ON COMMIT DROP;
INSERT INTO operator_test_templates_00075 VALUES
(1,'Hemoglobin'),(2,'Total Leukocyte Count'),(3,'Differential Leucocyte Count'),
(4,'Erythrocyte sedimentation rate (Westergren)'),(5,'Erythrocyte Sedimentation Rate (Wintrobe)'),
(6,'Platelet Count'),(7,'Absolute Eosinophil Count'),(8,'Blood Group & Rh.'),
(9,'Malaria Parasite (Card Test)'),(10,'Filarial Parasite (Card Test)'),(11,'Reticulocyte Count'),
(12,'Glucose-6-phosphate dehydrogenase'),(13,'Prothrombin time, PT/INR'),
(14,'Activated partial thromboplastin time, APTT'),(15,'Neutrophil Lymphocyte Ratio'),
(16,'Lupus Anticoagulant (DRVVT)'),(17,'Serum Phosphorus'),(18,'Serum Creatinine'),
(19,'Serum Urea'),(20,'Fasting Blood Sugar'),(21,'Blood Sugar PP'),
(22,'Serum Bilirubin (Total)'),(23,'Serum Bilirubin (Direct)'),(24,'Serum Bilirubin (Indirect)'),
(25,'Serum Uric Acid'),(26,'SGPT (ALT)'),(27,'SGOT (AST)'),(28,'Serum Protein'),
(29,'Serum Albumin'),(30,'Serum Alkaline Phosphatase'),(31,'Total Cholesterol'),
(32,'Triglycerides'),(33,'Serum Sodium'),(34,'BUN'),(35,'Serum Potassium'),
(36,'iCalcium'),(37,'Serum Calcium'),(38,'Total Calcium'),
(39,'Glucose Tolerance Test, GTT'),(40,'Random Blood Sugar'),(41,'Serum Chloride'),
(42,'Serum Amylase'),(43,'HbA1c (Glycosylated Hemoglobin)'),(44,'Lipase'),
(45,'Ferritin'),(46,'Microalbumin Creatinine Ratio, Urine Random'),(47,'CPK-MB'),
(48,'25 Hydroxy (OH) Vitamin D'),(49,'Vitamin B12'),(50,'Gamma Glutamyl Transferase, GGT'),
(51,'Serum IgE'),(52,'CMV IgG'),(53,'CMV IgM'),(54,'Anti TPO'),
(55,'Thyroglobulin (TG)'),(56,'Thyroglobulin Antibody (TgAb)'),(57,'DHEA'),
(58,'Troponin I'),(59,'CK-MB'),(60,'D-Dimer'),(61,'Calcitonin'),
(62,'Indirect Coomb''s Test'),(63,'Anti cyclic-citrullinated-peptide'),(64,'Iron'),
(65,'Total Iron Binding Capacity (TIBC)'),(66,'C3 Complement'),
(67,'High-Sensitivity C-Reactive Protein'),(68,'ANTI MULLERIAN HORMONE'),
(69,'Glucose Tolerance Test, GTT (Pregnancy)'),(70,'Widal Test (Slide Method)'),
(71,'Malaria Antigen'),(72,'HIV (Card Test)'),(73,'Hepatitis C Virus, HCV'),
(74,'VDRL'),(75,'HBsAg'),(76,'Occult Blood, Stool'),(77,'Typhidot Antibodies'),
(78,'Rubella'),(79,'Chikungunya'),(80,'Antistreptolysin O, ASO Titer'),
(81,'Rheumatoid Factor, RA (Quantitative)'),(82,'C-Reactive Protein, CRP (Quantitative)'),
(83,'C-Reactive Protein, CRP (Qualitative)'),(84,'Dengue NS1 Antigen'),
(85,'Beta Human Chorionic Gonodotropin (HCG)'),(86,'Total PSA'),(87,'HBeAg'),
(88,'Anti Nuclear Antibody (ANA) by ELISA'),(89,'Insulin Random'),(90,'Testosterone Free'),
(91,'Testosterone Total'),(92,'Progesterone'),(93,'Myoglobin'),
(94,'Beta 2 Glycoprotein 1, IgG'),(95,'Beta 2 Glycoprotein 1, IgM'),
(96,'Anti Phospholipid IgG'),(97,'Anti Phospholipid IgM'),(98,'Anti Cardiolipin IgG'),
(99,'Anti Cardiolipin IgM'),(100,'Urine for Microalbumin'),(101,'Urine Pregnancy Test'),
(102,'Semen Examination'),(103,'Urine Routine Examination'),(104,'Urine Cortisol'),
(105,'Acid - Fast Bacilli'),(106,'Serum Triiodothyronine, T3'),
(107,'Thyroid-Stimulating Hormone, TSH'),(108,'Alfa Fetoprotein, AFP'),
(109,'Prolactin'),(110,'Luteinising Hormone, LH'),(111,'Folic Acid');

INSERT INTO public.catalogue_test_templates(source_order,supplied_name,test_database_source_order,configuration_test_id,canonical_parameter_id)
SELECT s.source_order,s.supplied_name,d.source_order,d.configuration_test_id,d.canonical_parameter_id
FROM operator_test_templates_00075 s
JOIN LATERAL (
 SELECT d.* FROM public.catalogue_test_database_entries d
 WHERE regexp_replace(lower(d.test_name),'[^a-z0-9]+','','g')=regexp_replace(lower(s.supplied_name),'[^a-z0-9]+','','g')
    OR (s.source_order=80 AND d.test_name='Anti Streptolysin O Titre')
    OR (s.source_order=85 AND d.test_name='Beta Human Chorionic Gonadotropin (HCG)')
    OR (s.source_order=108 AND d.test_name='Alpha Fetoprotein, AFP')
 ORDER BY CASE WHEN d.test_name=s.supplied_name THEN 0 ELSE 1 END,d.source_order
 LIMIT 1
) d ON TRUE;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_test_templates)<>111 THEN RAISE EXCEPTION 'TEST_TEMPLATE_COUNT_OR_RECONCILIATION_INVALID'; END IF;
 IF (SELECT count(DISTINCT source_order) FROM public.catalogue_test_templates)<>111 THEN RAISE EXCEPTION 'TEST_TEMPLATE_ORDER_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_test_templates t JOIN public.catalogue_test_database_entries d ON d.source_order=t.test_database_source_order WHERE t.configuration_test_id<>d.configuration_test_id OR t.canonical_parameter_id IS DISTINCT FROM d.canonical_parameter_id) THEN RAISE EXCEPTION 'TEST_TEMPLATE_CANONICAL_LINK_INVALID'; END IF;
END $$;

-- FTFT is a canonical multi-parameter profile. Reuse the approved standalone
-- parameter structure while keeping its supplied profile-specific intervals
-- attached to the profile; do not collapse the two clinical services.
INSERT INTO public.parameters(
 test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,
 lifecycle_status,clinical_configuration_status,unit_validation_required,
 range_validation_required,method_validation_required
)
SELECT profile.id,m.profile_code,source_parameter.name,source_parameter.value_type,
 source_parameter.unit,m.display_order,TRUE,TRUE,'Active','Configured',
 (source_parameter.value_type IN('Numeric','Calculated')),TRUE,FALSE
FROM (VALUES(1,'FT3','FT3','FT3_VAL'),(2,'FT4','FT4','FT4_VAL'),(3,'TSH','TSH','TSH_VAL'))
 m(display_order,profile_code,source_test_code,source_parameter_code)
JOIN public.tests profile ON profile.code='THYROID_ECLIA'
JOIN public.tests source_test ON source_test.code=m.source_test_code
JOIN public.parameters source_parameter ON source_parameter.test_id=source_test.id AND source_parameter.code=m.source_parameter_code
ON CONFLICT(test_id,code) DO UPDATE SET
 name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,
 display_order=EXCLUDED.display_order,is_mandatory=TRUE,is_active=TRUE,
 lifecycle_status='Active',clinical_configuration_status='Configured',
 unit_validation_required=EXCLUDED.unit_validation_required,range_validation_required=TRUE,
 method_validation_required=FALSE,row_version=public.parameters.row_version+1,updated_at=now();

CREATE TEMP TABLE approved_ranges_00075(test_code TEXT,parameter_code TEXT,sex TEXT,age_min_days INT,age_max_days INT,normal_min NUMERIC,normal_max NUMERIC,critical_low NUMERIC,critical_high NUMERIC,reference_text TEXT,qualitative_normal TEXT,method TEXT,source_provenance TEXT,effective_from DATE,effective_to DATE) ON COMMIT DROP;
INSERT INTO approved_ranges_00075 VALUES
('THYROID_ECLIA','FT3','All',0,43800,1.3,2.7,NULL,NULL,NULL,NULL,NULL,NULL,'2026-08-19',NULL),
('THYROID_ECLIA','FT4','All',0,43800,78,154,NULL,NULL,NULL,NULL,NULL,NULL,'2026-08-19',NULL),
('THYROID_ECLIA','TSH','All',0,43800,0.4,4,NULL,NULL,NULL,NULL,NULL,NULL,'2026-08-19',NULL),
('CBC','HB','Male',6570,43800,13.5,17.5,NULL,NULL,'13.0 - 17.0 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','HB','Female',6570,43800,12,15.5,NULL,NULL,'12.0 - 15.0 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','TLC','All',6570,43800,4500,11000,NULL,NULL,'4000 - 11000 /cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','NEUT','All',6570,43800,40,60,NULL,NULL,'40 - 75 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','LYMPH','All',6570,43800,20,40,NULL,NULL,'20 - 45 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','EOSIN','All',6570,43800,1,4,NULL,NULL,'1 - 6 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','MONO','All',6570,43800,2,8,NULL,NULL,'2 - 10 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('ANTI_HCV','HCV_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Non-Reactive','Non-Reactive',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('HIV','HIV_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Non-Reactive','Non-Reactive',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('VDRL','VDRL_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Non-Reactive','Non-Reactive',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DENGUE_NS1','DENGUE_NS1_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','BASO','All',6570,43800,0.5,1,NULL,NULL,'0 - 1 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','RBC','Male',6570,43800,4.5,5.9,NULL,NULL,'4.5 - 5.9 million/cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','RBC','Female',6570,43800,4.1,5.1,NULL,NULL,'4.1 - 5.1 million/cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','PCV','Male',6570,43800,41,53,NULL,NULL,'40 - 52 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','PCV','Female',6570,43800,36,46,NULL,NULL,'36 - 48 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','MCV','All',6570,43800,80,100,NULL,NULL,'80 - 100 fL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','MCH','All',6570,43800,27,33,NULL,NULL,'27 - 33 pg',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','MCHC','All',6570,43800,32,36,NULL,NULL,'32 - 36 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','RDW','All',6570,43800,11.5,14.5,NULL,NULL,'11.5 - 14.5 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','PLT','All',6570,43800,150000,450000,NULL,NULL,'150000 - 450000 /cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('HB','HB_VAL','Male',6570,43800,13,17,NULL,NULL,'13.0 - 17.0 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('HB','HB_VAL','Female',6570,43800,12,15,NULL,NULL,'12.0 - 15.0 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('TLC','TLC_VAL','All',6570,43800,4000,11000,NULL,NULL,'4000 - 11000 /cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DLC','NEUT_VAL','All',6570,43800,40,75,NULL,NULL,'40 - 75 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DLC','LYMPH_VAL','All',6570,43800,20,45,NULL,NULL,'20 - 45 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DLC','EOSIN_VAL','All',6570,43800,1,6,NULL,NULL,'1 - 6 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DLC','MONO_VAL','All',6570,43800,2,10,NULL,NULL,'2 - 10 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DLC','BASO_VAL','All',6570,43800,0,1,NULL,NULL,'0 - 1 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('PLT','PLT_VAL','All',6570,43800,150000,450000,NULL,NULL,'150000 - 450000 /cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('ESR','ESR_VAL','Male',6570,43800,0,15,NULL,NULL,'0 - 15 mm/hr',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('ESR','ESR_VAL','Female',6570,43800,0,20,NULL,NULL,'0 - 20 mm/hr',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('PCV','PCV_VAL','Male',6570,43800,40,52,NULL,NULL,'40 - 52 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('PCV','PCV_VAL','Female',6570,43800,36,48,NULL,NULL,'36 - 48 %',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('RBC_COUNT','RBC_VAL','Male',6570,43800,4.5,5.9,NULL,NULL,'4.5 - 5.9 million/cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('RBC_COUNT','RBC_VAL','Female',6570,43800,4.1,5.1,NULL,NULL,'4.1 - 5.1 million/cumm',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('FBS','GLU_FASTING','All',6570,43800,70,99,NULL,NULL,'70 - 99 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('PPBS','GLU_PP','All',6570,43800,NULL,140,NULL,NULL,'< 140 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('RBS','GLU_RANDOM','All',6570,43800,70,140,NULL,NULL,'70 - 140 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('HBA1C','HBA1C_VAL','All',6570,43800,4,5.6,NULL,NULL,'4.0 - 5.6 % (Non-diabetic)',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('UREA','UREA_VAL','All',6570,43800,15,45,NULL,NULL,'15 - 45 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CREATININE','CREAT_VAL','Male',6570,43800,0.7,1.3,NULL,NULL,'0.7 - 1.3 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CREATININE','CREAT_VAL','Female',6570,43800,0.6,1.1,NULL,NULL,'0.6 - 1.1 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URIC_ACID','URIC_VAL','Male',6570,43800,3.4,7,NULL,NULL,'3.4 - 7.0 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URIC_ACID','URIC_VAL','Female',6570,43800,2.4,6,NULL,NULL,'2.4 - 6.0 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('SODIUM','NA_VAL','All',6570,43800,135,145,NULL,NULL,'135 - 145 mmol/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('POTASSIUM','K_VAL','All',6570,43800,3.5,5.1,NULL,NULL,'3.5 - 5.1 mmol/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CHLORIDE','CL_VAL','All',6570,43800,98,107,NULL,NULL,'98 - 107 mmol/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CALCIUM','CA_VAL','All',6570,43800,8.5,10.5,NULL,NULL,'8.5 - 10.5 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('PHOSPHORUS','PHOS_VAL','All',6570,43800,2.5,4.5,NULL,NULL,'2.5 - 4.5 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('MAGNESIUM','MG_VAL','All',6570,43800,1.7,2.4,NULL,NULL,'1.7 - 2.4 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','TBIL','All',6570,43800,0.3,1.2,NULL,NULL,'0.3 - 1.2 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','DBIL','All',6570,43800,0,0.3,NULL,NULL,'0.0 - 0.3 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','IBIL','All',6570,43800,0.2,0.9,NULL,NULL,'0.2 - 0.9 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','SGOT','All',6570,43800,10,40,NULL,NULL,'10 - 40 U/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','SGPT','All',6570,43800,7,56,NULL,NULL,'7 - 56 U/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','ALP','All',6570,43800,44,147,NULL,NULL,'44 - 147 U/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','TP','All',6570,43800,6.4,8.3,NULL,NULL,'6.4 - 8.3 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','ALB','All',6570,43800,3.5,5,NULL,NULL,'3.5 - 5.0 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','GLOB','All',6570,43800,2,3.5,NULL,NULL,'2.0 - 3.5 g/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LFT','AG_RATIO','All',6570,43800,1,2.5,NULL,NULL,'1.0 - 2.5',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','UREA','All',6570,43800,15,45,NULL,NULL,'15 - 45 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','CREAT','Male',6570,43800,0.7,1.3,NULL,NULL,'0.7 - 1.3 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','CREAT','Female',6570,43800,0.6,1.1,NULL,NULL,'0.6 - 1.1 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','NA','All',6570,43800,135,145,NULL,NULL,'135 - 145 mmol/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','K','All',6570,43800,3.5,5.1,NULL,NULL,'3.5 - 5.1 mmol/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','URIC','Male',6570,43800,3.4,7,NULL,NULL,'3.4 - 7.0 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('KFT','URIC','Female',6570,43800,2.4,6,NULL,NULL,'2.4 - 6.0 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','CHOL','All',6570,43800,NULL,200,NULL,NULL,'Desirable: < 200 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','TRIG','All',6570,43800,NULL,150,NULL,NULL,'Normal: < 150 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','HDL','Male',6570,43800,40,NULL,NULL,NULL,'> 40 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','HDL','Female',6570,43800,50,NULL,NULL,NULL,'> 50 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','LDL','All',6570,43800,NULL,100,NULL,NULL,'Optimal: < 100 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('LIPID_PROFILE','VLDL','All',6570,43800,5,40,NULL,NULL,'5 - 40 mg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('THYROID_PROFILE','T3','All',6570,43800,80,200,NULL,NULL,'80 - 200 ng/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('THYROID_PROFILE','T4','All',6570,43800,5,12,NULL,NULL,'5.0 - 12.0 µg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('THYROID_PROFILE','TSH','All',6570,43800,0.4,4,NULL,NULL,'0.4 - 4.0 µIU/mL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('T3','T3_VAL','All',6570,43800,80,200,NULL,NULL,'80 - 200 ng/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('T4','T4_VAL','All',6570,43800,5,12,NULL,NULL,'5.0 - 12.0 µg/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('TSH','TSH_VAL','All',6570,43800,0.4,4,NULL,NULL,'0.4 - 4.0 µIU/mL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('FT3','FT3_VAL','All',6570,43800,2.3,4.2,NULL,NULL,'2.3 - 4.2 pg/mL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('FT4','FT4_VAL','All',6570,43800,0.8,1.8,NULL,NULL,'0.8 - 1.8 ng/dL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CRP','CRP_VAL','All',6570,43800,NULL,6,NULL,NULL,'< 6 mg/L',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('RA_FACTOR','RA_VAL','All',6570,43800,NULL,14,NULL,NULL,'< 14 IU/mL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('ASO','ASO_VAL','All',6570,43800,NULL,200,NULL,NULL,'< 200 IU/mL',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('HBSAG','HBSAG_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Non-Reactive','Non-Reactive',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DENGUE_IGM','DENGUE_IGM_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('DENGUE_IGG','DENGUE_IGG_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','PROTEIN','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','GLUCOSE','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','KETONE','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','BILE_SALT','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','BILE_PIGMENT','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','PUS_CELLS','All',6570,43800,0,5,NULL,NULL,'0 - 5 /HPF','0 - 5',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','RBC_URINE','All',6570,43800,0,2,NULL,NULL,'0 - 2 /HPF','0 - 2',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','EPITHELIAL','All',6570,43800,0,5,NULL,NULL,'0 - 5 /HPF','0 - 5',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','CASTS','All',6570,43800,NULL,NULL,NULL,NULL,'Nil','Nil',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','CRYSTALS','All',6570,43800,NULL,NULL,NULL,NULL,'Nil','Nil',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','SP_GRAVITY','All',6570,43800,1.005,1.03,NULL,NULL,'1.005 - 1.030',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('URINE_RE','PH','All',6570,43800,4.5,8,NULL,NULL,'4.5 - 8.0',NULL,NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('STOOL_RE','STOOL_PUS','All',6570,43800,0,2,NULL,NULL,'0 - 2 /HPF','0 - 2',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('STOOL_RE','STOOL_RBC','All',6570,43800,NULL,NULL,NULL,NULL,'Nil','Nil',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('STOOL_RE','STOOL_OVA','All',6570,43800,NULL,NULL,NULL,NULL,'Not Seen','Not Seen',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('STOOL_RE','STOOL_CYST','All',6570,43800,NULL,NULL,NULL,NULL,'Not Seen','Not Seen',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('STOOL_OB','FOBT_RES','All',6570,43800,NULL,NULL,NULL,NULL,'Negative','Negative',NULL,'Default reference interval - verify with analyzer/reagent','2026-08-19',NULL),
('CBC','MPV','All',6570,43800,7.5,11.5,NULL,NULL,NULL,NULL,NULL,'Explicit final CBC operator specification',DATE '2026-08-29',NULL),
('CBC','PDW','All',6570,43800,9,17,NULL,NULL,NULL,NULL,NULL,'Explicit final CBC operator specification',DATE '2026-08-29',NULL);

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM approved_ranges_00075 a JOIN public.tests t ON t.code=a.test_code LEFT JOIN public.parameters p ON p.test_id=t.id AND p.code=a.parameter_code WHERE p.id IS NULL) THEN
   RAISE EXCEPTION 'APPROVED_RANGE_PARAMETER_IDENTITY_MISSING';
 END IF;
END $$;

-- Supersede rather than overwrite active range evidence. Placeholder text is provenance only.
UPDATE public.reference_ranges rr SET lifecycle_status='Archived',is_active=FALSE,archived_at=now(),row_version=rr.row_version+1,updated_at=now()
FROM public.parameters p,public.tests t
WHERE rr.parameter_id=p.id AND p.test_id=t.id AND rr.lifecycle_status='Active'
AND EXISTS(SELECT 1 FROM approved_ranges_00075 a WHERE a.test_code=t.code AND a.parameter_code=p.code);

INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source,effective_from,effective_to)
SELECT p.id,a.sex,a.age_min_days,a.age_max_days,a.normal_min,a.normal_max,a.critical_low,a.critical_high,
 NULLIF(a.qualitative_normal,''),NULLIF(a.reference_text,''),NULLIF(a.method,''),p.unit,TRUE,TRUE,'Active','ClinicallyValidated',
 concat_ws('; ','Operator-approved 2026-08-29 baseline',NULLIF(a.source_provenance,'')),a.effective_from,a.effective_to
FROM approved_ranges_00075 a JOIN public.tests t ON t.code=a.test_code JOIN public.parameters p ON p.test_id=t.id AND p.code=a.parameter_code;

-- Operator-approved supported services activate for future bookings only. Missing technical structure stays explicit.
UPDATE public.tests t SET clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now()
WHERE EXISTS(SELECT 1 FROM approved_catalogue_00075 a WHERE a.code=t.code)
 AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport') AND t.workflow_supported AND t.billing_enabled
 AND EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='')
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.range_validation_required AND NOT EXISTS(SELECT 1 FROM public.reference_ranges rr WHERE rr.parameter_id=p.id AND rr.is_active AND rr.lifecycle_status='Active' AND rr.is_approved AND rr.validation_state='ClinicallyValidated'));

UPDATE public.catalogue_service_readiness r SET state=CASE
 WHEN t.clinical_reporting_enabled THEN 'Approved'::public.catalogue_readiness_state_enum
 WHEN t.lifecycle_status='Draft' OR NOT t.is_active THEN 'Draft'::public.catalogue_readiness_state_enum
 ELSE 'NeedsConfiguration'::public.catalogue_readiness_state_enum END,
 decision_reason=CASE WHEN t.clinical_reporting_enabled THEN 'Final operator-approved catalogue/reference baseline reconciled for future bookings.' ELSE 'Exact missing configuration is available in the readiness checklist.' END,updated_at=now()
FROM public.tests t WHERE t.id=r.test_id;
-- END GENERATED OPERATOR-APPROVED DATA RECONCILIATION

-- ============================================================================
-- FINAL STRUCTURAL GATE: PANEL SERVICES, RESULT STRUCTURES, OPTIONS AND RATES
-- Prospective catalogue infrastructure only. Historical clinical rows are not
-- updated by this section.
-- ============================================================================

DO $$ BEGIN
 CREATE TYPE public.catalogue_billable_entity_enum AS ENUM ('Test','Panel','Package','Other');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
 CREATE TYPE public.catalogue_rate_status_enum AS ENUM ('Draft','Active','Inactive','Archived');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
 CREATE TYPE public.catalogue_result_readiness_enum AS ENUM ('Ready','Incomplete','SpecialistWorkflow','DocumentWorkflow','NoReporting','Inactive');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE public.catalogue_panels
 ADD COLUMN IF NOT EXISTS row_version BIGINT NOT NULL DEFAULT 1,
 ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
 ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES public.user_profiles(id);

ALTER TABLE public.tests ADD COLUMN IF NOT EXISTS catalogue_approved BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE public.tests t SET catalogue_approved=TRUE,updated_at=now()
WHERE EXISTS(SELECT 1 FROM public.catalogue_test_database_entries e WHERE e.configuration_test_id=t.id);

ALTER TABLE public.parameters
 ADD COLUMN IF NOT EXISTS parent_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT;

CREATE TABLE public.catalogue_option_sets (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
 code TEXT NOT NULL UNIQUE CHECK(code=upper(code) AND btrim(code)<>''),
 name TEXT NOT NULL CHECK(btrim(name)<>''),
 lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Draft',
 row_version BIGINT NOT NULL DEFAULT 1,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 archived_at TIMESTAMPTZ, archived_by UUID REFERENCES public.user_profiles(id)
);
CREATE UNIQUE INDEX catalogue_option_sets_name_key ON public.catalogue_option_sets(lower(btrim(name))) WHERE lifecycle_status<>'Archived';

CREATE TABLE public.catalogue_option_values (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
 option_set_id UUID NOT NULL REFERENCES public.catalogue_option_sets(id) ON DELETE RESTRICT,
 value_code TEXT NOT NULL CHECK(btrim(value_code)<>''), label TEXT NOT NULL CHECK(btrim(label)<>''),
 display_order INT NOT NULL CHECK(display_order>0), is_active BOOLEAN NOT NULL DEFAULT TRUE,
 row_version BIGINT NOT NULL DEFAULT 1, created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(option_set_id,value_code), UNIQUE(option_set_id,display_order)
);
ALTER TABLE public.parameters ADD COLUMN IF NOT EXISTS option_set_id UUID REFERENCES public.catalogue_option_sets(id) ON DELETE RESTRICT;

-- Reusable definitions are deliberately not assigned to any parameter. The
-- operator must choose the clinically correct set explicitly.
INSERT INTO public.catalogue_option_sets(code,name,lifecycle_status) VALUES
 ('POSITIVE_NEGATIVE','Positive / Negative','Active'),
 ('REACTIVE_NON_REACTIVE','Reactive / Non-Reactive','Active'),
 ('DETECTED_NOT_DETECTED','Detected / Not Detected','Active'),
 ('PRESENT_ABSENT','Present / Absent','Active'),
 ('NORMAL_ABNORMAL','Normal / Abnormal','Active')
ON CONFLICT(code) DO NOTHING;
INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order)
SELECT s.id,v.code,v.label,v.ord FROM public.catalogue_option_sets s CROSS JOIN LATERAL
 (VALUES
  (CASE s.code WHEN 'POSITIVE_NEGATIVE' THEN 'POSITIVE' WHEN 'REACTIVE_NON_REACTIVE' THEN 'REACTIVE' WHEN 'DETECTED_NOT_DETECTED' THEN 'DETECTED' WHEN 'PRESENT_ABSENT' THEN 'PRESENT' ELSE 'NORMAL' END,
   CASE s.code WHEN 'POSITIVE_NEGATIVE' THEN 'Positive' WHEN 'REACTIVE_NON_REACTIVE' THEN 'Reactive' WHEN 'DETECTED_NOT_DETECTED' THEN 'Detected' WHEN 'PRESENT_ABSENT' THEN 'Present' ELSE 'Normal' END,1),
  (CASE s.code WHEN 'POSITIVE_NEGATIVE' THEN 'NEGATIVE' WHEN 'REACTIVE_NON_REACTIVE' THEN 'NON_REACTIVE' WHEN 'DETECTED_NOT_DETECTED' THEN 'NOT_DETECTED' WHEN 'PRESENT_ABSENT' THEN 'ABSENT' ELSE 'ABNORMAL' END,
   CASE s.code WHEN 'POSITIVE_NEGATIVE' THEN 'Negative' WHEN 'REACTIVE_NON_REACTIVE' THEN 'Non-Reactive' WHEN 'DETECTED_NOT_DETECTED' THEN 'Not Detected' WHEN 'PRESENT_ABSENT' THEN 'Absent' ELSE 'Abnormal' END,2)
 ) v(code,label,ord)
ON CONFLICT(option_set_id,value_code) DO NOTHING;

CREATE TABLE public.catalogue_panel_services (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
 panel_id UUID NOT NULL UNIQUE REFERENCES public.catalogue_panels(id) ON DELETE RESTRICT,
 code TEXT NOT NULL UNIQUE CHECK(code=upper(code) AND btrim(code)<>''),
 name TEXT NOT NULL CHECK(btrim(name)<>''), category_id UUID NOT NULL REFERENCES public.test_categories(id) ON DELETE RESTRICT,
 reporting_type public.reporting_type_enum NOT NULL DEFAULT 'InHouse',
 collection_required BOOLEAN NOT NULL DEFAULT TRUE,
 specimen TEXT, container TEXT,
 lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active', row_version BIGINT NOT NULL DEFAULT 1,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 archived_at TIMESTAMPTZ, archived_by UUID REFERENCES public.user_profiles(id)
);

CREATE TABLE public.catalogue_panel_identity_resolution (
 panel_id UUID PRIMARY KEY REFERENCES public.catalogue_panels(id) ON DELETE RESTRICT,
 identity_kind public.catalogue_billable_entity_enum NOT NULL CHECK(identity_kind IN ('Test','Panel','Package')),
 canonical_test_id UUID REFERENCES public.tests(id) ON DELETE RESTRICT,
 panel_service_id UUID REFERENCES public.catalogue_panel_services(id) ON DELETE RESTRICT,
 package_id UUID REFERENCES public.health_packages(id) ON DELETE RESTRICT,
 CHECK((canonical_test_id IS NOT NULL)::INT+(panel_service_id IS NOT NULL)::INT+(package_id IS NOT NULL)::INT=1)
);

-- Prefer the existing canonical test, then an explicitly linked package. Only
-- the remaining eleven panels receive a first-class panel service.
INSERT INTO public.catalogue_panel_services(id,panel_id,code,name,category_id,reporting_type,collection_required,specimen,container,lifecycle_status)
SELECT (substr(md5('00075-panel-service:'||p.code),1,8)||'-'||substr(md5('00075-panel-service:'||p.code),9,4)||'-5'||substr(md5('00075-panel-service:'||p.code),14,3)||'-a'||substr(md5('00075-panel-service:'||p.code),18,3)||'-'||substr(md5('00075-panel-service:'||p.code),21,12))::UUID,p.id,'PANEL_'||p.code,p.name,p.category_id,p.reporting_type,TRUE,NULL,NULL,'Active'
FROM public.catalogue_panels p
WHERE NOT EXISTS(SELECT 1 FROM public.tests t WHERE t.id=p.id)
 AND NOT EXISTS(SELECT 1 FROM public.catalogue_panel_ratelist_links l WHERE l.panel_id=p.id AND l.health_package_id IS NOT NULL)
ON CONFLICT(panel_id) DO UPDATE SET name=EXCLUDED.name,category_id=EXCLUDED.category_id,reporting_type=EXCLUDED.reporting_type,updated_at=now();

INSERT INTO public.catalogue_panel_identity_resolution(panel_id,identity_kind,canonical_test_id,panel_service_id,package_id)
SELECT p.id,
 CASE WHEN t.id IS NOT NULL THEN 'Test'::public.catalogue_billable_entity_enum WHEN hp.id IS NOT NULL THEN 'Package'::public.catalogue_billable_entity_enum ELSE 'Panel'::public.catalogue_billable_entity_enum END,
 t.id,CASE WHEN t.id IS NULL AND hp.id IS NULL THEN ps.id END,CASE WHEN t.id IS NULL THEN hp.id END
FROM public.catalogue_panels p LEFT JOIN public.tests t ON t.id=p.id
LEFT JOIN LATERAL (SELECT l.health_package_id id FROM public.catalogue_panel_ratelist_links l WHERE l.panel_id=p.id AND l.health_package_id IS NOT NULL ORDER BY l.ratelist_name LIMIT 1) hp ON TRUE
LEFT JOIN public.catalogue_panel_services ps ON ps.panel_id=p.id
ON CONFLICT(panel_id) DO UPDATE SET identity_kind=EXCLUDED.identity_kind,canonical_test_id=EXCLUDED.canonical_test_id,panel_service_id=EXCLUDED.panel_service_id,package_id=EXCLUDED.package_id;

CREATE TABLE public.catalogue_rate_versions (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), entity_type public.catalogue_billable_entity_enum NOT NULL,
 test_id UUID REFERENCES public.tests(id) ON DELETE RESTRICT,
 panel_service_id UUID REFERENCES public.catalogue_panel_services(id) ON DELETE RESTRICT,
 package_id UUID REFERENCES public.health_packages(id) ON DELETE RESTRICT,
 other_service_code TEXT,
 version_number INT NOT NULL CHECK(version_number>0), price_paisa BIGINT CHECK(price_paisa IS NULL OR price_paisa>=0),
 effective_from TIMESTAMPTZ, effective_to TIMESTAMPTZ, status public.catalogue_rate_status_enum NOT NULL DEFAULT 'Draft',
 row_version BIGINT NOT NULL DEFAULT 1, created_by UUID REFERENCES public.user_profiles(id), created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK((test_id IS NOT NULL)::INT+(panel_service_id IS NOT NULL)::INT+(package_id IS NOT NULL)::INT+(other_service_code IS NOT NULL)::INT=1),
 CHECK((entity_type='Test' AND test_id IS NOT NULL) OR (entity_type='Panel' AND panel_service_id IS NOT NULL) OR (entity_type='Package' AND package_id IS NOT NULL) OR (entity_type='Other' AND other_service_code IS NOT NULL))
);
CREATE UNIQUE INDEX catalogue_rate_test_version_key ON public.catalogue_rate_versions(test_id,version_number) WHERE test_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_panel_version_key ON public.catalogue_rate_versions(panel_service_id,version_number) WHERE panel_service_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_package_version_key ON public.catalogue_rate_versions(package_id,version_number) WHERE package_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_other_version_key ON public.catalogue_rate_versions(other_service_code,version_number) WHERE other_service_code IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_one_active_test ON public.catalogue_rate_versions(test_id) WHERE status='Active' AND test_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_one_active_panel ON public.catalogue_rate_versions(panel_service_id) WHERE status='Active' AND panel_service_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_one_active_package ON public.catalogue_rate_versions(package_id) WHERE status='Active' AND package_id IS NOT NULL;
CREATE UNIQUE INDEX catalogue_rate_one_active_other ON public.catalogue_rate_versions(other_service_code) WHERE status='Active' AND other_service_code IS NOT NULL;

-- Existing approved prices become version 1. These ten panel-service prices
-- are the operator-authorized initial active selling prices for 00075.
INSERT INTO public.catalogue_rate_versions(entity_type,test_id,version_number,price_paisa,effective_from,status)
SELECT 'Test',t.id,1,t.price_paisa,t.created_at,(CASE WHEN t.price_configured THEN 'Active' ELSE 'Draft' END)::public.catalogue_rate_status_enum FROM public.tests t ON CONFLICT DO NOTHING;
INSERT INTO public.catalogue_rate_versions(entity_type,package_id,version_number,price_paisa,effective_from,status)
SELECT 'Package',p.id,1,p.price_paisa,p.created_at,(CASE WHEN p.lifecycle_status='Active' THEN 'Active' ELSE 'Draft' END)::public.catalogue_rate_status_enum FROM public.health_packages p ON CONFLICT DO NOTHING;
WITH approved_panel_prices(code,price_paisa) AS (VALUES
 ('PANEL_CBC_WITH_ABSOLUTE_COUNTS',40000::BIGINT),
 ('PANEL_KFT_WITHOUT_EGFR',70000::BIGINT),
 ('PANEL_ELECTROLYTES_PANEL',60000::BIGINT),
 ('PANEL_ARTHRITIS_PROFILE',350000::BIGINT),
 ('PANEL_PROTEIN_FRACTION',45000::BIGINT),
 ('PANEL_TORCH_PROFILE',400000::BIGINT),
 ('PANEL_AMH_PANEL',250000::BIGINT),
 ('PANEL_VIRAL_MARKER',120000::BIGINT),
 ('PANEL_PCOD_PANEL',500000::BIGINT),
 ('PANEL_CBC_WITH_MORPHOLOGY',50000::BIGINT)
)
INSERT INTO public.catalogue_rate_versions(entity_type,panel_service_id,version_number,price_paisa,effective_from,status)
SELECT 'Panel',ps.id,1,COALESCE(ap.price_paisa,(l.operator_rate_npr*100)::BIGINT),now(),
 (CASE WHEN COALESCE(ap.price_paisa,(l.operator_rate_npr*100)::BIGINT) IS NULL THEN 'Draft' ELSE 'Active' END)::public.catalogue_rate_status_enum
FROM public.catalogue_panel_services ps
LEFT JOIN public.catalogue_panel_ratelist_links l ON l.panel_id=ps.panel_id AND lower(btrim(l.ratelist_name))=lower(btrim(ps.name))
LEFT JOIN approved_panel_prices ap ON ap.code=ps.code
ON CONFLICT DO NOTHING;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_rate_versions r JOIN public.catalogue_panel_services ps ON ps.id=r.panel_service_id
     WHERE ps.code IN ('PANEL_CBC_WITH_ABSOLUTE_COUNTS','PANEL_KFT_WITHOUT_EGFR','PANEL_ELECTROLYTES_PANEL','PANEL_ARTHRITIS_PROFILE','PANEL_PROTEIN_FRACTION','PANEL_TORCH_PROFILE','PANEL_AMH_PANEL','PANEL_VIRAL_MARKER','PANEL_PCOD_PANEL','PANEL_CBC_WITH_MORPHOLOGY')
       AND r.version_number=1 AND r.status='Active' AND r.price_paisa=CASE ps.code
        WHEN 'PANEL_CBC_WITH_ABSOLUTE_COUNTS' THEN 40000 WHEN 'PANEL_KFT_WITHOUT_EGFR' THEN 70000
        WHEN 'PANEL_ELECTROLYTES_PANEL' THEN 60000 WHEN 'PANEL_ARTHRITIS_PROFILE' THEN 350000
        WHEN 'PANEL_PROTEIN_FRACTION' THEN 45000 WHEN 'PANEL_TORCH_PROFILE' THEN 400000
        WHEN 'PANEL_AMH_PANEL' THEN 250000 WHEN 'PANEL_VIRAL_MARKER' THEN 120000
        WHEN 'PANEL_PCOD_PANEL' THEN 500000 WHEN 'PANEL_CBC_WITH_MORPHOLOGY' THEN 50000 END)<>10
 THEN RAISE EXCEPTION 'OPERATOR_PANEL_PRICE_SEED_INCOMPLETE'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_test_result_readiness(p_test_id UUID)
RETURNS public.catalogue_result_readiness_enum LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT CASE
  WHEN t.lifecycle_status='Archived' OR (NOT t.catalogue_approved AND NOT t.is_active) THEN 'Inactive'
  WHEN t.reporting_type='NoReporting' THEN 'NoReporting'
  WHEN NOT t.workflow_supported THEN 'SpecialistWorkflow'
  WHEN t.reporting_model='NarrativeDocument' THEN 'DocumentWorkflow'
  WHEN NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND (btrim(p.name)='' OR btrim(p.code)='')) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Numeric','Calculated') AND p.unit_validation_required AND btrim(COALESCE(p.unit,''))='') THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Select','Boolean') AND (p.option_set_id IS NULL OR NOT EXISTS(SELECT 1 FROM public.catalogue_option_values ov WHERE ov.option_set_id=p.option_set_id AND ov.is_active))) THEN 'Incomplete'
  WHEN EXISTS(SELECT 1 FROM public.catalogue_test_database_entries e WHERE e.configuration_test_id=t.id AND e.test_type='Multi parameter nested') AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.parent_parameter_id IS NOT NULL AND p.is_active) THEN 'Incomplete'
  ELSE 'Ready' END::public.catalogue_result_readiness_enum
 FROM public.tests t WHERE t.id=p_test_id
$$;

CREATE OR REPLACE VIEW public.catalogue_test_operational_state AS
SELECT t.id test_id,public.catalogue_test_result_readiness(t.id) readiness,
 CASE public.catalogue_test_result_readiness(t.id)
  WHEN 'Ready' THEN 'Reportable & Ready' WHEN 'Incomplete' THEN 'Reportable · Result Structure Incomplete'
  WHEN 'SpecialistWorkflow' THEN 'Specialist workflow' WHEN 'DocumentWorkflow' THEN 'Specialist workflow'
  WHEN 'NoReporting' THEN 'Billing only · No Worklist' ELSE 'Inactive' END operational_state
FROM public.tests t;

CREATE OR REPLACE FUNCTION public.catalogue_panel_service_components(p_service_id UUID)
RETURNS TABLE(panel_service_id UUID,panel_id UUID,test_id UUID,test_code TEXT,test_name TEXT,display_order INT,readiness public.catalogue_result_readiness_enum)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_create_bill') OR public.has_permission('can_manage_catalogue')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH owners AS (
  SELECT ps.id service_id,ps.panel_id,COALESCE(pc.component_test_id,owner.id) owner_id,min(pc.display_order) ord
  FROM public.catalogue_panel_services ps JOIN public.catalogue_panel_components pc ON pc.panel_id=ps.panel_id
  LEFT JOIN public.parameters prm ON prm.id=pc.component_parameter_id LEFT JOIN public.tests owner ON owner.id=prm.test_id
  WHERE ps.id=p_service_id GROUP BY ps.id,ps.panel_id,COALESCE(pc.component_test_id,owner.id)
 ) SELECT o.service_id,o.panel_id,t.id,t.code::TEXT,t.name::TEXT,o.ord,public.catalogue_test_result_readiness(t.id)
 FROM owners o JOIN public.tests t ON t.id=o.owner_id ORDER BY o.ord;
END $$;

CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT,p_limit INT DEFAULT 20) RETURNS TABLE(entity_type TEXT,entity_id UUID,code TEXT,name TEXT,short_name TEXT,category TEXT,specimen TEXT,container TEXT,price_paisa BIGINT,price_configured BOOLEAN,pricing_policy public.catalogue_pricing_policy_enum,allow_zero_price_billing BOOLEAN,reporting_type public.reporting_type_enum,rank_score INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
#variable_conflict use_column
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH q AS (SELECT lower(btrim(COALESCE(p_query,''))) value),
 matches(entity_kind,item_id,item_code,item_name,item_short_name,item_category,item_specimen,item_container,item_price_paisa,item_price_configured,item_pricing_policy,item_zero_price,item_reporting_type,item_score) AS (
  SELECT 'Test'::TEXT,t.id,t.code::TEXT,t.name::TEXT,t.short_name::TEXT,c.name::TEXT,t.sample_type::TEXT,t.container::TEXT,r.price_paisa,(r.id IS NOT NULL AND r.price_paisa IS NOT NULL),COALESCE(t.pricing_policy,'Fixed'),t.allow_zero_price_billing,t.reporting_type,
   CASE WHEN lower(t.code)=q.value THEN 100 WHEN lower(t.code) LIKE q.value||'%' THEN 90 WHEN lower(t.name) LIKE q.value||'%' THEN 70 ELSE 50 END score
  FROM public.tests t CROSS JOIN q LEFT JOIN public.test_categories c ON c.id=t.category_id LEFT JOIN public.catalogue_rate_versions r ON r.test_id=t.id AND r.status='Active' AND (r.effective_to IS NULL OR r.effective_to>now())
  WHERE length(q.value)>=2 AND t.catalogue_approved AND t.lifecycle_status<>'Archived' AND (lower(t.code) LIKE '%'||q.value||'%' OR lower(t.name) LIKE '%'||q.value||'%' OR lower(COALESCE(t.short_name,'')) LIKE '%'||q.value||'%')
  UNION ALL
  SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,NULL,'Health Packages',NULL,NULL,r.price_paisa,(r.id IS NOT NULL AND r.price_paisa IS NOT NULL),p.pricing_policy,FALSE,'NoReporting'::public.reporting_type_enum,
   CASE WHEN lower(p.code)=q.value THEN 100 WHEN lower(p.code) LIKE q.value||'%' THEN 90 WHEN lower(p.name) LIKE q.value||'%' THEN 70 ELSE 50 END
  FROM public.health_packages p CROSS JOIN q LEFT JOIN public.catalogue_rate_versions r ON r.package_id=p.id AND r.status='Active' AND (r.effective_to IS NULL OR r.effective_to>now())
  WHERE length(q.value)>=2 AND p.lifecycle_status='Active' AND (lower(p.code) LIKE '%'||q.value||'%' OR lower(p.name) LIKE '%'||q.value||'%')
  UNION ALL
  SELECT 'Panel',ps.id,ps.code,ps.name,NULL,c.name,ps.specimen,ps.container,r.price_paisa,(r.id IS NOT NULL AND r.price_paisa IS NOT NULL),'Fixed'::public.catalogue_pricing_policy_enum,FALSE,ps.reporting_type,
   CASE WHEN lower(ps.code)=q.value THEN 100 WHEN lower(ps.code) LIKE q.value||'%' THEN 90 WHEN lower(ps.name) LIKE q.value||'%' THEN 70 ELSE 50 END
  FROM public.catalogue_panel_services ps JOIN public.test_categories c ON c.id=ps.category_id CROSS JOIN q LEFT JOIN public.catalogue_rate_versions r ON r.panel_service_id=ps.id AND r.status='Active' AND (r.effective_to IS NULL OR r.effective_to>now())
  WHERE length(q.value)>=2 AND ps.lifecycle_status='Active' AND (lower(ps.code) LIKE '%'||q.value||'%' OR lower(ps.name) LIKE '%'||q.value||'%')
 ) SELECT m.entity_kind,m.item_id,m.item_code,m.item_name,m.item_short_name,m.item_category,m.item_specimen,m.item_container,m.item_price_paisa,m.item_price_configured,m.item_pricing_policy,m.item_zero_price,m.item_reporting_type,m.item_score
 FROM matches m ORDER BY m.item_score DESC,m.item_name LIMIT greatest(1,least(COALESCE(p_limit,20),50));
END $$;

CREATE TABLE public.bill_panel_selections (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(), bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE RESTRICT,
 panel_service_id UUID NOT NULL REFERENCES public.catalogue_panel_services(id) ON DELETE RESTRICT,
 panel_id UUID NOT NULL REFERENCES public.catalogue_panels(id) ON DELETE RESTRICT,
 service_code_snapshot TEXT NOT NULL, panel_name_snapshot TEXT NOT NULL, panel_price_paisa BIGINT NOT NULL CHECK(panel_price_paisa>=0),
 rate_version_id UUID NOT NULL REFERENCES public.catalogue_rate_versions(id) ON DELETE RESTRICT,
 component_snapshot JSONB NOT NULL CHECK(jsonb_typeof(component_snapshot)='array'), created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 UNIQUE(bill_id,panel_service_id)
);
CREATE TABLE public.bill_panel_components (
 bill_panel_selection_id UUID NOT NULL REFERENCES public.bill_panel_selections(id) ON DELETE RESTRICT,
 bill_item_id UUID NOT NULL REFERENCES public.bill_items(id) ON DELETE RESTRICT,
 test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
 display_order INT NOT NULL, PRIMARY KEY(bill_panel_selection_id,test_id), UNIQUE(bill_panel_selection_id,bill_item_id)
);

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_panel_service(p_patient_data JSONB,p_bill_data JSONB,p_payment_data JSONB,p_idempotency_key TEXT,p_panel_service_id UUID,p_expected_panel_version BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE svc public.catalogue_panel_services%ROWTYPE; pnl public.catalogue_panels%ROWTYPE; rate public.catalogue_rate_versions%ROWTYPE; items JSONB[]; response JSONB; bill_uuid UUID; selection_uuid UUID; component_snapshot JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO svc FROM public.catalogue_panel_services WHERE id=p_panel_service_id AND lifecycle_status='Active' FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Panel service is inactive or missing.' USING ERRCODE='23503'; END IF;
 SELECT * INTO pnl FROM public.catalogue_panels WHERE id=svc.panel_id AND lifecycle_status='Active' FOR SHARE;
 IF pnl.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
 SELECT * INTO rate FROM public.catalogue_rate_versions WHERE panel_service_id=svc.id AND status='Active' AND price_paisa IS NOT NULL AND COALESCE(effective_from,now())<=now() AND (effective_to IS NULL OR effective_to>now()) FOR SHARE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Price not specified. A Super Admin must activate a panel rate before billing.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_panel_service_components(svc.id) c WHERE c.readiness<>'Ready') THEN RAISE EXCEPTION 'Result Structure Incomplete. Configure Result Structure before billing this panel.' USING ERRCODE='23514'; END IF;
 SELECT array_agg(jsonb_build_object('test_id',c.test_id,'unit_price_paisa',CASE WHEN c.display_order=min_ord THEN rate.price_paisa ELSE 0 END,'discount_paisa',0,'zero_price_acknowledged',TRUE) ORDER BY c.display_order),
        jsonb_agg(jsonb_build_object('test_id',c.test_id,'test_code',c.test_code,'test_name',c.test_name,'display_order',c.display_order) ORDER BY c.display_order)
 INTO items,component_snapshot FROM public.catalogue_panel_service_components(svc.id) c CROSS JOIN (SELECT min(display_order) min_ord FROM public.catalogue_panel_service_components(svc.id)) x;
 IF items IS NULL THEN RAISE EXCEPTION 'Panel has no canonical component tests.' USING ERRCODE='23514'; END IF;
 response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,items,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
 INSERT INTO public.bill_panel_selections(bill_id,panel_service_id,panel_id,service_code_snapshot,panel_name_snapshot,panel_price_paisa,rate_version_id,component_snapshot)
 VALUES(bill_uuid,svc.id,pnl.id,svc.code,pnl.name,rate.price_paisa,rate.id,component_snapshot) RETURNING id INTO selection_uuid;
 INSERT INTO public.bill_panel_components(bill_panel_selection_id,bill_item_id,test_id,display_order)
 SELECT selection_uuid,bi.id,bi.test_id,(x->>'display_order')::INT FROM jsonb_array_elements(component_snapshot)x JOIN public.bill_items bi ON bi.bill_id=bill_uuid AND bi.test_id=(x->>'test_id')::UUID;
 RETURN response||jsonb_build_object('panel_selection_id',selection_uuid,'panel_service_id',svc.id,'rate_version_id',rate.id);
END $$;

-- Guarded mutation helpers. Technical configuration and business administration
-- are intentionally separate and every mutation is audited/version checked.
CREATE OR REPLACE FUNCTION public.catalogue_require_technical() RETURNS VOID LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_configure_catalogue_technical') OR public.has_permission('can_manage_catalogue')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_option_set(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; v_old JSONB; BEGIN PERFORM public.catalogue_require_technical();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_option_sets(code,name) VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name')) RETURNING id INTO v_id;
 ELSE SELECT to_jsonb(s) INTO v_old FROM public.catalogue_option_sets s WHERE id=v_id FOR UPDATE; IF (v_old->>'row_version')::BIGINT<>p_expected_version THEN RAISE EXCEPTION 'Option set changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_sets SET code=upper(btrim(p_payload->>'code')),name=btrim(p_payload->>'name'),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_OPTION_SET_SAVED','CatalogueOptionSet',v_id::TEXT,v_old,(SELECT to_jsonb(s) FROM public.catalogue_option_sets s WHERE s.id=v_id)); RETURN v_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_option_value(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; v_old JSONB; BEGIN PERFORM public.catalogue_require_technical();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order) VALUES((p_payload->>'option_set_id')::UUID,upper(btrim(p_payload->>'value_code')),btrim(p_payload->>'label'),(p_payload->>'display_order')::INT) RETURNING id INTO v_id;
 ELSE SELECT to_jsonb(v) INTO v_old FROM public.catalogue_option_values v WHERE id=v_id FOR UPDATE; IF (v_old->>'row_version')::BIGINT<>p_expected_version THEN RAISE EXCEPTION 'Option changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_values SET value_code=upper(btrim(p_payload->>'value_code')),label=btrim(p_payload->>'label'),display_order=(p_payload->>'display_order')::INT,is_active=COALESCE((p_payload->>'is_active')::BOOLEAN,is_active),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF; RETURN v_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_option_set(p_parameter_id UUID,p_option_set_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.parameters%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO p FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF p.value_type NOT IN ('Select','Boolean') THEN RAISE EXCEPTION 'Option sets apply only to Select or Boolean parameters.' USING ERRCODE='23514'; END IF; UPDATE public.parameters SET option_set_id=p_option_set_id,row_version=row_version+1,updated_at=now() WHERE id=p_parameter_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_archive_option_set(p_option_set_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE s public.catalogue_option_sets%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO s FROM public.catalogue_option_sets WHERE id=p_option_set_id FOR UPDATE; IF s.row_version<>p_expected_version THEN RAISE EXCEPTION 'Option set changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_option_sets SET lifecycle_status='Archived',archived_at=now(),archived_by=auth.uid(),row_version=row_version+1,updated_at=now() WHERE id=s.id; UPDATE public.catalogue_option_values SET is_active=FALSE,row_version=row_version+1,updated_at=now() WHERE option_set_id=s.id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_panel(p_payload JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID:=NULLIF(p_payload->>'id','')::UUID; p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager();
 IF v_id IS NULL THEN INSERT INTO public.catalogue_panels(code,name,category_id,reporting_type,workflow_supported,clinical_reporting_enabled,lifecycle_status,display_order) VALUES(upper(btrim(p_payload->>'code')),btrim(p_payload->>'name'),(p_payload->>'category_id')::UUID,COALESCE((p_payload->>'reporting_type')::public.reporting_type_enum,'InHouse'),COALESCE((p_payload->>'workflow_supported')::BOOLEAN,TRUE),FALSE,'Draft',COALESCE((p_payload->>'display_order')::INT,0)) RETURNING id INTO v_id;
 ELSE SELECT * INTO p FROM public.catalogue_panels WHERE id=v_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_panels SET name=btrim(p_payload->>'name'),category_id=(p_payload->>'category_id')::UUID,display_order=COALESCE((p_payload->>'display_order')::INT,display_order),row_version=row_version+1,updated_at=now() WHERE id=v_id; END IF; RETURN v_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_panel_component(p_panel_id UUID,p_component_test_id UUID,p_component_parameter_id UUID,p_display_name TEXT,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE; IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF (p_component_test_id IS NOT NULL)::INT+(p_component_parameter_id IS NOT NULL)::INT<>1 THEN RAISE EXCEPTION 'Exactly one canonical component identity is required.' USING ERRCODE='23514'; END IF; INSERT INTO public.catalogue_panel_components(panel_id,component_test_id,component_parameter_id,display_name,display_order) VALUES(p_panel_id,p_component_test_id,p_component_parameter_id,btrim(p_display_name),p_display_order) ON CONFLICT(panel_id,display_order) DO UPDATE SET component_test_id=EXCLUDED.component_test_id,component_parameter_id=EXCLUDED.component_parameter_id,display_name=EXCLUDED.display_name; UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_remove_panel_component(p_panel_id UUID,p_display_order INT,p_expected_panel_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE; IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE panel_id=p_panel_id) THEN RAISE EXCEPTION 'Historically billed panel composition cannot be deleted; archive the panel and create a new definition.' USING ERRCODE='23503'; END IF; DELETE FROM public.catalogue_panel_components WHERE panel_id=p_panel_id AND display_order=p_display_order; UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_reorder_panel_components(p_panel_id UUID,p_component_ids UUID[],p_expected_panel_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_technical(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE; IF p.row_version<>p_expected_panel_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF cardinality(p_component_ids)<>(SELECT count(*) FROM public.catalogue_panel_components WHERE panel_id=p_panel_id) OR EXISTS(SELECT 1 FROM unnest(p_component_ids) id LEFT JOIN public.catalogue_panel_components c ON c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=id WHERE c.panel_id IS NULL) THEN RAISE EXCEPTION 'Complete canonical component order is required.' USING ERRCODE='23514'; END IF; UPDATE public.catalogue_panel_components SET display_order=display_order+10000 WHERE panel_id=p_panel_id; UPDATE public.catalogue_panel_components c SET display_order=x.ord FROM unnest(p_component_ids) WITH ORDINALITY x(id,ord) WHERE c.panel_id=p_panel_id AND COALESCE(c.component_test_id,c.component_parameter_id)=x.id; UPDATE public.catalogue_panels SET row_version=row_version+1,updated_at=now() WHERE id=p_panel_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_panel_lifecycle(p_panel_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.catalogue_panels SET lifecycle_status=p_status,archived_at=CASE WHEN p_status='Archived' THEN now() END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() END,row_version=row_version+1,updated_at=now() WHERE id=p_panel_id; UPDATE public.catalogue_panel_services SET lifecycle_status=p_status,row_version=row_version+1,updated_at=now() WHERE panel_id=p_panel_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_create_rate_version(p_entity_type public.catalogue_billable_entity_enum,p_entity_id UUID,p_other_service_code TEXT,p_price_paisa BIGINT,p_effective_from TIMESTAMPTZ DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v_id UUID; v_no INT; BEGIN PERFORM public.catalogue_require_manager(); IF p_price_paisa IS NOT NULL AND p_price_paisa<0 THEN RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514'; END IF;
 SELECT COALESCE(max(version_number),0)+1 INTO v_no FROM public.catalogue_rate_versions r WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id) OR (p_entity_type='Package' AND r.package_id=p_entity_id) OR (p_entity_type='Other' AND r.other_service_code=p_other_service_code);
 INSERT INTO public.catalogue_rate_versions(entity_type,test_id,panel_service_id,package_id,other_service_code,version_number,price_paisa,effective_from,status,created_by) VALUES(p_entity_type,CASE WHEN p_entity_type='Test' THEN p_entity_id END,CASE WHEN p_entity_type='Panel' THEN p_entity_id END,CASE WHEN p_entity_type='Package' THEN p_entity_id END,CASE WHEN p_entity_type='Other' THEN upper(btrim(p_other_service_code)) END,v_no,p_price_paisa,p_effective_from,'Draft',auth.uid()) RETURNING id INTO v_id; RETURN v_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_activate_rate(p_rate_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE; IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF r.price_paisa IS NULL THEN RAISE EXCEPTION 'Price not specified.' USING ERRCODE='23514'; END IF; UPDATE public.catalogue_rate_versions x SET status='Inactive',effective_to=COALESCE(x.effective_to,now()),row_version=x.row_version+1,updated_at=now() WHERE x.status='Active' AND x.id<>r.id AND ((r.test_id IS NOT NULL AND x.test_id=r.test_id) OR (r.panel_service_id IS NOT NULL AND x.panel_service_id=r.panel_service_id) OR (r.package_id IS NOT NULL AND x.package_id=r.package_id) OR (r.other_service_code IS NOT NULL AND x.other_service_code=r.other_service_code)); UPDATE public.catalogue_rate_versions SET status='Active',effective_from=COALESCE(effective_from,now()),effective_to=NULL,row_version=row_version+1,updated_at=now() WHERE id=r.id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_archive_rate(p_rate_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE; IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE rate_version_id=r.id) THEN UPDATE public.catalogue_rate_versions SET status='Inactive',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now() WHERE id=r.id; ELSE UPDATE public.catalogue_rate_versions SET status='Archived',effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now() WHERE id=r.id; END IF; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_or_archive_rate(p_rate_id UUID,p_expected_version BIGINT) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.catalogue_rate_versions%ROWTYPE; v_used BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_manager();
 SELECT * INTO r FROM public.catalogue_rate_versions WHERE id=p_rate_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Rate not found.' USING ERRCODE='P0002'; END IF;
 IF r.row_version<>p_expected_version THEN RAISE EXCEPTION 'Rate changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE rate_version_id=r.id) INTO v_used;
 IF NOT v_used AND r.status='Draft' THEN
  DELETE FROM public.catalogue_rate_versions WHERE id=r.id;
  RETURN 'Deleted';
 END IF;
 UPDATE public.catalogue_rate_versions SET status=CASE WHEN v_used THEN 'Inactive' ELSE 'Archived' END,
  effective_to=COALESCE(effective_to,now()),row_version=row_version+1,updated_at=now() WHERE id=r.id;
 RETURN CASE WHEN v_used THEN 'ArchivedUsedRate' ELSE 'Archived' END;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_rate_history(p_entity_type public.catalogue_billable_entity_enum,p_entity_id UUID,p_other_service_code TEXT DEFAULT NULL)
RETURNS TABLE(item JSONB) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 PERFORM public.catalogue_require_manager();
 RETURN QUERY SELECT jsonb_build_object('id',r.id,'version_number',r.version_number,'price_paisa',r.price_paisa,
  'effective_from',r.effective_from,'effective_to',r.effective_to,'status',r.status,'row_version',r.row_version,
  'used_by_bill_count',(SELECT count(*) FROM public.bill_panel_selections b WHERE b.rate_version_id=r.id))
 FROM public.catalogue_rate_versions r
 WHERE (p_entity_type='Test' AND r.test_id=p_entity_id) OR (p_entity_type='Panel' AND r.panel_service_id=p_entity_id)
  OR (p_entity_type='Package' AND r.package_id=p_entity_id) OR (p_entity_type='Other' AND r.other_service_code=upper(btrim(p_other_service_code)))
 ORDER BY r.version_number DESC;
END $$;

ALTER TABLE public.catalogue_option_sets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_option_values ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_services ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_panel_identity_resolution ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_rate_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_panel_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_panel_components ENABLE ROW LEVEL SECURITY;
CREATE POLICY catalogue_option_sets_staff_read ON public.catalogue_option_sets FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY catalogue_option_values_staff_read ON public.catalogue_option_values FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY catalogue_panel_services_staff_read ON public.catalogue_panel_services FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY catalogue_panel_resolution_staff_read ON public.catalogue_panel_identity_resolution FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY catalogue_rates_staff_read ON public.catalogue_rate_versions FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY bill_panel_selections_staff_read ON public.bill_panel_selections FOR SELECT TO authenticated USING(public.is_active_user());
CREATE POLICY bill_panel_components_staff_read ON public.bill_panel_components FOR SELECT TO authenticated USING(public.is_active_user());

REVOKE ALL ON public.catalogue_option_sets,public.catalogue_option_values,public.catalogue_panel_services,public.catalogue_panel_identity_resolution,public.catalogue_rate_versions,public.bill_panel_selections,public.bill_panel_components FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.catalogue_option_sets,public.catalogue_option_values,public.catalogue_panel_services,public.catalogue_panel_identity_resolution,public.catalogue_rate_versions,public.bill_panel_selections,public.bill_panel_components TO authenticated;
REVOKE ALL ON FUNCTION public.catalogue_test_result_readiness(UUID),public.catalogue_panel_service_components(UUID),public.create_patient_bill_order_with_panel_service(JSONB,JSONB,JSONB,TEXT,UUID,BIGINT),public.catalogue_save_option_set(JSONB,BIGINT),public.catalogue_save_option_value(JSONB,BIGINT),public.catalogue_set_parameter_option_set(UUID,UUID,BIGINT),public.catalogue_archive_option_set(UUID,BIGINT),public.catalogue_save_panel(JSONB,BIGINT),public.catalogue_save_panel_component(UUID,UUID,UUID,TEXT,INT,BIGINT),public.catalogue_remove_panel_component(UUID,INT,BIGINT),public.catalogue_reorder_panel_components(UUID,UUID[],BIGINT),public.catalogue_set_panel_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_create_rate_version(public.catalogue_billable_entity_enum,UUID,TEXT,BIGINT,TIMESTAMPTZ),public.catalogue_activate_rate(UUID,BIGINT),public.catalogue_archive_rate(UUID,BIGINT),public.catalogue_delete_or_archive_rate(UUID,BIGINT),public.catalogue_rate_history(public.catalogue_billable_entity_enum,UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_test_result_readiness(UUID),public.catalogue_panel_service_components(UUID),public.create_patient_bill_order_with_panel_service(JSONB,JSONB,JSONB,TEXT,UUID,BIGINT),public.catalogue_save_option_set(JSONB,BIGINT),public.catalogue_save_option_value(JSONB,BIGINT),public.catalogue_set_parameter_option_set(UUID,UUID,BIGINT),public.catalogue_archive_option_set(UUID,BIGINT),public.catalogue_save_panel(JSONB,BIGINT),public.catalogue_save_panel_component(UUID,UUID,UUID,TEXT,INT,BIGINT),public.catalogue_remove_panel_component(UUID,INT,BIGINT),public.catalogue_reorder_panel_components(UUID,UUID[],BIGINT),public.catalogue_set_panel_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_create_rate_version(public.catalogue_billable_entity_enum,UUID,TEXT,BIGINT,TIMESTAMPTZ),public.catalogue_activate_rate(UUID,BIGINT),public.catalogue_archive_rate(UUID,BIGINT),public.catalogue_delete_or_archive_rate(UUID,BIGINT),public.catalogue_rate_history(public.catalogue_billable_entity_enum,UUID,TEXT) TO authenticated;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_panel_identity_resolution)<>31 THEN RAISE EXCEPTION 'PANEL_BILLING_IDENTITY_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_panel_services)<>11 THEN RAISE EXCEPTION 'PANEL_SERVICE_IDENTITY_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_panel_identity_resolution WHERE (identity_kind='Test')<>(canonical_test_id IS NOT NULL) OR (identity_kind='Panel')<>(panel_service_id IS NOT NULL) OR (identity_kind='Package')<>(package_id IS NOT NULL)) THEN RAISE EXCEPTION 'PANEL_BILLING_IDENTITY_AMBIGUOUS'; END IF;
 IF EXISTS(SELECT 1 FROM public.catalogue_option_sets s WHERE EXISTS(SELECT 1 FROM public.parameters p WHERE p.option_set_id=s.id)) THEN RAISE EXCEPTION 'QUALITATIVE_OPTION_SET_AUTO_ASSIGNMENT_FORBIDDEN'; END IF;
END $$;

-- ============================================================================
-- SOURCE-BACKED RESULT-STRUCTURE RECONCILIATION
-- Optional unit/range metadata is intentionally nullable. No medical values or
-- qualitative vocabularies are inferred by this section.
-- ============================================================================
CREATE TABLE public.catalogue_result_structure_reconciliation (
 test_id UUID PRIMARY KEY REFERENCES public.tests(id) ON DELETE RESTRICT,
 historical_zero_parameter_inventory BOOLEAN NOT NULL,
 source_evidence TEXT NOT NULL,
 action_code TEXT NOT NULL CHECK(action_code IN
  ('MATERIALIZED_NUMERIC_SINGLE','MATERIALIZED_QUALITATIVE_WITH_OPTIONS',
   'OPTION_SET_REQUIRES_OPERATOR_SELECTION','RESULT_STRUCTURE_REQUIRES_OPERATOR_INPUT',
   'DOCUMENT_WORKFLOW_RETAINED','DOCUMENT_RECLASSIFIED_FROM_APPROVED_EVIDENCE',
   'ALREADY_CONFIGURED_PRODUCTION_BASELINE')),
 parameters_materialized INT NOT NULL DEFAULT 0,
 final_readiness public.catalogue_result_readiness_enum NOT NULL,
 notes TEXT NOT NULL,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.catalogue_result_structure_reconciliation ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.catalogue_result_structure_reconciliation FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.catalogue_result_structure_reconciliation TO authenticated;
CREATE POLICY catalogue_result_reconciliation_staff_read ON public.catalogue_result_structure_reconciliation FOR SELECT TO authenticated USING(public.is_active_user());

-- Operator-approved canonical quantitative Beta-hCG configuration. Gestational
-- intervals are contextual clinical metadata, not universal numeric flagging
-- ranges. No gestational age or diagnosis is inferred from an hCG result.
DO $$ DECLARE canonical_id UUID; canonical_parameter_id UUID; keeper_range_id UUID; BEGIN
 IF (SELECT count(*) FROM public.tests WHERE code='BETA_HCG')<>1 THEN RAISE EXCEPTION 'BETA_HCG_CANONICAL_IDENTITY_COUNT_INVALID'; END IF;
 SELECT id INTO canonical_id FROM public.tests WHERE code='BETA_HCG' FOR UPDATE;
 IF EXISTS(
  SELECT 1 FROM public.parameters p WHERE p.test_id=canonical_id AND p.code='HCG_VAL'
   AND p.is_active AND p.lifecycle_status='Active'
   AND (p.value_type<>'Numeric' OR lower(regexp_replace(COALESCE(p.unit,''),'[^a-zA-Z/]','','g')) NOT IN('miu/ml','iu/l'))
 ) THEN RAISE EXCEPTION 'BETA_HCG_EXISTING_HCG_VAL_INCOMPATIBLE'; END IF;
 IF EXISTS(
  SELECT 1 FROM public.parameters p WHERE p.test_id=canonical_id AND p.code<>'HCG_VAL'
   AND p.is_active AND p.lifecycle_status='Active'
   AND (p.code~*'(^|_)HCG($|_)' OR p.name~*'(beta|total).*hcg|hcg.*(beta|total)')
 ) THEN RAISE EXCEPTION 'BETA_HCG_CONFLICTING_ACTIVE_PARAMETER'; END IF;

 INSERT INTO public.parameters(
  test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,
  clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required,interpretation_config
 ) VALUES(
  canonical_id,'HCG_VAL','Total Beta hCG (Quantitative)','Numeric','mIU/mL',1,TRUE,TRUE,'Active',
  'Configured',FALSE,FALSE,FALSE,
  jsonb_build_object(
   'assay_methodologies',jsonb_build_array('ECLIA','CLIA','CMIA'),
   'canonical_unit','mIU/mL','equivalent_units',jsonb_build_array('IU/L'),
   'default_reference',jsonb_build_object('population','Non-Pregnant Adult Females','operator','<','threshold',5.0,'display','< 5.0 mIU/mL'),
   'contextual_reference_model','LMP-based; display only when sex/state and gestational context is available or intentionally selected',
   'contextual_references',jsonb_build_array(
    jsonb_build_object('context','Non-Pregnant Adult Females','sex','Female','state','NonPregnant','display','< 5.0 mIU/mL'),
    jsonb_build_object('context','Postmenopausal Females','sex','Female','state','Postmenopausal','display','< 9.5 mIU/mL'),
    jsonb_build_object('context','Healthy Adult Males','sex','Male','state','HealthyAdult','display','< 2.0 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 3 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','3','min',5,'max',50,'display','5 – 50 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 4 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','4','min',5,'max',426,'display','5 – 426 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 5 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','5','min',18,'max',7340,'display','18 – 7,340 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 6 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','6','min',1080,'max',56500,'display','1,080 – 56,500 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 7–8 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','7-8','min',7650,'max',229000,'display','7,650 – 229,000 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 9–12 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','9-12','min',25700,'max',288000,'display','25,700 – 288,000 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 13–16 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','13-16','min',13300,'max',254000,'display','13,300 – 254,000 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 17–24 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','17-24','min',4060,'max',165400,'display','4,060 – 165,400 mIU/mL'),
    jsonb_build_object('context','Pregnancy — 25–40 Weeks LMP','sex','Female','state','Pregnant','lmp_weeks','25-40','min',3640,'max',117000,'display','3,640 – 117,000 mIU/mL')
   ),
   'automatic_gestational_age_inference',FALSE,'automatic_diagnosis',FALSE,
   'clinical_caution','Do not infer pregnancy viability, ectopic pregnancy, miscarriage, or gestational status from hCG alone.'
  )
 )
 ON CONFLICT(test_id,code) DO UPDATE SET
  name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,
  is_mandatory=TRUE,is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',
  unit_validation_required=FALSE,range_validation_required=FALSE,method_validation_required=FALSE,
  interpretation_config=EXCLUDED.interpretation_config,row_version=public.parameters.row_version+1,updated_at=now()
 RETURNING id INTO canonical_parameter_id;

 SELECT id INTO keeper_range_id FROM public.reference_ranges
 WHERE parameter_id=canonical_parameter_id AND lifecycle_status<>'Archived'
 ORDER BY (is_active AND lifecycle_status='Active') DESC,id LIMIT 1 FOR UPDATE;
 UPDATE public.reference_ranges SET is_active=FALSE,lifecycle_status='Archived',archived_at=COALESCE(archived_at,now()),updated_at=now()
 WHERE parameter_id=canonical_parameter_id AND id<>COALESCE(keeper_range_id,'00000000-0000-0000-0000-000000000000'::UUID) AND lifecycle_status<>'Archived';
 IF keeper_range_id IS NULL THEN
  INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_text,reference_text,unit,method,is_active,is_approved,lifecycle_status,validation_state,validation_source)
  VALUES(canonical_parameter_id,'All',0,43800,'< 5.0 mIU/mL','Default ordinary non-pregnant display reference. Contextual sex/state and LMP-based gestational brackets are stored on HCG_VAL interpretation_config and require explicit context.','mIU/mL','ECLIA / CLIA / CMIA',TRUE,TRUE,'Active','ClinicallyValidated','Final operator-approved Beta-hCG quantitative configuration')
  RETURNING id INTO keeper_range_id;
 ELSE
  UPDATE public.reference_ranges SET gender='All',age_min_days=0,age_max_days=43800,normal_min=NULL,normal_max=NULL,
   critical_low=NULL,critical_high=NULL,normal_text='< 5.0 mIU/mL',
   reference_text='Default ordinary non-pregnant display reference. Contextual sex/state and LMP-based gestational brackets are stored on HCG_VAL interpretation_config and require explicit context.',
   unit='mIU/mL',method='ECLIA / CLIA / CMIA',is_active=TRUE,is_approved=TRUE,lifecycle_status='Active',
   validation_state='ClinicallyValidated',validation_source='Final operator-approved Beta-hCG quantitative configuration',updated_at=now()
  WHERE id=keeper_range_id;
 END IF;
 IF (SELECT count(*) FROM public.parameters WHERE test_id=canonical_id AND code='HCG_VAL' AND is_active AND lifecycle_status='Active')<>1 THEN RAISE EXCEPTION 'BETA_HCG_ACTIVE_HCG_VAL_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.reference_ranges WHERE parameter_id=canonical_parameter_id AND is_active AND lifecycle_status='Active')<>1 THEN RAISE EXCEPTION 'BETA_HCG_ACTIVE_REFERENCE_GROUP_COUNT_INVALID'; END IF;
END $$;

-- The historical remediation scope is an identity contract, not a runtime
-- aggregate. Production 00074 legitimately retains the pre-canonical
-- `BETA HCG` alias beside configured `BETA_HCG`; quarantine that alias from
-- generic result entry only when the complete canonical relationship is true.
CREATE TEMP TABLE expected_historical_incomplete_00075(code TEXT PRIMARY KEY) ON COMMIT DROP;
INSERT INTO expected_historical_incomplete_00075(code)
SELECT unnest(ARRAY[
 'ABG','ABS_DLC','ADA','ADA_PLEURAL_PERICARDIAL_OR_ASCITIC_FLUID','AEC','AFP','ALLERGY_SCREENING_TEST','ALP','ALT','AMH','AMMONIA','AMYLASE','ANC',
 'ANTI_CARDIOLIPIN_IGG','ANTI_CARDIOLIPIN_IGM','ANTI_HBC','ANTI_HBE','ANTI_HBS','ANTI_NUCLEAR_ANTIBODY_ANA_BY_ELISA','ANTI_PHOSPHOLIPID_IGG','ANTI_PHOSPHOLIPID_IGM','ANTI_TPO','APTT','ASO_ANTI_STREPTOLYSIN_O_QUALITATIVE','AST',
 'BETA_2_GLYCOPROTEIN_1_IGG','BETA_2_GLYCOPROTEIN_1_IGM','BICARBONATE','BILE_ACID','BILIRUBIN_TD','BLOOD_GROUP_RH','BT_CT','BUN','C3','CA_125','CA_15_3','CA_19_9','CA_242','CA_50','CA_72_4','CALCITONIN','CCP','CEA_CARCINOEMBRYONIC_ANTIGEN','CHIKUNGUNYA','CHOL_TOTAL','CK_MB','CK_TOTAL','CMV_IGG','CMV_IGM','COAG_PROFILE','CORTISOL_SERUM','CORTISOL_URINE','CRP_QUALITATIVE',
 'D_DIMER','DENGUE_IGM_IGG_PANEL','DENGUE_PANEL','DHEA','DIRECT_COOMB_S_TEST','DLC_3PART','DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','EGFR','ESR_WESTERGREN','ESR_WINTROBE','ESTRADIOL','FASTING_INSULIN','FOLIC_ACID','FREE_PSA','FSH','G6PD','GCT','GGT','GLOBULIN','GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY','GTT','H_ALB','HAV_IGG','HAV_IGM','HAV_PANEL','HAV_TOTAL_AB','HBEAG','HBSAG_ELISA','HCV','HDL_CHOL','HIV_CARD_TEST','HIV_ELISA_I_II','HOMOCYSTEINE','HPLC','HSCRP','HSV_1_2_IGG','HSV_1_2_IGM','HSV_2_IGG',
 'ICALCIUM','IGA_URINE','IHC','INDIRECT_COOMB_S_TEST','INSULIN_RANDOM','IRON_PROFILE','KALA_AZAR','LDH','LDL_CHOL','LEUKEMIA_DLC','LH','LIPASE','LIPID','LUPUS_ANTICOAGULANT_DRVVT','MALARIA_ANTIGEN','MANTOUX_TEST','MF','MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM','MICROALBUMIN_URINE_24_HOURS','MP_CARD_TEST','MP_MICROSCOPIC','MPV','MYOGLOBIN','NLR','NT_PROBNP','OCCULT_BLOOD_STOOL','OGCT','P_D_W','P_LCR','PARATHYROID_HORMONE_PTH','PLATELET_INDICES','PRL','PROCALCITONIN','PROGESTERONE','PT_INR',
 'R_D_W_CV','R_D_W_SD','RA_QUALITATIVE','RA_QUANTITATIVE','RBC_INDICES','RETIC_COUNT','RFT','RUBELLA','RUBELLA_IGG','RUBELLA_IGM','SCRUB_TYPHUS','SERUM_CHOLINESTERASE','SERUM_IGA','SERUM_IGE','SERUM_IGG','SERUM_IGM','SERUM_ZINC','SKIN_TEST_FOR_LEPROSY','STOOL_REDUCING_SUBSTANCES','TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','TESTOSTERONE_FREE','TESTOSTERONE_TOTAL','THYROGLOBULIN_ANTIBODY_TGAB','THYROGLOBULIN_TG','TOXO_IGG','TOXO_IGM','TPHA','TRIGLYCERIDES','TROPONIN_I','TROPONIN_I_RAPID','TROPONIN_T','TYPHIDOT_ANTIBODIES','UCT','UIBC','UPCR','UPT',
 'URINE_BILE_PIGMENT','URINE_BILE_SALT','URINE_FOR_AFB_24_HOURS','URINE_FOR_CHYLE','URINE_FOR_CREATININE','URINE_FOR_ELISA_PREGNANCY','URINE_FOR_FUNGAL','URINE_FOR_KETONE','URINE_FOR_MICROALBUMIN','URINE_FOR_PROTEIN','URINE_SUGAR_FASTING','URINE_SUGAR_PP','URINE_SUGAR_RANDOM','WEIL_FELIX_TEST_SERUM','WIDAL_SLIDE','WIDAL_TUBE_METHOD'
]::TEXT[]);

DO $$ BEGIN
 IF (SELECT count(*) FROM expected_historical_incomplete_00075)<>178 THEN RAISE EXCEPTION 'EXPECTED_HISTORICAL_IDENTITY_SET_NOT_178'; END IF;
 IF EXISTS(SELECT 1 FROM expected_historical_incomplete_00075 e LEFT JOIN public.tests t ON t.code=e.code WHERE t.id IS NULL) THEN
  RAISE EXCEPTION 'EXPECTED_HISTORICAL_CANONICAL_IDENTITY_MISSING: %',(SELECT string_agg(e.code,', ' ORDER BY e.code) FROM expected_historical_incomplete_00075 e LEFT JOIN public.tests t ON t.code=e.code WHERE t.id IS NULL);
 END IF;
 IF EXISTS(SELECT code FROM public.tests WHERE code IN(SELECT code FROM expected_historical_incomplete_00075) GROUP BY code HAVING count(*)<>1) THEN RAISE EXCEPTION 'EXPECTED_HISTORICAL_CANONICAL_IDENTITY_AMBIGUOUS'; END IF;
END $$;

CREATE TEMP TABLE production_predicate_extras_00075 AS
SELECT t.id,t.code,t.name,t.reporting_model
FROM public.tests t
WHERE t.workflow_supported
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
 AND NOT EXISTS(SELECT 1 FROM expected_historical_incomplete_00075 e WHERE e.code=t.code);

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM production_predicate_extras_00075 WHERE code<>'BETA HCG') THEN
  RAISE EXCEPTION 'UNKNOWN_PRODUCTION_PREDICATE_EXTRA: %',(SELECT string_agg(code,', ' ORDER BY code) FROM production_predicate_extras_00075 WHERE code<>'BETA HCG');
 END IF;
 IF (SELECT count(*) FROM production_predicate_extras_00075 WHERE code='BETA HCG')>1 THEN RAISE EXCEPTION 'LEGACY_BETA_HCG_ALIAS_AMBIGUOUS'; END IF;
 IF EXISTS(SELECT 1 FROM production_predicate_extras_00075 WHERE code='BETA HCG') AND NOT EXISTS(
  SELECT 1 FROM public.tests legacy JOIN public.tests canonical ON canonical.code='BETA_HCG'
  WHERE legacy.code='BETA HCG' AND legacy.name='Beta HCG' AND legacy.workflow_supported
   AND legacy.is_active AND legacy.lifecycle_status='Active' AND legacy.reporting_model='NumericSingle'
   AND canonical.is_active AND canonical.lifecycle_status='Active' AND canonical.reporting_model='NumericSingle'
   AND lower('Beta HCG')=ANY(canonical.search_aliases)
   AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=legacy.id AND p.is_active AND p.lifecycle_status='Active')
   AND (SELECT count(*) FROM public.parameters p WHERE p.test_id=canonical.id AND p.code='HCG_VAL' AND p.name='Total Beta hCG (Quantitative)' AND p.value_type='Numeric' AND p.unit='mIU/mL' AND p.is_active AND p.lifecycle_status='Active')=1)
 THEN RAISE EXCEPTION 'LEGACY_BETA_HCG_ALIAS_RECONCILIATION_UNSAFE'; END IF;
END $$;

UPDATE public.tests legacy SET workflow_supported=FALSE,billing_enabled=FALSE,clinical_reporting_enabled=FALSE,
 configuration_notes=concat_ws(' ',legacy.configuration_notes,'00075 canonical reconciliation: legacy BETA HCG alias retained; generic workflow belongs to configured BETA_HCG.'),
 row_version=legacy.row_version+1,updated_at=now()
WHERE legacy.code='BETA HCG' AND legacy.workflow_supported
 AND EXISTS(SELECT 1 FROM public.tests canonical JOIN public.parameters p ON p.test_id=canonical.id AND p.code='HCG_VAL' AND p.name='Total Beta hCG (Quantitative)' AND p.value_type='Numeric' AND p.unit='mIU/mL' AND p.is_active AND p.lifecycle_status='Active' WHERE canonical.code='BETA_HCG');

CREATE TEMP TABLE historical_incomplete_00075 AS
SELECT t.id,t.code,t.name,t.reporting_model,
 COALESCE((SELECT (array_agg(s.reporting_model::TEXT ORDER BY s.source_number))[1]
           FROM public.catalogue_master_source_rows s
           WHERE s.canonical_test_id=t.id AND s.canonical_parameter_id IS NULL),t.reporting_model::TEXT) approved_reporting_model,
 COALESCE((SELECT (array_agg(s.source_type ORDER BY s.source_number))[1]
           FROM public.catalogue_master_source_rows s
           WHERE s.canonical_test_id=t.id AND s.canonical_parameter_id IS NULL),
          CASE WHEN t.reporting_model='NarrativeDocument' THEN 'Document' ELSE 'Single parameter' END) approved_test_type
FROM public.tests t
JOIN expected_historical_incomplete_00075 expected ON expected.code=t.code
WHERE t.workflow_supported
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active');

DO $$ BEGIN
 IF (SELECT count(*) FROM historical_incomplete_00075)+(SELECT count(*) FROM expected_historical_incomplete_00075 e JOIN public.tests t ON t.code=e.code WHERE EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'))<>178 THEN RAISE EXCEPTION 'HISTORICAL_IDENTITY_CLASSIFICATION_NOT_178'; END IF;
 IF EXISTS(SELECT 1 FROM public.tests t WHERE t.workflow_supported AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') AND NOT EXISTS(SELECT 1 FROM expected_historical_incomplete_00075 e WHERE e.code=t.code)) THEN
  RAISE EXCEPTION 'UNEXPECTED_HISTORICAL_INCOMPLETE_IDENTITY: %',(SELECT string_agg(t.code,', ' ORDER BY t.code) FROM public.tests t WHERE t.workflow_supported AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active') AND NOT EXISTS(SELECT 1 FROM expected_historical_incomplete_00075 e WHERE e.code=t.code));
 END IF;
END $$;

-- Explicit canonical equivalents provide approved units where present. A NULL
-- unit means the source has no approved unit and remains displayed as Not specified.
CREATE TEMP TABLE single_parameter_alias_evidence_00075(test_code TEXT PRIMARY KEY,source_test_code TEXT,source_parameter_code TEXT,source_note TEXT) ON COMMIT DROP;
INSERT INTO single_parameter_alias_evidence_00075 VALUES
 ('AST','LFT','SGOT','AST / SGOT canonical alias'),('ALT','LFT','SGPT','ALT / SGPT canonical alias'),
 ('ALP','LFT','ALP','LFT canonical component'),('CHOL_TOTAL','LIPID_PROFILE','CHOL','Lipid canonical component'),
 ('TRIGLYCERIDES','LIPID_PROFILE','TRIG','Lipid canonical component'),('HDL_CHOL','LIPID_PROFILE','HDL','Lipid canonical component'),
 ('LDL_CHOL','LIPID_PROFILE','LDL','Lipid canonical component'),('MPV','CBC','MPV','CBC canonical component'),
 ('P_D_W','CBC','PDW','CBC canonical component'),('EGFR','KFT','EGFR','KFT canonical calculated component');

-- NumericSingle is an approved result model. Materialize exactly one parameter;
-- this does not activate billing or invent a range, method, instrument, or unit.
INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
SELECT h.id,CASE WHEN length(h.code)<=45 THEN h.code||'_RESULT' ELSE 'RESULT' END,h.name,'Numeric',src.unit,1,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE
FROM historical_incomplete_00075 h
LEFT JOIN single_parameter_alias_evidence_00075 a ON a.test_code=h.code
LEFT JOIN public.tests st ON st.code=a.source_test_code
LEFT JOIN public.parameters src ON src.test_id=st.id AND src.code=a.source_parameter_code AND src.is_active AND src.lifecycle_status='Active'
WHERE h.approved_reporting_model='NumericSingle' AND h.approved_test_type='Single parameter'
ON CONFLICT(test_id,code) DO NOTHING;

-- eGFR has approved existing KFT parameter/calculation evidence even though its
-- standalone historical workflow was mislabeled NarrativeDocument.
INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
SELECT target.id,'EGFR_RESULT','Estimated Glomerular Filtration Rate',source.value_type,source.unit,1,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE
FROM public.tests target JOIN public.tests owner ON owner.code='KFT' JOIN public.parameters source ON source.test_id=owner.id AND source.code='EGFR'
WHERE target.code='EGFR' AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=target.id AND p.is_active AND p.lifecycle_status='Active')
ON CONFLICT(test_id,code) DO NOTHING;
UPDATE public.tests SET reporting_model='NumericSingle',workflow_type='Routine',reporting_type='InHouse',updated_at=now() WHERE code='EGFR';

-- Qualitative semantics are approved for these sixteen identities. The result
-- parameter is safe to create; an option set is assigned only for the three
-- identities with an explicit canonical normal vocabulary in approved evidence.
CREATE TEMP TABLE qualitative_inventory_00075(code TEXT PRIMARY KEY) ON COMMIT DROP;
INSERT INTO qualitative_inventory_00075 VALUES
 ('MP_MICROSCOPIC'),('GCT'),('THYROGLOBULIN_ANTIBODY_TGAB'),('ANTI_NUCLEAR_ANTIBODY_ANA_BY_ELISA'),
 ('HBSAG_ELISA'),('HAV_IGG'),('HAV_IGM'),('HAV_TOTAL_AB'),('HIV_ELISA_I_II'),('KALA_AZAR'),
 ('OCCULT_BLOOD_STOOL'),('TPHA'),('TROPONIN_I_RAPID'),('URINE_FOR_ELISA_PREGNANCY'),('UPT'),('CEA_CARCINOEMBRYONIC_ANTIGEN');
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
SELECT t.id,CASE WHEN length(t.code)<=45 THEN t.code||'_RESULT' ELSE 'RESULT' END,t.name,'Select',1,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE
FROM qualitative_inventory_00075 q JOIN public.tests t ON t.code=q.code
WHERE NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
ON CONFLICT(test_id,code) DO NOTHING;

UPDATE public.parameters p SET option_set_id=os.id,row_version=p.row_version+1,updated_at=now()
FROM public.tests t,public.catalogue_option_sets os
WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'
 AND ((t.code='HBSAG_ELISA' AND os.code='REACTIVE_NON_REACTIVE')
   OR (t.code='HIV_ELISA_I_II' AND os.code='REACTIVE_NON_REACTIVE')
   OR (t.code='OCCULT_BLOOD_STOOL' AND os.code='POSITIVE_NEGATIVE'));

INSERT INTO public.catalogue_result_structure_reconciliation(test_id,historical_zero_parameter_inventory,source_evidence,action_code,parameters_materialized,final_readiness,notes)
SELECT h.id,TRUE,
 CASE WHEN h.code='EGFR' THEN 'Existing canonical KFT.EGFR parameter and approved calculation structure.'
      WHEN h.approved_reporting_model='NumericSingle' AND h.approved_test_type='Single parameter' THEN concat('Operator TM256 reporting model NumericSingle',CASE WHEN a.source_note IS NOT NULL THEN '; '||a.source_note ELSE '; optional unit/range not specified' END)
      WHEN q.code IS NOT NULL AND h.code IN('HBSAG_ELISA','HIV_ELISA_I_II','OCCULT_BLOOD_STOOL') THEN 'Existing canonical qualitative result and approved normal vocabulary.'
      WHEN q.code IS NOT NULL THEN 'Approved qualitative reporting model; no approved option vocabulary located.'
      WHEN h.approved_test_type='Document' OR h.reporting_model='NarrativeDocument' THEN 'Existing operator/document workflow classification; no silent reclassification.'
      ELSE 'All approved sources exhausted; approved child/result structure absent.' END,
 CASE WHEN h.code='EGFR' THEN 'DOCUMENT_RECLASSIFIED_FROM_APPROVED_EVIDENCE'
      WHEN h.approved_reporting_model='NumericSingle' AND h.approved_test_type='Single parameter' THEN 'MATERIALIZED_NUMERIC_SINGLE'
      WHEN h.code IN('HBSAG_ELISA','HIV_ELISA_I_II','OCCULT_BLOOD_STOOL') THEN 'MATERIALIZED_QUALITATIVE_WITH_OPTIONS'
      WHEN q.code IS NOT NULL THEN 'OPTION_SET_REQUIRES_OPERATOR_SELECTION'
      WHEN h.approved_test_type='Document' OR h.reporting_model='NarrativeDocument' THEN 'DOCUMENT_WORKFLOW_RETAINED'
      ELSE 'RESULT_STRUCTURE_REQUIRES_OPERATOR_INPUT' END,
 (SELECT count(*) FROM public.parameters p WHERE p.test_id=h.id AND p.is_active AND p.lifecycle_status='Active'),
 public.catalogue_test_result_readiness(h.id),
 CASE WHEN public.catalogue_test_result_readiness(h.id)='Ready' THEN 'Approved source-backed result structure is ready.'
      WHEN q.code IS NOT NULL THEN 'OPTION_SET_REQUIRES_OPERATOR_SELECTION'
      WHEN h.approved_test_type='Document' OR h.reporting_model='NarrativeDocument' THEN 'Document/text workflow retained pending explicit operator correction.'
      ELSE 'RESULT_STRUCTURE_REQUIRES_OPERATOR_INPUT' END
FROM historical_incomplete_00075 h LEFT JOIN single_parameter_alias_evidence_00075 a ON a.test_code=h.code LEFT JOIN qualitative_inventory_00075 q ON q.code=h.code;

INSERT INTO public.catalogue_result_structure_reconciliation(test_id,historical_zero_parameter_inventory,source_evidence,action_code,parameters_materialized,final_readiness,notes)
SELECT t.id,FALSE,'Production baseline already contained an active canonical result structure.',
 'ALREADY_CONFIGURED_PRODUCTION_BASELINE',
 (SELECT count(*) FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active'),
 public.catalogue_test_result_readiness(t.id),'Existing active canonical result structure retained idempotently.'
FROM expected_historical_incomplete_00075 e JOIN public.tests t ON t.code=e.code
WHERE EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
ON CONFLICT(test_id) DO NOTHING;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.catalogue_result_structure_reconciliation)<>178 THEN RAISE EXCEPTION 'RESULT_STRUCTURE_RECONCILIATION_COUNT_INVALID'; END IF;
END $$;

-- ============================================================================
-- FINAL OPERATOR-APPROVED 33 RESULT STRUCTURES + 13 QUALITATIVE DEFINITIONS
-- Source: approved-data/final_33_result_structures_13_qualitative.md
-- SHA-256: c90997ff59a885393338f6eadf171cd61f7615f6a5ec4fe5588272179072f591
-- Context-, lot-, reagent- and gestation-specific statements remain reference
-- text/interpretation metadata. A Calculated classification does not manufacture
-- a formula where the source did not supply one.
-- ============================================================================
CREATE TEMP TABLE final_structure_parameters_00075(
 test_code TEXT, parameter_code TEXT, parameter_name TEXT,
 value_type public.parameter_value_type_enum, unit TEXT, display_order INT,
 options JSONB, reference_text TEXT, interpretation JSONB,
 PRIMARY KEY(test_code,parameter_code)
) ON COMMIT DROP;

INSERT INTO final_structure_parameters_00075 VALUES
('ABG','PH','pH','Numeric',NULL,1,NULL,'7.35 - 7.45',NULL),
('ABG','PCO2','pCO₂','Numeric','mmHg',2,NULL,'35 - 45',NULL),
('ABG','PO2','pO₂','Numeric','mmHg',3,NULL,'80 - 100',NULL),
('ABG','HCO3','HCO₃⁻','Calculated','mmol/L',4,NULL,'22 - 26',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('ABG','BASE_EXCESS','Base Excess (BE)','Numeric','mmol/L',5,NULL,'-2 to +2',NULL),
('ABG','SAO2','SaO₂','Numeric','%',6,NULL,'95 - 100',NULL),
('ABG','FIO2','FiO₂ (Input)','Numeric','%',7,NULL,'Clinical context',jsonb_build_object('reference_semantics','Context-specific')),
('ABS_DLC','ANC','Absolute Neutrophil Count (ANC)','Numeric','/µL',1,NULL,'2,000 - 7,000 /µL (2.0-7.0 ×10⁹/L)',jsonb_build_object('alternate_unit','10^9/L')),
('ABS_DLC','ALC','Absolute Lymphocyte Count (ALC)','Numeric','/µL',2,NULL,'1,000 - 3,000 /µL (1.0-3.0 ×10⁹/L)',jsonb_build_object('alternate_unit','10^9/L')),
('ABS_DLC','AMC','Absolute Monocyte Count (AMC)','Numeric','/µL',3,NULL,'200 - 1,000 /µL (0.2-1.0 ×10⁹/L)',jsonb_build_object('alternate_unit','10^9/L')),
('ABS_DLC','AEC','Absolute Eosinophil Count (AEC)','Numeric','/µL',4,NULL,'20 - 500 /µL (0.02-0.5 ×10⁹/L)',jsonb_build_object('alternate_unit','10^9/L')),
('ABS_DLC','ABC','Absolute Basophil Count (ABC)','Numeric','/µL',5,NULL,'0 - 100 /µL (0.0-0.1 ×10⁹/L)',jsonb_build_object('alternate_unit','10^9/L')),
('ADA','FLUID_TYPE','Fluid Type','Select',NULL,1,'["Pleural","Ascitic","CSF","Serum"]','Pleural / Ascitic / CSF / Serum',NULL),
('ADA','ADA_LEVEL','ADA Level','Numeric','U/L',2,NULL,'Serum: < 15; Pleural: < 30 (Suspicious > 40 U/L)',jsonb_build_object('reference_semantics','Context-specific by fluid type')),
('APTT','PATIENT_TIME','Patient Time','Numeric','Seconds',1,NULL,'26.0 - 36.0 sec',NULL),
('APTT','CONTROL_TIME','Control Time','Numeric','Seconds',2,NULL,'Lot specific',jsonb_build_object('reference_semantics','Lot/Reagent-specific')),
('APTT','RATIO','Ratio','Numeric','Ratio',3,NULL,'0.8 - 1.2',NULL),
('BILE_ACID','TOTAL_BILE_ACIDS','Total Bile Acids','Numeric','µmol/L',1,NULL,'Fasting: 0.0 - 10.0 µmol/L',NULL),
('BILIRUBIN_TD','TOTAL_BILIRUBIN','Total Bilirubin','Numeric','mg/dL',1,NULL,'0.2 - 1.2 mg/dL',NULL),
('BILIRUBIN_TD','DIRECT_BILIRUBIN','Direct (Conjugated) Bilirubin','Numeric','mg/dL',2,NULL,'0.0 - 0.3 mg/dL',NULL),
('BILIRUBIN_TD','INDIRECT_BILIRUBIN','Indirect (Unconjugated) Bilirubin','Calculated','mg/dL',3,NULL,'0.2 - 0.9 mg/dL',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('BLOOD_GROUP_RH','ABO','ABO Blood Group','Select',NULL,1,'["A","B","AB","O"]',NULL,NULL),
('BLOOD_GROUP_RH','RH_D','Rh (D) Factor','Select',NULL,2,'["Positive","Negative"]',NULL,NULL),
('BT_CT','BLEEDING_TIME','Bleeding Time (BT)','Text','Min:Sec',1,NULL,'Duke: 1-5 min / Ivy: 2-9 min',jsonb_build_object('control','Time')),
('BT_CT','CLOTTING_TIME','Clotting Time (CT)','Text','Min:Sec',2,NULL,'Lee-White: 5-11 min / Capillary: 3-8 min',jsonb_build_object('control','Time')),
('BT_CT','METHOD_USED','Method Used','Text',NULL,3,NULL,'e.g., Duke / Capillary Tube',NULL),
('COAG_PROFILE','PT','Prothrombin Time (PT)','Numeric','Seconds',1,NULL,'11.0 - 15.0 sec',NULL),
('COAG_PROFILE','PT_CONTROL','PT Control','Numeric','Seconds',2,NULL,'Lot specific',jsonb_build_object('reference_semantics','Lot/Reagent-specific')),
('COAG_PROFILE','INR','INR','Calculated',NULL,3,NULL,'0.8 - 1.2 (Therapeutic: 2.0-3.0)',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('COAG_PROFILE','APTT_PATIENT','APTT Patient','Numeric','Seconds',4,NULL,'26.0 - 36.0 sec',NULL),
('COAG_PROFILE','APTT_CONTROL','APTT Control','Numeric','Seconds',5,NULL,'Lot specific',jsonb_build_object('reference_semantics','Lot/Reagent-specific')),
('COAG_PROFILE','FIBRINOGEN','Fibrinogen','Numeric','mg/dL',6,NULL,'200 - 400 mg/dL',NULL),
('COAG_PROFILE','PLATELET_COUNT','Platelet Count','Numeric','/µL',7,NULL,'150,000 - 450,000 /µL',NULL),
('DENGUE_IGM_IGG_PANEL','DENGUE_IGM','Dengue IgM Antibody','Select','Qualitative or Ratio',1,'["Negative","Positive","Equivocal"]','< 0.90 Negative; > 1.10 Positive',jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('DENGUE_IGM_IGG_PANEL','DENGUE_IGG','Dengue IgG Antibody','Select','Qualitative or Ratio',2,'["Negative","Positive","Equivocal"]','< 0.90 Negative; > 1.10 Positive',jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('DENGUE_PANEL','DENGUE_NS1','Dengue NS1 Antigen','Select',NULL,1,'["Negative","Positive"]',NULL,NULL),
('DENGUE_PANEL','DENGUE_IGM','Dengue IgM Antibody','Select',NULL,2,'["Negative","Positive"]',NULL,NULL),
('DENGUE_PANEL','DENGUE_IGG','Dengue IgG Antibody','Select',NULL,3,'["Negative","Positive"]',NULL,NULL),
('DLC_3PART','GRANULOCYTES','Granulocytes %','Numeric','%',1,NULL,'50.0 - 70.0%',NULL),
('DLC_3PART','LYMPHOCYTES','Lymphocytes %','Numeric','%',2,NULL,'20.0 - 40.0%',NULL),
('DLC_3PART','MID_CELLS','Mid cells (Monocytes/Eos/Baso) %','Numeric','%',3,NULL,'3.0 - 12.0%',NULL),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','GESTATIONAL_AGE','Gestational Age (Ultrasound)','Text','Weeks/Days',1,NULL,'11w 0d to 13w 6d',jsonb_build_object('control','Time/Duration')),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','FREE_BETA_HCG','Free Beta hCG','Numeric','mIU/mL',2,NULL,'Gestation-specific',jsonb_build_object('reference_semantics','Gestation-specific')),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','FREE_BETA_HCG_MOM','Free Beta hCG MoM','Numeric','MoM',3,NULL,'Corrected MoM (~1.0)',NULL),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','PAPP_A','PAPP-A','Numeric','mIU/L',4,NULL,'Gestation-specific',jsonb_build_object('reference_semantics','Gestation-specific')),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','PAPP_A_MOM','PAPP-A MoM','Numeric','MoM',5,NULL,'Corrected MoM (~1.0)',NULL),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','NT','Nuchal Translucency (NT)','Numeric','mm',6,NULL,'< 3.0 mm',NULL),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','T21_RISK','T21 (Down Syndrome) Risk Cut-off','Select',NULL,7,'["Low Risk (< 1:250)","High Risk (> 1:250)"]',NULL,jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Ratio'))),
('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','T18_13_RISK','T18/13 Risk Cut-off','Select',NULL,8,'["Low Risk","High Risk"]',NULL,jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Ratio'))),
('GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY','FASTING_GLUCOSE','Fasting Blood Glucose','Numeric','mg/dL',1,NULL,'< 92 mg/dL (IADPSG)',NULL),
('GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY','GLUCOSE_1H','1-Hour Post 75g Glucose','Numeric','mg/dL',2,NULL,'< 180 mg/dL',NULL),
('GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY','GLUCOSE_2H','2-Hour Post 75g Glucose','Numeric','mg/dL',3,NULL,'< 153 mg/dL',NULL),
('GTT','FASTING_GLUCOSE','Fasting Glucose','Numeric','mg/dL',1,NULL,'70 - 99 mg/dL',NULL),
('GTT','GLUCOSE_30M','30-Minute Glucose','Numeric','mg/dL',2,NULL,'For curve mapping',jsonb_build_object('reference_semantics','Context-specific')),
('GTT','GLUCOSE_60M','60-Minute Glucose','Numeric','mg/dL',3,NULL,'< 200 mg/dL',NULL),
('GTT','GLUCOSE_90M','90-Minute Glucose','Numeric','mg/dL',4,NULL,'For curve mapping',jsonb_build_object('reference_semantics','Context-specific')),
('GTT','GLUCOSE_120M','120-Minute (2-Hr) Glucose','Numeric','mg/dL',5,NULL,'< 140 Normal; 140-199 IGT; ≥ 200 Diabetic',NULL),
('HAV_PANEL','ANTI_HAV_IGM','Anti-HAV IgM','Select','S/CO or Index',1,'["Non-Reactive","Reactive"]','Acute marker',jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('HAV_PANEL','ANTI_HAV_IGG_TOTAL','Anti-HAV IgG / Total','Select','S/CO or Index',2,'["Non-Reactive","Reactive"]','Past immunity',jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('HIV_CARD_TEST','HIV_1_BAND','HIV-1 Antibody Band','Select',NULL,1,'["Non-Reactive","Reactive"]',NULL,NULL),
('HIV_CARD_TEST','HIV_2_BAND','HIV-2 Antibody Band','Select',NULL,2,'["Non-Reactive","Reactive"]',NULL,NULL),
('HIV_CARD_TEST','FINAL_INTERPRETATION','Final Result Interpretation','Select',NULL,3,'["Non-Reactive","Reactive","Invalid"]',NULL,NULL),
('HPLC','HB_A0','Hb A0','Numeric','%',1,NULL,'95.0 - 97.5%',NULL),
('HPLC','HB_A2','Hb A2','Numeric','%',2,NULL,'1.5 - 3.5% (High >3.8% suggests β-thal trait)',NULL),
('HPLC','HB_F','Hb F','Numeric','%',3,NULL,'< 1.0% (Adults)',NULL),
('HPLC','VARIANT_WINDOW','Variant Window (Hb S/D/E/C)','Text','%',4,NULL,'Not Detected (0%)',jsonb_build_object('accepted_result_modes',jsonb_build_array('Numeric','Text'))),
('HPLC','IMPRESSION','Impression / Interpretation','Text',NULL,5,NULL,'Descriptive pathological review',jsonb_build_object('control','Text Multi-line')),
('IRON_PROFILE','SERUM_IRON','Serum Iron','Numeric','µg/dL',1,NULL,'60 - 170 µg/dL',NULL),
('IRON_PROFILE','TIBC','Total Iron Binding Capacity (TIBC)','Numeric','µg/dL',2,NULL,'240 - 450 µg/dL',NULL),
('IRON_PROFILE','TRANSFERRIN_SAT','Transferrin Saturation (%)','Calculated','%',3,NULL,'20 - 50% ([Iron/TIBC]×100)',jsonb_build_object('formula_status','Formula explicitly supplied: [Iron/TIBC]×100')),
('IRON_PROFILE','FERRITIN','Serum Ferritin','Numeric','ng/mL',4,NULL,'Male: 30-400; Female: 15-150 ng/mL',NULL),
('LEUKEMIA_DLC','BLASTS','Blast Cells %','Numeric','%',1,NULL,'0%',NULL),
('LEUKEMIA_DLC','PROMYELOCYTES','Promyelocytes %','Numeric','%',2,NULL,'0%',NULL),
('LEUKEMIA_DLC','MYELOCYTES','Myelocytes %','Numeric','%',3,NULL,'0%',NULL),
('LEUKEMIA_DLC','METAMYELOCYTES','Metamyelocytes %','Numeric','%',4,NULL,'0%',NULL),
('LEUKEMIA_DLC','NEUTROPHILS','Neutrophils (Band/Seg) %','Numeric','%',5,NULL,'40 - 70%',NULL),
('LEUKEMIA_DLC','LYMPHOCYTES','Lymphocytes %','Numeric','%',6,NULL,'20 - 40%',NULL),
('LEUKEMIA_DLC','MONOCYTES','Monocytes %','Numeric','%',7,NULL,'2 - 8%',NULL),
('LEUKEMIA_DLC','EOSINOPHILS','Eosinophils %','Numeric','%',8,NULL,'1 - 6%',NULL),
('LEUKEMIA_DLC','BASOPHILS','Basophils %','Numeric','%',9,NULL,'0 - 1%',NULL),
('LEUKEMIA_DLC','PATHOLOGIST_IMPRESSION','Pathologist Impression','Text',NULL,10,NULL,'Smear review notes / Flow cytometry recommendation',jsonb_build_object('control','Text Multi-line')),
('LUPUS_ANTICOAGULANT_DRVVT','DRVVT_SCREEN','dRVVT Screen Time','Numeric','Seconds',1,NULL,'30.0 - 45.0 sec',NULL),
('LUPUS_ANTICOAGULANT_DRVVT','DRVVT_CONFIRM','dRVVT Confirm Time','Numeric','Seconds',2,NULL,'30.0 - 40.0 sec',NULL),
('LUPUS_ANTICOAGULANT_DRVVT','DRVVT_RATIO','dRVVT Screen/Confirm Ratio','Calculated','Ratio',3,NULL,'Normal < 1.20; Equivocal 1.20-1.37; Positive > 1.38',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('LUPUS_ANTICOAGULANT_DRVVT','INTERPRETATION','Interpretation','Select',NULL,4,'["Negative","Equivocal","Positive"]',NULL,NULL),
('MALARIA_ANTIGEN','PF_HRP2','Plasmodium falciparum (Pf - HRP2)','Select',NULL,1,'["Negative","Positive"]',NULL,NULL),
('MALARIA_ANTIGEN','PAN_LDH','Pan (Pv/Pm/Po - LDH / Aldolase)','Select',NULL,2,'["Negative","Positive"]',NULL,NULL),
('MALARIA_ANTIGEN','INTERPRETATION','Interpretation','Select',NULL,3,'["Negative for Malaria Parasite","Positive for P. falciparum","Positive for Non-falciparum (P. vivax/ovale/malariae)","Mixed Infection"]',NULL,NULL),
('MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM','URINE_MICROALBUMIN','Urine Microalbumin','Numeric','mg/L',1,NULL,'0 - 20 mg/L',NULL),
('MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM','URINE_CREATININE','Urine Creatinine','Numeric','mg/dL',2,NULL,'20 - 300 mg/dL',jsonb_build_object('alternate_unit','g/L')),
('MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM','ACR','Albumin-to-Creatinine Ratio (ACR)','Calculated','mg/g',3,NULL,'Normal < 30; Microalbuminuria 30-300; Clinical > 300 mg/g',jsonb_build_object('alternate_unit','mg/mmol','formula_status','Operator-approved calculated designation; formula not supplied')),
('MICROALBUMIN_URINE_24_HOURS','TOTAL_VOLUME','Total 24h Urine Volume','Numeric','mL',1,NULL,'800 - 2000 mL',NULL),
('MICROALBUMIN_URINE_24_HOURS','ALBUMIN_CONCENTRATION','Urine Albumin Concentration','Numeric','mg/L',2,NULL,'Contextual',jsonb_build_object('reference_semantics','Context-specific')),
('MICROALBUMIN_URINE_24_HOURS','ALBUMIN_EXCRETION','Total 24-Hour Albumin Excretion','Calculated','mg/24 hours',3,NULL,'Normal < 30; Microalbuminuria 30-300; Macroalbuminuria > 300 mg/24h',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('MP_CARD_TEST','PF_AG','P. falciparum Ag','Select',NULL,1,'["Negative","Positive"]',NULL,NULL),
('MP_CARD_TEST','PV_AG','P. vivax Ag','Select',NULL,2,'["Negative","Positive"]',NULL,NULL),
('PLATELET_INDICES','PLATELET_COUNT','Platelet Count','Numeric','10³/µL',1,NULL,'150 - 450 ×10³/µL',NULL),
('PLATELET_INDICES','MPV','Mean Platelet Volume (MPV)','Numeric','fL',2,NULL,'7.5 - 11.5 fL',NULL),
('PLATELET_INDICES','PDW','Platelet Distribution Width (PDW)','Numeric','fL',3,NULL,'9.0 - 17.0 fL',jsonb_build_object('alternate_unit','%')),
('PLATELET_INDICES','PCT','Plateletcrit (PCT)','Numeric','%',4,NULL,'0.15 - 0.40%',NULL),
('PT_INR','PATIENT_PT','Patient Prothrombin Time','Numeric','Seconds',1,NULL,'11.0 - 14.5 sec',NULL),
('PT_INR','CONTROL_TIME','Control Time','Numeric','Seconds',2,NULL,'Lot specific (e.g., 12.0 sec)',jsonb_build_object('reference_semantics','Lot/Reagent-specific')),
('PT_INR','INR','International Normalized Ratio (INR)','Calculated','Ratio',3,NULL,'Normal 0.8 - 1.2; Warfarin Target 2.0 - 3.0',jsonb_build_object('formula_status','Operator-approved calculated designation; formula not supplied')),
('PT_INR','ISI','ISI Value (Instrument parameter)','Numeric',NULL,4,NULL,'Lot/reagent specific (~1.0)',jsonb_build_object('reference_semantics','Lot/Reagent-specific')),
('RBC_INDICES','MCV','Mean Corpuscular Volume (MCV)','Numeric','fL',1,NULL,'80.0 - 100.0 fL',NULL),
('RBC_INDICES','MCH','Mean Corpuscular Hemoglobin (MCH)','Numeric','pg',2,NULL,'27.0 - 33.0 pg',NULL),
('RBC_INDICES','MCHC','MCH Concentration (MCHC)','Numeric','g/dL',3,NULL,'32.0 - 36.0 g/dL',NULL),
('RBC_INDICES','RDW_CV','Red Cell Distribution Width (RDW-CV)','Numeric','%',4,NULL,'11.5 - 14.5%',NULL),
('RUBELLA','RUBELLA_IGM','Rubella IgM Antibody','Numeric','AU/mL or Index',1,NULL,'< 0.8 Negative; 0.8-1.0 Equivocal; > 1.0 Positive',jsonb_build_object('accepted_result_modes',jsonb_build_array('Numeric','Dropdown'))),
('RUBELLA','RUBELLA_IGG','Rubella IgG Antibody','Numeric','IU/mL or Index',2,NULL,'< 10 IU/mL Non-immune; ≥ 10 IU/mL Immune',jsonb_build_object('accepted_result_modes',jsonb_build_array('Numeric','Dropdown'))),
('SCRUB_TYPHUS','SCRUB_IGM','Scrub Typhus IgM Antibody','Select','Qualitative / Index',1,'["Negative","Positive","Equivocal"]',NULL,jsonb_build_object('accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('SCRUB_TYPHUS','SCRUB_IGG','Scrub Typhus IgG Antibody','Select','Qualitative / Index',2,'["Negative","Positive"]','If combo',jsonb_build_object('conditional','if combo','accepted_result_modes',jsonb_build_array('Dropdown','Index'))),
('TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','NIL','Nil (Negative Control)','Numeric','IU/mL',1,NULL,'≤ 8.0 IU/mL',NULL),
('TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','TB_AG_MINUS_NIL','TB Antigen Minus Nil','Numeric','IU/mL',2,NULL,'≥ 0.35 IU/mL and ≥25% of Nil = Positive',NULL),
('TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','MITOGEN_MINUS_NIL','Mitogen Minus Nil (Positive Control)','Numeric','IU/mL',3,NULL,'≥ 0.5 IU/mL (Valid)',NULL),
('TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','FINAL_RESULT','Final Result','Select',NULL,4,'["Negative","Positive","Indeterminate"]',NULL,NULL),
('TYPHIDOT_ANTIBODIES','TYPHI_IGM','S. typhi IgM (Specific for Acute Phase)','Select',NULL,1,'["Non-Reactive","Reactive"]',NULL,NULL),
('TYPHIDOT_ANTIBODIES','TYPHI_IGG','S. typhi IgG (Past / Chronic / Anamnestic)','Select',NULL,2,'["Non-Reactive","Reactive"]',NULL,NULL),
('WEIL_FELIX_TEST_SERUM','OX_19','Proteus OX-19 Titer','Select','Titer Dilution',1,'["< 1:20","1:20","1:40","1:80","1:160","1:320","> 1:320"]','Normal <1:80; Diagnostic / Significant ≥1:160',NULL),
('WEIL_FELIX_TEST_SERUM','OX_2','Proteus OX-2 Titer','Select','Titer Dilution',2,'["< 1:20","1:20","1:40","1:80","1:160","1:320","> 1:320"]','Normal <1:80; Diagnostic / Significant ≥1:160',NULL),
('WEIL_FELIX_TEST_SERUM','OX_K','Proteus OX-K Titer','Select','Titer Dilution',3,'["< 1:20","1:20","1:40","1:80","1:160","1:320","> 1:320"]','Normal <1:80; Diagnostic / Significant ≥1:160',NULL),
('WEIL_FELIX_TEST_SERUM','INTERPRETATION','Interpretation','Text',NULL,4,NULL,'OX-19/OX-2 (Epidemic/Endemic/Spotted Fevers); OX-K (Scrub Typhus)',NULL);

-- Apply exact specimens without changing unrelated workflow classification.
UPDATE public.tests t SET sample_type=s.specimen,updated_at=now()
FROM (VALUES
 ('ABG','Heparinized Arterial Whole Blood'),('ABS_DLC','EDTA Whole Blood'),('ADA','Body Fluids (Pleural / Ascitic / CSF / Serum)'),('APTT','Sodium Citrate Plasma (3.2%)'),('BILE_ACID','Serum (Fasting preferred)'),('BILIRUBIN_TD','Serum'),('BLOOD_GROUP_RH','EDTA Whole Blood'),('BT_CT','Capillary / Whole Blood'),('COAG_PROFILE','Sodium Citrate Plasma (3.2%) + EDTA'),('DENGUE_IGM_IGG_PANEL','Serum'),('DENGUE_PANEL','Serum'),('DLC_3PART','EDTA Whole Blood'),('DOUBLE_MARKER_MATERNAL_SCREEN_2_TESTS','Serum'),('GLUCOSE_TOLERANCE_TEST_GTT_PREGNANCY','Fluoride Plasma'),('GTT','Fluoride Plasma'),('HAV_PANEL','Serum'),('HIV_CARD_TEST','Serum / Plasma / Whole Blood'),('HPLC','EDTA Whole Blood'),('IRON_PROFILE','Serum (Fasting)'),('LEUKEMIA_DLC','EDTA Whole Blood / Smear'),('LUPUS_ANTICOAGULANT_DRVVT','Citrated Platelet-Poor Plasma'),('MALARIA_ANTIGEN','EDTA Whole Blood'),('MICROALBUMIN_CREATININE_RATIO_URINE_RANDOM','Random Spot Urine'),('MICROALBUMIN_URINE_24_HOURS','24-Hour Urine Collection'),('MP_CARD_TEST','EDTA Whole Blood'),('PLATELET_INDICES','EDTA Whole Blood'),('PT_INR','Sodium Citrate Plasma (3.2%)'),('RBC_INDICES','EDTA Whole Blood'),('RUBELLA','Serum'),('SCRUB_TYPHUS','Serum'),('TB_GOLD_INTERFERON_GAMMA_RELEASE_ASSAY','Specialized IGRA Blood Tubes (Nil, TB Ag, Mitogen)'),('TYPHIDOT_ANTIBODIES','Serum'),('WEIL_FELIX_TEST_SERUM','Serum')
) s(test_code,specimen) WHERE t.code=s.test_code;

-- PT/INR is an explicitly supplied generic clinical structure and a required
-- Coagulation Profile component; retire its obsolete billing-only classification.
UPDATE public.tests SET reporting_type='InHouse',workflow_supported=TRUE,clinical_reporting_enabled=TRUE,updated_at=now()
WHERE code='PT_INR';

INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,interpretation_config,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
SELECT t.id,s.parameter_code,s.parameter_name,s.value_type,s.unit,s.options,s.interpretation,s.display_order,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE
FROM final_structure_parameters_00075 s JOIN public.tests t ON t.code=s.test_code
ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,
 options=EXCLUDED.options,interpretation_config=EXCLUDED.interpretation_config,display_order=EXCLUDED.display_order,
 is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',unit_validation_required=FALSE,
 range_validation_required=FALSE,method_validation_required=FALSE,row_version=public.parameters.row_version+1,updated_at=now();

UPDATE public.parameters p SET clinical_class='Calculated'
FROM public.tests t WHERE p.test_id=t.id AND p.value_type='Calculated'
 AND t.code IN(SELECT DISTINCT test_code FROM final_structure_parameters_00075);

-- The source explicitly supplies Iron/TIBC×100 but no rounding rule. Preserve
-- it as a governed candidate; it is never executed client-side or presented as
-- an approved server formula until the normal approval RPC receives rounding.
INSERT INTO public.catalogue_calculation_definitions(identifier,parameter_code,server_authoritative,implementation_note,is_active)
VALUES('IRON_TRANSFERRIN_SAT_V1','TRANSFERRIN_SAT',FALSE,'Operator formula [Iron/TIBC]×100 captured; server implementation and rounding approval required.',TRUE)
ON CONFLICT(identifier) DO UPDATE SET implementation_note=EXCLUDED.implementation_note,is_active=TRUE;
UPDATE public.parameters p SET formula='(SERUM_IRON / TIBC) * 100',formula_dependencies=ARRAY['SERUM_IRON','TIBC'],
 calculation_identifier='IRON_TRANSFERRIN_SAT_V1',row_version=p.row_version+1,updated_at=now()
FROM public.tests t WHERE p.test_id=t.id AND t.code='IRON_PROFILE' AND p.code='TRANSFERRIN_SAT';
INSERT INTO public.clinical_calculation_formula_versions(formula_identifier,formula_version,formula_key,formula_expression,output_parameter_id,output_parameter_code,output_unit,calculation_mode,lifecycle_status,source_provenance,definition_hash)
SELECT 'IRON_TRANSFERRIN_SAT_V1',1,'IRON_TRANSFERRIN_SAT','(SERUM_IRON / TIBC) * 100',p.id,p.code,'%',
 'Result','Candidate','Final operator clinical source supplied formula; rounding rule not supplied.',encode(extensions.digest('IRON_TRANSFERRIN_SAT_V1|1|(SERUM_IRON/TIBC)*100|%','sha256'),'hex')
FROM public.tests t JOIN public.parameters p ON p.test_id=t.id AND p.code='TRANSFERRIN_SAT' WHERE t.code='IRON_PROFILE'
ON CONFLICT(formula_identifier,formula_version) DO NOTHING;
INSERT INTO public.clinical_calculation_formula_inputs(formula_version_id,input_key,parameter_id,parameter_code,canonical_unit,ordinal)
SELECT f.id,m.input_key,p.id,p.code,p.unit,m.ordinal FROM public.clinical_calculation_formula_versions f
JOIN (VALUES('IRON', 'SERUM_IRON',1),('TIBC','TIBC',2)) m(input_key,parameter_code,ordinal) ON TRUE
JOIN public.tests t ON t.code='IRON_PROFILE' JOIN public.parameters p ON p.test_id=t.id AND p.code=m.parameter_code
WHERE f.formula_identifier='IRON_TRANSFERRIN_SAT_V1' AND f.formula_version=1
ON CONFLICT(formula_version_id,input_key) DO NOTHING;

-- Reusable option sets are keyed by their exact ordered vocabulary, so identical
-- vocabularies are reused and no test receives an unrelated option set.
WITH vocabularies AS (SELECT DISTINCT options FROM final_structure_parameters_00075 WHERE options IS NOT NULL)
INSERT INTO public.catalogue_option_sets(code,name,lifecycle_status)
SELECT 'OPERATOR_'||upper(substr(md5(options::TEXT),1,20)),array_to_string(ARRAY(SELECT jsonb_array_elements_text(options)),' / '),'Active' FROM vocabularies v
WHERE NOT EXISTS(SELECT 1 FROM public.catalogue_option_sets os WHERE lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(v.options)),' / '))) AND os.lifecycle_status<>'Archived')
ON CONFLICT(code) DO UPDATE SET lifecycle_status='Active',updated_at=now();

INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order)
SELECT os.id,upper(substr(md5(v.label),1,24)),v.label,v.ord::INT
FROM (SELECT DISTINCT options FROM final_structure_parameters_00075 WHERE options IS NOT NULL) x
CROSS JOIN LATERAL jsonb_array_elements_text(x.options) WITH ORDINALITY v(label,ord)
JOIN public.catalogue_option_sets os ON lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(x.options)),' / '))) AND os.lifecycle_status<>'Archived' AND os.code LIKE 'OPERATOR_%'
ON CONFLICT(option_set_id,value_code) DO UPDATE SET label=EXCLUDED.label,display_order=EXCLUDED.display_order,is_active=TRUE,updated_at=now();

UPDATE public.parameters p SET option_set_id=os.id,row_version=p.row_version+1,updated_at=now()
FROM final_structure_parameters_00075 s JOIN public.tests t ON t.code=s.test_code
JOIN public.catalogue_option_sets os ON lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(s.options)),' / '))) AND os.lifecycle_status<>'Archived'
WHERE p.test_id=t.id AND p.code=s.parameter_code AND s.options IS NOT NULL;

-- Preserve every supplied range/value as approved reference text. This avoids
-- turning contextual statements into universal numeric limits.
INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_text,unit,method,reference_text,lifecycle_status,validation_state,validation_source)
SELECT p.id,'All',0,43800,s.reference_text,s.unit,NULL,s.reference_text,'Active','ClinicallyValidated','Operator-approved final 33 result structures; source SHA-256 c90997ff59a885393338f6eadf171cd61f7615f6a5ec4fe5588272179072f591'
FROM final_structure_parameters_00075 s JOIN public.tests t ON t.code=s.test_code JOIN public.parameters p ON p.test_id=t.id AND p.code=s.parameter_code
WHERE s.reference_text IS NOT NULL
ON CONFLICT DO NOTHING;

-- The supplied Iron Profile ferritin range is explicitly sex-specific.
INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,normal_text,unit,method,reference_text,lifecycle_status,validation_state,validation_source)
SELECT p.id,v.gender,0,43800,v.lo,v.hi,v.txt,'ng/mL',NULL,v.txt,'Active','ClinicallyValidated','Operator-approved final 33 result structures'
FROM public.tests t JOIN public.parameters p ON p.test_id=t.id AND p.code='FERRITIN'
CROSS JOIN (VALUES('Male',30::NUMERIC,400::NUMERIC,'30 - 400 ng/mL'),('Female',15::NUMERIC,150::NUMERIC,'15 - 150 ng/mL')) v(gender,lo,hi,txt)
WHERE t.code='IRON_PROFILE' ON CONFLICT DO NOTHING;

-- Final thirteen previously unresolved qualitative selections.
CREATE TEMP TABLE final_qualitative_00075(test_code TEXT PRIMARY KEY,options JSONB,normal_value TEXT,interpretation TEXT) ON COMMIT DROP;
INSERT INTO final_qualitative_00075 VALUES
('ANTI_NUCLEAR_ANTIBODY_ANA_BY_ELISA','["Negative","Equivocal","Positive"]','Negative','Ratio: <0.8 Negative, 0.8-1.2 Equivocal, >1.2 Positive'),
('CEA_CARCINOEMBRYONIC_ANTIGEN','["Negative (< 5 ng/mL)","Positive (≥ 5 ng/mL)"]','Negative (< 5 ng/mL)','For screening card formats; ELISA/CLIA uses numeric ng/mL'),
('GCT','["Normal (< 140 mg/dL)","Abnormal / Elevated (≥ 140 mg/dL)"]','Normal (< 140 mg/dL)','Indicates need for definitive 3-hour OGTT if Abnormal'),
('HAV_IGG','["Non-Reactive","Reactive"]','Non-Reactive','Non-Reactive indicates non-immune; Reactive indicates immunity'),
('HAV_IGM','["Non-Reactive","Reactive"]','Non-Reactive','Reactive indicates acute Hepatitis A infection'),
('HAV_TOTAL_AB','["Non-Reactive","Reactive"]','Non-Reactive','Reactive indicates prior infection or vaccination'),
('KALA_AZAR','["Negative","Positive","Invalid"]','Negative','Rapid immunochromatographic detection of Leishmania donovani'),
('MP_MICROSCOPIC','["No Malaria Parasites Seen (NMP)","Plasmodium vivax Seen","Plasmodium falciparum Seen","Plasmodium malariae Seen","Plasmodium ovale Seen","Mixed Infection Seen"]','No Malaria Parasites Seen (NMP)','Thick & Thin Smear Examination'),
('THYROGLOBULIN_ANTIBODY_TGAB','["Negative","Positive"]','Negative','Identifies autoimmune thyroiditis'),
('TPHA','["Non-Reactive","Reactive","Inconclusive / Borderline"]','Non-Reactive','Confirmatory treponemal test for syphilis'),
('TROPONIN_I_RAPID','["Negative (< 0.5 ng/mL)","Positive (≥ 0.5 ng/mL)","Invalid"]','Negative (< 0.5 ng/mL)','Rapid qualitative exclusion of acute myocardial infarction'),
('UPT','["Negative","Positive","Invalid"]','Negative','Rapid qualitative lateral flow detection'),
('URINE_FOR_ELISA_PREGNANCY','["Negative","Positive","Equivocal / Borderline"]','Negative','Highly sensitive microplate-based hCG detection');

WITH vocabularies AS (SELECT DISTINCT options FROM final_qualitative_00075)
INSERT INTO public.catalogue_option_sets(code,name,lifecycle_status)
SELECT 'OPERATOR_'||upper(substr(md5(options::TEXT),1,20)),array_to_string(ARRAY(SELECT jsonb_array_elements_text(options)),' / '),'Active' FROM vocabularies v
WHERE NOT EXISTS(SELECT 1 FROM public.catalogue_option_sets os WHERE lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(v.options)),' / '))) AND os.lifecycle_status<>'Archived')
ON CONFLICT(code) DO UPDATE SET lifecycle_status='Active',updated_at=now();
INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order)
SELECT os.id,upper(substr(md5(v.label),1,24)),v.label,v.ord::INT FROM (SELECT DISTINCT options FROM final_qualitative_00075) x
CROSS JOIN LATERAL jsonb_array_elements_text(x.options) WITH ORDINALITY v(label,ord)
JOIN public.catalogue_option_sets os ON lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(x.options)),' / '))) AND os.lifecycle_status<>'Archived' AND os.code LIKE 'OPERATOR_%'
ON CONFLICT(option_set_id,value_code) DO UPDATE SET label=EXCLUDED.label,display_order=EXCLUDED.display_order,is_active=TRUE,updated_at=now();
UPDATE public.parameters p SET value_type='Select',options=q.options,option_set_id=os.id,
 interpretation_config=jsonb_build_object('normal_value',q.normal_value,'clinical_interpretation',q.interpretation),
 clinical_configuration_status='Configured',row_version=p.row_version+1,updated_at=now()
FROM final_qualitative_00075 q JOIN public.tests t ON t.code=q.test_code
JOIN public.catalogue_option_sets os ON lower(btrim(os.name))=lower(btrim(array_to_string(ARRAY(SELECT jsonb_array_elements_text(q.options)),' / '))) AND os.lifecycle_status<>'Archived'
WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active';

-- Malaria microscopy retains a separate density/quantification narrative field.
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required,interpretation_config)
SELECT t.id,'DENSITY_QUANTIFICATION','Density / Quantification','Text',2,FALSE,TRUE,'Active','Configured',FALSE,FALSE,FALSE,jsonb_build_object('control','Text Multi-line')
FROM public.tests t WHERE t.code='MP_MICROSCOPIC'
ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type='Text',display_order=2,is_active=TRUE,lifecycle_status='Active',interpretation_config=EXCLUDED.interpretation_config,row_version=public.parameters.row_version+1,updated_at=now();

UPDATE public.catalogue_result_structure_reconciliation r SET
 source_evidence='Final operator-approved 33 result structures + 13 qualitative definitions; source SHA-256 c90997ff59a885393338f6eadf171cd61f7615f6a5ec4fe5588272179072f591',
 action_code=CASE WHEN q.test_code IS NOT NULL THEN 'MATERIALIZED_QUALITATIVE_WITH_OPTIONS' ELSE 'MATERIALIZED_NUMERIC_SINGLE' END,
 parameters_materialized=(SELECT count(*) FROM public.parameters p WHERE p.test_id=r.test_id AND p.is_active AND p.lifecycle_status='Active'),
 final_readiness=public.catalogue_test_result_readiness(r.test_id),notes='Approved operator result structure is ready.'
FROM public.tests t LEFT JOIN final_qualitative_00075 q ON q.test_code=t.code
WHERE r.test_id=t.id AND (t.code IN(SELECT DISTINCT test_code FROM final_structure_parameters_00075) OR q.test_code IS NOT NULL);

DO $$ BEGIN
 IF (SELECT count(DISTINCT test_code) FROM final_structure_parameters_00075)<>33 THEN RAISE EXCEPTION 'FINAL_RESULT_STRUCTURE_SOURCE_COUNT_NOT_33'; END IF;
 IF (SELECT count(*) FROM final_qualitative_00075)<>13 THEN RAISE EXCEPTION 'FINAL_QUALITATIVE_SOURCE_COUNT_NOT_13'; END IF;
 IF EXISTS(SELECT 1 FROM final_structure_parameters_00075 s LEFT JOIN public.tests t ON t.code=s.test_code WHERE t.id IS NULL) THEN RAISE EXCEPTION 'FINAL_RESULT_STRUCTURE_TEST_UNRESOLVED'; END IF;
 IF EXISTS(SELECT 1 FROM final_qualitative_00075 q LEFT JOIN public.tests t ON t.code=q.test_code WHERE t.id IS NULL) THEN RAISE EXCEPTION 'FINAL_QUALITATIVE_TEST_UNRESOLVED'; END IF;
 IF EXISTS(SELECT 1 FROM final_structure_parameters_00075 s JOIN public.tests t ON t.code=s.test_code WHERE public.catalogue_test_result_readiness(t.id)='Incomplete') THEN RAISE EXCEPTION 'FINAL_RESULT_STRUCTURE_INCOMPLETE: %',(SELECT string_agg(DISTINCT t.code,', ' ORDER BY t.code) FROM final_structure_parameters_00075 s JOIN public.tests t ON t.code=s.test_code WHERE public.catalogue_test_result_readiness(t.id)='Incomplete'); END IF;
 IF EXISTS(SELECT 1 FROM final_qualitative_00075 q JOIN public.tests t ON t.code=q.test_code WHERE public.catalogue_test_result_readiness(t.id)='Incomplete') THEN RAISE EXCEPTION 'FINAL_QUALITATIVE_INCOMPLETE: %',(SELECT string_agg(t.code,', ' ORDER BY t.code) FROM final_qualitative_00075 q JOIN public.tests t ON t.code=q.test_code WHERE public.catalogue_test_result_readiness(t.id)='Incomplete'); END IF;
 IF (SELECT count(*) FROM public.catalogue_result_structure_reconciliation WHERE action_code='RESULT_STRUCTURE_REQUIRES_OPERATOR_INPUT')<>0 THEN RAISE EXCEPTION 'RESULT_STRUCTURE_QUEUE_NOT_ZERO'; END IF;
 IF (SELECT count(*) FROM public.catalogue_result_structure_reconciliation WHERE action_code='OPTION_SET_REQUIRES_OPERATOR_SELECTION')<>0 THEN RAISE EXCEPTION 'QUALITATIVE_QUEUE_NOT_ZERO'; END IF;
 IF EXISTS(SELECT test_id,code FROM public.parameters WHERE is_active AND lifecycle_status='Active' GROUP BY test_id,code HAVING count(*)>1) THEN RAISE EXCEPTION 'DUPLICATE_ACTIVE_PARAMETER_IDENTITY'; END IF;
END $$;

-- Final operator-approved WIDAL_SLIDE configuration. WIDAL_TUBE_METHOD remains distinct.
INSERT INTO public.catalogue_option_sets(code,name,lifecycle_status)
VALUES('WIDAL_SLIDE_TITER','Widal Slide Controlled Titer','Active')
ON CONFLICT(code) DO UPDATE SET name=EXCLUDED.name,lifecycle_status='Active',updated_at=now();

INSERT INTO public.catalogue_option_values(option_set_id,value_code,label,display_order,is_active)
SELECT os.id,v.code,v.label,v.ord,TRUE FROM public.catalogue_option_sets os CROSS JOIN (VALUES
 ('NO_AGGLUTINATION','No Agglutination (< 1:20)',1),('TITER_1_20','1:20',2),('TITER_1_40','1:40',3),
 ('TITER_1_80','1:80',4),('TITER_1_160','1:160',5),('TITER_1_320','1:320',6),('TITER_GT_1_320','> 1:320',7)
) v(code,label,ord) WHERE os.code='WIDAL_SLIDE_TITER'
ON CONFLICT(option_set_id,value_code) DO UPDATE SET label=EXCLUDED.label,display_order=EXCLUDED.display_order,is_active=TRUE,updated_at=now();

UPDATE public.tests t SET
 name='Widal Slide Method',category_id=c.id,department='Serology & Immunology',category='Serology & Immunology',
 sample_type='Serum',container='Not specified',method='Slide Agglutination / Rapid Semi-Quantitative Screening',reporting_type='InHouse',
 workflow_supported=TRUE,clinical_reporting_enabled=TRUE,billing_enabled=TRUE,collection_required=TRUE,
 allow_zero_price_billing=TRUE,is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',
 workflow_type='Routine',reporting_model='MixedTyped',catalogue_approved=TRUE,
 interpretation_template='Significant diagnostic titer in endemic regions is typically ≥1:80 or ≥1:160 for S. typhi ''O'' (TO) and ≥1:160 for S. typhi ''H'' (TH). Clinical/reference information only; no automatic diagnosis or impression generation.',
 configuration_notes='Slide titration technical/reference mapping: No clumping with 80 µL → < 1:20 → Non-Reactive / Negative; 80 µL (0.08 mL) + 1 drop antigen → 1:20 → Baseline / Non-significant; 40 µL (0.04 mL) + 1 drop antigen → 1:40 → Baseline / Non-significant; 20 µL (0.02 mL) + 1 drop antigen → 1:80 → Borderline / Endemic Basal Titer; 10 µL (0.01 mL) + 1 drop antigen → 1:160 → Clinically Significant / Diagnostic Cut-off; 5 µL (0.005 mL) + 1 drop antigen → 1:320 → Strongly Positive; Clumping beyond 5 µL → > 1:320 → Strongly Positive. Technician independently reports titers and impression.',
 row_version=t.row_version+1,updated_at=now()
FROM public.test_categories c WHERE t.code='WIDAL_SLIDE' AND c.code='SEROLOGY';

CREATE TEMP TABLE widal_slide_parameters_00075(code TEXT PRIMARY KEY,name TEXT,value_type public.parameter_value_type_enum,display_order INT,target TEXT,default_value TEXT,multiline BOOLEAN) ON COMMIT DROP;
INSERT INTO widal_slide_parameters_00075 VALUES
 ('WIDAL_TO','Salmonella typhi ''O''','Select',1,'Somatic (O) Ag','No Agglutination (< 1:20)',FALSE),
 ('WIDAL_TH','Salmonella typhi ''H''','Select',2,'Flagellar (H) Ag','No Agglutination (< 1:20)',FALSE),
 ('WIDAL_AH','Salmonella paratyphi ''AH''','Select',3,'Flagellar (AH) Ag','No Agglutination (< 1:20)',FALSE),
 ('WIDAL_BH','Salmonella paratyphi ''BH''','Select',4,'Flagellar (BH) Ag','No Agglutination (< 1:20)',FALSE),
 ('WIDAL_IMPRESSION','Impression / Remarks','Text',5,'Overall Interpretation','No significant agglutination titers observed.',TRUE);

INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required,option_set_id,interpretation_config)
SELECT t.id,w.code,w.name,w.value_type,CASE WHEN w.value_type='Select' THEN 'Titer Dilution' END,
 CASE WHEN w.value_type='Select' THEN '["No Agglutination (< 1:20)","1:20","1:40","1:80","1:160","1:320","> 1:320"]'::JSONB END,
 w.display_order,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE,CASE WHEN w.value_type='Select' THEN os.id END,
 jsonb_build_object('target',w.target,'default_value',w.default_value,'control',CASE WHEN w.multiline THEN 'Text Multi-line' WHEN w.value_type='Select' THEN 'Controlled Titer Selector' ELSE 'Text' END,'automatic_interpretation',FALSE)
FROM public.tests t CROSS JOIN widal_slide_parameters_00075 w LEFT JOIN public.catalogue_option_sets os ON os.code='WIDAL_SLIDE_TITER'
WHERE t.code='WIDAL_SLIDE'
ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type=EXCLUDED.value_type,unit=EXCLUDED.unit,options=EXCLUDED.options,
 display_order=EXCLUDED.display_order,is_mandatory=TRUE,is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',
 unit_validation_required=FALSE,range_validation_required=FALSE,method_validation_required=FALSE,option_set_id=EXCLUDED.option_set_id,
 interpretation_config=EXCLUDED.interpretation_config,row_version=public.parameters.row_version+1,updated_at=now();

INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_text,reference_text,unit,method,is_active,is_approved,lifecycle_status,validation_state,validation_source)
SELECT p.id,'All',0,43800,'No Agglutination (< 1:20)','Controlled slide titer; technical volume/titer/significance mapping is stored on WIDAL_SLIDE. Technician interpretation required.','Titer Dilution','Slide Agglutination / Rapid Semi-Quantitative Screening',TRUE,TRUE,'Active','ClinicallyValidated','Final operator WIDAL_SLIDE authorization'
FROM public.tests t JOIN public.parameters p ON p.test_id=t.id
WHERE t.code='WIDAL_SLIDE' AND p.code IN('WIDAL_TO','WIDAL_TH','WIDAL_AH','WIDAL_BH')
ON CONFLICT DO NOTHING;

UPDATE public.catalogue_result_structure_reconciliation r SET
 source_evidence='Final operator-approved WIDAL_SLIDE configuration',action_code='MATERIALIZED_QUALITATIVE_WITH_OPTIONS',parameters_materialized=5,
 final_readiness=public.catalogue_test_result_readiness(r.test_id),notes='WIDAL_SLIDE is Reportable & Ready.'
FROM public.tests t WHERE r.test_id=t.id AND t.code='WIDAL_SLIDE';

DO $$ BEGIN
 IF (SELECT count(*) FROM public.tests WHERE code='WIDAL_SLIDE')<>1 THEN RAISE EXCEPTION 'WIDAL_SLIDE_IDENTITY_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.tests WHERE code='WIDAL_TUBE_METHOD')<>1 THEN RAISE EXCEPTION 'WIDAL_TUBE_IDENTITY_CHANGED'; END IF;
 IF (SELECT count(*) FROM public.parameters p JOIN public.tests t ON t.id=p.test_id WHERE t.code='WIDAL_SLIDE' AND p.is_active AND p.lifecycle_status='Active')<>5 THEN RAISE EXCEPTION 'WIDAL_SLIDE_PARAMETER_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT 1 FROM public.parameters p JOIN public.tests t ON t.id=p.test_id WHERE t.code='WIDAL_SLIDE' AND p.is_active AND p.lifecycle_status='Active' AND (p.code,p.display_order) NOT IN (('WIDAL_TO',1),('WIDAL_TH',2),('WIDAL_AH',3),('WIDAL_BH',4),('WIDAL_IMPRESSION',5))) THEN RAISE EXCEPTION 'WIDAL_SLIDE_PARAMETER_ORDER_INVALID'; END IF;
 IF (SELECT count(*) FROM public.catalogue_option_values v JOIN public.catalogue_option_sets s ON s.id=v.option_set_id WHERE s.code='WIDAL_SLIDE_TITER' AND v.is_active)<>7 THEN RAISE EXCEPTION 'WIDAL_SLIDE_TITER_OPTION_COUNT_INVALID'; END IF;
 IF (SELECT count(DISTINCT p.option_set_id) FROM public.parameters p JOIN public.tests t ON t.id=p.test_id WHERE t.code='WIDAL_SLIDE' AND p.code IN('WIDAL_TO','WIDAL_TH','WIDAL_AH','WIDAL_BH'))<>1 THEN RAISE EXCEPTION 'WIDAL_SLIDE_OPTION_SET_NOT_SHARED'; END IF;
 IF public.catalogue_test_result_readiness((SELECT id FROM public.tests WHERE code='WIDAL_SLIDE'))<>'Ready' THEN RAISE EXCEPTION 'WIDAL_SLIDE_NOT_READY'; END IF;
 IF (SELECT count(*) FROM public.catalogue_result_structure_reconciliation WHERE action_code IN('RESULT_STRUCTURE_REQUIRES_OPERATOR_INPUT','OPTION_SET_REQUIRES_OPERATOR_SELECTION'))<>0 THEN RAISE EXCEPTION 'CATALOGUE_COMPLETION_QUEUE_NOT_ZERO'; END IF;
END $$;

CREATE TEMP TABLE ast_rules_00075(
 group_code TEXT,antibiotic_code TEXT,method TEXT,potency TEXT,auto_allowed BOOLEAN,
 s_min NUMERIC,s_max NUMERIC,s_secondary NUMERIC,i_min NUMERIC,i_max NUMERIC,i_secondary_min NUMERIC,i_secondary_max NUMERIC,
 r_min NUMERIC,r_max NUMERIC,r_secondary NUMERIC,i_semantics TEXT,notes TEXT,
 PRIMARY KEY(group_code,antibiotic_code,method)
) ON COMMIT DROP;
INSERT INTO ast_rules_00075 VALUES
-- Staphylococcus spp. — disk and MIC
('STAPHYLOCOCCUS_SPP','AB_FOX','Disk','30 µg',TRUE,22,NULL,NULL,NULL,NULL,NULL,NULL,NULL,21,NULL,NULL,'MRSA surrogate'),
('STAPHYLOCOCCUS_SPP','AB_FOX','MIC','30 µg',TRUE,NULL,4,NULL,NULL,NULL,NULL,NULL,8,NULL,NULL,NULL,'MRSA surrogate'),
('STAPHYLOCOCCUS_SPP','AB_PEN','Disk','10 units',TRUE,29,NULL,NULL,NULL,NULL,NULL,NULL,NULL,28,NULL,NULL,NULL),
('STAPHYLOCOCCUS_SPP','AB_PEN','MIC','10 units',TRUE,NULL,0.12,NULL,NULL,NULL,NULL,NULL,0.25,NULL,NULL,NULL,NULL),
('STAPHYLOCOCCUS_SPP','AB_CIP','Disk','5 µg',TRUE,21,NULL,NULL,16,20,NULL,NULL,NULL,15,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_CIP','MIC','5 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_CLI','Disk','2 µg',TRUE,21,NULL,NULL,15,20,NULL,NULL,NULL,14,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_CLI','MIC','2 µg',TRUE,NULL,0.5,NULL,1,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_ERY','Disk','15 µg',TRUE,23,NULL,NULL,14,22,NULL,NULL,NULL,13,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_ERY','MIC','15 µg',TRUE,NULL,0.5,NULL,1,4,NULL,NULL,8,NULL,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_GEN','Disk','10 µg',TRUE,15,NULL,NULL,13,14,NULL,NULL,NULL,12,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_GEN','MIC','10 µg',TRUE,NULL,4,NULL,8,8,NULL,NULL,16,NULL,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_LZD','Disk','30 µg',TRUE,21,NULL,NULL,NULL,NULL,NULL,NULL,NULL,20,NULL,NULL,NULL),
('STAPHYLOCOCCUS_SPP','AB_LZD','MIC','30 µg',TRUE,NULL,4,NULL,NULL,NULL,NULL,NULL,8,NULL,NULL,NULL,NULL),
('STAPHYLOCOCCUS_SPP','AB_COT','Disk','TMP-SMX 1.25/23.75 µg',TRUE,16,NULL,NULL,11,15,NULL,NULL,NULL,10,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_COT','MIC','TMP-SMX 1.25/23.75 µg',TRUE,NULL,2,38,NULL,NULL,NULL,NULL,4,NULL,76,NULL,NULL),
('STAPHYLOCOCCUS_SPP','AB_DOX','Disk','30 µg',TRUE,16,NULL,NULL,13,15,NULL,NULL,NULL,12,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_DOX','MIC','30 µg',TRUE,NULL,4,NULL,8,8,NULL,NULL,16,NULL,NULL,'I',NULL),
('STAPHYLOCOCCUS_SPP','AB_VAN','Disk',NULL,FALSE,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'NOT VALID / NOT RECOMMENDED; MIC required for breakpoint interpretation'),
('STAPHYLOCOCCUS_SPP','AB_VAN','MIC',NULL,TRUE,NULL,2,NULL,4,8,NULL,NULL,16,NULL,NULL,'I','4–8 = VISA; >=16 = VRSA; no automatic resistance-mechanism remark'),
-- Enterobacterales
('ENTEROBACTERALES','AB_AMP','Disk','10 µg',TRUE,17,NULL,NULL,14,16,NULL,NULL,NULL,13,NULL,'I',NULL),('ENTEROBACTERALES','AB_AMP','MIC','10 µg',TRUE,NULL,8,NULL,16,16,NULL,NULL,32,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_AMC','Disk','20/10 µg',TRUE,18,NULL,NULL,14,17,NULL,NULL,NULL,13,NULL,'I',NULL),('ENTEROBACTERALES','AB_AMC','MIC','20/10 µg',TRUE,NULL,8,4,16,16,8,8,32,NULL,16,'I',NULL),
('ENTEROBACTERALES','AB_TZP','Disk','100/10 µg',TRUE,21,NULL,NULL,18,20,NULL,NULL,NULL,17,NULL,'I',NULL),('ENTEROBACTERALES','AB_TZP','MIC','100/10 µg',TRUE,NULL,16,4,32,64,4,4,128,NULL,4,'I',NULL),
('ENTEROBACTERALES','AB_CTX','Disk','30 µg',TRUE,26,NULL,NULL,23,25,NULL,NULL,NULL,22,NULL,'I',NULL),('ENTEROBACTERALES','AB_CTX','MIC','30 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_CTR','Disk','30 µg',TRUE,23,NULL,NULL,20,22,NULL,NULL,NULL,19,NULL,'I',NULL),('ENTEROBACTERALES','AB_CTR','MIC','30 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_CAZ','Disk','30 µg',TRUE,21,NULL,NULL,18,20,NULL,NULL,NULL,17,NULL,'I',NULL),('ENTEROBACTERALES','AB_CAZ','MIC','30 µg',TRUE,NULL,4,NULL,8,8,NULL,NULL,16,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_FEP','Disk','30 µg',TRUE,25,NULL,NULL,19,24,NULL,NULL,NULL,18,NULL,'SDD','Susceptible Dose-Dependent is preserved distinctly'),('ENTEROBACTERALES','AB_FEP','MIC','30 µg',TRUE,NULL,2,NULL,4,8,NULL,NULL,16,NULL,NULL,'SDD','Susceptible Dose-Dependent is preserved distinctly'),
('ENTEROBACTERALES','AB_MEM','Disk','10 µg',TRUE,23,NULL,NULL,20,22,NULL,NULL,NULL,19,NULL,'I',NULL),('ENTEROBACTERALES','AB_MEM','MIC','10 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_IPM','Disk','10 µg',TRUE,23,NULL,NULL,20,22,NULL,NULL,NULL,19,NULL,'I',NULL),('ENTEROBACTERALES','AB_IPM','MIC','10 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_AMK','Disk','30 µg',TRUE,17,NULL,NULL,15,16,NULL,NULL,NULL,14,NULL,'I',NULL),('ENTEROBACTERALES','AB_AMK','MIC','30 µg',TRUE,NULL,16,NULL,32,32,NULL,NULL,64,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_GEN','Disk','10 µg',TRUE,15,NULL,NULL,13,14,NULL,NULL,NULL,12,NULL,'I',NULL),('ENTEROBACTERALES','AB_GEN','MIC','10 µg',TRUE,NULL,4,NULL,8,8,NULL,NULL,16,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_CIP','Disk','5 µg',TRUE,26,NULL,NULL,22,25,NULL,NULL,NULL,21,NULL,'I',NULL),('ENTEROBACTERALES','AB_CIP','MIC','5 µg',TRUE,NULL,0.25,NULL,0.5,0.5,NULL,NULL,1,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_LEV','Disk','5 µg',TRUE,21,NULL,NULL,17,20,NULL,NULL,NULL,16,NULL,'I',NULL),('ENTEROBACTERALES','AB_LEV','MIC','5 µg',TRUE,NULL,0.5,NULL,1,1,NULL,NULL,2,NULL,NULL,'I',NULL),
('ENTEROBACTERALES','AB_COT','Disk','TMP-SMX 1.25/23.75 µg',TRUE,16,NULL,NULL,11,15,NULL,NULL,NULL,10,NULL,'I',NULL),('ENTEROBACTERALES','AB_COT','MIC','TMP-SMX 1.25/23.75 µg',TRUE,NULL,2,38,NULL,NULL,NULL,NULL,4,NULL,76,NULL,NULL),
-- Pseudomonas aeruginosa
('PSEUDOMONAS_AERUGINOSA','AB_CAZ','Disk','30 µg',TRUE,21,NULL,NULL,18,20,NULL,NULL,NULL,17,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_CAZ','MIC','30 µg',TRUE,NULL,8,NULL,16,16,NULL,NULL,32,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_FEP','Disk','30 µg',TRUE,18,NULL,NULL,15,17,NULL,NULL,NULL,14,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_FEP','MIC','30 µg',TRUE,NULL,8,NULL,16,16,NULL,NULL,32,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_TZP','Disk','100/10 µg',TRUE,21,NULL,NULL,15,20,NULL,NULL,NULL,14,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_TZP','MIC','100/10 µg',TRUE,NULL,16,4,32,64,4,4,128,NULL,4,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_MEM','Disk','10 µg',TRUE,19,NULL,NULL,16,18,NULL,NULL,NULL,15,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_MEM','MIC','10 µg',TRUE,NULL,2,NULL,4,4,NULL,NULL,8,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_IPM','Disk','10 µg',TRUE,19,NULL,NULL,16,18,NULL,NULL,NULL,15,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_IPM','MIC','10 µg',TRUE,NULL,2,NULL,4,4,NULL,NULL,8,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_AMK','Disk','30 µg',TRUE,17,NULL,NULL,15,16,NULL,NULL,NULL,14,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_AMK','MIC','30 µg',TRUE,NULL,16,NULL,32,32,NULL,NULL,64,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_TOB','Disk','10 µg',TRUE,15,NULL,NULL,13,14,NULL,NULL,NULL,12,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_TOB','MIC','10 µg',TRUE,NULL,4,NULL,8,8,NULL,NULL,16,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_CIP','Disk','5 µg',TRUE,25,NULL,NULL,19,24,NULL,NULL,NULL,18,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_CIP','MIC','5 µg',TRUE,NULL,0.5,NULL,1,1,NULL,NULL,2,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_LEV','Disk','5 µg',TRUE,22,NULL,NULL,18,21,NULL,NULL,NULL,17,NULL,'I',NULL),('PSEUDOMONAS_AERUGINOSA','AB_LEV','MIC','5 µg',TRUE,NULL,1,NULL,2,2,NULL,NULL,4,NULL,NULL,'I',NULL),
('PSEUDOMONAS_AERUGINOSA','AB_COL','Disk',NULL,FALSE,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,'INVALID / DO NOT INTERPRET; MIC required for breakpoint interpretation'),
('PSEUDOMONAS_AERUGINOSA','AB_COL','MIC',NULL,TRUE,NULL,NULL,NULL,0,2,NULL,NULL,4,NULL,NULL,'I','No Susceptible category; <=2 Intermediate; >=4 Resistant');

INSERT INTO public.ast_breakpoint_rules(breakpoint_set_id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,
 susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,
 resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes)
SELECT bs.id,g.id,a.id,r.method,CASE WHEN r.method='Disk' THEN 'ZoneDiameterMm' ELSE 'MicConcentration' END,r.potency,r.auto_allowed,
 r.s_min,r.s_max,r.s_secondary,r.i_min,r.i_max,r.i_secondary_min,r.i_secondary_max,r.r_min,r.r_max,r.r_secondary,r.i_semantics,
 jsonb_build_object('susceptible','S','intermediate',r.i_semantics,'resistant','R','mechanism_inference',FALSE),r.notes
FROM ast_rules_00075 r JOIN public.ast_breakpoint_sets bs ON bs.name='Local AST Breakpoint Baseline' AND bs.version='1.0'
JOIN public.ast_organism_groups g ON g.code=r.group_code JOIN public.ast_antibiotics a ON a.code=r.antibiotic_code
ON CONFLICT(breakpoint_set_id,organism_group_id,antibiotic_id,method) DO UPDATE SET
 metric_type=EXCLUDED.metric_type,potency=EXCLUDED.potency,automatic_interpretation_allowed=EXCLUDED.automatic_interpretation_allowed,
 susceptible_min=EXCLUDED.susceptible_min,susceptible_max=EXCLUDED.susceptible_max,susceptible_secondary=EXCLUDED.susceptible_secondary,
 intermediate_min=EXCLUDED.intermediate_min,intermediate_max=EXCLUDED.intermediate_max,intermediate_secondary_min=EXCLUDED.intermediate_secondary_min,intermediate_secondary_max=EXCLUDED.intermediate_secondary_max,
 resistant_min=EXCLUDED.resistant_min,resistant_max=EXCLUDED.resistant_max,resistant_secondary=EXCLUDED.resistant_secondary,
 intermediate_semantics=EXCLUDED.intermediate_semantics,interpretation_semantics=EXCLUDED.interpretation_semantics,notes=EXCLUDED.notes,updated_at=now();

CREATE OR REPLACE FUNCTION public.ast_interpret_breakpoint(
 p_organism_group_code TEXT,p_antibiotic_code TEXT,p_method TEXT,p_metric_value NUMERIC,p_metric_secondary_value NUMERIC DEFAULT NULL,p_breakpoint_set_id UUID DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE r public.ast_breakpoint_rules%ROWTYPE; bs public.ast_breakpoint_sets%ROWTYPE; result_code TEXT;
BEGIN
 IF p_metric_value IS NULL OR p_metric_value<0 THEN RAISE EXCEPTION 'A non-negative exact numeric AST metric is required.' USING ERRCODE='22023'; END IF;
 IF p_method NOT IN('Disk','MIC') THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'message','No approved breakpoint configured'); END IF;
 SELECT * INTO bs FROM public.ast_breakpoint_sets WHERE id=COALESCE(p_breakpoint_set_id,(SELECT id FROM public.ast_breakpoint_sets WHERE is_active)) AND status='Active';
 IF NOT FOUND THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'message','No active breakpoint-set version selected'); END IF;
 SELECT br.* INTO r FROM public.ast_breakpoint_rules br JOIN public.ast_organism_groups g ON g.id=br.organism_group_id
 JOIN public.ast_antibiotics a ON a.id=br.antibiotic_id
 WHERE br.breakpoint_set_id=bs.id AND g.code=p_organism_group_code AND a.code=p_antibiotic_code AND br.method=p_method;
 IF NOT FOUND THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'message','No approved breakpoint configured'); END IF;
 IF NOT r.automatic_interpretation_allowed THEN RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,'message','MIC required for breakpoint interpretation','notes',r.notes); END IF;
 IF (r.susceptible_secondary IS NOT NULL OR r.intermediate_secondary_min IS NOT NULL OR r.resistant_secondary IS NOT NULL) AND p_metric_secondary_value IS NULL THEN
  RETURN jsonb_build_object('automatic_interpretation',NULL,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,'message','Compound MIC metric requires both numeric components');
 END IF;
 IF r.susceptible_min IS NOT NULL AND p_metric_value>=r.susceptible_min THEN result_code:='S';
 ELSIF r.susceptible_max IS NOT NULL AND p_metric_value<=r.susceptible_max AND (r.susceptible_secondary IS NULL OR p_metric_secondary_value=r.susceptible_secondary) THEN result_code:='S';
 ELSIF r.intermediate_min IS NOT NULL AND r.intermediate_max IS NOT NULL AND p_metric_value BETWEEN r.intermediate_min AND r.intermediate_max
   AND (r.intermediate_secondary_min IS NULL OR p_metric_secondary_value BETWEEN r.intermediate_secondary_min AND r.intermediate_secondary_max) THEN result_code:=COALESCE(r.intermediate_semantics,'I');
 ELSIF r.resistant_min IS NOT NULL AND p_metric_value>=r.resistant_min AND (r.resistant_secondary IS NULL OR p_metric_secondary_value=r.resistant_secondary) THEN result_code:='R';
 ELSIF r.resistant_max IS NOT NULL AND p_metric_value<=r.resistant_max THEN result_code:='R'; END IF;
 RETURN jsonb_build_object('automatic_interpretation',result_code,'breakpoint_set_id',bs.id,'breakpoint_version',bs.version,'rule_id',r.id,
  'message',CASE WHEN result_code IS NULL THEN 'No approved breakpoint configured for this exact metric' ELSE NULL END,'notes',r.notes);
END $$;

CREATE OR REPLACE FUNCTION public.ast_save_isolate(p_order_item_id UUID,p_isolate_number INT,p_microorganism_id UUID,p_growth_state TEXT,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE prior public.ast_isolates%ROWTYPE; org public.ast_microorganisms%ROWTYPE; grp public.ast_organism_groups%ROWTYPE; saved public.ast_isolates%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_growth_state NOT IN('Positive','NoGrowth') THEN RAISE EXCEPTION 'Invalid growth state.' USING ERRCODE='22023'; END IF;
 SELECT * INTO prior FROM public.ast_isolates WHERE order_item_id=p_order_item_id AND isolate_number=p_isolate_number FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'AST isolate changed. Reload before saving.' USING ERRCODE='PT409'; END IF;
 IF p_growth_state='Positive' THEN SELECT * INTO org FROM public.ast_microorganisms WHERE id=p_microorganism_id AND is_active; IF NOT FOUND THEN RAISE EXCEPTION 'Select an active microorganism.' USING ERRCODE='23503'; END IF; SELECT * INTO grp FROM public.ast_organism_groups WHERE id=org.organism_group_id; END IF;
 INSERT INTO public.ast_isolates(order_item_id,isolate_number,microorganism_id,organism_name_snapshot,organism_group_id,organism_group_snapshot,growth_state,created_by)
 VALUES(p_order_item_id,p_isolate_number,CASE WHEN p_growth_state='Positive' THEN org.id END,CASE WHEN p_growth_state='Positive' THEN org.display_name ELSE 'No growth' END,
  CASE WHEN p_growth_state='Positive' THEN grp.id END,CASE WHEN p_growth_state='Positive' THEN grp.display_name END,p_growth_state,auth.uid())
 ON CONFLICT(order_item_id,isolate_number) DO UPDATE SET microorganism_id=EXCLUDED.microorganism_id,organism_name_snapshot=EXCLUDED.organism_name_snapshot,
  organism_group_id=EXCLUDED.organism_group_id,organism_group_snapshot=EXCLUDED.organism_group_snapshot,growth_state=EXCLUDED.growth_state,row_version=public.ast_isolates.row_version+1,updated_at=now()
 RETURNING * INTO saved;
 RETURN to_jsonb(saved);
END $$;

CREATE OR REPLACE FUNCTION public.ast_save_observation(p_isolate_id UUID,p_antibiotic_id UUID,p_method TEXT,p_metric_value NUMERIC,p_metric_secondary_value NUMERIC,
 p_final_interpretation TEXT,p_override_reason TEXT,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE iso public.ast_isolates%ROWTYPE; ab public.ast_antibiotics%ROWTYPE; grp public.ast_organism_groups%ROWTYPE; prior public.ast_observations%ROWTYPE; calc JSONB; auto_code TEXT; saved public.ast_observations%ROWTYPE; manual BOOLEAN;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_final_interpretation NOT IN('S','I','R','SDD') THEN RAISE EXCEPTION 'Final interpretation must be S, I, R or SDD.' USING ERRCODE='22023'; END IF;
 SELECT * INTO iso FROM public.ast_isolates WHERE id=p_isolate_id AND growth_state='Positive' FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Positive isolate not found.' USING ERRCODE='23503'; END IF;
 SELECT * INTO ab FROM public.ast_antibiotics WHERE id=p_antibiotic_id AND is_active; IF NOT FOUND THEN RAISE EXCEPTION 'Active antibiotic not found.' USING ERRCODE='23503'; END IF;
 SELECT * INTO grp FROM public.ast_organism_groups WHERE id=iso.organism_group_id;
 calc:=public.ast_interpret_breakpoint(grp.code,ab.code,p_method,p_metric_value,p_metric_secondary_value,NULL); auto_code:=calc->>'automatic_interpretation'; manual:=auto_code IS NULL OR auto_code<>p_final_interpretation;
 IF manual AND btrim(COALESCE(p_override_reason,''))='' THEN RAISE EXCEPTION 'Manual interpretation or override requires an explicit reason.' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM public.ast_observations WHERE isolate_id=p_isolate_id AND antibiotic_id=p_antibiotic_id AND method=p_method FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'AST observation changed. Reload before saving.' USING ERRCODE='PT409'; END IF;
 INSERT INTO public.ast_observations(isolate_id,antibiotic_id,antibiotic_code_snapshot,antibiotic_name_snapshot,method,metric_type,metric_value,metric_secondary_value,
  automatic_interpretation,final_interpretation,breakpoint_set_id,breakpoint_set_version_snapshot,breakpoint_rule_id,manual_override,override_reason,actor_id)
 VALUES(iso.id,ab.id,ab.code,ab.name,p_method,CASE WHEN p_method='Disk' THEN 'ZoneDiameterMm' ELSE 'MicConcentration' END,p_metric_value,p_metric_secondary_value,
  NULLIF(auto_code,''),p_final_interpretation,NULLIF(calc->>'breakpoint_set_id','')::UUID,calc->>'breakpoint_version',NULLIF(calc->>'rule_id','')::UUID,manual,p_override_reason,auth.uid())
 ON CONFLICT(isolate_id,antibiotic_id,method) DO UPDATE SET metric_type=EXCLUDED.metric_type,metric_value=EXCLUDED.metric_value,metric_secondary_value=EXCLUDED.metric_secondary_value,
  automatic_interpretation=EXCLUDED.automatic_interpretation,final_interpretation=EXCLUDED.final_interpretation,breakpoint_set_id=EXCLUDED.breakpoint_set_id,
  breakpoint_set_version_snapshot=EXCLUDED.breakpoint_set_version_snapshot,breakpoint_rule_id=EXCLUDED.breakpoint_rule_id,manual_override=EXCLUDED.manual_override,
  override_reason=EXCLUDED.override_reason,actor_id=auth.uid(),row_version=public.ast_observations.row_version+1,updated_at=now() RETURNING * INTO saved;
 INSERT INTO public.ast_observation_audit(observation_id,isolate_id,actor_id,action,before_state,after_state,reason)
 VALUES(saved.id,iso.id,auth.uid(),CASE WHEN prior.id IS NULL THEN 'AST_OBSERVATION_CREATED' WHEN manual THEN 'AST_INTERPRETATION_OVERRIDDEN' ELSE 'AST_OBSERVATION_UPDATED' END,
  CASE WHEN prior.id IS NULL THEN NULL ELSE to_jsonb(prior) END,to_jsonb(saved),p_override_reason);
 RETURN to_jsonb(saved)||jsonb_build_object('interpretation_message',calc->>'message','rule_notes',calc->>'notes');
END $$;

CREATE OR REPLACE FUNCTION public.ast_activate_breakpoint_set(p_set_id UUID,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE target public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO target FROM public.ast_breakpoint_sets WHERE id=p_set_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint set not found.' USING ERRCODE='23503'; END IF;
 IF target.row_version<>p_expected_revision THEN RAISE EXCEPTION 'Breakpoint version changed. Reload.' USING ERRCODE='PT409'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ast_breakpoint_rules WHERE breakpoint_set_id=target.id) THEN RAISE EXCEPTION 'Breakpoint set has no rules.' USING ERRCODE='23514'; END IF;
 UPDATE public.ast_breakpoint_sets SET status='Retired',is_active=FALSE,retired_at=now(),row_version=row_version+1 WHERE is_active AND id<>target.id;
 UPDATE public.ast_breakpoint_sets SET status='Active',is_active=TRUE,approved_by=auth.uid(),approved_at=now(),row_version=row_version+1 WHERE id=target.id RETURNING * INTO target;
 RETURN to_jsonb(target);
END $$;

CREATE OR REPLACE FUNCTION public.ast_save_breakpoint_set(p_payload JSONB,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_breakpoint_sets%ROWTYPE; target_id UUID:=NULLIF(p_payload->>'id','')::UUID;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF target_id IS NULL THEN
  INSERT INTO public.ast_breakpoint_sets(name,version,effective_date,provenance,status,is_active,created_by)
  VALUES(btrim(p_payload->>'name'),btrim(p_payload->>'version'),(p_payload->>'effective_date')::DATE,btrim(p_payload->>'provenance'),'Draft',FALSE,auth.uid()) RETURNING * INTO saved;
 ELSE
  UPDATE public.ast_breakpoint_sets SET name=btrim(p_payload->>'name'),version=btrim(p_payload->>'version'),effective_date=(p_payload->>'effective_date')::DATE,
   provenance=btrim(p_payload->>'provenance'),row_version=row_version+1 WHERE id=target_id AND status='Draft' AND row_version=p_expected_revision RETURNING * INTO saved;
  IF NOT FOUND THEN RAISE EXCEPTION 'Draft breakpoint set changed or is immutable.' USING ERRCODE='PT409'; END IF;
 END IF; RETURN to_jsonb(saved);
END $$;
CREATE OR REPLACE FUNCTION public.ast_clone_breakpoint_set(p_source_id UUID,p_new_version TEXT,p_effective_date DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE source public.ast_breakpoint_sets%ROWTYPE; target public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT * INTO source FROM public.ast_breakpoint_sets WHERE id=p_source_id; IF NOT FOUND THEN RAISE EXCEPTION 'Source breakpoint set not found.' USING ERRCODE='23503'; END IF;
 INSERT INTO public.ast_breakpoint_sets(name,version,effective_date,provenance,status,is_active,created_by) VALUES(source.name,btrim(p_new_version),p_effective_date,source.provenance,'Draft',FALSE,auth.uid()) RETURNING * INTO target;
 INSERT INTO public.ast_breakpoint_rules(breakpoint_set_id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes)
 SELECT target.id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes FROM public.ast_breakpoint_rules WHERE breakpoint_set_id=source.id;
 RETURN to_jsonb(target);
END $$;
CREATE OR REPLACE FUNCTION public.ast_save_breakpoint_rule(p_payload JSONB,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE saved public.ast_breakpoint_rules%ROWTYPE; target_id UUID:=NULLIF(p_payload->>'id','')::UUID; set_id UUID:=(p_payload->>'breakpoint_set_id')::UUID;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.ast_breakpoint_sets WHERE id=set_id AND status='Draft') THEN RAISE EXCEPTION 'Rules may be edited only in a draft breakpoint version.' USING ERRCODE='55000'; END IF;
 IF target_id IS NULL THEN
  INSERT INTO public.ast_breakpoint_rules(breakpoint_set_id,organism_group_id,antibiotic_id,method,metric_type,potency,automatic_interpretation_allowed,
   susceptible_min,susceptible_max,susceptible_secondary,intermediate_min,intermediate_max,intermediate_secondary_min,intermediate_secondary_max,
   resistant_min,resistant_max,resistant_secondary,intermediate_semantics,interpretation_semantics,notes)
  VALUES(set_id,(p_payload->>'organism_group_id')::UUID,(p_payload->>'antibiotic_id')::UUID,p_payload->>'method',p_payload->>'metric_type',p_payload->>'potency',COALESCE((p_payload->>'automatic_interpretation_allowed')::BOOLEAN,TRUE),
   NULLIF(p_payload->>'susceptible_min','')::NUMERIC,NULLIF(p_payload->>'susceptible_max','')::NUMERIC,NULLIF(p_payload->>'susceptible_secondary','')::NUMERIC,
   NULLIF(p_payload->>'intermediate_min','')::NUMERIC,NULLIF(p_payload->>'intermediate_max','')::NUMERIC,NULLIF(p_payload->>'intermediate_secondary_min','')::NUMERIC,NULLIF(p_payload->>'intermediate_secondary_max','')::NUMERIC,
   NULLIF(p_payload->>'resistant_min','')::NUMERIC,NULLIF(p_payload->>'resistant_max','')::NUMERIC,NULLIF(p_payload->>'resistant_secondary','')::NUMERIC,NULLIF(p_payload->>'intermediate_semantics',''),
   COALESCE(p_payload->'interpretation_semantics','{}'::JSONB),p_payload->>'notes') RETURNING * INTO saved;
 ELSE
  UPDATE public.ast_breakpoint_rules SET potency=p_payload->>'potency',automatic_interpretation_allowed=COALESCE((p_payload->>'automatic_interpretation_allowed')::BOOLEAN,TRUE),
   susceptible_min=NULLIF(p_payload->>'susceptible_min','')::NUMERIC,susceptible_max=NULLIF(p_payload->>'susceptible_max','')::NUMERIC,susceptible_secondary=NULLIF(p_payload->>'susceptible_secondary','')::NUMERIC,
   intermediate_min=NULLIF(p_payload->>'intermediate_min','')::NUMERIC,intermediate_max=NULLIF(p_payload->>'intermediate_max','')::NUMERIC,intermediate_secondary_min=NULLIF(p_payload->>'intermediate_secondary_min','')::NUMERIC,intermediate_secondary_max=NULLIF(p_payload->>'intermediate_secondary_max','')::NUMERIC,
   resistant_min=NULLIF(p_payload->>'resistant_min','')::NUMERIC,resistant_max=NULLIF(p_payload->>'resistant_max','')::NUMERIC,resistant_secondary=NULLIF(p_payload->>'resistant_secondary','')::NUMERIC,
   intermediate_semantics=NULLIF(p_payload->>'intermediate_semantics',''),interpretation_semantics=COALESCE(p_payload->'interpretation_semantics','{}'::JSONB),notes=p_payload->>'notes',row_version=row_version+1,updated_at=now()
  WHERE id=target_id AND breakpoint_set_id=set_id AND row_version=p_expected_revision RETURNING * INTO saved;
  IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint rule changed. Reload.' USING ERRCODE='PT409'; END IF;
 END IF; RETURN to_jsonb(saved);
END $$;
CREATE OR REPLACE FUNCTION public.ast_retire_breakpoint_set(p_set_id UUID,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_breakpoint_sets%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 UPDATE public.ast_breakpoint_sets SET status='Retired',is_active=FALSE,retired_at=now(),row_version=row_version+1 WHERE id=p_set_id AND row_version=p_expected_revision RETURNING * INTO saved;
 IF NOT FOUND THEN RAISE EXCEPTION 'Breakpoint set changed. Reload.' USING ERRCODE='PT409'; END IF; RETURN to_jsonb(saved);
END $$;
CREATE OR REPLACE FUNCTION public.ast_save_microorganism_mapping(p_code TEXT,p_display_name TEXT,p_group_id UUID,p_expected_revision BIGINT DEFAULT 0)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$ DECLARE saved public.ast_microorganisms%ROWTYPE;
BEGIN
 IF auth.uid() IS NULL OR NOT (public.is_super_admin() OR public.has_permission('can_manage_ast_breakpoints')) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 INSERT INTO public.ast_microorganisms(code,display_name,organism_group_id) VALUES(upper(btrim(p_code)),btrim(p_display_name),p_group_id)
 ON CONFLICT(code) DO UPDATE SET display_name=EXCLUDED.display_name,organism_group_id=EXCLUDED.organism_group_id,row_version=public.ast_microorganisms.row_version+1,updated_at=now()
 WHERE public.ast_microorganisms.row_version=p_expected_revision RETURNING * INTO saved;
 IF NOT FOUND THEN RAISE EXCEPTION 'Microorganism mapping changed. Reload.' USING ERRCODE='PT409'; END IF; RETURN to_jsonb(saved);
END $$;

CREATE OR REPLACE FUNCTION public.ast_guard_used_breakpoint_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.ast_observations WHERE breakpoint_set_id=OLD.id) AND
   (TG_OP='DELETE' OR OLD.name IS DISTINCT FROM NEW.name OR OLD.version IS DISTINCT FROM NEW.version OR OLD.effective_date IS DISTINCT FROM NEW.effective_date OR OLD.provenance IS DISTINCT FROM NEW.provenance) THEN
  RAISE EXCEPTION 'Historically used breakpoint versions are immutable; clone a new version.' USING ERRCODE='55000';
 END IF; RETURN CASE WHEN TG_OP='DELETE' THEN OLD ELSE NEW END;
END $$;
CREATE TRIGGER ast_used_breakpoint_immutable BEFORE UPDATE OR DELETE ON public.ast_breakpoint_sets FOR EACH ROW EXECUTE FUNCTION public.ast_guard_used_breakpoint_mutation();
CREATE OR REPLACE FUNCTION public.ast_guard_used_rule_mutation() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN
 IF EXISTS(SELECT 1 FROM public.ast_observations WHERE breakpoint_rule_id=OLD.id) THEN RAISE EXCEPTION 'Historically used breakpoint rules are immutable; clone a new version.' USING ERRCODE='55000'; END IF; RETURN NEW;
END $$;
CREATE TRIGGER ast_used_rule_immutable BEFORE UPDATE OR DELETE ON public.ast_breakpoint_rules FOR EACH ROW EXECUTE FUNCTION public.ast_guard_used_rule_mutation();

REVOKE ALL ON public.ast_breakpoint_sets,public.ast_organism_groups,public.ast_antibiotics,public.ast_microorganisms,public.ast_breakpoint_rules,public.ast_isolates,public.ast_observations,public.ast_observation_audit FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.ast_breakpoint_sets,public.ast_organism_groups,public.ast_antibiotics,public.ast_microorganisms,public.ast_breakpoint_rules TO authenticated;
GRANT SELECT ON public.ast_isolates,public.ast_observations,public.ast_observation_audit TO authenticated;
REVOKE ALL ON FUNCTION public.ast_interpret_breakpoint(TEXT,TEXT,TEXT,NUMERIC,NUMERIC,UUID),public.ast_save_isolate(UUID,INT,UUID,TEXT,BIGINT),public.ast_save_observation(UUID,UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,BIGINT),public.ast_activate_breakpoint_set(UUID,BIGINT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ast_interpret_breakpoint(TEXT,TEXT,TEXT,NUMERIC,NUMERIC,UUID),public.ast_save_isolate(UUID,INT,UUID,TEXT,BIGINT),public.ast_save_observation(UUID,UUID,TEXT,NUMERIC,NUMERIC,TEXT,TEXT,BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ast_activate_breakpoint_set(UUID,BIGINT) TO authenticated;
REVOKE ALL ON FUNCTION public.ast_save_breakpoint_set(JSONB,BIGINT),public.ast_clone_breakpoint_set(UUID,TEXT,DATE),public.ast_retire_breakpoint_set(UUID,BIGINT),public.ast_save_microorganism_mapping(TEXT,TEXT,UUID,BIGINT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ast_save_breakpoint_set(JSONB,BIGINT),public.ast_clone_breakpoint_set(UUID,TEXT,DATE),public.ast_retire_breakpoint_set(UUID,BIGINT),public.ast_save_microorganism_mapping(TEXT,TEXT,UUID,BIGINT) TO authenticated;
REVOKE ALL ON FUNCTION public.ast_save_breakpoint_rule(JSONB,BIGINT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.ast_save_breakpoint_rule(JSONB,BIGINT) TO authenticated;

DO $$ BEGIN
 IF (SELECT count(*) FROM public.ast_breakpoint_rules r JOIN public.ast_organism_groups g ON g.id=r.organism_group_id WHERE g.code='STAPHYLOCOCCUS_SPP')<>20 THEN RAISE EXCEPTION 'STAPH_BREAKPOINT_RULE_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.ast_breakpoint_rules r JOIN public.ast_organism_groups g ON g.id=r.organism_group_id WHERE g.code='ENTEROBACTERALES')<>28 THEN RAISE EXCEPTION 'ENTEROBACTERALES_BREAKPOINT_RULE_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.ast_breakpoint_rules r JOIN public.ast_organism_groups g ON g.id=r.organism_group_id WHERE g.code='PSEUDOMONAS_AERUGINOSA')<>20 THEN RAISE EXCEPTION 'PSEUDOMONAS_BREAKPOINT_RULE_COUNT_INVALID'; END IF;
 IF (SELECT count(*) FROM public.ast_antibiotics)<>23 THEN RAISE EXCEPTION 'AST_ANTIBIOTIC_MASTER_COUNT_INVALID'; END IF;
 IF EXISTS(SELECT code FROM public.ast_antibiotics GROUP BY code HAVING count(*)>1) THEN RAISE EXCEPTION 'AST_ANTIBIOTIC_DUPLICATE'; END IF;
END $$;

-- Activate only the dedicated specialist Pus Culture pathway after catalogue columns exist.
UPDATE public.tests SET name='Pus Culture and Sensitivity',sample_type='Pus',container='Not specified',method='Culture and antimicrobial susceptibility testing',
 reporting_type='InHouse',clinical_reporting_enabled=TRUE,billing_enabled=TRUE,collection_required=TRUE,allow_zero_price_billing=TRUE,
 workflow_supported=FALSE,is_active=TRUE,lifecycle_status='Active',clinical_configuration_status='Configured',catalogue_approved=TRUE,
 row_version=row_version+1,updated_at=now() WHERE code='PUS_CULTURE_AND_SENSITIVITY';
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required,interpretation_config)
SELECT id,'CULTURE_AST_SPECIALIST_SUMMARY','Culture and AST specialist summary','Text',1,TRUE,TRUE,'Active','Configured',FALSE,FALSE,FALSE,
 jsonb_build_object('control','Text Multi-line','specialist_workflow','PusCultureAST','report_visibility',FALSE)
FROM public.tests WHERE code='PUS_CULTURE_AND_SENSITIVITY'
ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,value_type='Text',display_order=1,is_active=TRUE,lifecycle_status='Active',interpretation_config=EXCLUDED.interpretation_config,row_version=public.parameters.row_version+1,updated_at=now();

CREATE OR REPLACE FUNCTION public.ast_enrich_frozen_report_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE inv JSONB; enriched JSONB:='[]'::JSONB; isolates JSONB;
BEGIN
 FOR inv IN SELECT value FROM jsonb_array_elements(COALESCE(NEW.clinical_snapshot_json->'investigations','[]'::JSONB)) LOOP
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'isolate_number',i.isolate_number,'organism',i.organism_name_snapshot,'organism_group',i.organism_group_snapshot,'growth_state',i.growth_state,
   'breakpoint_reference',CASE WHEN i.growth_state='Positive' THEN (SELECT 'AST interpreted using laboratory-approved breakpoint set '||max(o.breakpoint_set_version_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id) END,
   'observations',COALESCE((SELECT jsonb_agg(jsonb_build_object('antibiotic',o.antibiotic_name_snapshot,'antibiotic_code',o.antibiotic_code_snapshot,
    'method',o.method,'metric_type',o.metric_type,'metric_value',o.metric_value,'metric_secondary_value',o.metric_secondary_value,
    'interpretation',o.final_interpretation,'automatic_interpretation',o.automatic_interpretation,'manual_override',o.manual_override,
    'breakpoint_version',o.breakpoint_set_version_snapshot,'actor_id',o.actor_id) ORDER BY o.antibiotic_name_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id),'[]'::JSONB)
  ) ORDER BY i.isolate_number),'[]'::JSONB) INTO isolates FROM public.ast_isolates i WHERE i.order_item_id=(inv->>'order_item_id')::UUID;
  enriched:=enriched||jsonb_build_array(inv||jsonb_build_object('ast_isolates',isolates));
 END LOOP;
 NEW.clinical_snapshot_json:=jsonb_set(NEW.clinical_snapshot_json,'{investigations}',enriched,TRUE);
 RETURN NEW;
END $$;
CREATE TRIGGER ast_enrich_frozen_report BEFORE INSERT ON public.diagnostic_reports FOR EACH ROW EXECUTE FUNCTION public.ast_enrich_frozen_report_snapshot();
-- FINAL WINDOWS SMS GATEWAY OUTBOX HARDENING
-- Windows is the sole delivery owner. Cloud, browser and Edge callers have no
-- queue mutation or provider-dispatch authority.
ALTER TABLE public.sms_queue_items
  ADD COLUMN IF NOT EXISTS lease_owner UUID,
  ADD COLUMN IF NOT EXISTS lease_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS provider_call_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS provider_response_code TEXT,
  ADD COLUMN IF NOT EXISTS error_classification TEXT,
  ADD COLUMN IF NOT EXISTS final_state_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_attempt_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS manual_retry_count INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_manual_retry_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS last_manual_retry_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_sms_queue_gateway_due
  ON public.sms_queue_items(status, scheduled_at, created_at)
  WHERE status IN ('Pending','Failed');
CREATE INDEX IF NOT EXISTS idx_sms_queue_gateway_lease
  ON public.sms_queue_items(lease_expires_at)
  WHERE status='Processing';

CREATE OR REPLACE FUNCTION public.normalize_nepal_sms_mobile(p_mobile TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SET search_path=public,pg_temp AS $$
DECLARE v TEXT:=regexp_replace(btrim(COALESCE(p_mobile,'')),'[[:space:]()+-]','','g');
BEGIN
  IF v LIKE '977%' AND length(v)=13 THEN v:=substring(v FROM 4); END IF;
  IF v !~ '^(97|98)[0-9]{8}$' THEN
    RAISE EXCEPTION 'A valid Nepal mobile number is required.' USING ERRCODE='22023';
  END IF;
  RETURN v;
END;$$;

CREATE OR REPLACE FUNCTION public.guard_sms_queue_item()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
BEGIN
  NEW.recipient_phone:=public.normalize_nepal_sms_mobile(NEW.recipient_phone);
  IF NEW.idempotency_key IS NULL OR btrim(NEW.idempotency_key)='' THEN
    RAISE EXCEPTION 'SMS idempotency key is required.' USING ERRCODE='22023';
  END IF;
  IF NEW.status='Sent' AND NEW.sent_at IS NULL THEN NEW.sent_at:=NOW(); END IF;
  IF NEW.status IN ('Sent','DeadLetter') THEN NEW.final_state_at:=COALESCE(NEW.final_state_at,NOW()); END IF;
  NEW.updated_at:=NOW();
  RETURN NEW;
END;$$;
DROP TRIGGER IF EXISTS trg_sms_queue_item_guard ON public.sms_queue_items;
CREATE TRIGGER trg_sms_queue_item_guard BEFORE INSERT OR UPDATE ON public.sms_queue_items
FOR EACH ROW EXECUTE FUNCTION public.guard_sms_queue_item();

CREATE OR REPLACE FUNCTION public.claim_next_sms_gateway_item(p_worker_id UUID,p_lease_seconds INT DEFAULT 300)
RETURNS TABLE(id UUID,sms_type VARCHAR,recipient_phone VARCHAR,message_body TEXT,retry_count INT,max_attempts INT,idempotency_key VARCHAR,lease_owner UUID)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF p_worker_id IS NULL OR p_lease_seconds NOT BETWEEN 60 AND 900 THEN RAISE EXCEPTION 'Valid worker and lease are required.' USING ERRCODE='22023'; END IF;
 RETURN QUERY WITH candidate AS (
   SELECT q.id FROM public.sms_queue_items q
   WHERE q.status IN ('Pending','Failed') AND q.scheduled_at<=NOW() AND q.retry_count<q.max_attempts
   ORDER BY q.scheduled_at,q.created_at,q.id FOR UPDATE SKIP LOCKED LIMIT 1
 ) UPDATE public.sms_queue_items q SET status='Processing',lease_owner=p_worker_id,
   lease_expires_at=NOW()+make_interval(secs=>p_lease_seconds),provider_call_started_at=NULL,
   error_message=NULL,error_classification=NULL,updated_at=NOW()
 FROM candidate c WHERE q.id=c.id
 RETURNING q.id,q.sms_type,q.recipient_phone,q.message_body,q.retry_count,q.max_attempts,q.idempotency_key,q.lease_owner;
END;$$;

CREATE OR REPLACE FUNCTION public.mark_sms_provider_call_started(p_sms_id UUID,p_worker_id UUID)
RETURNS BOOLEAN LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 UPDATE public.sms_queue_items SET provider_call_started_at=NOW(),updated_at=NOW()
 WHERE id=p_sms_id AND status='Processing' AND lease_owner=p_worker_id AND lease_expires_at>NOW() AND provider_call_started_at IS NULL;
 RETURN FOUND;
END;$$;

CREATE OR REPLACE FUNCTION public.complete_sms_gateway_item(
 p_sms_id UUID,p_worker_id UUID,p_accepted BOOLEAN,p_provider_msg_id TEXT DEFAULT NULL,
 p_provider_response JSONB DEFAULT NULL,p_provider_response_code TEXT DEFAULT NULL,
 p_error_msg TEXT DEFAULT NULL,p_error_classification TEXT DEFAULT NULL,p_retryable BOOLEAN DEFAULT FALSE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE; attempts INT; next_status TEXT;
BEGIN
 SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
 IF q.status='Sent' THEN RETURN jsonb_build_object('success',true,'status','Sent','already_completed',true); END IF;
 IF q.status<>'Processing' OR q.lease_owner IS DISTINCT FROM p_worker_id THEN RAISE EXCEPTION 'SMS lease ownership conflict.' USING ERRCODE='40001'; END IF;
 IF q.provider_call_started_at IS NULL THEN RAISE EXCEPTION 'Provider call was not marked as started.' USING ERRCODE='55000'; END IF;
 IF p_accepted THEN
   UPDATE public.sms_queue_items SET status='Sent',sent_at=NOW(),final_state_at=NOW(),delivery_attempt_count=delivery_attempt_count+1,provider_message_id=p_provider_msg_id,
    provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,error_message=NULL,error_classification=NULL,
    lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
   INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_SENT','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('provider_message_id',p_provider_msg_id));
   RETURN jsonb_build_object('success',true,'status','Sent');
 END IF;
 attempts:=q.retry_count+1;
 next_status:=CASE WHEN NOT p_retryable OR attempts>=q.max_attempts THEN 'DeadLetter' ELSE 'Failed' END;
 UPDATE public.sms_queue_items SET status=next_status,retry_count=attempts,delivery_attempt_count=delivery_attempt_count+1,
   scheduled_at=CASE WHEN next_status='Failed' THEN NOW()+make_interval(secs=>CASE attempts WHEN 1 THEN 120 WHEN 2 THEN 600 WHEN 3 THEN 1800 ELSE 3600 END) ELSE scheduled_at END,
   provider_response_json=p_provider_response,provider_response_code=p_provider_response_code,
   error_message=left(COALESCE(p_error_msg,'Delivery failed'),500),error_classification=COALESCE(p_error_classification,CASE WHEN p_retryable THEN 'RetryableProviderFailure' ELSE 'PermanentProviderFailure' END),
   final_state_at=CASE WHEN next_status='DeadLetter' THEN NOW() ELSE NULL END,lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
 INSERT INTO public.audit_logs(action,entity_type,entity_id,new_data) VALUES('SMS_FAILED','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('attempt',attempts,'status',next_status,'classification',p_error_classification));
 RETURN jsonb_build_object('success',true,'status',next_status,'attempt',attempts);
END;$$;

CREATE OR REPLACE FUNCTION public.recover_stale_sms_gateway_items(p_stale_after_seconds INT DEFAULT 300)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE recovered INT:=0; quarantined INT:=0;
BEGIN
 IF p_stale_after_seconds NOT BETWEEN 60 AND 3600 THEN RAISE EXCEPTION 'Stale threshold must be between 60 and 3600 seconds.' USING ERRCODE='22023'; END IF;
 WITH stale AS (SELECT id,provider_call_started_at FROM public.sms_queue_items WHERE status='Processing' AND COALESCE(lease_expires_at,updated_at+make_interval(secs=>p_stale_after_seconds))<=NOW() FOR UPDATE SKIP LOCKED), changed AS (
 UPDATE public.sms_queue_items q SET status=CASE WHEN s.provider_call_started_at IS NULL THEN 'Pending' ELSE 'DeadLetter' END,
   retry_count=CASE WHEN s.provider_call_started_at IS NULL THEN q.retry_count ELSE LEAST(q.retry_count+1,q.max_attempts) END,
   scheduled_at=CASE WHEN s.provider_call_started_at IS NULL THEN NOW() ELSE q.scheduled_at END,
   error_classification=CASE WHEN s.provider_call_started_at IS NULL THEN 'LeaseExpiredBeforeProviderCall' ELSE 'ProviderOutcomeUnknown' END,
   error_message=CASE WHEN s.provider_call_started_at IS NULL THEN 'Gateway lease expired before provider call; safely returned to queue.' ELSE 'Gateway stopped after provider call began; automatic resend blocked because provider outcome is unknown.' END,
   final_state_at=CASE WHEN s.provider_call_started_at IS NULL THEN NULL ELSE NOW() END,lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW()
 FROM stale s WHERE q.id=s.id RETURNING q.status)
 SELECT count(*) FILTER(WHERE status='Pending'),count(*) FILTER(WHERE status='DeadLetter') INTO recovered,quarantined FROM changed;
 RETURN jsonb_build_object('success',true,'recovered',recovered,'deadlettered',quarantined);
END;$$;

CREATE OR REPLACE FUNCTION public.retry_sms_delivery(p_sms_id UUID,p_reason TEXT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE q public.sms_queue_items%ROWTYPE; reason TEXT:=btrim(COALESCE(p_reason,''));
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF length(reason) NOT BETWEEN 5 AND 500 THEN RAISE EXCEPTION 'A retry reason is required.' USING ERRCODE='22023'; END IF;
 SELECT * INTO q FROM public.sms_queue_items WHERE id=p_sms_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'SMS queue item not found.' USING ERRCODE='P0002'; END IF;
 IF q.status='Sent' THEN RAISE EXCEPTION 'Sent SMS cannot be retried.' USING ERRCODE='55000'; END IF;
 IF q.status NOT IN ('Failed','DeadLetter') THEN RAISE EXCEPTION 'Only Failed or DeadLetter SMS may be retried.' USING ERRCODE='55000'; END IF;
 UPDATE public.sms_queue_items SET status='Pending',retry_count=0,scheduled_at=NOW(),final_state_at=NULL,error_classification='ManualRetry',
  manual_retry_count=manual_retry_count+1,last_manual_retry_at=NOW(),last_manual_retry_by=auth.uid(),lease_owner=NULL,lease_expires_at=NULL,provider_call_started_at=NULL,updated_at=NOW() WHERE id=p_sms_id;
 INSERT INTO public.audit_logs(user_id,action,entity_type,entity_id,new_data) VALUES(auth.uid(),'SMS_MANUAL_RETRY','SmsQueueItem',p_sms_id::TEXT,jsonb_build_object('reason',reason,'previous_status',q.status,'manual_retry_count',q.manual_retry_count+1));
 RETURN jsonb_build_object('success',true,'status','Pending','id',p_sms_id);
END;$$;

REVOKE ALL ON FUNCTION public.normalize_nepal_sms_mobile(TEXT),public.guard_sms_queue_item(),public.claim_next_sms_gateway_item(UUID,INT),public.mark_sms_provider_call_started(UUID,UUID),public.complete_sms_gateway_item(UUID,UUID,BOOLEAN,TEXT,JSONB,TEXT,TEXT,TEXT,BOOLEAN),public.recover_stale_sms_gateway_items(INT),public.retry_sms_delivery(UUID,TEXT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.claim_next_sms_gateway_item(UUID,INT),public.mark_sms_provider_call_started(UUID,UUID),public.complete_sms_gateway_item(UUID,UUID,BOOLEAN,TEXT,JSONB,TEXT,TEXT,TEXT,BOOLEAN),public.recover_stale_sms_gateway_items(INT) TO service_role;
GRANT EXECUTE ON FUNCTION public.retry_sms_delivery(UUID,TEXT) TO authenticated;

DROP FUNCTION IF EXISTS public.get_sms_delivery_status(INT);
CREATE FUNCTION public.get_sms_delivery_status(p_limit INT DEFAULT 200)
RETURNS TABLE(id UUID,event_type TEXT,lab_no TEXT,mobile TEXT,status TEXT,provider_status TEXT,provider_message_id TEXT,retry_count INT,manual_retry_count INT,estimated_segments INT,created_at TIMESTAMPTZ,sent_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT q.id,
  CASE q.sms_type WHEN 'BillRegistration' THEN 'Payment Confirmation' WHEN 'ReportReady' THEN 'Report Ready' ELSE 'Transactional SMS' END::TEXT,
  COALESCE(o.order_number,ro.order_number,b.bill_number)::TEXT,q.recipient_phone::TEXT,q.status::TEXT,
  left(COALESCE(q.error_message,CASE WHEN q.status='Sent' THEN 'Accepted' ELSE q.error_classification END,q.status),500)::TEXT,
  q.provider_message_id::TEXT,q.delivery_attempt_count,q.manual_retry_count,
  CASE WHEN q.message_body~'^[\u0000-\u007F]*$' THEN CASE WHEN length(q.message_body)<=160 THEN 1 ELSE ceil(length(q.message_body)::NUMERIC/153)::INT END ELSE CASE WHEN length(q.message_body)<=70 THEN 1 ELSE ceil(length(q.message_body)::NUMERIC/67)::INT END END,
  q.created_at,q.sent_at
 FROM public.sms_queue_items q LEFT JOIN public.bills b ON b.id=q.bill_id LEFT JOIN public.clinical_orders o ON o.bill_id=q.bill_id
 LEFT JOIN public.diagnostic_reports r ON r.id=q.diagnostic_report_id LEFT JOIN public.clinical_orders ro ON ro.id=r.order_id
 ORDER BY q.created_at DESC LIMIT greatest(1,least(COALESCE(p_limit,200),500));
END;$$;
REVOKE ALL ON FUNCTION public.get_sms_delivery_status(INT) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.get_sms_delivery_status(INT) TO authenticated;
DROP POLICY IF EXISTS "Admins can view SMS queue items" ON public.sms_queue_items;
REVOKE SELECT ON public.sms_queue_items FROM authenticated;

-- ============================================================================
-- FINAL MINIMAL-LIS OPERATIONAL REMEDIATION
-- These forward definitions replace capped browser reads and complete the
-- specialist Pus Culture worksheet without changing historical clinical rows.
-- ============================================================================

CREATE TABLE public.pus_culture_worksheets (
 id UUID PRIMARY KEY DEFAULT public.uuid_generate_v4(),
 order_item_id UUID NOT NULL UNIQUE REFERENCES public.clinical_order_items(id) ON DELETE RESTRICT,
 specimen_source TEXT NOT NULL CHECK(specimen_source IN('Wound Swab','Abscess Aspirate','Surgical Site','Ulcer Swab','Tissue Biopsy','Other')),
 specimen_source_other TEXT,
 gram_stain_pus_cells TEXT NOT NULL CHECK(gram_stain_pus_cells IN('Occasional (0-1 / LPF)','Few (1-5 / HPF)','Moderate (5-20 / HPF)','Plenty / Numerous (>20 / HPF)')),
 direct_smear_organisms TEXT NOT NULL DEFAULT '',
 culture_status TEXT NOT NULL CHECK(culture_status IN(
  'No growth after 48 hours of aerobic incubation at 37°C',
  'Growth obtained (Pathogen isolated)',
  'Mixed bacterial growth (Skin flora / Probable contamination)',
  'Light growth of doubtful clinical significance')),
 final_remarks TEXT NOT NULL DEFAULT '',
 status TEXT NOT NULL DEFAULT 'Draft' CHECK(status IN('Draft','Submitted','Verified','SignedOff')),
 row_version BIGINT NOT NULL DEFAULT 1,
 created_by UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 updated_by UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE RESTRICT,
 created_at TIMESTAMPTZ NOT NULL DEFAULT now(), updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
 CHECK(specimen_source<>'Other' OR btrim(COALESCE(specimen_source_other,''))<>'' )
);
ALTER TABLE public.pus_culture_worksheets ENABLE ROW LEVEL SECURITY;
CREATE POLICY pus_culture_worksheet_staff_read ON public.pus_culture_worksheets FOR SELECT TO authenticated
 USING(public.is_active_user() AND (public.has_permission('can_enter_results') OR public.has_permission('can_verify_results') OR public.has_permission('can_sign_reports')));
REVOKE ALL ON public.pus_culture_worksheets FROM PUBLIC,anon,authenticated;
GRANT SELECT ON public.pus_culture_worksheets TO authenticated;

CREATE OR REPLACE FUNCTION public.save_pus_culture_worksheet(p_order_item_id UUID,p_payload JSONB,p_expected_revision BIGINT)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE prior public.pus_culture_worksheets%ROWTYPE; saved public.pus_culture_worksheets%ROWTYPE; test_code TEXT;
 source_value TEXT:=btrim(COALESCE(p_payload->>'specimen_source','')); other_value TEXT:=NULLIF(btrim(COALESCE(p_payload->>'specimen_source_other','')),'');
 pus_cells TEXT:=btrim(COALESCE(p_payload->>'gram_stain_pus_cells','')); culture_value TEXT:=btrim(COALESCE(p_payload->>'culture_status',''));
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_enter_results') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 SELECT t.code INTO test_code FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id WHERE oi.id=p_order_item_id;
 IF test_code IS DISTINCT FROM 'PUS_CULTURE_AND_SENSITIVITY' THEN RAISE EXCEPTION 'Pus Culture order item required.' USING ERRCODE='23514'; END IF;
 IF source_value NOT IN('Wound Swab','Abscess Aspirate','Surgical Site','Ulcer Swab','Tissue Biopsy','Other') OR
    pus_cells NOT IN('Occasional (0-1 / LPF)','Few (1-5 / HPF)','Moderate (5-20 / HPF)','Plenty / Numerous (>20 / HPF)') OR
    culture_value NOT IN('No growth after 48 hours of aerobic incubation at 37°C','Growth obtained (Pathogen isolated)','Mixed bacterial growth (Skin flora / Probable contamination)','Light growth of doubtful clinical significance') THEN
   RAISE EXCEPTION 'Complete the controlled specimen, smear and culture fields.' USING ERRCODE='23514';
 END IF;
 IF source_value='Other' AND other_value IS NULL THEN RAISE EXCEPTION 'Specify the Other specimen source/site.' USING ERRCODE='23514'; END IF;
 SELECT * INTO prior FROM public.pus_culture_worksheets WHERE order_item_id=p_order_item_id FOR UPDATE;
 IF FOUND AND prior.row_version<>p_expected_revision THEN RAISE EXCEPTION 'PUS_CULTURE_WORKSHEET_REVISION_CONFLICT' USING ERRCODE='PT409'; END IF;
 INSERT INTO public.pus_culture_worksheets(order_item_id,specimen_source,specimen_source_other,gram_stain_pus_cells,direct_smear_organisms,culture_status,final_remarks,status,created_by,updated_by)
 VALUES(p_order_item_id,source_value,other_value,pus_cells,btrim(COALESCE(p_payload->>'direct_smear_organisms','')),culture_value,btrim(COALESCE(p_payload->>'final_remarks','')),COALESCE(NULLIF(p_payload->>'status',''),'Draft'),auth.uid(),auth.uid())
 ON CONFLICT(order_item_id) DO UPDATE SET specimen_source=EXCLUDED.specimen_source,specimen_source_other=EXCLUDED.specimen_source_other,
  gram_stain_pus_cells=EXCLUDED.gram_stain_pus_cells,direct_smear_organisms=EXCLUDED.direct_smear_organisms,culture_status=EXCLUDED.culture_status,
  final_remarks=EXCLUDED.final_remarks,status=EXCLUDED.status,row_version=public.pus_culture_worksheets.row_version+1,updated_by=auth.uid(),updated_at=now()
 RETURNING * INTO saved;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
 VALUES(auth.uid(),public.catalogue_actor_name(),'PUS_CULTURE_WORKSHEET_SAVED','ClinicalOrderItem',p_order_item_id::TEXT,
  CASE WHEN prior.id IS NULL THEN NULL ELSE jsonb_build_object('row_version',prior.row_version,'status',prior.status) END,
  jsonb_build_object('row_version',saved.row_version,'status',saved.status,'specimen_source',saved.specimen_source,'culture_status',saved.culture_status));
 RETURN to_jsonb(saved);
END $$;
REVOKE ALL ON FUNCTION public.save_pus_culture_worksheet(UUID,JSONB,BIGINT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.save_pus_culture_worksheet(UUID,JSONB,BIGINT) TO authenticated;

-- Extend the existing immutable report snapshot trigger with worksheet evidence.
CREATE OR REPLACE FUNCTION public.ast_enrich_frozen_report_snapshot() RETURNS trigger LANGUAGE plpgsql SET search_path=public,pg_temp AS $$
DECLARE inv JSONB; enriched JSONB:='[]'::JSONB; isolates JSONB; worksheet JSONB;
BEGIN
 FOR inv IN SELECT value FROM jsonb_array_elements(COALESCE(NEW.clinical_snapshot_json->'investigations','[]'::JSONB)) LOOP
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
   'isolate_number',i.isolate_number,'organism',i.organism_name_snapshot,'organism_group',i.organism_group_snapshot,'growth_state',i.growth_state,
   'breakpoint_reference',CASE WHEN i.growth_state='Positive' THEN (SELECT 'AST interpreted using laboratory-approved breakpoint set '||max(o.breakpoint_set_version_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id) END,
   'observations',COALESCE((SELECT jsonb_agg(jsonb_build_object('antibiotic',o.antibiotic_name_snapshot,'antibiotic_code',o.antibiotic_code_snapshot,
    'method',o.method,'metric_type',o.metric_type,'metric_value',o.metric_value,'metric_secondary_value',o.metric_secondary_value,
    'interpretation',o.final_interpretation,'automatic_interpretation',o.automatic_interpretation,'manual_override',o.manual_override,
    'breakpoint_version',o.breakpoint_set_version_snapshot) ORDER BY o.antibiotic_name_snapshot) FROM public.ast_observations o WHERE o.isolate_id=i.id),'[]'::JSONB)
  ) ORDER BY i.isolate_number),'[]'::JSONB) INTO isolates FROM public.ast_isolates i WHERE i.order_item_id=(inv->>'order_item_id')::UUID;
  SELECT jsonb_build_object('specimen_source',w.specimen_source,'specimen_source_other',w.specimen_source_other,'gram_stain_pus_cells',w.gram_stain_pus_cells,
   'direct_smear_organisms',w.direct_smear_organisms,'culture_status',w.culture_status,'final_remarks',w.final_remarks,'status',w.status,'row_version',w.row_version)
   INTO worksheet FROM public.pus_culture_worksheets w WHERE w.order_item_id=(inv->>'order_item_id')::UUID;
  enriched:=enriched||jsonb_build_array(inv||jsonb_build_object('ast_isolates',isolates,'pus_culture_worksheet',worksheet));
 END LOOP;
 NEW.clinical_snapshot_json:=jsonb_set(NEW.clinical_snapshot_json,'{investigations}',enriched,TRUE); RETURN NEW;
END $$;

CREATE INDEX sms_queue_admin_cursor_idx ON public.sms_queue_items(created_at DESC,id DESC);
CREATE INDEX sms_queue_admin_type_cursor_idx ON public.sms_queue_items(sms_type,created_at DESC,id DESC);
CREATE INDEX audit_logs_admin_cursor_idx ON public.audit_logs(timestamp DESC,id DESC);
CREATE INDEX audit_logs_actor_cursor_idx ON public.audit_logs(user_name,timestamp DESC,id DESC);

DROP FUNCTION IF EXISTS public.search_sms_delivery_status(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT);
CREATE FUNCTION public.search_sms_delivery_status(p_status TEXT DEFAULT NULL,p_event_type TEXT DEFAULT NULL,p_search TEXT DEFAULT NULL,p_date DATE DEFAULT NULL,p_cursor_created_at TIMESTAMPTZ DEFAULT NULL,p_cursor_id UUID DEFAULT NULL,p_limit INT DEFAULT 50)
RETURNS TABLE(item JSONB,sort_created_at TIMESTAMPTZ,sort_id UUID) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT (public.has_permission('can_manage_users') OR public.is_super_admin()) THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',q.id,'event_type',CASE q.sms_type WHEN 'BillRegistration' THEN 'Payment Confirmation' WHEN 'ReportReady' THEN 'Report Ready' ELSE 'Transactional SMS' END,
  'lab_no',COALESCE(o.order_number,ro.order_number,b.bill_number),'mobile',q.recipient_phone,'status',q.status,
  'provider_status',left(COALESCE(q.error_message,CASE WHEN q.status='Sent' THEN 'Accepted' ELSE q.error_classification END,q.status),500),
  'provider_message_id',q.provider_message_id,'retry_count',q.delivery_attempt_count,'manual_retry_count',q.manual_retry_count,'created_at',q.created_at,'sent_at',q.sent_at),q.created_at,q.id
 FROM public.sms_queue_items q LEFT JOIN public.bills b ON b.id=q.bill_id LEFT JOIN public.clinical_orders o ON o.bill_id=q.bill_id
 LEFT JOIN public.diagnostic_reports r ON r.id=q.diagnostic_report_id LEFT JOIN public.clinical_orders ro ON ro.id=r.order_id
 WHERE (p_status IS NULL OR q.status=p_status) AND (p_event_type IS NULL OR q.sms_type=CASE p_event_type WHEN 'Payment Confirmation' THEN 'BillRegistration' WHEN 'Report Ready' THEN 'ReportReady' ELSE p_event_type END)
  AND (p_date IS NULL OR (q.created_at AT TIME ZONE 'Asia/Kathmandu')::DATE=p_date)
  AND (p_search IS NULL OR COALESCE(o.order_number,ro.order_number,b.bill_number,'') ILIKE '%'||btrim(p_search)||'%' OR q.recipient_phone ILIKE '%'||regexp_replace(p_search,'\s','','g')||'%')
  AND (p_cursor_created_at IS NULL OR (q.created_at,q.id)<(p_cursor_created_at,p_cursor_id))
 ORDER BY q.created_at DESC,q.id DESC LIMIT greatest(1,least(COALESCE(p_limit,50),101));
END $$;
REVOKE ALL ON FUNCTION public.search_sms_delivery_status(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_sms_delivery_status(TEXT,TEXT,TEXT,DATE,TIMESTAMPTZ,UUID,INT) TO authenticated;

CREATE FUNCTION public.search_audit_log(p_actor TEXT DEFAULT NULL,p_action TEXT DEFAULT NULL,p_entity TEXT DEFAULT NULL,p_date_from DATE DEFAULT NULL,p_date_to DATE DEFAULT NULL,p_exact_id TEXT DEFAULT NULL,p_cursor_timestamp TIMESTAMPTZ DEFAULT NULL,p_cursor_id UUID DEFAULT NULL,p_limit INT DEFAULT 50)
RETURNS TABLE(item JSONB,sort_timestamp TIMESTAMPTZ,sort_id UUID) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_view_audit_logs') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT jsonb_build_object('id',a.id,'action',a.action,'entity_type',a.entity_type,'entity_id',a.entity_id,'user_name',a.user_name,'timestamp',a.timestamp),a.timestamp,a.id
 FROM public.audit_logs a WHERE (p_actor IS NULL OR a.user_name ILIKE '%'||btrim(p_actor)||'%') AND (p_action IS NULL OR a.action ILIKE '%'||btrim(p_action)||'%')
  AND (p_entity IS NULL OR a.entity_type ILIKE '%'||btrim(p_entity)||'%') AND (p_exact_id IS NULL OR a.entity_id=p_exact_id)
  AND (p_date_from IS NULL OR (a.timestamp AT TIME ZONE 'Asia/Kathmandu')::DATE>=p_date_from) AND (p_date_to IS NULL OR (a.timestamp AT TIME ZONE 'Asia/Kathmandu')::DATE<=p_date_to)
  AND (p_cursor_timestamp IS NULL OR (a.timestamp,a.id)<(p_cursor_timestamp,p_cursor_id))
 ORDER BY a.timestamp DESC,a.id DESC LIMIT greatest(1,least(COALESCE(p_limit,50),101));
END $$;
REVOKE ALL ON FUNCTION public.search_audit_log(TEXT,TEXT,TEXT,DATE,DATE,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_audit_log(TEXT,TEXT,TEXT,DATE,DATE,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;

CREATE FUNCTION public.get_technician_operational_summary() RETURNS JSONB LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE today_start TIMESTAMPTZ:=(date_trunc('day',now() AT TIME ZONE 'Asia/Kathmandu') AT TIME ZONE 'Asia/Kathmandu');
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() OR NOT public.has_permission('can_view_dashboard') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN jsonb_build_object(
  'today_patients',(SELECT count(*) FROM public.patients WHERE created_at>=today_start),'today_orders',(SELECT count(*) FROM public.clinical_orders WHERE created_at>=today_start),
  'samples_pending',(SELECT count(*) FROM public.samples WHERE status='Pending'),'samples_received',(SELECT count(*) FROM public.samples WHERE status='Received'),
  'samples_rejected',(SELECT count(*) FROM public.samples WHERE status='Rejected'),'worklist_pending',(SELECT count(*) FROM public.clinical_order_items WHERE status IN('SampleReceived','ResultDrafted')),
  'result_entry_pending',(SELECT count(*) FROM public.clinical_order_items WHERE status='SampleReceived'),
  'awaiting_verification',(SELECT count(DISTINCT order_item_id) FROM public.test_results WHERE status='SubmittedForVerification'),
  'specialist_microbiology_pending',(SELECT count(*) FROM public.clinical_order_items oi JOIN public.tests t ON t.id=oi.test_id WHERE t.code='PUS_CULTURE_AND_SENSITIVITY' AND oi.status NOT IN('Verified','SignedOff')),
  'signed_reports_today',(SELECT count(*) FROM public.diagnostic_reports WHERE status IN('SignedOff','Amended') AND created_at>=today_start),
  'critical_unacknowledged',(SELECT count(*) FROM public.test_results WHERE is_critical AND NOT critical_acknowledged),
  'department_workload',(SELECT COALESCE(jsonb_agg(jsonb_build_object('department',x.department,'count',x.count) ORDER BY x.department),'[]'::JSONB) FROM (SELECT COALESCE(NULLIF(btrim(department),''),'Unassigned') department,count(*) count FROM public.clinical_order_items WHERE status IN('Pending','SampleCollected','SampleReceived','ResultDrafted','Verified') GROUP BY 1)x),
  'recent_orders',(SELECT COALESCE(jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC),'[]'::JSONB) FROM (SELECT o.id,o.order_number,o.status,o.created_at,p.uhid,p.full_name,p.age_years,p.gender FROM public.clinical_orders o JOIN public.patients p ON p.id=o.patient_id ORDER BY o.created_at DESC LIMIT 8)x),
  'critical_items',(SELECT COALESCE(jsonb_agg(to_jsonb(x)),'[]'::JSONB) FROM (SELECT tr.id,tr.parameter_name,tr.display_value,tr.flag FROM public.test_results tr WHERE tr.is_critical AND NOT tr.critical_acknowledged ORDER BY tr.created_at DESC LIMIT 5)x));
END $$;
REVOKE ALL ON FUNCTION public.get_technician_operational_summary() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.get_technician_operational_summary() TO authenticated;

CREATE FUNCTION public.catalogue_delete_panel(p_panel_id UUID,p_expected_version BIGINT) RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE p public.catalogue_panels%ROWTYPE; referenced BOOLEAN;
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO p FROM public.catalogue_panels WHERE id=p_panel_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Panel not found.' USING ERRCODE='P0002'; END IF; IF p.row_version<>p_expected_version THEN RAISE EXCEPTION 'Panel changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 SELECT EXISTS(SELECT 1 FROM public.bill_panel_selections WHERE panel_id=p_panel_id) INTO referenced;
 IF referenced THEN PERFORM public.catalogue_set_panel_lifecycle(p_panel_id,'Archived',p_expected_version); RETURN 'Archived'; END IF;
 DELETE FROM public.catalogue_panel_components WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panel_ratelist_links WHERE panel_id=p_panel_id;
 DELETE FROM public.catalogue_panel_identity_resolution WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panel_services WHERE panel_id=p_panel_id; DELETE FROM public.catalogue_panels WHERE id=p_panel_id; RETURN 'Deleted';
END $$;
REVOKE ALL ON FUNCTION public.catalogue_delete_panel(UUID,BIGINT) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_delete_panel(UUID,BIGINT) TO authenticated;

CREATE FUNCTION public.catalogue_price_master() RETURNS TABLE(item JSONB) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY WITH entities AS (
  SELECT 'Test'::TEXT type,t.id,t.code::TEXT,t.name::TEXT,c.name::TEXT category,t.lifecycle_status::TEXT status FROM public.tests t LEFT JOIN public.test_categories c ON c.id=t.category_id
  UNION ALL SELECT 'Panel',ps.id,ps.code,ps.name,c.name,ps.lifecycle_status::TEXT FROM public.catalogue_panel_services ps LEFT JOIN public.test_categories c ON c.id=ps.category_id
  UNION ALL SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,'Packages',p.lifecycle_status::TEXT FROM public.health_packages p
 ), rates AS (SELECT r.*,row_number() OVER(PARTITION BY entity_type,test_id,panel_service_id,package_id,other_service_code ORDER BY version_number DESC) rn FROM public.catalogue_rate_versions r)
 SELECT jsonb_build_object('entity_type',e.type,'entity_id',e.id,'code',e.code,'name',e.name,'category',e.category,'entity_status',e.status,
  'rate_id',r.id,'version_number',r.version_number,'price_paisa',r.price_paisa,'effective_from',r.effective_from,'rate_status',r.status,'row_version',r.row_version)
 FROM entities e LEFT JOIN rates r ON r.rn=1 AND ((e.type='Test' AND r.test_id=e.id) OR(e.type='Panel' AND r.panel_service_id=e.id) OR(e.type='Package' AND r.package_id=e.id)) ORDER BY e.type,e.name;
END $$;
REVOKE ALL ON FUNCTION public.catalogue_price_master() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.catalogue_price_master() TO authenticated;

CREATE FUNCTION public.search_patient_history(p_patient_id UUID,p_section TEXT,p_cursor_timestamp TIMESTAMPTZ DEFAULT NULL,p_cursor_id UUID DEFAULT NULL,p_limit INT DEFAULT 25)
RETURNS TABLE(item JSONB,sort_timestamp TIMESTAMPTZ,sort_id UUID) LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.is_active_user() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF p_section='orders' THEN RETURN QUERY SELECT jsonb_build_object('id',o.id,'order_number',o.order_number,'status',o.status,'created_at',o.created_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('test_name',i.test_name) ORDER BY i.created_at) FROM public.clinical_order_items i WHERE i.order_id=o.id),'[]'::JSONB)),o.created_at,o.id FROM public.clinical_orders o WHERE o.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(o.created_at,o.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY o.created_at DESC,o.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='bills' THEN RETURN QUERY SELECT jsonb_build_object('id',b.id,'bill_number',b.bill_number,'bill_date',b.bill_date,'gross_amount_paisa',b.gross_amount_paisa,'net_amount_paisa',b.net_amount_paisa,'paid_amount_paisa',b.paid_amount_paisa,'due_amount_paisa',b.due_amount_paisa,'payment_status',b.payment_status,'created_at',b.created_at,'clinical_orders',COALESCE((SELECT jsonb_agg(jsonb_build_object('order_number',o.order_number) ORDER BY o.created_at) FROM public.clinical_orders o WHERE o.bill_id=b.id),'[]'::JSONB),'payment_transactions',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pt.id,'receipt_number',pt.receipt_number,'amount_paisa',pt.amount_paisa,'payment_mode',pt.payment_mode,'created_at',pt.created_at) ORDER BY pt.created_at) FROM public.payment_transactions pt WHERE pt.bill_id=b.id),'[]'::JSONB)),b.created_at,b.id FROM public.bills b WHERE b.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(b.created_at,b.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY b.created_at DESC,b.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSIF p_section='reports' THEN RETURN QUERY SELECT jsonb_build_object('id',r.id,'report_number',r.report_number,'version',r.version,'is_amendment',r.is_amendment,'amendment_reason',r.amendment_reason,'status',r.status,'signed_at',r.signed_at,'integrity_hash',r.integrity_hash),r.signed_at,r.id FROM public.diagnostic_reports r WHERE r.patient_id=p_patient_id AND(p_cursor_timestamp IS NULL OR(r.signed_at,r.id)<(p_cursor_timestamp,p_cursor_id)) ORDER BY r.signed_at DESC,r.id DESC LIMIT greatest(1,least(COALESCE(p_limit,25),51));
 ELSE RAISE EXCEPTION 'Unknown patient history section.' USING ERRCODE='22023'; END IF;
END $$;
REVOKE ALL ON FUNCTION public.search_patient_history(UUID,TEXT,TIMESTAMPTZ,UUID,INT) FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.search_patient_history(UUID,TEXT,TIMESTAMPTZ,UUID,INT) TO authenticated;
