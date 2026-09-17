-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00013: Enforce Patient Uniqueness (One Mobile Number = One Patient)
-- Safe, forward-only, idempotent migration
-- ============================================================================

-- 1. Create UNIQUE INDEX on patients(mobile)
CREATE UNIQUE INDEX IF NOT EXISTS uq_patients_mobile ON public.patients (mobile);

-- 2. Update create_patient_bill_and_order with atomic mobile normalization and patient deduplication
CREATE OR REPLACE FUNCTION public.create_patient_bill_and_order(
    p_patient_data JSONB,
    p_bill_data JSONB,
    p_items_data JSONB[],
    p_payment_data JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_patient_id UUID;
    v_patient_uhid VARCHAR(50);
    v_bill_id UUID;
    v_bill_number VARCHAR(50);
    v_order_id UUID;
    v_order_number VARCHAR(50);
    v_order_item_id UUID;
    v_sample_id UUID;
    v_clean_mobile VARCHAR(20);
    v_gross_paisa BIGINT := 0;
    v_discount_paisa BIGINT := 0;
    v_net_paisa BIGINT := 0;
    v_paid_paisa BIGINT := 0;
    v_due_paisa BIGINT := 0;
    v_pay_status payment_status_enum;
    v_current_year VARCHAR(4);
    v_item JSONB;
    v_test RECORD;
    v_param RECORD;
    v_has_clinical_items BOOLEAN := FALSE;
    v_pay_amount BIGINT;
    v_sample_key TEXT;
    v_specimen TEXT;
    v_container TEXT;
    v_sample_map JSONB := '{}'::JSONB;
BEGIN
    -- ------------------------------------------------------------------------
    -- 0. CALLER AUTHORIZATION CHECK
    -- ------------------------------------------------------------------------
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required: Anonymous callers cannot create bills.';
    END IF;

    IF NOT public.has_permission('can_create_bill') THEN
        RAISE EXCEPTION 'Access Denied: Caller does not possess can_create_bill permission.';
    END IF;

    v_current_year := TO_CHAR(CURRENT_DATE, 'YYYY');

    -- ------------------------------------------------------------------------
    -- 1. PATIENT RULE ENFORCEMENT: 1 Mobile = 1 Patient
    -- ------------------------------------------------------------------------
    v_clean_mobile := REGEXP_REPLACE(TRIM(COALESCE(p_patient_data->>'mobile', '')), '[^0-9]', '', 'g');
    
    -- Strip country code 977 if present and length > 10
    IF v_clean_mobile LIKE '977%' AND LENGTH(v_clean_mobile) > 10 THEN
        v_clean_mobile := SUBSTRING(v_clean_mobile FROM 4);
    END IF;
    
    -- Strip leading 0 if 11 digits
    IF v_clean_mobile LIKE '0%' AND LENGTH(v_clean_mobile) = 11 THEN
        v_clean_mobile := SUBSTRING(v_clean_mobile FROM 2);
    END IF;

    IF LENGTH(v_clean_mobile) != 10 OR (v_clean_mobile NOT LIKE '98%' AND v_clean_mobile NOT LIKE '97%') THEN
        RAISE EXCEPTION 'Invalid Nepal mobile number (%). Must be a valid 10-digit number starting with 98 or 97.', v_clean_mobile;
    END IF;

    -- Atomic check for existing patient (with lock)
    SELECT id, uhid INTO v_patient_id, v_patient_uhid
    FROM public.patients
    WHERE mobile = v_clean_mobile
    FOR UPDATE;

    IF v_patient_id IS NULL THEN
        -- Create new Patient with sequential UHID
        v_patient_uhid := 'BP-' || v_current_year || '-' || LPAD(NEXTVAL('uhid_seq')::TEXT, 5, '0');
        
        INSERT INTO public.patients (
            uhid,
            mobile,
            title,
            full_name,
            gender,
            dob,
            age_years,
            age_months,
            age_days,
            address,
            email,
            identification_no
        ) VALUES (
            v_patient_uhid,
            v_clean_mobile,
            p_patient_data->>'title',
            TRIM(p_patient_data->>'full_name'),
            COALESCE(p_patient_data->>'gender', 'Other'),
            (p_patient_data->>'dob')::DATE,
            (p_patient_data->>'age_years')::INT,
            (p_patient_data->>'age_months')::INT,
            (p_patient_data->>'age_days')::INT,
            COALESCE(TRIM(p_patient_data->>'address'), 'Bharatpur, Chitwan'),
            p_patient_data->>'email',
            p_patient_data->>'identification_no'
        )
        ON CONFLICT (mobile) DO UPDATE 
        SET updated_at = NOW()
        RETURNING id, uhid INTO v_patient_id, v_patient_uhid;
    END IF;

    -- ------------------------------------------------------------------------
    -- 2. SERVER-SIDE FINANCIAL MATH (Integer Paisa - Never Trust Client Math)
    -- ------------------------------------------------------------------------
    v_gross_paisa := 0;
    
    FOREACH v_item IN ARRAY p_items_data LOOP
        SELECT id, code, name, price_paisa, reporting_type, outsource_lab_name, sample_type, container
        INTO v_test
        FROM public.tests
        WHERE id = (v_item->>'test_id')::UUID;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Test item ID % does not exist in master catalogue.', v_item->>'test_id';
        END IF;

        v_gross_paisa := v_gross_paisa + v_test.price_paisa;

        IF v_test.reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN
            v_has_clinical_items := TRUE;
        END IF;
    END LOOP;

    v_discount_paisa := COALESCE((p_bill_data->>'discount_amount_paisa')::BIGINT, 0);
    IF v_discount_paisa < 0 THEN
        RAISE EXCEPTION 'Discount amount cannot be negative.';
    END IF;
    IF v_discount_paisa > v_gross_paisa THEN
        RAISE EXCEPTION 'Discount amount (%) cannot exceed gross bill total (%).', v_discount_paisa, v_gross_paisa;
    END IF;

    v_net_paisa := v_gross_paisa - v_discount_paisa;
    v_paid_paisa := COALESCE((p_bill_data->>'paid_amount_paisa')::BIGINT, 0);
    
    IF v_paid_paisa < 0 THEN
        RAISE EXCEPTION 'Paid amount cannot be negative.';
    END IF;
    IF v_paid_paisa > v_net_paisa THEN
        RAISE EXCEPTION 'Paid amount (%) cannot exceed net payable (%).', v_paid_paisa, v_net_paisa;
    END IF;

    v_due_paisa := v_net_paisa - v_paid_paisa;

    IF v_due_paisa = 0 AND v_net_paisa > 0 THEN
        v_pay_status := 'Paid';
    ELSIF v_paid_paisa > 0 AND v_due_paisa > 0 THEN
        v_pay_status := 'Partial';
    ELSE
        v_pay_status := 'Due';
    END IF;

    v_bill_number := 'INV-' || v_current_year || '-' || LPAD(NEXTVAL('bill_seq')::TEXT, 5, '0');

    -- Insert Bill Header
    INSERT INTO public.bills (
        bill_number,
        patient_id,
        patient_uhid_snapshot,
        patient_name_snapshot,
        patient_mobile_snapshot,
        patient_age_gender_snapshot,
        referring_doctor_id,
        referring_doctor_name_snapshot,
        gross_amount_paisa,
        discount_amount_paisa,
        discount_reason,
        net_amount_paisa,
        paid_amount_paisa,
        due_amount_paisa,
        payment_status,
        remarks,
        created_by
    ) VALUES (
        v_bill_number,
        v_patient_id,
        v_patient_uhid,
        p_patient_data->>'full_name',
        v_clean_mobile,
        COALESCE(p_patient_data->>'age_years', '0') || 'Y / ' || COALESCE(p_patient_data->>'gender', 'Other'),
        (p_bill_data->>'referring_doctor_id')::UUID,
        p_bill_data->>'referring_doctor_name_snapshot',
        v_gross_paisa,
        v_discount_paisa,
        p_bill_data->>'discount_reason',
        v_net_paisa,
        v_paid_paisa,
        v_due_paisa,
        v_pay_status,
        p_bill_data->>'remarks',
        auth.uid()
    ) RETURNING id INTO v_bill_id;

    -- Insert Bill Items
    FOREACH v_item IN ARRAY p_items_data LOOP
        SELECT id, code, name, price_paisa, reporting_type, outsource_lab_name, sample_type, container
        INTO v_test
        FROM public.tests
        WHERE id = (v_item->>'test_id')::UUID;

        INSERT INTO public.bill_items (
            bill_id,
            test_id,
            test_code_snapshot,
            test_name_snapshot,
            reporting_type,
            outsource_lab_name,
            unit_price_paisa,
            discount_paisa,
            net_price_paisa
        ) VALUES (
            v_bill_id,
            v_test.id,
            v_test.code,
            v_test.name,
            v_test.reporting_type,
            v_test.outsource_lab_name,
            v_test.price_paisa,
            COALESCE((v_item->>'discount_paisa')::BIGINT, 0),
            v_test.price_paisa - COALESCE((v_item->>'discount_paisa')::BIGINT, 0)
        );
    END LOOP;

    -- ------------------------------------------------------------------------
    -- 3. PAYMENT TRANSACTION RECORDING
    -- ------------------------------------------------------------------------
    IF v_paid_paisa > 0 AND p_payment_data IS NOT NULL THEN
        v_pay_amount := v_paid_paisa;
        
        INSERT INTO public.payment_transactions (
            bill_id,
            amount_paisa,
            payment_mode,
            transaction_reference,
            received_by,
            received_by_name,
            remarks
        ) VALUES (
            v_bill_id,
            v_pay_amount,
            COALESCE(p_payment_data->>'payment_mode', 'Cash')::payment_mode_enum,
            p_payment_data->>'transaction_reference',
            auth.uid(),
            COALESCE(p_payment_data->>'received_by_name', 'Reception Staff'),
            p_payment_data->>'remarks'
        );
    END IF;

    -- ------------------------------------------------------------------------
    -- 4. CLINICAL ORDER & SAMPLE ACCESSIONING INITIALIZATION
    -- ------------------------------------------------------------------------
    IF v_has_clinical_items THEN
        v_order_number := 'LAB-' || v_current_year || '-' || LPAD(NEXTVAL('clinical_order_seq')::TEXT, 5, '0');

        INSERT INTO public.clinical_orders (
            order_number,
            bill_id,
            patient_id,
            order_date_ad,
            order_date_bs,
            status,
            created_by
        ) VALUES (
            v_order_number,
            v_bill_id,
            v_patient_id,
            CURRENT_DATE,
            COALESCE(p_bill_data->>'order_date_bs', '2083-05-03'),
            'Pending',
            auth.uid()
        ) RETURNING id INTO v_order_id;

        FOREACH v_item IN ARRAY p_items_data LOOP
            SELECT id, code, name, department, reporting_type, outsource_lab_name, sample_type, container
            INTO v_test
            FROM public.tests
            WHERE id = (v_item->>'test_id')::UUID;

            IF v_test.reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN
                v_specimen := COALESCE(v_test.sample_type, 'Whole Blood');
                v_container := COALESCE(v_test.container, 'EDTA / Lavender Top');
                v_sample_key := v_specimen || '::' || v_container;

                IF (v_sample_map ? v_sample_key) THEN
                    v_sample_id := (v_sample_map->>v_sample_key)::UUID;
                ELSE
                    INSERT INTO public.samples (
                        barcode,
                        order_id,
                        specimen_type,
                        container_type,
                        status
                    ) VALUES (
                        'BC-' || v_current_year || '-' || LPAD(NEXTVAL('sample_barcode_seq')::TEXT, 6, '0'),
                        v_order_id,
                        v_specimen,
                        v_container,
                        'Pending'
                    ) RETURNING id INTO v_sample_id;

                    v_sample_map := jsonb_set(v_sample_map, ARRAY[v_sample_key], to_jsonb(v_sample_id::TEXT));
                END IF;

                INSERT INTO public.clinical_order_items (
                    order_id,
                    bill_item_id,
                    test_id,
                    test_name,
                    department,
                    reporting_type,
                    outsource_lab_name,
                    specimen_type,
                    container_type,
                    status,
                    sample_id
                ) VALUES (
                    v_order_id,
                    (SELECT id FROM public.bill_items WHERE bill_id = v_bill_id AND test_id = v_test.id LIMIT 1),
                    v_test.id,
                    v_test.name,
                    v_test.department,
                    v_test.reporting_type,
                    v_test.outsource_lab_name,
                    v_specimen,
                    v_container,
                    'Pending',
                    v_sample_id
                ) RETURNING id INTO v_order_item_id;

                -- Initialize Draft Parameter Result Rows for Worklist
                FOR v_param IN (
                    SELECT id, code, name, unit, value_type
                    FROM public.parameters
                    WHERE test_id = v_test.id AND is_active = TRUE
                    ORDER BY display_order ASC
                ) LOOP
                    INSERT INTO public.test_results (
                        order_item_id,
                        parameter_id,
                        parameter_name,
                        unit,
                        value_type,
                        display_value,
                        flag,
                        status
                    ) VALUES (
                        v_order_item_id,
                        v_param.id,
                        v_param.name,
                        v_param.unit,
                        v_param.value_type,
                        '',
                        'Normal',
                        'Draft'
                    );
                END LOOP;
            END IF;
        END LOOP;
    END IF;

    -- ------------------------------------------------------------------------
    -- 5. AUDIT TRAIL LOGGING
    -- ------------------------------------------------------------------------
    INSERT INTO public.audit_logs (
        user_id,
        user_name,
        action,
        entity_type,
        entity_id,
        new_data
    ) VALUES (
        auth.uid(),
        'Billing Staff',
        'BILL_CREATED',
        'bills',
        v_bill_id::TEXT,
        jsonb_build_object(
            'bill_number', v_bill_number,
            'uhid', v_patient_uhid,
            'net_amount_paisa', v_net_paisa,
            'paid_amount_paisa', v_paid_paisa,
            'payment_status', v_pay_status,
            'order_number', v_order_number
        )
    );

    RETURN jsonb_build_object(
        'bill_id', v_bill_id,
        'bill_number', v_bill_number,
        'patient_id', v_patient_id,
        'uhid', v_patient_uhid,
        'order_id', v_order_id,
        'order_number', v_order_number,
        'net_amount_paisa', v_net_paisa,
        'paid_amount_paisa', v_paid_paisa,
        'payment_status', v_pay_status
    );
END;
$$;

COMMENT ON FUNCTION public.create_patient_bill_and_order IS 'Authoritative billing RPC with 1 Mobile = 1 Patient atomic enforcement, server financial math, sample grouping, and order initialization';
