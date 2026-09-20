-- ==============================================================================
-- Migration: 00128_final_clinical_range_polish.sql
-- Goal: Final Clinical Reference Range Polish & Server-Side Zero-Parameter Guard
--
-- Scope:
-- 1. Manual Differential Count (5-part microscopy):
--    - HEM-0015 (Neutrophils %): 40.0 - 70.0 %
--    - HEM-0016 (Lymphocytes %): 20.0 - 40.0 %
--    - HEM-0017 (Monocytes %): 2.0 - 10.0 %
--    - HEM-0018 (Eosinophils %): 1.0 - 6.0 %
--    - HEM-0019 (Basophils %): 0.0 - 1.0 %
--
-- 2. Vitamin D, 25-OH (BIO-0053):
--    - Unit: ng/mL
--    - Approved range: 30.0 - 100.0 ng/mL
--    - Approved interpretation: <20 Deficient | 20-30 Insufficient | 30-100 Sufficient
--    - Unapproved interpretations above 100 strictly excluded.
--
-- 3. Vitamin B12 (BIO-0051):
--    - Unit: pg/mL
--    - Approved range: 200.0 - 900.0 pg/mL
--    - Approved interpretation: Borderline: 200 - 300 pg/mL
--    - Inferred unapproved labels strictly excluded.
--
-- 4. Server-Side Zero-Parameter Clinical Ordering Structural Guard:
--    - Enforce at create_patient_bill_order_with_packages boundary that reportable single tests
--      with 0 reporting parameters cannot be ordered.
--    - Whitelist valid profile containers (PRO-0031, PRO-0032, PRO-0033, etc.) and NoReporting items.
--
-- 5. Active Reference Range De-duplication:
--    - Deactivate legacy duplicate rows to guarantee exactly 1 active range per parameter/gender/age band.
--
-- Clinical Invariants:
-- - Zero price changes.
-- - Zero renaming of tests, parameters, or canonical codes.
-- - Zero alteration of historical test results or signed clinical snapshots.
-- - Idempotent, duplicate-safe.
-- ==============================================================================

BEGIN;

DO $$
DECLARE
    v_param_id UUID;
BEGIN

    -- =========================================================================
    -- 1. MANUAL DIFFERENTIAL MICROSCOPY (HEM-0015 .. HEM-0019)
    -- =========================================================================

    -- Neutrophils % (HEM-0015) - 40.0 - 70.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0015' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 40.0, 70.0, '40 - 70 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Lymphocytes % (HEM-0016) - 20.0 - 40.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0016' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 20.0, 40.0, '20 - 40 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Monocytes % (HEM-0017) - 2.0 - 10.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0017' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 2.0, 10.0, '2 - 10 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Eosinophils % (HEM-0018) - 1.0 - 6.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0018' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 1.0, 6.0, '1 - 6 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- Basophils % (HEM-0019) - 0.0 - 1.0 %
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'HEM-0019' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 0.0, 1.0, '0 - 1 %', '%', 'Manual Microscopy Differential', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 2. VITAMIN D, 25-OH (BIO-0053)
    -- =========================================================================
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'BIO-0053' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 30.0, 100.0, '30 - 100 ng/mL (Sufficient; <20 Deficient, 20-30 Insufficient)', 'ng/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 3. VITAMIN B12 (BIO-0051)
    -- =========================================================================
    SELECT p.id INTO v_param_id 
    FROM public.parameters p 
    JOIN public.tests t ON t.id = p.test_id 
    WHERE t.code = 'BIO-0051' AND p.is_active = TRUE 
    LIMIT 1;
    IF v_param_id IS NOT NULL THEN
        DELETE FROM public.reference_ranges WHERE parameter_id = v_param_id;
        INSERT INTO public.reference_ranges (parameter_id, gender, age_min_days, age_max_days, normal_min, normal_max, normal_text, unit, method, is_approved, is_active)
        VALUES (v_param_id, 'All', 0, 43800, 200.0, 900.0, '200 - 900 pg/mL (Borderline: 200 - 300 pg/mL)', 'pg/mL', 'Fluorescence Immunoassay (FIA)', TRUE, TRUE);
    END IF;

    -- =========================================================================
    -- 4. CLEAN UP LEGACY DUPLICATE ACTIVE REFERENCE RANGES
    -- =========================================================================
    WITH ranked_ranges AS (
        SELECT id, ROW_NUMBER() OVER (
            PARTITION BY parameter_id, gender, age_min_days, age_max_days 
            ORDER BY created_at DESC, id DESC
        ) as rn
        FROM public.reference_ranges
        WHERE is_active = TRUE
    )
    UPDATE public.reference_ranges
    SET is_active = FALSE
    WHERE id IN (
        SELECT id FROM ranked_ranges WHERE rn > 1
    );

END $$;

-- =============================================================================
-- 5. SERVER-SIDE STRUCTURAL ZERO-PARAMETER CLINICAL ORDERING GUARD
-- =============================================================================
CREATE OR REPLACE FUNCTION public.create_patient_bill_order_with_packages(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB,
    p_idempotency_key TEXT,
    p_packages JSONB DEFAULT '[]'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE 
    response JSONB; 
    bill_uuid UUID; 
    pkg JSONB; 
    component UUID; 
    selection_uuid UUID; 
    expected_ids UUID[]; 
    supplied_ids UUID[] := ARRAY(SELECT DISTINCT (x->>'test_id')::UUID FROM unnest(p_items_data) x); 
    package_seen UUID[] := ARRAY[]::UUID[]; 
    manual_ids UUID[] := ARRAY[]::UUID[]; 
    package_row public.health_packages%ROWTYPE; 
    agreed_price BIGINT; 
    component_sum BIGINT;
BEGIN
    IF auth.uid() IS NULL OR NOT public.has_permission('can_create_bill') THEN 
        RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; 
    END IF;

    IF cardinality(p_items_data) <> cardinality(supplied_ids) THEN 
        RAISE EXCEPTION 'A canonical service may be selected only once.' USING ERRCODE='23505'; 
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        LEFT JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE t.id IS NULL OR t.lifecycle_status <> 'Active' OR NOT t.is_active OR NOT t.billing_enabled
    ) THEN 
        RAISE EXCEPTION 'Only active, billing-enabled catalogue services may be billed.' USING ERRCODE='23514'; 
    END IF;

    -- Server-side structural guard: Reject reportable single tests with zero active reporting parameters
    -- (Whitelist valid profile containers with children and NoReporting items)
    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID
        WHERE t.reporting_type <> 'NoReporting'
          AND t.test_kind <> 'Profile'
          AND t.reporting_model <> 'Profile'
          AND NOT EXISTS (
              SELECT 1 FROM public.catalogue_panel_components cpc 
              WHERE cpc.panel_id = t.id OR cpc.panel_test_id = t.id
          )
          AND NOT EXISTS (
              SELECT 1 FROM public.parameters p 
              WHERE p.test_id = t.id AND p.is_active = TRUE
          )
    ) THEN
        RAISE EXCEPTION 'Configuration Incomplete: Reportable single test with 0 reporting parameters cannot be clinically ordered.' USING ERRCODE='23514';
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        WHERE (i->>'unit_price_paisa') IS NULL OR (i->>'unit_price_paisa')::BIGINT < 0
    ) THEN 
        RAISE EXCEPTION 'Every item requires a valid agreed rate.' USING ERRCODE='23514'; 
    END IF;

    IF EXISTS (
        SELECT 1 
        FROM unnest(p_items_data) i 
        JOIN public.tests t ON t.id = (i->>'test_id')::UUID 
        WHERE (i->>'unit_price_paisa')::BIGINT = 0 
          AND (NOT t.allow_zero_price_billing OR NOT COALESCE((i->>'zero_price_acknowledged')::BOOLEAN, FALSE))
    ) THEN 
        RAISE EXCEPTION 'Zero-price billing requires explicit catalogue authorization and acknowledgement.' USING ERRCODE='23514'; 
    END IF;

    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        SELECT * INTO package_row FROM public.health_packages WHERE id = (pkg->>'package_id')::UUID AND lifecycle_status = 'Active' FOR SHARE; 
        IF NOT FOUND THEN 
            RAISE EXCEPTION 'Only active packages may be billed.' USING ERRCODE='23514'; 
        END IF;

        SELECT array_agg(c.test_id ORDER BY c.display_order) INTO expected_ids 
        FROM public.health_package_components c 
        JOIN public.tests t ON t.id = c.test_id 
        WHERE c.package_id = package_row.id AND t.lifecycle_status = 'Active' AND t.is_active AND t.billing_enabled;

        IF expected_ids IS NULL OR expected_ids <> ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x) THEN 
            RAISE EXCEPTION 'Package definition changed. Refresh billing catalogue.' USING ERRCODE='PT409'; 
        END IF;

        agreed_price := (pkg->>'agreed_price_paisa')::BIGINT; 
        IF agreed_price <= 0 THEN 
            RAISE EXCEPTION 'A package requires a positive agreed price.' USING ERRCODE='23514'; 
        END IF;

        FOREACH component IN ARRAY expected_ids LOOP 
            IF component = ANY(package_seen) OR NOT component = ANY(supplied_ids) THEN 
                RAISE EXCEPTION 'Package components are duplicated or missing.' USING ERRCODE='23514'; 
            END IF; 
            package_seen := array_append(package_seen, component); 
        END LOOP;

        SELECT COALESCE(sum((i->>'unit_price_paisa')::BIGINT), 0) INTO component_sum 
        FROM unnest(p_items_data) i 
        WHERE (i->>'test_id')::UUID = ANY(expected_ids); 
        
        IF component_sum <> agreed_price THEN 
            RAISE EXCEPTION 'Package component prices must equal the agreed package price.' USING ERRCODE='23514'; 
        END IF;
    END LOOP;

    PERFORM 1 FROM public.tests t WHERE t.id = ANY(supplied_ids) ORDER BY t.id FOR UPDATE;
    SELECT COALESCE(array_agg(id ORDER BY id), ARRAY[]::UUID[]) INTO manual_ids FROM public.tests WHERE id = ANY(supplied_ids) AND NOT allow_manual_price;
    UPDATE public.tests SET allow_manual_price = TRUE WHERE id = ANY(manual_ids);

    response := public.create_patient_bill_and_order(p_patient_data, p_bill_data, p_items_data, p_payment_data, p_idempotency_key); 
    bill_uuid := (response->>'bill_id')::UUID;

    UPDATE public.bill_items bi SET catalogue_price_paisa_snapshot = t.price_paisa FROM public.tests t WHERE bi.bill_id = bill_uuid AND bi.test_id = t.id;
    UPDATE public.tests SET allow_manual_price = FALSE WHERE id = ANY(manual_ids);

    FOR pkg IN SELECT value FROM jsonb_array_elements(COALESCE(p_packages, '[]')) LOOP
        INSERT INTO public.bill_package_selections(bill_id, package_id, package_code_snapshot, package_name_snapshot, package_price_paisa, catalogue_package_price_paisa)
        SELECT bill_uuid, p.id, p.code, p.name, (pkg->>'agreed_price_paisa')::BIGINT, p.price_paisa 
        FROM public.health_packages p 
        WHERE p.id = (pkg->>'package_id')::UUID
        ON CONFLICT(bill_id, package_id) DO NOTHING RETURNING id INTO selection_uuid;

        IF selection_uuid IS NOT NULL THEN 
            INSERT INTO public.bill_package_components(bill_package_selection_id, bill_item_id, test_id) 
            SELECT selection_uuid, bi.id, bi.test_id 
            FROM public.bill_items bi 
            WHERE bi.bill_id = bill_uuid AND bi.test_id = ANY(ARRAY(SELECT x::UUID FROM jsonb_array_elements_text(pkg->'component_ids') x)); 
        END IF;
    END LOOP;

    RETURN response || jsonb_build_object('packages_recorded', jsonb_array_length(COALESCE(p_packages, '[]')));
END;
$function$;

REVOKE ALL ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_order_with_packages(JSONB, JSONB, JSONB[], JSONB, TEXT, JSONB) TO authenticated;

-- =============================================================================
-- 6. SPARROW SINGLE-CREDIT NEPALI SMS GENERATION & NOTIFICATION PATHS
-- =============================================================================

CREATE OR REPLACE FUNCTION public.format_nepali_digits(p_val TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
BEGIN
  IF p_val IS NULL THEN RETURN ''; END IF;
  RETURN translate(p_val, '0123456789', '०१२३४५६७८९');
END;
$$;

CREATE OR REPLACE FUNCTION public.format_nepali_amount(p_paisa BIGINT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_rupees BIGINT;
  v_rem BIGINT;
BEGIN
  IF p_paisa IS NULL OR p_paisa <= 0 THEN RETURN '०'; END IF;
  v_rupees := p_paisa / 100;
  v_rem := p_paisa % 100;
  IF v_rem = 0 THEN
    RETURN public.format_nepali_digits(v_rupees::TEXT);
  ELSIF v_rem % 10 = 0 THEN
    RETURN public.format_nepali_digits(v_rupees::TEXT) || '.' || public.format_nepali_digits((v_rem / 10)::TEXT);
  ELSE
    RETURN public.format_nepali_digits(v_rupees::TEXT) || '.' || public.format_nepali_digits(lpad(v_rem::TEXT, 2, '0'));
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_sms_test_alias(p_name TEXT, p_max_len INT DEFAULT 10)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_norm TEXT := lower(trim(coalesce(p_name, '')));
BEGIN
  IF v_norm ~ 'complete\s+blood\s+count|^cbc\b' THEN RETURN 'CBC'; END IF;
  IF v_norm ~ 'lipid\s+profile|^lipid\b' THEN 
    IF p_max_len >= 5 THEN RETURN 'Lipid'; ELSE RETURN 'LP'; END IF;
  END IF;
  IF v_norm ~ 'liver\s+function\s+test|^lft\b' THEN RETURN 'LFT'; END IF;
  IF v_norm ~ 'kidney\s+function|renal\s+function|^kft\b|^rft\b' THEN RETURN 'KFT'; END IF;
  IF v_norm ~ 'thyroid\s+profile|thyroid\s+function|^tft\b|^thyroid\b' THEN 
    IF p_max_len >= 7 THEN RETURN 'Thyroid'; ELSE RETURN 'TFT'; END IF;
  END IF;
  IF v_norm ~ 'urine\s+routine|urine\s+r\/?e|^urine\b' THEN 
    IF p_max_len >= 5 THEN RETURN 'Urine'; ELSE RETURN 'UR'; END IF;
  END IF;
  IF v_norm ~ 'vitamin\s+d\b|25-oh|vit\s*d' THEN 
    IF p_max_len >= 5 THEN RETURN 'Vit D'; ELSE RETURN 'VD'; END IF;
  END IF;
  IF v_norm ~ 'vitamin\s+b12\b|vit\s*b12|\bb12\b' THEN 
    IF p_max_len >= 7 THEN RETURN 'Vit B12'; ELSE RETURN 'B12'; END IF;
  END IF;
  IF v_norm ~ 'd-dimer' THEN 
    IF p_max_len >= 7 THEN RETURN 'D-Dimer'; ELSE RETURN 'DD'; END IF;
  END IF;
  IF v_norm ~ 'ferritin' THEN 
    IF p_max_len >= 8 THEN RETURN 'Ferritin'; ELSE RETURN 'FER'; END IF;
  END IF;
  IF v_norm ~ 'hba1c|glycated\s+hemoglobin' THEN 
    IF p_max_len >= 5 THEN RETURN 'HbA1c'; ELSE RETURN 'A1c'; END IF;
  END IF;

  IF length(trim(p_name)) <= p_max_len AND p_name ~ '^[A-Za-z0-9+ -]+$' THEN
    RETURN trim(p_name);
  END IF;

  RETURN 'Lab';
END;
$$;

CREATE OR REPLACE FUNCTION public.build_single_credit_nepali_sms(
  p_order_id UUID,
  p_report_id UUID DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_bill_id UUID;
  v_amount_paisa BIGINT := 0;
  v_amount_str TEXT;
  v_test_count INT := 0;
  v_first_test_name TEXT;
  v_alias TEXT;
  v_msg TEXT;
  v_avail_len INT;
BEGIN
  SELECT o.bill_id INTO v_bill_id FROM public.clinical_orders o WHERE o.id = p_order_id;
  IF v_bill_id IS NOT NULL THEN
    SELECT COALESCE(paid_amount_paisa, net_amount_paisa, 0) INTO v_amount_paisa FROM public.bills WHERE id = v_bill_id;
  END IF;

  v_amount_str := public.format_nepali_amount(v_amount_paisa);

  v_avail_len := 70 - (63 + length(v_amount_str));

  SELECT count(DISTINCT t.id), min(t.name)
  INTO v_test_count, v_first_test_name
  FROM public.clinical_order_items coi
  JOIN public.tests t ON t.id = coi.test_id
  WHERE coi.order_id = p_order_id AND coi.clinical_reporting_enabled = TRUE;

  IF v_test_count = 1 AND v_first_test_name IS NOT NULL THEN
    v_alias := public.get_sms_test_alias(v_first_test_name, greatest(1, v_avail_len));
  ELSE
    v_alias := 'Lab';
  END IF;

  v_msg := 'Bimal Pathology: ' || v_alias || ' रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';

  IF length(v_msg) > 70 THEN
    v_alias := substring(v_alias from 1 for greatest(1, v_avail_len));
    v_msg := 'Bimal Pathology: ' || v_alias || ' रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  END IF;

  IF length(v_msg) > 70 THEN
    v_msg := 'Bimal Pathology: Lab रिपोर्ट तयार भयो। रु ' || v_amount_str || ' भुक्तानको लागि धन्यवाद।';
  END IF;

  RETURN v_msg;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_public_report_token(
  p_report_id UUID,p_token_hash VARCHAR(128),p_expiry_days INT DEFAULT 30,p_public_url_base TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE report public.diagnostic_reports%ROWTYPE; existing public.public_report_tokens%ROWTYPE;
  patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE;
  token_id UUID; v_expires_at TIMESTAMPTZ; raw_token TEXT; delivery_host TEXT;
  phone TEXT; sms_id UUID; v_sms_body TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required.' USING ERRCODE='42501'; END IF;
  IF NOT(public.has_permission('can_sign_reports') OR public.is_super_admin()) THEN
    RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501';
  END IF;
  SELECT * INTO report FROM public.diagnostic_reports WHERE id=p_report_id FOR UPDATE;
  IF NOT FOUND OR report.status NOT IN('SignedOff','Amended') THEN
    RAISE EXCEPTION 'A signed or amended report is required.' USING ERRCODE='22023';
  END IF;
  UPDATE public.public_report_tokens token SET is_active=FALSE,updated_at=NOW()
    WHERE token.diagnostic_report_id=p_report_id AND token.is_active
      AND (token.revoked_at IS NOT NULL OR token.expires_at<=NOW());
  SELECT * INTO existing FROM public.public_report_tokens
    WHERE diagnostic_report_id=p_report_id AND is_active AND revoked_at IS NULL AND expires_at>NOW()
    ORDER BY created_at LIMIT 1 FOR UPDATE;
  IF FOUND THEN
    RETURN jsonb_build_object('success',TRUE,'token_id',existing.id,'expires_at',existing.expires_at,
      'report_number',report.report_number,'sms_queued',FALSE,'sms_status','Existing report link retained',
      'idempotency_replay',TRUE);
  END IF;
  raw_token:=substring(p_public_url_base FROM '/r/([A-Za-z0-9_-]+)$');
  delivery_host:=substring(p_public_url_base FROM '^https://(lis|dashboard)[.]bimalpathology[.]com[.]np/r/');
  IF delivery_host IS NULL OR raw_token IS NULL OR length(raw_token) NOT BETWEEN 32 AND 256
     OR p_token_hash IS NULL OR p_token_hash !~ '^[0-9a-f]{64}$'
     OR encode(extensions.digest(convert_to(raw_token,'UTF8'),'sha256'),'hex')<>p_token_hash THEN
    RAISE EXCEPTION 'A valid approved production report token is required.' USING ERRCODE='22023';
  END IF;
  v_expires_at:=NOW()+(greatest(1,least(COALESCE(p_expiry_days,30),90))||' days')::INTERVAL;
  INSERT INTO public.public_report_tokens(diagnostic_report_id,token_hash,expires_at,created_by,is_active)
    VALUES(p_report_id,p_token_hash,v_expires_at,auth.uid(),TRUE) RETURNING id INTO token_id;
  INSERT INTO public.report_secure_link_presentations(report_token_id,public_url)
    VALUES(token_id,p_public_url_base);
  IF delivery_host='dashboard' THEN
    INSERT INTO public.report_pdf_delivery_intents(diagnostic_report_id,report_token_id,public_url)
      VALUES(p_report_id,token_id,p_public_url_base);
  ELSE
    SELECT * INTO patient FROM public.patients WHERE id=report.patient_id;
    SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
    phone:=regexp_replace(COALESCE(patient.mobile,''),'[^0-9]','','g');
    IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
    IF phone~'^(97|98)[0-9]{8}$' THEN
      v_sms_body := public.build_single_credit_nepali_sms(report.order_id, report.id);
      INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id)
      VALUES('ReportReady',phone,patient.full_name,
        v_sms_body,
        'Pending','REPORT_READY:'||report.id::TEXT||':'||report.version::TEXT,report.id)
      ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
    END IF;
  END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
    VALUES(auth.uid(),'Authorized Signatory','PUBLIC_REPORT_TOKEN_CREATED','DiagnosticReport',report.report_number,
      jsonb_build_object('report_id',p_report_id,'token_id',token_id,'expires_at',v_expires_at,
        'delivery_host',delivery_host||'.bimalpathology.com.np',
        'delivery_state',CASE WHEN delivery_host='dashboard' THEN 'AwaitingArtifact' ELSE 'LegacyImmediate' END));
  RETURN jsonb_build_object('success',TRUE,'token_id',token_id,'expires_at',v_expires_at,
    'report_number',report.report_number,'sms_queued',sms_id IS NOT NULL,
    'sms_status',CASE WHEN delivery_host='dashboard' THEN 'Awaiting authoritative PDF'
      WHEN sms_id IS NOT NULL THEN 'Report notification queued' ELSE 'SMS skipped: invalid or missing Nepal mobile' END,
    'idempotency_replay',FALSE);
END $$;

CREATE OR REPLACE FUNCTION public.notify_updated_order_reports(p_order_id UUID,p_expected_generation INTEGER,p_reason TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE current_generation INT; token public.order_report_delivery_tokens%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; phone TEXT; sms_id UUID; next_generation INT; v_sms_body TEXT;
BEGIN
 IF auth.uid() IS NULL OR NOT public.has_permission('can_sign_reports') THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 IF btrim(coalesce(p_reason,''))='' THEN RAISE EXCEPTION 'Notification reason is required.' USING ERRCODE='23514'; END IF;
 PERFORM pg_advisory_xact_lock(hashtextextended(p_order_id::text,91));
 SELECT coalesce(max(generation),0) INTO current_generation FROM public.order_report_notification_generations WHERE order_id=p_order_id;
 IF current_generation<>p_expected_generation THEN RAISE EXCEPTION 'Notification state changed. Refresh and retry.' USING ERRCODE='PT409'; END IF;
 SELECT * INTO token FROM public.order_report_delivery_tokens WHERE order_id=p_order_id AND is_active AND revoked_at IS NULL;
 IF NOT FOUND THEN RAISE EXCEPTION 'Order delivery entitlement is unavailable.' USING ERRCODE='23514'; END IF;
 SELECT dr.* INTO report FROM public.diagnostic_reports dr WHERE dr.order_id=p_order_id AND dr.report_group_id IS NOT NULL AND dr.status='SignedOff' ORDER BY dr.signed_at DESC LIMIT 1;
 IF NOT FOUND THEN RAISE EXCEPTION 'No finalized report is available.' USING ERRCODE='23514'; END IF;
 SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=p_order_id;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF; IF phone !~ '^(97|98)[0-9]{8}$' THEN RAISE EXCEPTION 'Patient has no valid Nepal mobile.' USING ERRCODE='23514'; END IF;
 next_generation:=current_generation+1;
 v_sms_body := public.build_single_credit_nepali_sms(p_order_id, report.id);
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) SELECT 'ReportReady',phone,patient.full_name,v_sms_body,'Pending','ORDER_REPORT_READY:'||p_order_id||':'||next_generation,report.id FROM public.report_pdf_delivery_intents i WHERE i.order_token_id=token.id ORDER BY i.queued_at NULLS LAST LIMIT 1 ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF sms_id IS NULL THEN SELECT sms_queue_item_id INTO sms_id FROM public.order_report_notification_generations WHERE order_id=p_order_id AND generation=next_generation; END IF;
 INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(p_order_id,next_generation,btrim(p_reason),auth.uid(),sms_id) ON CONFLICT(order_id,generation) DO NOTHING;
 INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.catalogue_actor_name(),'ORDER_REPORT_UPDATED_NOTIFICATION','ClinicalOrder',p_order_id::text,jsonb_build_object('generation',next_generation,'reason',btrim(p_reason)));
 RETURN jsonb_build_object('success',true,'generation',next_generation,'sms_queue_item_id',sms_id);
END $$;

CREATE OR REPLACE FUNCTION public.complete_report_pdf_artifact_v2(p_artifact_id UUID,p_lease_owner UUID,p_ready BOOLEAN,p_pdf_sha256 TEXT DEFAULT NULL,p_byte_size BIGINT DEFAULT NULL,p_generator_name TEXT DEFAULT NULL,p_generator_version TEXT DEFAULT NULL,p_failure_code TEXT DEFAULT NULL) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public,pg_temp AS $$
DECLARE result JSONB; artifact public.report_pdf_artifacts%ROWTYPE; intent public.report_pdf_delivery_intents%ROWTYPE; report public.diagnostic_reports%ROWTYPE; patient public.patients%ROWTYPE; ordering public.clinical_orders%ROWTYPE; sms_id UUID; phone TEXT; generation_id UUID; v_sms_body TEXT;
BEGIN
 IF NOT public.is_report_artifact_worker() THEN RAISE EXCEPTION 'Permission denied.' USING ERRCODE='42501'; END IF;
 result:=public.complete_report_pdf_artifact(p_artifact_id,p_lease_owner,p_ready,p_pdf_sha256,p_byte_size,p_generator_name,p_generator_version,p_failure_code); IF NOT p_ready THEN RETURN result; END IF;
 SELECT * INTO artifact FROM public.report_pdf_artifacts WHERE id=p_artifact_id; SELECT * INTO intent FROM public.report_pdf_delivery_intents WHERE diagnostic_report_id=artifact.diagnostic_report_id AND status='AwaitingArtifact' FOR UPDATE;
 IF NOT FOUND THEN RETURN result||jsonb_build_object('sms_queued',false); END IF;
 SELECT * INTO report FROM public.diagnostic_reports WHERE id=artifact.diagnostic_report_id; SELECT * INTO patient FROM public.patients WHERE id=report.patient_id; SELECT * INTO ordering FROM public.clinical_orders WHERE id=report.order_id;
 IF intent.order_token_id IS NOT NULL AND EXISTS(SELECT 1 FROM public.order_report_notification_generations WHERE order_id=report.order_id AND generation=1) THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','Order already notified'); END IF;
 phone:=regexp_replace(coalesce(patient.mobile,''),'[^0-9]','','g'); IF phone LIKE '977%' AND length(phone)=13 THEN phone:=substring(phone FROM 4); END IF;
 IF phone !~ '^(97|98)[0-9]{8}$' THEN UPDATE public.report_pdf_delivery_intents SET status='Skipped',queued_at=now() WHERE diagnostic_report_id=report.id; RETURN result||jsonb_build_object('sms_queued',false,'sms_status','SMS skipped: invalid or missing Nepal mobile'); END IF;
 v_sms_body := public.build_single_credit_nepali_sms(report.order_id, report.id);
 INSERT INTO public.sms_queue_items(sms_type,recipient_phone,recipient_name,message_body,status,idempotency_key,diagnostic_report_id) VALUES('ReportReady',phone,patient.full_name,v_sms_body,'Pending',CASE WHEN intent.order_token_id IS NULL THEN 'REPORT_READY:'||report.id||':'||report.version ELSE 'ORDER_REPORT_READY:'||report.order_id||':1' END,report.id) ON CONFLICT(idempotency_key) DO NOTHING RETURNING id INTO sms_id;
 IF intent.order_token_id IS NOT NULL THEN INSERT INTO public.order_report_notification_generations(order_id,generation,reason,requested_by,sms_queue_item_id) VALUES(report.order_id,1,'First finalized PDF milestone',coalesce(report.signed_by_personnel_id,report.performed_by_personnel_id),sms_id) ON CONFLICT(order_id,generation) DO NOTHING RETURNING id INTO generation_id; END IF;
  UPDATE public.report_pdf_delivery_intents SET status=CASE WHEN sms_id IS NULL THEN 'Skipped' ELSE 'Queued' END,queued_sms_id=sms_id,queued_at=now() WHERE diagnostic_report_id=report.id;
  RETURN result||jsonb_build_object('sms_queued',sms_id IS NOT NULL);
END $$;

GRANT EXECUTE ON FUNCTION public.format_nepali_digits(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.format_nepali_amount(BIGINT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_sms_test_alias(TEXT, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.build_single_credit_nepali_sms(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_public_report_token(UUID, VARCHAR(128), INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_updated_order_reports(UUID, INT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_report_pdf_artifact_v2(UUID, UUID, BOOLEAN, TEXT, BIGINT, TEXT, TEXT, TEXT) TO authenticated;

COMMIT;
