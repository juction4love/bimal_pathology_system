-- Bimal Pathology: production catalogue management architecture.
-- Forward-only. This migration contains no clinical ranges and is not auto-applied.

-- Existing installations did not execute the clean-install 00000 bootstrap.
-- Keep the forward upgrade independently safe without altering historical
-- migrations or depending on the migration role search_path.
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA extensions;
CREATE OR REPLACE FUNCTION public.uuid_generate_v4()
RETURNS UUID
LANGUAGE sql
VOLATILE
SET search_path = extensions, pg_temp
AS $$ SELECT extensions.uuid_generate_v4() $$;

CREATE TYPE public.catalogue_lifecycle_enum AS ENUM ('Draft', 'Active', 'Archived');
CREATE TYPE public.catalogue_test_kind_enum AS ENUM ('Individual', 'Profile');
CREATE TYPE public.clinical_configuration_status_enum AS ENUM ('Configured', 'Requires Clinical Validation', 'Ready for Activation', 'Workflow Not Supported');
CREATE TYPE public.catalogue_pricing_policy_enum AS ENUM ('Fixed', 'Negotiable', 'PricePending', 'Manual');
CREATE TYPE public.reference_range_validation_state_enum AS ENUM ('Unclassified', 'ClinicallyValidated', 'LegacyDefaultRequiresValidation');
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE TABLE public.test_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(150) NOT NULL,
    description TEXT,
    lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Draft',
    row_version BIGINT NOT NULL DEFAULT 1,
    display_order INT NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT test_categories_name_not_blank CHECK (btrim(name) <> '')
);

CREATE TABLE public.catalogue_calculation_definitions (
    identifier VARCHAR(100) PRIMARY KEY,
    parameter_code VARCHAR(50) NOT NULL UNIQUE,
    server_authoritative BOOLEAN NOT NULL DEFAULT FALSE,
    implementation_note TEXT NOT NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE
);
INSERT INTO public.catalogue_calculation_definitions(identifier,parameter_code,server_authoritative,implementation_note) VALUES
 ('SERVER_IBIL','IBIL',TRUE,'Implemented by recompute_order_item_calculated_results'),
 ('SERVER_GLOB','GLOB',TRUE,'Implemented by recompute_order_item_calculated_results'),
 ('SERVER_AG_RATIO','AG_RATIO',TRUE,'Implemented by recompute_order_item_calculated_results'),
 ('SERVER_VLDL','VLDL',TRUE,'Implemented by recompute_order_item_calculated_results');

CREATE UNIQUE INDEX test_categories_normalized_name_key
ON public.test_categories (lower(regexp_replace(btrim(name), '[^[:alnum:]]+', '', 'g')));

INSERT INTO public.test_categories(code, name, lifecycle_status, display_order)
VALUES
 ('BIOCHEMISTRY','Biochemistry & Clinical Chemistry','Active',10),
 ('HEMATOLOGY','Hematology','Active',20),
 ('ENDOCRINOLOGY','Hormones & Endocrinology','Active',30),
 ('SEROLOGY','Serology & Immunology','Active',40),
 ('MOLECULAR','Molecular & PCR','Draft',50),
 ('MICROBIOLOGY','Microbiology & Culture','Draft',60),
 ('HEPATITIS_HIV','Hepatitis & HIV','Draft',70),
 ('TUMOR_MARKERS','Tumor Markers','Draft',80),
 ('HISTOPATHOLOGY','Histopathology & Biopsy','Draft',90),
 ('IHC','Immunohistochemistry (IHC)','Draft',100),
 ('ALLERGY','Allergy','Draft',110),
 ('VITAMINS_MINERALS','Vitamins & Minerals','Draft',120),
 ('GENETICS','Genetics / Karyotyping','Draft',130),
 ('TOXICOLOGY','Toxicology','Draft',140),
 ('GENERAL','General Tests','Active',150),
 ('HEALTH_PACKAGES','Health Packages','Draft',160)
ON CONFLICT (code) DO NOTHING;

ALTER TABLE public.tests
    ADD COLUMN description TEXT,
    ADD COLUMN test_kind public.catalogue_test_kind_enum NOT NULL DEFAULT 'Individual',
    ADD COLUMN lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    ADD COLUMN category_id UUID REFERENCES public.test_categories(id) ON DELETE RESTRICT,
    ADD COLUMN sample_volume VARCHAR(50),
    ADD COLUMN configuration_notes TEXT,
    ADD COLUMN row_version BIGINT NOT NULL DEFAULT 1,
    ADD COLUMN archived_at TIMESTAMPTZ,
    ADD COLUMN archived_by UUID REFERENCES public.user_profiles(id),
    ADD COLUMN activated_at TIMESTAMPTZ,
    ADD COLUMN activated_by UUID REFERENCES public.user_profiles(id),
    ADD COLUMN price_configured BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN allow_zero_price_billing BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN clinical_configuration_status public.clinical_configuration_status_enum NOT NULL DEFAULT 'Configured',
    ADD COLUMN workflow_supported BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN normalized_name_collision_exempt BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.tests ADD COLUMN pricing_policy public.catalogue_pricing_policy_enum NOT NULL DEFAULT 'Fixed', ADD COLUMN search_aliases TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
ALTER TABLE public.tests ADD CONSTRAINT tests_zero_price_authority_check CHECK (price_paisa > 0 OR price_configured = FALSE OR allow_zero_price_billing = TRUE) NOT VALID;
UPDATE public.tests
SET price_configured=FALSE,
    pricing_policy=CASE WHEN COALESCE(allow_manual_price,FALSE) THEN 'Manual'::public.catalogue_pricing_policy_enum ELSE 'PricePending'::public.catalogue_pricing_policy_enum END
WHERE price_paisa=0;

UPDATE public.tests t SET category_id = c.id
FROM public.test_categories c
WHERE t.category_id IS NULL AND (
 lower(t.department) = lower(c.name)
 OR lower(t.category) = lower(c.name)
 OR (c.code='BIOCHEMISTRY' AND lower(t.department) LIKE '%biochem%')
 OR (c.code='HEMATOLOGY' AND lower(t.department) LIKE '%hemat%')
 OR (c.code='SEROLOGY' AND (lower(t.department) LIKE '%serolog%' OR lower(t.department) LIKE '%immunolog%'))
 OR (c.code='ENDOCRINOLOGY' AND (lower(t.department) LIKE '%hormon%' OR lower(t.department) LIKE '%endocr%'))
 OR (c.code='IHC' AND t.code='IHC')
);

WITH collisions AS (
 SELECT lower(regexp_replace(btrim(name),'[^[:alnum:]]+','','g')) normalized_name
 FROM public.tests GROUP BY 1 HAVING count(*)>1
)
UPDATE public.tests t SET normalized_name_collision_exempt=TRUE
FROM collisions c
WHERE lower(regexp_replace(btrim(t.name),'[^[:alnum:]]+','','g'))=c.normalized_name;

CREATE UNIQUE INDEX tests_normalized_name_key
ON public.tests (lower(regexp_replace(btrim(name), '[^[:alnum:]]+', '', 'g')))
WHERE lifecycle_status <> 'Archived' AND NOT normalized_name_collision_exempt;
CREATE INDEX tests_catalogue_filters_idx ON public.tests(lifecycle_status, category_id, reporting_type, sample_type);
CREATE INDEX tests_search_name_trgm_idx ON public.tests USING gin(lower(name) gin_trgm_ops);
CREATE INDEX tests_search_code_trgm_idx ON public.tests USING gin(lower(code) gin_trgm_ops);
CREATE INDEX tests_search_aliases_idx ON public.tests USING gin(search_aliases);

ALTER TABLE public.parameters
    ADD COLUMN decimal_precision SMALLINT,
    ADD COLUMN interpretation_config JSONB,
    ADD COLUMN calculation_identifier VARCHAR(100),
    ADD COLUMN lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    ADD COLUMN row_version BIGINT NOT NULL DEFAULT 1,
    ADD COLUMN archived_at TIMESTAMPTZ,
    ADD COLUMN archived_by UUID REFERENCES public.user_profiles(id),
    ADD COLUMN clinical_configuration_status public.clinical_configuration_status_enum NOT NULL DEFAULT 'Configured',
    ADD COLUMN unit_validation_required BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN range_validation_required BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN method_validation_required BOOLEAN NOT NULL DEFAULT FALSE,
    ADD CONSTRAINT parameters_decimal_precision_check CHECK (decimal_precision BETWEEN 0 AND 8);

ALTER TABLE public.reference_ranges
    ADD COLUMN lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Active',
    ADD COLUMN row_version BIGINT NOT NULL DEFAULT 1,
    ADD COLUMN archived_at TIMESTAMPTZ,
    ADD COLUMN archived_by UUID REFERENCES public.user_profiles(id),
    ADD COLUMN validation_state public.reference_range_validation_state_enum NOT NULL DEFAULT 'Unclassified',
    ADD COLUMN validation_source TEXT;

-- Migration 00011 explicitly described these rows as practical/default
-- analyzer/reagent templates. Preserve their values and historical use while
-- recording that clinical validation is still required.
UPDATE public.reference_ranges
SET validation_state='LegacyDefaultRequiresValidation',
    validation_source='Migration 00011 default practical interval; analyzer/reagent verification required'
WHERE method='Default reference interval - verify with analyzer/reagent';

CREATE UNIQUE INDEX reference_ranges_definition_key ON public.reference_ranges(
 parameter_id, gender, age_min_days, age_max_days,
 COALESCE(method,''), COALESCE(unit,''), COALESCE(normal_min,-999999999),
 COALESCE(normal_max,-999999999), COALESCE(normal_text,''), COALESCE(reference_text,'')
) WHERE lifecycle_status <> 'Archived';

CREATE TABLE public.health_packages (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code VARCHAR(50) NOT NULL UNIQUE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    price_paisa BIGINT NOT NULL DEFAULT 0 CHECK(price_paisa >= 0),
    lifecycle_status public.catalogue_lifecycle_enum NOT NULL DEFAULT 'Draft',
    row_version BIGINT NOT NULL DEFAULT 1,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at TIMESTAMPTZ,
    archived_by UUID REFERENCES public.user_profiles(id)
);
ALTER TABLE public.health_packages ADD COLUMN pricing_policy public.catalogue_pricing_policy_enum NOT NULL DEFAULT 'Fixed', ADD COLUMN search_aliases TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];
CREATE UNIQUE INDEX health_packages_normalized_name_key
ON public.health_packages(lower(regexp_replace(btrim(name), '[^[:alnum:]]+', '', 'g')))
WHERE lifecycle_status <> 'Archived';

CREATE TABLE public.health_package_components (
    package_id UUID NOT NULL REFERENCES public.health_packages(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    display_order INT NOT NULL DEFAULT 0,
    PRIMARY KEY(package_id, test_id),
    UNIQUE(package_id, display_order)
);

CREATE TABLE public.bill_package_selections (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE RESTRICT,
    package_id UUID NOT NULL REFERENCES public.health_packages(id) ON DELETE RESTRICT,
    package_code_snapshot VARCHAR(50) NOT NULL,
    package_name_snapshot VARCHAR(255) NOT NULL,
    package_price_paisa BIGINT NOT NULL CHECK(package_price_paisa >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(bill_id, package_id)
);

CREATE TABLE public.bill_package_components (
    bill_package_selection_id UUID NOT NULL REFERENCES public.bill_package_selections(id) ON DELETE RESTRICT,
    bill_item_id UUID NOT NULL REFERENCES public.bill_items(id) ON DELETE RESTRICT,
    test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,
    PRIMARY KEY(bill_package_selection_id, test_id),
    UNIQUE(bill_package_selection_id, bill_item_id)
);

ALTER TABLE public.test_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.catalogue_calculation_definitions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_package_components ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_package_selections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bill_package_components ENABLE ROW LEVEL SECURITY;

CREATE POLICY test_categories_read ON public.test_categories FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY catalogue_calculations_read ON public.catalogue_calculation_definitions FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY packages_read ON public.health_packages FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY package_components_read ON public.health_package_components FOR SELECT TO authenticated USING (TRUE);
CREATE POLICY bill_package_read ON public.bill_package_selections FOR SELECT TO authenticated
USING (public.has_permission('can_create_bill') OR public.has_permission('can_view_financials'));
CREATE POLICY bill_package_components_read ON public.bill_package_components FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.bill_package_selections s WHERE s.id=bill_package_selection_id AND (public.has_permission('can_create_bill') OR public.has_permission('can_view_financials'))));

REVOKE INSERT, UPDATE, DELETE ON public.tests, public.parameters, public.reference_ranges FROM authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.test_categories, public.health_packages, public.health_package_components FROM authenticated;

CREATE OR REPLACE FUNCTION public.catalogue_actor_name() RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
 SELECT COALESCE((SELECT full_name FROM public.user_profiles WHERE id=auth.uid()), 'Catalogue Administrator')
$$;

CREATE OR REPLACE FUNCTION public.catalogue_require_manager() RETURNS VOID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_catalogue') THEN
  RAISE EXCEPTION 'You do not have permission to manage the catalogue.' USING ERRCODE='42501';
 END IF;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_test_missing_configuration(p_test_id UUID) RETURNS TEXT[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE t public.tests%ROWTYPE; missing TEXT[]:=ARRAY[]::TEXT[]; p RECORD;
BEGIN
 PERFORM public.catalogue_require_manager();
 SELECT * INTO t FROM public.tests WHERE id=p_test_id;
 IF NOT FOUND THEN RETURN ARRAY['canonical identity']; END IF;
 IF btrim(COALESCE(t.code,''))='' THEN missing:=array_append(missing,'unique code'); END IF;
 IF btrim(COALESCE(t.name,''))='' THEN missing:=array_append(missing,'canonical name'); END IF;
 IF t.category_id IS NULL THEN missing:=array_append(missing,'category'); END IF;
 IF t.reporting_type IS NULL THEN missing:=array_append(missing,'reporting tier'); END IF;
 IF NOT t.workflow_supported OR t.clinical_configuration_status='Workflow Not Supported' THEN missing:=array_append(missing,'supported clinical workflow'); END IF;
 IF t.clinical_configuration_status='Requires Clinical Validation' THEN missing:=array_append(missing,'clinical validation approval'); END IF;
 IF NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual') AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'configured production price'); END IF;
 IF t.price_paisa=0 AND t.price_configured AND NOT t.allow_zero_price_billing THEN missing:=array_append(missing,'zero-price billing authorization'); END IF;
 IF t.reporting_type <> 'NoReporting' AND btrim(COALESCE(t.sample_type,''))='' THEN missing:=array_append(missing,'specimen'); END IF;
 IF t.reporting_type <> 'NoReporting' AND NOT EXISTS(SELECT 1 FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active) THEN missing:=array_append(missing,'at least one active parameter'); END IF;
 FOR p IN SELECT * FROM public.parameters WHERE test_id=t.id AND lifecycle_status='Active' AND is_active LOOP
  IF p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='' THEN missing:=array_append(missing,p.code||': unit'); END IF;
  IF p.clinical_configuration_status='Requires Clinical Validation' OR p.unit_validation_required OR p.range_validation_required OR p.method_validation_required THEN missing:=array_append(missing,p.code||': clinical validation'); END IF;
  IF p.value_type='Select' AND COALESCE(jsonb_array_length(p.options),0)=0 THEN missing:=array_append(missing,p.code||': select options'); END IF;
  IF p.value_type='Calculated' AND (btrim(COALESCE(p.calculation_identifier,''))='' OR btrim(COALESCE(p.formula,''))='' OR NOT EXISTS(SELECT 1 FROM public.catalogue_calculation_definitions d WHERE d.identifier=p.calculation_identifier AND d.parameter_code=p.code AND d.server_authoritative AND d.is_active)) THEN missing:=array_append(missing,p.code||': approved server-authoritative calculation configuration'); END IF;
  IF p.value_type IN ('Numeric','Calculated') AND NOT EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=p.id AND r.lifecycle_status='Active' AND r.is_active AND r.is_approved AND r.validation_state='ClinicallyValidated') THEN missing:=array_append(missing,p.code||': clinically validated reference-range policy'); END IF;
 END LOOP;
 RETURN missing;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_test(p_test JSONB, p_expected_version BIGINT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE; old_row JSONB; new_id UUID; normalized_name TEXT;
BEGIN
 PERFORM public.catalogue_require_manager();
 normalized_name:=lower(regexp_replace(btrim(COALESCE(p_test->>'name','')), '[^[:alnum:]]+', '', 'g'));
 IF btrim(COALESCE(p_test->>'code',''))='' OR normalized_name='' THEN RAISE EXCEPTION 'Code and canonical name are required.' USING ERRCODE='22023'; END IF;
 IF EXISTS(SELECT 1 FROM public.tests WHERE id<>COALESCE((p_test->>'id')::UUID,'00000000-0000-0000-0000-000000000000'::UUID) AND lower(code)=lower(p_test->>'code')) THEN RAISE EXCEPTION 'Duplicate test code.' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM public.tests WHERE id<>COALESCE((p_test->>'id')::UUID,'00000000-0000-0000-0000-000000000000'::UUID) AND lifecycle_status<>'Archived' AND lower(regexp_replace(btrim(name),'[^[:alnum:]]+','','g'))=normalized_name) THEN RAISE EXCEPTION 'Duplicate normalized test name; review semantic/profile collision.' USING ERRCODE='23505'; END IF;
 IF p_test ? 'id' AND NULLIF(p_test->>'id','') IS NOT NULL THEN
  SELECT * INTO v FROM public.tests WHERE id=(p_test->>'id')::UUID FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Test no longer exists.' USING ERRCODE='P0002'; END IF;
  IF p_expected_version IS NULL OR v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
  old_row:=to_jsonb(v);
  UPDATE public.tests SET code=upper(btrim(p_test->>'code')),name=btrim(p_test->>'name'),short_name=NULLIF(btrim(p_test->>'short_name'),''),
   description=NULLIF(btrim(p_test->>'description'),''),category_id=(p_test->>'category_id')::UUID,
   department=btrim(p_test->>'department'),category=btrim(p_test->>'category'),test_kind=COALESCE((p_test->>'test_kind')::public.catalogue_test_kind_enum,test_kind),
   reporting_type=(p_test->>'reporting_type')::public.reporting_type_enum,outsource_lab_name=NULLIF(btrim(p_test->>'outsource_lab_name'),''),
   price_paisa=COALESCE((p_test->>'price_paisa')::BIGINT,0),sample_type=COALESCE(btrim(p_test->>'sample_type'),''),container=COALESCE(btrim(p_test->>'container'),''),
   sample_volume=NULLIF(btrim(p_test->>'sample_volume'),''),method=NULLIF(btrim(p_test->>'method'),''),tat_hours=(p_test->>'tat_hours')::INT,
   display_order=COALESCE((p_test->>'display_order')::INT,0),configuration_notes=NULLIF(btrim(p_test->>'configuration_notes'),''),price_configured=COALESCE((p_test->>'price_configured')::BOOLEAN,price_configured),allow_zero_price_billing=COALESCE((p_test->>'allow_zero_price_billing')::BOOLEAN,allow_zero_price_billing),pricing_policy=COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum,pricing_policy),allow_manual_price=COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum,pricing_policy)<>'Fixed',search_aliases=ARRAY(SELECT lower(btrim(x)) FROM jsonb_array_elements_text(COALESCE(p_test->'search_aliases','[]'))x WHERE btrim(x)<>''),clinical_configuration_status=COALESCE((p_test->>'clinical_configuration_status')::public.clinical_configuration_status_enum,clinical_configuration_status),workflow_supported=COALESCE((p_test->>'workflow_supported')::BOOLEAN,workflow_supported),row_version=row_version+1,updated_at=NOW()
  WHERE id=v.id RETURNING id INTO new_id;
 ELSE
  INSERT INTO public.tests(code,name,short_name,description,department,category,category_id,test_kind,reporting_type,outsource_lab_name,price_paisa,sample_type,container,sample_volume,method,tat_hours,display_order,is_active,lifecycle_status,configuration_notes,price_configured,allow_zero_price_billing,pricing_policy,allow_manual_price,search_aliases,clinical_configuration_status,workflow_supported)
  VALUES(upper(btrim(p_test->>'code')),btrim(p_test->>'name'),NULLIF(btrim(p_test->>'short_name'),''),NULLIF(btrim(p_test->>'description'),''),btrim(p_test->>'department'),btrim(p_test->>'category'),(p_test->>'category_id')::UUID,COALESCE((p_test->>'test_kind')::public.catalogue_test_kind_enum,'Individual'),(p_test->>'reporting_type')::public.reporting_type_enum,NULLIF(btrim(p_test->>'outsource_lab_name'),''),COALESCE((p_test->>'price_paisa')::BIGINT,0),COALESCE(btrim(p_test->>'sample_type'),''),COALESCE(btrim(p_test->>'container'),''),NULLIF(btrim(p_test->>'sample_volume'),''),NULLIF(btrim(p_test->>'method'),''),(p_test->>'tat_hours')::INT,COALESCE((p_test->>'display_order')::INT,0),FALSE,'Draft',NULLIF(btrim(p_test->>'configuration_notes'),''),COALESCE((p_test->>'price_configured')::BOOLEAN,FALSE),COALESCE((p_test->>'allow_zero_price_billing')::BOOLEAN,FALSE),COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum,'PricePending'),COALESCE((p_test->>'pricing_policy')::public.catalogue_pricing_policy_enum,'PricePending')<>'Fixed',ARRAY(SELECT lower(btrim(x)) FROM jsonb_array_elements_text(COALESCE(p_test->'search_aliases','[]'))x WHERE btrim(x)<>''),COALESCE((p_test->>'clinical_configuration_status')::public.clinical_configuration_status_enum,'Requires Clinical Validation'),COALESCE((p_test->>'workflow_supported')::BOOLEAN,TRUE)) RETURNING id INTO new_id;
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),CASE WHEN old_row IS NULL THEN 'CATALOGUE_TEST_CREATED' ELSE 'CATALOGUE_TEST_UPDATED' END,'Test',new_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.tests x WHERE x.id=new_id));
 RETURN jsonb_build_object('id',new_id,'missing',public.catalogue_test_missing_configuration(new_id));
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_test_lifecycle(p_test_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE; missing TEXT[];
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Test no longer exists.'; END IF;
 IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 missing:=public.catalogue_test_missing_configuration(p_test_id);
 IF p_status='Active' AND cardinality(missing)>0 THEN RAISE EXCEPTION 'Cannot activate. Missing: %',array_to_string(missing,', ') USING ERRCODE='23514'; END IF;
 UPDATE public.tests SET lifecycle_status=p_status,is_active=(p_status='Active'),row_version=row_version+1,updated_at=NOW(),archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END,activated_at=CASE WHEN p_status='Active' THEN NOW() ELSE activated_at END,activated_by=CASE WHEN p_status='Active' THEN auth.uid() ELSE activated_by END WHERE id=p_test_id;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_'||upper(p_status::TEXT),'Test',p_test_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.tests x WHERE x.id=p_test_id));
 RETURN jsonb_build_object('id',p_test_id,'status',p_status,'missing',missing);
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_update_test_price(p_test_id UUID,p_price_paisa BIGINT,p_acknowledge_zero_price BOOLEAN DEFAULT FALSE) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE old_price BIGINT; BEGIN PERFORM public.catalogue_require_manager(); IF p_price_paisa<0 THEN RAISE EXCEPTION 'Price cannot be negative.' USING ERRCODE='23514'; END IF; IF p_price_paisa=0 AND NOT p_acknowledge_zero_price THEN RAISE EXCEPTION 'Explicit acknowledgement is required to configure a genuine zero price.' USING ERRCODE='23514'; END IF; SELECT price_paisa INTO old_price FROM public.tests WHERE id=p_test_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Test no longer exists.'; END IF; UPDATE public.tests SET price_paisa=p_price_paisa,price_configured=TRUE,allow_zero_price_billing=(p_price_paisa=0 AND p_acknowledge_zero_price),row_version=row_version+1,updated_at=NOW() WHERE id=p_test_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PRICE_UPDATED','Test',p_test_id::TEXT,jsonb_build_object('price_paisa',old_price),jsonb_build_object('price_paisa',p_price_paisa,'zero_price_acknowledged',p_acknowledge_zero_price)); END $$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_test(p_test_id UUID,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.tests%ROWTYPE;
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.tests WHERE id=p_test_id FOR UPDATE;
 IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Test changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 IF EXISTS(SELECT 1 FROM public.bill_items WHERE test_id=p_test_id) OR EXISTS(SELECT 1 FROM public.clinical_order_items WHERE test_id=p_test_id) OR EXISTS(SELECT 1 FROM public.test_results r JOIN public.parameters p ON p.id=r.parameter_id WHERE p.test_id=p_test_id) THEN RAISE EXCEPTION 'Referenced tests cannot be deleted. Archive this test.' USING ERRCODE='23503'; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_DELETED','Test',p_test_id::TEXT,to_jsonb(v)); DELETE FROM public.tests WHERE id=p_test_id;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_clone_test(p_test_id UUID,p_code TEXT,p_name TEXT) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE source public.tests%ROWTYPE; target UUID; p RECORD; new_p UUID;
BEGIN
 PERFORM public.catalogue_require_manager(); SELECT * INTO source FROM public.tests WHERE id=p_test_id FOR SHARE; IF NOT FOUND THEN RAISE EXCEPTION 'Source test not found.'; END IF;
 INSERT INTO public.tests(code,name,short_name,description,department,category,category_id,test_kind,reporting_type,outsource_lab_name,price_paisa,sample_type,container,sample_volume,method,tat_hours,display_order,is_active,lifecycle_status,configuration_notes,price_configured,clinical_configuration_status)
 VALUES(upper(btrim(p_code)),btrim(p_name),source.short_name,source.description,source.department,source.category,source.category_id,source.test_kind,source.reporting_type,source.outsource_lab_name,0,source.sample_type,source.container,source.sample_volume,source.method,source.tat_hours,source.display_order,FALSE,'Draft','Cloned configuration; clinical values and price require review.',FALSE,'Requires Clinical Validation') RETURNING id INTO target;
 FOR p IN SELECT * FROM public.parameters WHERE test_id=p_test_id AND lifecycle_status<>'Archived' ORDER BY display_order LOOP
  INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,display_order,is_mandatory,is_active,lifecycle_status,decimal_precision,interpretation_config)
  VALUES(target,p.code,p.name,p.value_type,p.unit,p.options,p.display_order,p.is_mandatory,FALSE,'Draft',p.decimal_precision,p.interpretation_config) RETURNING id INTO new_p;
 END LOOP;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_TEST_CLONED','Test',target::TEXT,jsonb_build_object('source_id',p_test_id,'code',p_code)); RETURN target;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_parameter(p_parameter JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE; result_id UUID; old_row JSONB; vt public.parameter_value_type_enum;
BEGIN
 PERFORM public.catalogue_require_manager(); vt:=(p_parameter->>'value_type')::public.parameter_value_type_enum;
 IF vt='Calculated' AND (NULLIF(btrim(p_parameter->>'calculation_identifier'),'') IS NULL OR NULLIF(btrim(p_parameter->>'formula'),'') IS NULL) THEN RAISE EXCEPTION 'Calculated parameters require an approved calculation identifier and formula.' USING ERRCODE='23514'; END IF;
 IF p_parameter ? 'id' AND NULLIF(p_parameter->>'id','') IS NOT NULL THEN
  SELECT * INTO v FROM public.parameters WHERE id=(p_parameter->>'id')::UUID FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v);
  UPDATE public.parameters SET code=upper(btrim(p_parameter->>'code')),name=btrim(p_parameter->>'name'),value_type=vt,unit=NULLIF(btrim(p_parameter->>'unit'),''),options=p_parameter->'options',formula=NULLIF(btrim(p_parameter->>'formula'),''),formula_dependencies=ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_parameter->'formula_dependencies','[]'))),calculation_identifier=NULLIF(btrim(p_parameter->>'calculation_identifier'),''),decimal_precision=(p_parameter->>'decimal_precision')::SMALLINT,interpretation_config=p_parameter->'interpretation_config',display_order=COALESCE((p_parameter->>'display_order')::INT,0),is_mandatory=COALESCE((p_parameter->>'is_mandatory')::BOOLEAN,TRUE),row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE
  INSERT INTO public.parameters(test_id,code,name,value_type,unit,options,formula,formula_dependencies,calculation_identifier,decimal_precision,interpretation_config,display_order,is_mandatory,is_active,lifecycle_status)
  VALUES((p_parameter->>'test_id')::UUID,upper(btrim(p_parameter->>'code')),btrim(p_parameter->>'name'),vt,NULLIF(btrim(p_parameter->>'unit'),''),p_parameter->'options',NULLIF(btrim(p_parameter->>'formula'),''),ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_parameter->'formula_dependencies','[]'))),NULLIF(btrim(p_parameter->>'calculation_identifier'),''),(p_parameter->>'decimal_precision')::SMALLINT,p_parameter->'interpretation_config',COALESCE((p_parameter->>'display_order')::INT,0),COALESCE((p_parameter->>'is_mandatory')::BOOLEAN,TRUE),FALSE,'Draft') RETURNING id INTO result_id;
 END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),CASE WHEN old_row IS NULL THEN 'CATALOGUE_PARAMETER_CREATED' ELSE 'CATALOGUE_PARAMETER_UPDATED' END,'Parameter',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.parameters x WHERE x.id=result_id)); RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_parameter_lifecycle(p_parameter_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE;
BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 IF p_status='Active' AND v.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(v.unit,''))='' THEN RAISE EXCEPTION 'Numeric/calculated parameters require a unit.' USING ERRCODE='23514'; END IF;
 UPDATE public.parameters SET lifecycle_status=p_status,is_active=(p_status='Active'),row_version=row_version+1,archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_parameter_id;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PARAMETER_'||upper(p_status::TEXT),'Parameter',p_parameter_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.parameters x WHERE x.id=p_parameter_id)); END $$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_parameter(p_parameter_id UUID,p_expected_version BIGINT) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.parameters%ROWTYPE;
BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.parameters WHERE id=p_parameter_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Parameter changed. Refresh and try again.' USING ERRCODE='PT409'; END IF;
 IF EXISTS(SELECT 1 FROM public.test_results WHERE parameter_id=p_parameter_id) THEN RAISE EXCEPTION 'Referenced parameters cannot be deleted. Archive this parameter.' USING ERRCODE='23503'; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PARAMETER_DELETED','Parameter',p_parameter_id::TEXT,to_jsonb(v)); DELETE FROM public.parameters WHERE id=p_parameter_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_range(p_range JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; result_id UUID; old_row JSONB; min_age INT:=COALESCE((p_range->>'age_min_days')::INT,0); max_age INT:=COALESCE((p_range->>'age_max_days')::INT,43800);
BEGIN PERFORM public.catalogue_require_manager(); IF min_age>max_age THEN RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514'; END IF;
 IF COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) AND COALESCE(p_range->>'validation_state','Unclassified')<>'ClinicallyValidated' THEN RAISE EXCEPTION 'Approval requires an explicit ClinicallyValidated provenance state.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=(p_range->>'parameter_id')::UUID AND r.id<>COALESCE((p_range->>'id')::UUID,'00000000-0000-0000-0000-000000000000'::UUID) AND r.lifecycle_status='Active' AND r.is_active AND r.gender=COALESCE(p_range->>'gender','All') AND int4range(r.age_min_days,r.age_max_days,'[]') && int4range(min_age,max_age,'[]') AND COALESCE(r.method,'')=COALESCE(p_range->>'method','')) THEN RAISE EXCEPTION 'Overlapping active reference range for the same sex and method.' USING ERRCODE='23505'; END IF;
 IF p_range ? 'id' AND NULLIF(p_range->>'id','') IS NOT NULL THEN SELECT * INTO v FROM public.reference_ranges WHERE id=(p_range->>'id')::UUID FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v);
  UPDATE public.reference_ranges SET gender=COALESCE(p_range->>'gender','All'),age_min_days=min_age,age_max_days=max_age,normal_min=(p_range->>'normal_min')::NUMERIC,normal_max=(p_range->>'normal_max')::NUMERIC,critical_low=(p_range->>'critical_low')::NUMERIC,critical_high=(p_range->>'critical_high')::NUMERIC,normal_text=NULLIF(btrim(p_range->>'normal_text'),''),reference_text=NULLIF(btrim(p_range->>'reference_text'),''),method=NULLIF(btrim(p_range->>'method'),''),unit=NULLIF(btrim(p_range->>'unit'),''),validation_state=COALESCE((p_range->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),validation_source=NULLIF(btrim(p_range->>'validation_source'),''),is_approved=COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE),approved_by=CASE WHEN COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) THEN auth.uid() ELSE NULL END,approved_at=CASE WHEN COALESCE((p_range->>'is_approved')::BOOLEAN,FALSE) THEN NOW() ELSE NULL END,row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source)
  VALUES((p_range->>'parameter_id')::UUID,COALESCE(p_range->>'gender','All'),min_age,max_age,(p_range->>'normal_min')::NUMERIC,(p_range->>'normal_max')::NUMERIC,(p_range->>'critical_low')::NUMERIC,(p_range->>'critical_high')::NUMERIC,NULLIF(btrim(p_range->>'normal_text'),''),NULLIF(btrim(p_range->>'reference_text'),''),NULLIF(btrim(p_range->>'method'),''),NULLIF(btrim(p_range->>'unit'),''),FALSE,FALSE,'Draft',COALESCE((p_range->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(p_range->>'validation_source'),'')) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),CASE WHEN old_row IS NULL THEN 'CATALOGUE_RANGE_CREATED' ELSE 'CATALOGUE_RANGE_UPDATED' END,'ReferenceRange',result_id::TEXT,old_row,(SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id=result_id)); RETURN result_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_package(p_package JSONB,p_components UUID[],p_expected_version BIGINT DEFAULT NULL) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.health_packages%ROWTYPE; result_id UUID; component UUID; n INT:=0;
BEGIN PERFORM public.catalogue_require_manager(); IF cardinality(p_components)<>cardinality(ARRAY(SELECT DISTINCT x FROM unnest(p_components)x)) THEN RAISE EXCEPTION 'Package components must be unique.' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_components)x LEFT JOIN public.tests t ON t.id=x WHERE t.id IS NULL OR t.lifecycle_status<>'Active') THEN RAISE EXCEPTION 'Packages may contain only active canonical tests/profiles.' USING ERRCODE='23514'; END IF;
 IF p_package ? 'id' AND NULLIF(p_package->>'id','') IS NOT NULL THEN SELECT * INTO v FROM public.health_packages WHERE id=(p_package->>'id')::UUID FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; result_id:=v.id; UPDATE public.health_packages SET code=upper(btrim(p_package->>'code')),name=btrim(p_package->>'name'),description=NULLIF(btrim(p_package->>'description'),''),price_paisa=COALESCE((p_package->>'price_paisa')::BIGINT,0),row_version=row_version+1,updated_at=NOW() WHERE id=result_id; DELETE FROM public.health_package_components WHERE package_id=result_id;
 ELSE INSERT INTO public.health_packages(code,name,description,price_paisa,lifecycle_status) VALUES(upper(btrim(p_package->>'code')),btrim(p_package->>'name'),NULLIF(btrim(p_package->>'description'),''),COALESCE((p_package->>'price_paisa')::BIGINT,0),'Draft') RETURNING id INTO result_id; END IF;
 FOREACH component IN ARRAY p_components LOOP n:=n+1; INSERT INTO public.health_package_components(package_id,test_id,display_order) VALUES(result_id,component,n); END LOOP;
 UPDATE public.tests SET allow_manual_price=TRUE WHERE id=ANY(p_components);
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PACKAGE_SAVED','HealthPackage',result_id::TEXT,jsonb_build_object('package',p_package,'components',p_components)); RETURN result_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_save_category(p_category JSONB,p_expected_version BIGINT DEFAULT NULL) RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; v public.test_categories%ROWTYPE; old_row JSONB; BEGIN PERFORM public.catalogue_require_manager();
 IF p_category ? 'id' AND NULLIF(p_category->>'id','') IS NOT NULL THEN SELECT * INTO v FROM public.test_categories WHERE id=(p_category->>'id')::UUID FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists.' USING ERRCODE='P0002'; END IF; IF p_expected_version IS NULL OR v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; old_row:=to_jsonb(v); UPDATE public.test_categories SET code=upper(btrim(p_category->>'code')),name=btrim(p_category->>'name'),description=NULLIF(btrim(p_category->>'description'),''),display_order=COALESCE((p_category->>'display_order')::INT,0),row_version=row_version+1,updated_at=NOW() WHERE id=v.id RETURNING id INTO result_id;
 ELSE INSERT INTO public.test_categories(code,name,description,display_order,lifecycle_status) VALUES(upper(btrim(p_category->>'code')),btrim(p_category->>'name'),NULLIF(btrim(p_category->>'description'),''),COALESCE((p_category->>'display_order')::INT,0),'Draft') RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_SAVED','TestCategory',result_id::TEXT,old_row,(SELECT to_jsonb(c) FROM public.test_categories c WHERE c.id=result_id)); RETURN result_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_category_lifecycle(p_category_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.test_categories%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.test_categories WHERE id=p_category_id FOR UPDATE; IF NOT FOUND THEN RAISE EXCEPTION 'Category no longer exists.' USING ERRCODE='P0002'; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Category changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF p_status='Archived' AND EXISTS(SELECT 1 FROM public.tests WHERE category_id=p_category_id AND lifecycle_status<>'Archived') THEN RAISE EXCEPTION 'Archive or move category tests first.' USING ERRCODE='23503'; END IF; UPDATE public.test_categories SET lifecycle_status=p_status,row_version=row_version+1,updated_at=NOW() WHERE id=p_category_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_CATEGORY_'||upper(p_status::TEXT),'TestCategory',p_category_id::TEXT,to_jsonb(v),(SELECT to_jsonb(c) FROM public.test_categories c WHERE c.id=p_category_id)); END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_range_lifecycle(p_range_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.reference_ranges WHERE id=p_range_id FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; UPDATE public.reference_ranges SET lifecycle_status=p_status,is_active=(p_status='Active'),row_version=row_version+1,archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_range_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGE_'||upper(p_status::TEXT),'ReferenceRange',p_range_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.reference_ranges x WHERE x.id=p_range_id)); END $$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_range(p_range_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.reference_ranges%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.reference_ranges WHERE id=p_range_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Reference range changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.test_results WHERE parameter_id=v.parameter_id) THEN RAISE EXCEPTION 'A historically used parameter range cannot be hard deleted. Archive it.' USING ERRCODE='23503'; END IF; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGE_DELETED','ReferenceRange',p_range_id::TEXT,to_jsonb(v)); DELETE FROM public.reference_ranges WHERE id=p_range_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_replace_ranges(p_parameter_ids UUID[],p_ranges JSONB) RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE item JSONB; inserted_count INT:=0; parameter_uuid UUID; min_age INT; max_age INT;
BEGIN PERFORM public.catalogue_require_manager(); PERFORM 1 FROM public.parameters WHERE id=ANY(p_parameter_ids) FOR UPDATE;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_ranges,'[]'))x WHERE NOT ((x->>'parameter_id')::UUID=ANY(p_parameter_ids))) THEN RAISE EXCEPTION 'Range payload contains an unexpected parameter.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM jsonb_array_elements(COALESCE(p_ranges,'[]'))x WHERE COALESCE((x->>'is_approved')::BOOLEAN,FALSE) AND COALESCE(x->>'validation_state','Unclassified')<>'ClinicallyValidated') THEN RAISE EXCEPTION 'Approval requires an explicit ClinicallyValidated provenance state.' USING ERRCODE='23514'; END IF;
 UPDATE public.reference_ranges SET lifecycle_status='Archived',is_active=FALSE,archived_at=NOW(),archived_by=auth.uid(),row_version=row_version+1,updated_at=NOW() WHERE parameter_id=ANY(p_parameter_ids) AND lifecycle_status<>'Archived';
 FOR item IN SELECT * FROM jsonb_array_elements(COALESCE(p_ranges,'[]')) LOOP parameter_uuid:=(item->>'parameter_id')::UUID;min_age:=COALESCE((item->>'age_min_days')::INT,0);max_age:=COALESCE((item->>'age_max_days')::INT,43800);IF min_age>max_age THEN RAISE EXCEPTION 'Minimum age cannot exceed maximum age.' USING ERRCODE='23514';END IF;
  IF EXISTS(SELECT 1 FROM public.reference_ranges r WHERE r.parameter_id=parameter_uuid AND r.lifecycle_status='Active' AND r.gender=COALESCE(item->>'gender','All') AND int4range(r.age_min_days,r.age_max_days,'[]')&&int4range(min_age,max_age,'[]') AND COALESCE(r.method,'')=COALESCE(item->>'method','')) THEN RAISE EXCEPTION 'Overlapping active reference ranges.' USING ERRCODE='23505';END IF;
  INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,approved_by,approved_at,validation_state,validation_source) VALUES(parameter_uuid,COALESCE(item->>'gender','All'),min_age,max_age,(item->>'normal_min')::NUMERIC,(item->>'normal_max')::NUMERIC,(item->>'critical_low')::NUMERIC,(item->>'critical_high')::NUMERIC,NULLIF(btrim(item->>'normal_text'),''),NULLIF(btrim(item->>'reference_text'),''),NULLIF(btrim(item->>'method'),''),NULLIF(btrim(item->>'unit'),''),TRUE,COALESCE((item->>'is_approved')::BOOLEAN,FALSE),'Active',CASE WHEN COALESCE((item->>'is_approved')::BOOLEAN,FALSE) THEN auth.uid() END,CASE WHEN COALESCE((item->>'is_approved')::BOOLEAN,FALSE) THEN NOW() END,COALESCE((item->>'validation_state')::public.reference_range_validation_state_enum,'Unclassified'),NULLIF(btrim(item->>'validation_source'),''));inserted_count:=inserted_count+1;
 END LOOP; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_RANGES_REPLACED','ParameterSet',array_to_string(p_parameter_ids,','),jsonb_build_object('count',inserted_count));RETURN inserted_count;END $$;

CREATE OR REPLACE FUNCTION public.catalogue_set_package_lifecycle(p_package_id UUID,p_status public.catalogue_lifecycle_enum,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.health_packages%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.health_packages WHERE id=p_package_id FOR UPDATE; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF p_status='Active' AND (v.price_paisa<=0 OR NOT EXISTS(SELECT 1 FROM public.health_package_components WHERE package_id=p_package_id)) THEN RAISE EXCEPTION 'Active packages require a positive price and components.' USING ERRCODE='23514'; END IF; UPDATE public.health_packages SET lifecycle_status=p_status,row_version=row_version+1,updated_at=NOW(),archived_at=CASE WHEN p_status='Archived' THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_status='Archived' THEN auth.uid() ELSE NULL END WHERE id=p_package_id; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PACKAGE_'||upper(p_status::TEXT),'HealthPackage',p_package_id::TEXT,to_jsonb(v),(SELECT to_jsonb(x) FROM public.health_packages x WHERE x.id=p_package_id)); END $$;

CREATE OR REPLACE FUNCTION public.catalogue_delete_package(p_package_id UUID,p_expected_version BIGINT) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE v public.health_packages%ROWTYPE; BEGIN PERFORM public.catalogue_require_manager(); SELECT * INTO v FROM public.health_packages WHERE id=p_package_id FOR UPDATE; IF NOT FOUND THEN RETURN; END IF; IF v.row_version<>p_expected_version THEN RAISE EXCEPTION 'Package changed. Refresh and try again.' USING ERRCODE='PT409'; END IF; IF EXISTS(SELECT 1 FROM public.bill_package_selections WHERE package_id=p_package_id) THEN RAISE EXCEPTION 'Billed packages cannot be deleted. Archive this package.' USING ERRCODE='23503'; END IF; INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.catalogue_actor_name(),'CATALOGUE_PACKAGE_DELETED','HealthPackage',p_package_id::TEXT,to_jsonb(v)); DELETE FROM public.health_packages WHERE id=p_package_id; END $$;

CREATE OR REPLACE FUNCTION public.catalogue_expand_package(p_package_id UUID) RETURNS TABLE(package_id UUID,package_code TEXT,package_name TEXT,package_price_paisa BIGINT,test_id UUID,test_code TEXT,test_name TEXT,display_order INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT p.id,p.code::TEXT,p.name::TEXT,p.price_paisa,t.id,t.code::TEXT,t.name::TEXT,c.display_order FROM public.health_packages p JOIN public.health_package_components c ON c.package_id=p.id JOIN public.tests t ON t.id=c.test_id WHERE p.id=p_package_id AND p.lifecycle_status='Active' AND t.lifecycle_status='Active' ORDER BY c.display_order;
END $$;

CREATE OR REPLACE FUNCTION public.search_billable_catalogue(p_query TEXT,p_limit INT DEFAULT 20) RETURNS TABLE(entity_type TEXT,entity_id UUID,code TEXT,name TEXT,short_name TEXT,category TEXT,specimen TEXT,container TEXT,price_paisa BIGINT,price_configured BOOLEAN,pricing_policy public.catalogue_pricing_policy_enum,allow_zero_price_billing BOOLEAN,reporting_type public.reporting_type_enum,rank_score INT)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 WITH q AS (SELECT lower(btrim(COALESCE(p_query,''))) value), matches AS (
  SELECT 'Test'::TEXT,t.id,t.code::TEXT,t.name::TEXT,t.short_name::TEXT,t.category::TEXT,t.sample_type::TEXT,t.container::TEXT,t.price_paisa,t.price_configured,t.pricing_policy,t.allow_zero_price_billing,t.reporting_type,
   CASE WHEN lower(t.code)=q.value THEN 100 WHEN lower(t.code) LIKE q.value||'%' THEN 90 WHEN lower(COALESCE(t.short_name,'')) LIKE q.value||'%' THEN 85 WHEN q.value=ANY(t.search_aliases) THEN 82 WHEN lower(t.name) LIKE q.value||'%' THEN 75 WHEN lower(t.name) LIKE '%'||q.value||'%' THEN 60 ELSE 40 END score
  FROM public.tests t,q WHERE length(q.value)>=2 AND t.lifecycle_status='Active' AND t.is_active AND t.clinical_configuration_status IN ('Configured','Ready for Activation') AND t.workflow_supported AND (lower(t.code) LIKE '%'||q.value||'%' OR lower(t.name) LIKE '%'||q.value||'%' OR lower(COALESCE(t.short_name,'')) LIKE '%'||q.value||'%' OR EXISTS(SELECT 1 FROM unnest(t.search_aliases)a WHERE a LIKE '%'||q.value||'%'))
  UNION ALL
  SELECT 'Package',p.id,p.code::TEXT,p.name::TEXT,NULL,'Health Packages',NULL,NULL,p.price_paisa,TRUE,p.pricing_policy,FALSE,'NoReporting'::public.reporting_type_enum,
   CASE WHEN lower(p.code)=q.value THEN 100 WHEN lower(p.code) LIKE q.value||'%' THEN 90 WHEN q.value=ANY(p.search_aliases) THEN 82 WHEN lower(p.name) LIKE q.value||'%' THEN 75 ELSE 60 END
  FROM public.health_packages p,q WHERE length(q.value)>=2 AND p.lifecycle_status='Active' AND (lower(p.code) LIKE '%'||q.value||'%' OR lower(p.name) LIKE '%'||q.value||'%' OR EXISTS(SELECT 1 FROM unnest(p.search_aliases)a WHERE a LIKE '%'||q.value||'%'))
 ) SELECT m.* FROM matches m ORDER BY m.score DESC,m.name LIMIT greatest(1,least(COALESCE(p_limit,20),50));
END $$;

CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(p_patient_data JSONB,p_bill_data JSONB,p_items_data JSONB[],p_payment_data JSONB,p_idempotency_key TEXT,p_packages JSONB DEFAULT '[]') RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE response JSONB; bill_uuid UUID; pkg JSONB; component UUID; selection_uuid UUID; expected_ids UUID[]; supplied_ids UUID[]:=ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data)x); package_seen UUID[]:=ARRAY[]::UUID[];
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF cardinality(p_items_data)<>cardinality(supplied_ids) THEN RAISE EXCEPTION 'A canonical test/profile may be selected only once.' USING ERRCODE='23505'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item LEFT JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE t.id IS NULL OR t.lifecycle_status<>'Active' OR NOT t.is_active OR NOT t.workflow_supported OR t.clinical_configuration_status NOT IN ('Configured','Ready for Activation')) THEN RAISE EXCEPTION 'Only active, clinically configured, supported catalogue tests may be billed.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE COALESCE((item->>'unit_price_paisa')::BIGINT,t.price_paisa)=0 AND (NOT t.allow_zero_price_billing OR NOT COALESCE((item->>'zero_price_acknowledged')::BOOLEAN,FALSE))) THEN RAISE EXCEPTION 'Zero-price billing requires catalogue authorization and explicit operator acknowledgement.' USING ERRCODE='23514'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE NOT t.price_configured AND t.pricing_policy NOT IN ('PricePending','Manual')) THEN RAISE EXCEPTION 'A configured catalogue price is required for this pricing policy.' USING ERRCODE='23514'; END IF;
 FOR pkg IN SELECT * FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
  SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids FROM public.health_packages p JOIN public.health_package_components c ON c.package_id=p.id WHERE p.id=(pkg->>'package_id')::UUID AND p.lifecycle_status='Active';
  IF expected_ids IS NULL OR expected_ids<>ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x) THEN RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; END IF;
  FOREACH component IN ARRAY expected_ids LOOP IF component=ANY(package_seen) THEN RAISE EXCEPTION 'A component test may be expanded only once.' USING ERRCODE='23505'; END IF; IF NOT component=ANY(supplied_ids) THEN RAISE EXCEPTION 'Package component is missing from bill items.' USING ERRCODE='23514'; END IF; package_seen:=array_append(package_seen,component); END LOOP;
 END LOOP;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE t.pricing_policy='Fixed' AND NOT t.id=ANY(package_seen) AND COALESCE((item->>'unit_price_paisa')::BIGINT,-1)<>t.price_paisa) THEN RAISE EXCEPTION 'Fixed catalogue prices cannot be overridden during billing.' USING ERRCODE='42501'; END IF;
 IF EXISTS(SELECT 1 FROM unnest(p_items_data)item JOIN public.tests t ON t.id=(item->>'test_id')::UUID WHERE t.pricing_policy IN ('Negotiable','PricePending','Manual') AND ((item->>'unit_price_paisa') IS NULL OR (item->>'unit_price_paisa')::BIGINT<0)) THEN RAISE EXCEPTION 'Negotiable, pending, and manual items require a valid agreed rate.' USING ERRCODE='23514'; END IF;
 FOR pkg IN SELECT * FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
  IF (SELECT COALESCE(sum((item->>'unit_price_paisa')::BIGINT),0) FROM unnest(p_items_data)item WHERE (item->>'test_id')::UUID=ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x)))<>(SELECT price_paisa FROM public.health_packages WHERE id=(pkg->>'package_id')::UUID) THEN RAISE EXCEPTION 'Package component prices must equal the authoritative package price.' USING ERRCODE='23514'; END IF;
 END LOOP;
 response:=public.create_patient_bill_and_order(p_patient_data,p_bill_data,p_items_data,p_payment_data,p_idempotency_key); bill_uuid:=(response->>'bill_id')::UUID;
 FOR pkg IN SELECT * FROM jsonb_array_elements(COALESCE(p_packages,'[]')) LOOP
  INSERT INTO public.bill_package_selections(bill_id,package_id,package_code_snapshot,package_name_snapshot,package_price_paisa)
  SELECT bill_uuid,p.id,p.code,p.name,p.price_paisa FROM public.health_packages p WHERE p.id=(pkg->>'package_id')::UUID ON CONFLICT(bill_id,package_id) DO NOTHING RETURNING id INTO selection_uuid;
  IF selection_uuid IS NOT NULL THEN INSERT INTO public.bill_package_components(bill_package_selection_id,bill_item_id,test_id) SELECT selection_uuid,bi.id,bi.test_id FROM public.bill_items bi WHERE bi.bill_id=bill_uuid AND bi.test_id=ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids')x)); END IF;
 END LOOP;
 RETURN response||jsonb_build_object('packages_recorded',jsonb_array_length(COALESCE(p_packages,'[]')));
END $$;

-- Atomic administrative master mutations. Direct browser writes are revoked below.
CREATE OR REPLACE FUNCTION public.replace_role_permission_matrix(p_matrix JSONB) RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE entry JSONB; role_row public.roles%ROWTYPE; role_ids UUID[]:=ARRAY[]::UUID[]; permission_count INT:=0; allowed_permissions TEXT[]:=ARRAY['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_catalogue','can_manage_referring_doctors','can_manage_personnel','can_view_financials','can_manage_users','can_manage_roles','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports','can_finalize_hmis_reports'];
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

CREATE OR REPLACE FUNCTION public.save_reporting_personnel(p_personnel JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; old_row JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_personnel') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_personnel->>'full_name',''))='' OR btrim(COALESCE(p_personnel->>'qualification',''))='' OR btrim(COALESCE(p_personnel->>'registration_council',''))='' OR btrim(COALESCE(p_personnel->>'registration_number',''))='' THEN RAISE EXCEPTION 'Name, qualification, council and registration number are required.' USING ERRCODE='22023'; END IF;
 IF NULLIF(p_personnel->>'id','') IS NOT NULL THEN SELECT to_jsonb(r),r.id INTO old_row,result_id FROM public.reporting_personnel r WHERE r.id=(p_personnel->>'id')::UUID FOR UPDATE; IF result_id IS NULL THEN RAISE EXCEPTION 'Reporting personnel no longer exists.' USING ERRCODE='P0002'; END IF; UPDATE public.reporting_personnel SET full_name=btrim(p_personnel->>'full_name'),professional_type=(p_personnel->>'professional_type')::public.professional_type_enum,qualification=btrim(p_personnel->>'qualification'),registration_council=btrim(p_personnel->>'registration_council'),registration_number=btrim(p_personnel->>'registration_number'),specialization=NULLIF(btrim(p_personnel->>'specialization'),''),phone=NULLIF(btrim(p_personnel->>'phone'),''),email=NULLIF(btrim(p_personnel->>'email'),''),can_enter_results=COALESCE((p_personnel->>'can_enter_results')::BOOLEAN,TRUE),can_verify_results=COALESCE((p_personnel->>'can_verify_results')::BOOLEAN,FALSE),can_acknowledge_critical=COALESCE((p_personnel->>'can_acknowledge_critical')::BOOLEAN,FALSE),can_sign_reports=COALESCE((p_personnel->>'can_sign_reports')::BOOLEAN,FALSE),is_active=COALESCE((p_personnel->>'is_active')::BOOLEAN,TRUE),display_order=COALESCE((p_personnel->>'display_order')::INT,0),updated_at=NOW() WHERE id=result_id;
 ELSE INSERT INTO public.reporting_personnel(full_name,professional_type,qualification,registration_council,registration_number,specialization,phone,email,can_enter_results,can_verify_results,can_acknowledge_critical,can_sign_reports,is_active,display_order) VALUES(btrim(p_personnel->>'full_name'),(p_personnel->>'professional_type')::public.professional_type_enum,btrim(p_personnel->>'qualification'),btrim(p_personnel->>'registration_council'),btrim(p_personnel->>'registration_number'),NULLIF(btrim(p_personnel->>'specialization'),''),NULLIF(btrim(p_personnel->>'phone'),''),NULLIF(btrim(p_personnel->>'email'),''),COALESCE((p_personnel->>'can_enter_results')::BOOLEAN,TRUE),COALESCE((p_personnel->>'can_verify_results')::BOOLEAN,FALSE),COALESCE((p_personnel->>'can_acknowledge_critical')::BOOLEAN,FALSE),COALESCE((p_personnel->>'can_sign_reports')::BOOLEAN,FALSE),COALESCE((p_personnel->>'is_active')::BOOLEAN,TRUE),COALESCE((p_personnel->>'display_order')::INT,0)) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REPORTING_PERSONNEL_SAVED','ReportingPersonnel',result_id::TEXT,old_row,(SELECT to_jsonb(r) FROM public.reporting_personnel r WHERE r.id=result_id)); RETURN result_id;
END $$;

CREATE OR REPLACE FUNCTION public.save_referring_doctor(p_doctor JSONB) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result_id UUID; old_row JSONB;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_manage_referring_doctors') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(COALESCE(p_doctor->>'full_name',''))='' THEN RAISE EXCEPTION 'Doctor name is required.' USING ERRCODE='22023'; END IF;
 IF NULLIF(p_doctor->>'id','') IS NOT NULL THEN SELECT to_jsonb(d),d.id INTO old_row,result_id FROM public.referring_doctors d WHERE d.id=(p_doctor->>'id')::UUID FOR UPDATE; IF result_id IS NULL THEN RAISE EXCEPTION 'Referring doctor no longer exists.' USING ERRCODE='P0002'; END IF; UPDATE public.referring_doctors SET full_name=btrim(p_doctor->>'full_name'),code=NULLIF(upper(btrim(p_doctor->>'code')),''),degree=NULLIF(btrim(p_doctor->>'degree'),''),institution=NULLIF(btrim(p_doctor->>'institution'),''),phone=NULLIF(btrim(p_doctor->>'phone'),''),email=NULLIF(btrim(p_doctor->>'email'),''),address=NULLIF(btrim(p_doctor->>'address'),''),is_active=COALESCE((p_doctor->>'is_active')::BOOLEAN,TRUE),updated_at=NOW() WHERE id=result_id;
 ELSE INSERT INTO public.referring_doctors(full_name,code,degree,institution,phone,email,address,is_active) VALUES(btrim(p_doctor->>'full_name'),NULLIF(upper(btrim(p_doctor->>'code')),''),NULLIF(btrim(p_doctor->>'degree'),''),NULLIF(btrim(p_doctor->>'institution'),''),NULLIF(btrim(p_doctor->>'phone'),''),NULLIF(btrim(p_doctor->>'email'),''),NULLIF(btrim(p_doctor->>'address'),''),COALESCE((p_doctor->>'is_active')::BOOLEAN,TRUE)) RETURNING id INTO result_id; END IF;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'REFERRING_DOCTOR_SAVED','ReferringDoctor',result_id::TEXT,old_row,(SELECT to_jsonb(d) FROM public.referring_doctors d WHERE d.id=result_id)); RETURN result_id;
END $$;

REVOKE INSERT,UPDATE,DELETE ON public.role_permissions,public.reporting_personnel,public.referring_doctors FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB,JSONB,JSONB[],JSONB,TEXT) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.catalogue_actor_name(),public.catalogue_require_manager(),public.catalogue_test_missing_configuration(UUID),public.catalogue_save_test(JSONB,BIGINT),public.catalogue_set_test_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_update_test_price(UUID,BIGINT,BOOLEAN),public.catalogue_delete_test(UUID,BIGINT),public.catalogue_clone_test(UUID,TEXT,TEXT),public.catalogue_save_parameter(JSONB,BIGINT),public.catalogue_set_parameter_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_parameter(UUID,BIGINT),public.catalogue_save_range(JSONB,BIGINT),public.catalogue_set_range_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_range(UUID,BIGINT),public.catalogue_replace_ranges(UUID[],JSONB),public.catalogue_save_category(JSONB,BIGINT),public.catalogue_set_category_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_save_package(JSONB,UUID[],BIGINT),public.catalogue_set_package_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_package(UUID,BIGINT),public.catalogue_expand_package(UUID),public.search_billable_catalogue(TEXT,INT),public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB),public.replace_role_permission_matrix(JSONB),public.save_reporting_personnel(JSONB),public.save_referring_doctor(JSONB) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.catalogue_test_missing_configuration(UUID),public.catalogue_save_test(JSONB,BIGINT),public.catalogue_set_test_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_update_test_price(UUID,BIGINT,BOOLEAN),public.catalogue_delete_test(UUID,BIGINT),public.catalogue_clone_test(UUID,TEXT,TEXT),public.catalogue_save_parameter(JSONB,BIGINT),public.catalogue_set_parameter_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_parameter(UUID,BIGINT),public.catalogue_save_range(JSONB,BIGINT),public.catalogue_set_range_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_range(UUID,BIGINT),public.catalogue_replace_ranges(UUID[],JSONB),public.catalogue_save_category(JSONB,BIGINT),public.catalogue_set_category_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_save_package(JSONB,UUID[],BIGINT),public.catalogue_set_package_lifecycle(UUID,public.catalogue_lifecycle_enum,BIGINT),public.catalogue_delete_package(UUID,BIGINT),public.catalogue_expand_package(UUID),public.search_billable_catalogue(TEXT,INT),public.create_patient_bill_order_with_packages(JSONB,JSONB,JSONB[],JSONB,TEXT,JSONB),public.replace_role_permission_matrix(JSONB),public.save_reporting_personnel(JSONB),public.save_referring_doctor(JSONB) TO authenticated;

COMMENT ON TABLE public.health_packages IS 'Billing identities only. Components remain canonical tests and expand exactly once.';
COMMENT ON COLUMN public.tests.configuration_notes IS 'Administrative configuration notes; never clinical reference data.';

-- Reviewed identities only: deliberately Draft, non-billable, and clinically
-- incomplete. Source prices/specimens are not promoted to production truth.
WITH draft(code,name,kind,category_code,notes) AS (VALUES
 ('AFP','Alpha-Fetoprotein (AFP)','Individual','TUMOR_MARKERS','Clinical parameter, unit, method, specimen, range, tier and price require Bimal approval.'),
 ('BT_CT','Bleeding Time and Clotting Time (BT & CT)','Profile','HEMATOLOGY','One canonical profile; component parameter types, units and ranges require Bimal approval.'),
 ('PT_INR','Prothrombin Time / International Normalized Ratio (PT / INR)','Profile','HEMATOLOGY','Patient PT, Control PT, ISI and server-authoritative INR calculation remain unconfigured.'),
 ('LDH','Lactate Dehydrogenase (LDH)','Individual','BIOCHEMISTRY','Method-dependent parameter, unit, specimen, range, tier and price require Bimal approval.'),
 ('CHOL_TOTAL','Total Cholesterol','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('HDL_CHOL','HDL Cholesterol','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('LDL_CHOL','LDL Cholesterol','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('TRIGLYCERIDES','Triglycerides','Individual','BIOCHEMISTRY','Potential profile-component collision; review required.'),
 ('BILIRUBIN_TD','Bilirubin Total and Direct','Profile','BIOCHEMISTRY','Potential LFT collision; review required.'),
 ('AST','AST / SGOT','Individual','BIOCHEMISTRY','Potential LFT component collision; review required.'),
 ('ALT','ALT / SGPT','Individual','BIOCHEMISTRY','Potential LFT component collision; review required.'),
 ('ALP','Alkaline Phosphatase','Individual','BIOCHEMISTRY','Potential LFT component collision; review required.'),
 ('GGT','Gamma-Glutamyl Transferase','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('LIPASE','Lipase','Individual','BIOCHEMISTRY','Multi-specimen workflow requires review.'),
 ('AMYLASE','Amylase','Individual','BIOCHEMISTRY','Multi-specimen workflow requires review.'),
 ('CK_TOTAL','Creatine Kinase Total','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('CK_MB','Creatine Kinase MB','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('BICARBONATE','Bicarbonate','Individual','BIOCHEMISTRY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('GLOBULIN','Globulin','Individual','BIOCHEMISTRY','Existing calculated-parameter collision requires review.'),
 ('EGFR','Estimated Glomerular Filtration Rate','Individual','BIOCHEMISTRY','Calculation is not approved/configured.'),
 ('RETIC_COUNT','Reticulocyte Count','Individual','HEMATOLOGY','Reviewed reference-catalogue identity; clinical configuration required.'),
 ('AEC','Absolute Eosinophil Count','Individual','HEMATOLOGY','CBC-derived relationship requires review.'),
 ('ANC','Absolute Neutrophil Count','Individual','HEMATOLOGY','CBC-derived relationship requires review.')
)
INSERT INTO public.tests(code,name,department,category,category_id,test_kind,reporting_type,price_paisa,price_configured,sample_type,container,is_active,lifecycle_status,clinical_configuration_status,configuration_notes)
SELECT d.code,d.name,c.name,c.name,c.id,d.kind::public.catalogue_test_kind_enum,'NoReporting',0,FALSE,'','',FALSE,'Draft','Requires Clinical Validation',d.notes
FROM draft d JOIN public.test_categories c ON c.code=d.category_code
ON CONFLICT DO NOTHING;

-- Clinically correct result shapes for the four priority investigations.
-- Units, methods, ranges, critical limits and INR formula remain explicitly
-- validation-pending; no clinical value is inferred here.
WITH definitions(test_code,param_code,param_name,value_type,position,unit_pending,range_pending,method_pending) AS (VALUES
 ('AFP','AFP','Alpha-Fetoprotein','Numeric'::public.parameter_value_type_enum,1,TRUE,TRUE,TRUE),
 ('BT_CT','BLEEDING_TIME','Bleeding Time','Numeric'::public.parameter_value_type_enum,1,TRUE,TRUE,TRUE),
 ('BT_CT','CLOTTING_TIME','Clotting Time','Numeric'::public.parameter_value_type_enum,2,TRUE,TRUE,TRUE),
 ('PT_INR','PATIENT_PT','Patient PT','Numeric'::public.parameter_value_type_enum,1,TRUE,TRUE,TRUE),
 ('PT_INR','CONTROL_PT','Control PT','Numeric'::public.parameter_value_type_enum,2,TRUE,TRUE,TRUE),
 ('PT_INR','ISI','ISI','Numeric'::public.parameter_value_type_enum,3,TRUE,TRUE,TRUE),
 ('PT_INR','INR','INR','Calculated'::public.parameter_value_type_enum,4,TRUE,TRUE,TRUE),
 ('LDH','LDH','Lactate Dehydrogenase','Numeric'::public.parameter_value_type_enum,1,TRUE,TRUE,TRUE)
)
INSERT INTO public.parameters(test_id,code,name,value_type,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
SELECT t.id,d.param_code,d.param_name,d.value_type,d.position,TRUE,FALSE,'Draft','Requires Clinical Validation',d.unit_pending,d.range_pending,d.method_pending
FROM definitions d JOIN public.tests t ON t.code=d.test_code
ON CONFLICT(test_id,code) DO NOTHING;

UPDATE public.tests SET workflow_supported=FALSE,clinical_configuration_status='Workflow Not Supported',configuration_notes=COALESCE(configuration_notes||' ','')||'Catalogue identity only; specialized result workflow is not supported.'
WHERE lifecycle_status='Draft' AND category_id IN (SELECT id FROM public.test_categories WHERE code IN ('MOLECULAR','MICROBIOLOGY','HISTOPATHOLOGY','IHC','GENETICS'));
