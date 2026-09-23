-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Atomic PostgreSQL Functions & Stored Procedures (Phase 2 - Production Hardened)
-- Enforces Patient Rule, Integer Paisa Math, Sample Grouping & 3-Tier Dispatch
-- ============================================================================

-- Sequence generators for human-readable IDs
CREATE SEQUENCE IF NOT EXISTS uhid_seq START 1;
CREATE SEQUENCE IF NOT EXISTS bill_seq START 1;
CREATE SEQUENCE IF NOT EXISTS lab_order_seq START 1;
CREATE SEQUENCE IF NOT EXISTS sample_seq START 1;
CREATE SEQUENCE IF NOT EXISTS receipt_seq START 1;

-- ============================================================================
-- 1. ATOMIC BILLING & CLINICAL ORDER CREATION RPC
-- ============================================================================
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
    v_order_id UUID := NULL;
    v_order_number VARCHAR(50) := NULL;
    v_receipt_number VARCHAR(50) := NULL;
    v_item JSONB;
    v_test RECORD;
    v_reporting_type reporting_type_enum;
    v_has_clinical_items BOOLEAN := FALSE;
    v_current_year VARCHAR(4);
    v_sample_id UUID;
    v_sample_barcode VARCHAR(50);
    v_bill_item_id UUID;
    v_order_item_id UUID;
    v_param RECORD;
    v_gross_paisa BIGINT := 0;
    v_discount_paisa BIGINT := 0;
    v_net_paisa BIGINT := 0;
    v_paid_paisa BIGINT := 0;
    v_due_paisa BIGINT := 0;
    v_pay_status payment_status_enum;
    v_clean_mobile VARCHAR(20);
    v_pay_item JSONB;
    v_pay_amount BIGINT;
    v_pay_mode payment_mode_enum;
    v_sample_key TEXT;
    v_specimen TEXT;
    v_container TEXT;
    
    -- In-memory map of (specimen||container -> sample_id) for tube grouping
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
    -- 1. PATIENT RULE ENFORCEMENT (Normalize mobile & Lookup)
    -- ------------------------------------------------------------------------
    v_clean_mobile := REGEXP_REPLACE(TRIM(COALESCE(p_patient_data->>'mobile', '')), '[^0-9]', '', 'g');
    IF LENGTH(v_clean_mobile) < 7 THEN
        RAISE EXCEPTION 'Patient mobile number is mandatory and must contain at least 7 digits.';
    END IF;

    SELECT id, uhid INTO v_patient_id, v_patient_uhid
    FROM public.patients
    WHERE mobile = v_clean_mobile
    LIMIT 1;

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
        ) RETURNING id INTO v_patient_id;
    END IF;

    -- ------------------------------------------------------------------------
    -- 2. SERVER-SIDE FINANCIAL MATH (Integer Paisa - Never Trust Client Math)
    -- ------------------------------------------------------------------------
    v_gross_paisa := 0;
    
    -- Verify every item against server test catalogue
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
            0,
            v_test.price_paisa
        );
    END LOOP;

    -- ------------------------------------------------------------------------
    -- 3. PAYMENT RECEIPT TRANSACTIONS (Multi-allocation support)
    -- ------------------------------------------------------------------------
    IF v_paid_paisa > 0 AND p_payment_data IS NOT NULL THEN
        IF jsonb_typeof(p_payment_data) = 'array' THEN
            -- Array of payments
            FOR v_pay_item IN SELECT * FROM jsonb_array_elements(p_payment_data) LOOP
                v_pay_amount := (v_pay_item->>'amount_paisa')::BIGINT;
                IF v_pay_amount > 0 THEN
                    v_receipt_number := 'RCP-' || v_current_year || '-' || LPAD(NEXTVAL('receipt_seq')::TEXT, 5, '0');
                    INSERT INTO public.payment_transactions (
                        bill_id,
                        receipt_number,
                        amount_paisa,
                        payment_mode,
                        transaction_reference,
                        remarks,
                        received_by,
                        received_by_name
                    ) VALUES (
                        v_bill_id,
                        v_receipt_number,
                        v_pay_amount,
                        (v_pay_item->>'payment_mode')::payment_mode_enum,
                        v_pay_item->>'transaction_reference',
                        v_pay_item->>'remarks',
                        auth.uid(),
                        COALESCE(v_pay_item->>'received_by_name', 'Front Desk Staff')
                    );
                END IF;
            END LOOP;
        ELSE
            -- Single payment object
            v_receipt_number := 'RCP-' || v_current_year || '-' || LPAD(NEXTVAL('receipt_seq')::TEXT, 5, '0');
            INSERT INTO public.payment_transactions (
                bill_id,
                receipt_number,
                amount_paisa,
                payment_mode,
                transaction_reference,
                remarks,
                received_by,
                received_by_name
            ) VALUES (
                v_bill_id,
                v_receipt_number,
                v_paid_paisa,
                (p_payment_data->>'payment_mode')::payment_mode_enum,
                p_payment_data->>'transaction_reference',
                p_payment_data->>'remarks',
                auth.uid(),
                COALESCE(p_payment_data->>'received_by_name', 'Front Desk Staff')
            );
        END IF;
    END IF;

    -- ------------------------------------------------------------------------
    -- 4. 3-TIER REPORTING TYPE DISPATCH & SAMPLE TUBE GROUPING
    -- NoReporting items generate ZERO order items, ZERO samples, ZERO worklist.
    -- ------------------------------------------------------------------------
    IF v_has_clinical_items THEN
        v_order_number := 'LAB-' || v_current_year || '-' || LPAD(NEXTVAL('lab_order_seq')::TEXT, 5, '0');
        
        INSERT INTO public.clinical_orders (
            bill_id,
            patient_id,
            order_number,
            order_date_ad,
            order_date_bs,
            status
        ) VALUES (
            v_bill_id,
            v_patient_id,
            v_order_number,
            CURRENT_DATE,
            COALESCE(p_bill_data->>'order_date_bs', '2083-05-03 BS'),
            'Registered'
        ) RETURNING id INTO v_order_id;

        -- Iterate over reportable tests and group samples by (specimen_type, container_type)
        FOREACH v_item IN ARRAY p_items_data LOOP
            SELECT id, code, name, department, reporting_type, outsource_lab_name, sample_type, container
            INTO v_test
            FROM public.tests
            WHERE id = (v_item->>'test_id')::UUID;

            IF v_test.reporting_type IN ('InHouse', 'OutsourceWithBimalReport') THEN
                v_specimen := COALESCE(v_test.sample_type, 'Blood / Serum');
                v_container := COALESCE(v_test.container, 'Standard Vacutainer');
                v_sample_key := v_specimen || '||' || v_container;

                -- Check if a sample for this tube type was already created in this order
                IF v_sample_map ? v_sample_key THEN
                    v_sample_id := (v_sample_map->>v_sample_key)::UUID;
                ELSE
                    -- Generate new Sample Barcode
                    v_sample_barcode := 'SMP-' || v_current_year || '-' || LPAD(NEXTVAL('sample_seq')::TEXT, 5, '0');
                    
                    INSERT INTO public.samples (
                        barcode,
                        order_id,
                        patient_id,
                        specimen_type,
                        container_type,
                        status
                    ) VALUES (
                        v_sample_barcode,
                        v_order_id,
                        v_patient_id,
                        v_specimen,
                        v_container,
                        'Pending'
                    ) RETURNING id INTO v_sample_id;

                    -- Record initial lifecycle event
                    INSERT INTO public.sample_lifecycle_events (
                        sample_id,
                        from_status,
                        to_status,
                        reason,
                        performed_by,
                        performed_by_name
                    ) VALUES (
                        v_sample_id,
                        'Pending',
                        'Pending',
                        'Sample order registered',
                        auth.uid(),
                        'Front Desk Billing'
                    );

                    -- Store in map
                    v_sample_map := jsonb_set(v_sample_map, ARRAY[v_sample_key], to_jsonb(v_sample_id::TEXT));
                END IF;

                -- Find matching bill_item_id
                SELECT id INTO v_bill_item_id
                FROM public.bill_items
                WHERE bill_id = v_bill_id AND test_id = v_test.id
                LIMIT 1;

                -- Insert Clinical Order Item
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
                    v_bill_item_id,
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
        COALESCE(p_payment_data->>'received_by_name', 'Front Desk Staff'),
        'BILL_COMMITTED',
        'Bill',
        v_bill_number,
        jsonb_build_object(
            'bill_id', v_bill_id,
            'uhid', v_patient_uhid,
            'gross_amount_paisa', v_gross_paisa,
            'net_amount_paisa', v_net_paisa,
            'paid_amount_paisa', v_paid_paisa,
            'due_amount_paisa', v_due_paisa,
            'lab_order_number', v_order_number
        )
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'patient_id', v_patient_id,
        'uhid', v_patient_uhid,
        'bill_id', v_bill_id,
        'bill_number', v_bill_number,
        'order_id', v_order_id,
        'order_number', v_order_number,
        'receipt_number', v_receipt_number,
        'gross_amount_paisa', v_gross_paisa,
        'discount_amount_paisa', v_discount_paisa,
        'net_amount_paisa', v_net_paisa,
        'paid_amount_paisa', v_paid_paisa,
        'due_amount_paisa', v_due_paisa
    );
END;
$$;

-- Explicitly revoke from public and anon, grant only to authenticated
REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB) TO authenticated;
