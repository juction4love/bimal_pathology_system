-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00018: Outsourced Sample Tracking Engine (IHC & Referral Pathology)
-- Supports end-to-end chain-of-custody tracking for physical specimens:
-- Reception -> Dispatch -> External Reference Lab -> Result Receipt -> Material Return -> Completion.
-- ============================================================================

-- 1. Extend Master Test Catalogue
ALTER TABLE public.tests
ADD COLUMN IF NOT EXISTS requires_sample_tracking BOOLEAN NOT NULL DEFAULT FALSE;

-- Update IHC to enable sample tracking with manual pricing and NoReporting
UPDATE public.tests
SET requires_sample_tracking = TRUE,
    allow_manual_price = TRUE,
    reporting_type = 'NoReporting',
    sample_type = 'Paraffin Block / Biopsy',
    container = 'Slide / Block',
    updated_at = NOW()
WHERE code = 'IHC';

-- 2. Status Enum for Outsource Samples
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'outsource_sample_status_enum') THEN
        CREATE TYPE outsource_sample_status_enum AS ENUM (
            'ReceivedAtBimal',
            'PreparedForDispatch',
            'DispatchedToReferenceLab',
            'ReceivedByReferenceLab',
            'ProcessingAtReferenceLab',
            'ResultReceived',
            'MaterialReturned',
            'Completed',
            'Rejected',
            'Cancelled',
            'LostInTransit'
        );
    END IF;
END $$;

-- 3. Sequential Tracking Number Generator
CREATE SEQUENCE IF NOT EXISTS outsource_tracking_seq START 1;

-- 4. Outsource Samples Table
CREATE TABLE IF NOT EXISTS public.outsource_samples (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    tracking_number VARCHAR(50) NOT NULL UNIQUE,
    bill_id UUID NOT NULL REFERENCES public.bills(id) ON DELETE CASCADE,
    bill_item_id UUID NOT NULL REFERENCES public.bill_items(id) ON DELETE CASCADE,
    patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
    test_id UUID NOT NULL REFERENCES public.tests(id),
    service_description TEXT NOT NULL,
    specimen_type VARCHAR(100) NOT NULL DEFAULT 'Paraffin Block',
    specimen_description TEXT,
    quantity_received VARCHAR(100) NOT NULL DEFAULT '1 Block',
    reference_lab_name VARCHAR(255) DEFAULT 'External Reference Lab',
    status outsource_sample_status_enum NOT NULL DEFAULT 'ReceivedAtBimal',
    
    -- Reception Details
    received_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    received_by UUID REFERENCES auth.users(id),
    received_by_name VARCHAR(255) DEFAULT 'Reception Staff',
    
    -- Dispatch Tracking
    dispatched_at TIMESTAMPTZ,
    dispatched_by UUID REFERENCES auth.users(id),
    dispatched_by_name VARCHAR(255),
    courier_name VARCHAR(255),
    courier_tracking_no VARCHAR(100),
    items_sent_count VARCHAR(100),
    dispatch_notes TEXT,
    
    -- Result Receipt Tracking
    external_report_received BOOLEAN NOT NULL DEFAULT FALSE,
    external_report_date DATE,
    reference_lab_report_no VARCHAR(100),
    result_received_at TIMESTAMPTZ,
    result_received_by UUID REFERENCES auth.users(id),
    result_received_by_name VARCHAR(255),
    result_notes TEXT,
    
    -- Histopathology Material Return Tracking
    material_returned BOOLEAN NOT NULL DEFAULT FALSE,
    material_returned_at TIMESTAMPTZ,
    blocks_returned_count INT DEFAULT 0,
    slides_returned_count INT DEFAULT 0,
    material_received_by UUID REFERENCES auth.users(id),
    material_received_by_name VARCHAR(255),
    return_notes TEXT,
    
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Immutable Event & Audit Log
CREATE TABLE IF NOT EXISTS public.outsource_sample_events (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    outsource_sample_id UUID NOT NULL REFERENCES public.outsource_samples(id) ON DELETE CASCADE,
    event_type VARCHAR(100) NOT NULL,
    from_status outsource_sample_status_enum,
    to_status outsource_sample_status_enum NOT NULL,
    notes TEXT,
    meta JSONB DEFAULT '{}'::JSONB,
    performed_by UUID REFERENCES auth.users(id),
    performed_by_name VARCHAR(255) DEFAULT 'Staff',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Indexes for Performance
CREATE INDEX IF NOT EXISTS idx_outsource_samples_bill_id ON public.outsource_samples(bill_id);
CREATE INDEX IF NOT EXISTS idx_outsource_samples_patient_id ON public.outsource_samples(patient_id);
CREATE INDEX IF NOT EXISTS idx_outsource_samples_status ON public.outsource_samples(status);
CREATE INDEX IF NOT EXISTS idx_outsource_samples_tracking_no ON public.outsource_samples(tracking_number);
CREATE INDEX IF NOT EXISTS idx_outsource_events_sample_id ON public.outsource_sample_events(outsource_sample_id);

-- 7. Enable RLS & Security Policies
ALTER TABLE public.outsource_samples ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.outsource_sample_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow authenticated read outsource samples" ON public.outsource_samples;
CREATE POLICY "Allow authenticated read outsource samples"
ON public.outsource_samples
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Allow authenticated insert outsource samples" ON public.outsource_samples;
CREATE POLICY "Allow authenticated insert outsource samples"
ON public.outsource_samples
FOR INSERT
TO authenticated
WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated update outsource samples" ON public.outsource_samples;
CREATE POLICY "Allow authenticated update outsource samples"
ON public.outsource_samples
FOR UPDATE
TO authenticated
USING (true)
WITH CHECK (true);

DROP POLICY IF EXISTS "Allow authenticated read outsource events" ON public.outsource_sample_events;
CREATE POLICY "Allow authenticated read outsource events"
ON public.outsource_sample_events
FOR SELECT
TO authenticated
USING (true);

DROP POLICY IF EXISTS "Allow authenticated insert outsource events" ON public.outsource_sample_events;
CREATE POLICY "Allow authenticated insert outsource events"
ON public.outsource_sample_events
FOR INSERT
TO authenticated
WITH CHECK (true);

-- 8. Atomic Status Transition RPC Function
CREATE OR REPLACE FUNCTION public.update_outsource_sample_status(
    p_sample_id UUID,
    p_to_status outsource_sample_status_enum,
    p_notes TEXT DEFAULT NULL,
    p_meta JSONB DEFAULT '{}'::JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_sample RECORD;
    v_user_name VARCHAR(255);
    v_now TIMESTAMPTZ := NOW();
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required.';
    END IF;

    SELECT full_name INTO v_user_name FROM public.user_profiles WHERE user_id = auth.uid();
    v_user_name := COALESCE(v_user_name, 'Staff');

    SELECT * INTO v_sample FROM public.outsource_samples WHERE id = p_sample_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Outsource sample with ID % not found.', p_sample_id;
    END IF;

    -- Update main record based on transition state
    UPDATE public.outsource_samples
    SET status = p_to_status,
        updated_at = v_now,
        -- Dispatch payload mapping
        dispatched_at = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN v_now ELSE dispatched_at END,
        dispatched_by = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN auth.uid() ELSE dispatched_by END,
        dispatched_by_name = CASE WHEN p_to_status = 'DispatchedToReferenceLab' THEN v_user_name ELSE dispatched_by_name END,
        reference_lab_name = COALESCE(p_meta->>'reference_lab_name', reference_lab_name),
        courier_name = COALESCE(p_meta->>'courier_name', courier_name),
        courier_tracking_no = COALESCE(p_meta->>'courier_tracking_no', courier_tracking_no),
        items_sent_count = COALESCE(p_meta->>'items_sent_count', items_sent_count),
        dispatch_notes = COALESCE(p_meta->>'dispatch_notes', dispatch_notes),
        
        -- Result Receipt payload mapping
        external_report_received = CASE WHEN p_to_status IN ('ResultReceived', 'MaterialReturned', 'Completed') THEN TRUE ELSE external_report_received END,
        external_report_date = COALESCE((p_meta->>'external_report_date')::DATE, external_report_date),
        reference_lab_report_no = COALESCE(p_meta->>'reference_lab_report_no', reference_lab_report_no),
        result_received_at = CASE WHEN p_to_status = 'ResultReceived' THEN v_now ELSE result_received_at END,
        result_received_by = CASE WHEN p_to_status = 'ResultReceived' THEN auth.uid() ELSE result_received_by END,
        result_received_by_name = CASE WHEN p_to_status = 'ResultReceived' THEN v_user_name ELSE result_received_by_name END,
        result_notes = COALESCE(p_meta->>'result_notes', result_notes),
        
        -- Material Return payload mapping
        material_returned = CASE WHEN p_to_status IN ('MaterialReturned', 'Completed') THEN TRUE ELSE material_returned END,
        material_returned_at = CASE WHEN p_to_status = 'MaterialReturned' THEN v_now ELSE material_returned_at END,
        blocks_returned_count = COALESCE((p_meta->>'blocks_returned_count')::INT, blocks_returned_count),
        slides_returned_count = COALESCE((p_meta->>'slides_returned_count')::INT, slides_returned_count),
        material_received_by = CASE WHEN p_to_status = 'MaterialReturned' THEN auth.uid() ELSE material_received_by END,
        material_received_by_name = CASE WHEN p_to_status = 'MaterialReturned' THEN v_user_name ELSE material_received_by_name END,
        return_notes = COALESCE(p_meta->>'return_notes', return_notes),
        
        completed_at = CASE WHEN p_to_status = 'Completed' THEN v_now ELSE completed_at END
    WHERE id = p_sample_id;

    -- Append Immutable Audit Event
    INSERT INTO public.outsource_sample_events (
        outsource_sample_id,
        event_type,
        from_status,
        to_status,
        notes,
        meta,
        performed_by,
        performed_by_name
    ) VALUES (
        p_sample_id,
        'STATUS_TRANSITION_' || p_to_status::TEXT,
        v_sample.status,
        p_to_status,
        p_notes,
        p_meta,
        auth.uid(),
        v_user_name
    );

    RETURN jsonb_build_object(
        'success', TRUE,
        'sample_id', p_sample_id,
        'from_status', v_sample.status,
        'to_status', p_to_status,
        'updated_at', v_now
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.update_outsource_sample_status(UUID, outsource_sample_status_enum, TEXT, JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_outsource_sample_status(UUID, outsource_sample_status_enum, TEXT, JSONB) TO authenticated;

-- 9. Update Billing RPC with Automatic Outsource Sample Tracking Creation
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
    v_bill_item_id UUID;
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
    v_item_unit_price BIGINT;
    v_item_discount BIGINT;
    v_item_desc TEXT;
    v_outsource_tracking_no VARCHAR(50);
    v_outsource_sample_id UUID;
    v_user_name VARCHAR(255);
    v_outsource_tracking_list JSONB := '[]'::JSONB;
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

    SELECT full_name INTO v_user_name FROM public.user_profiles WHERE user_id = auth.uid();
    v_user_name := COALESCE(v_user_name, 'Reception Staff');

    v_current_year := TO_CHAR(CURRENT_DATE, 'YYYY');

    -- ------------------------------------------------------------------------
    -- 1. PATIENT RULE ENFORCEMENT: 1 Mobile = 1 Patient
    -- ------------------------------------------------------------------------
    v_clean_mobile := REGEXP_REPLACE(TRIM(COALESCE(p_patient_data->>'mobile', '')), '[^0-9]', '', 'g');
    
    IF v_clean_mobile LIKE '977%' AND LENGTH(v_clean_mobile) > 10 THEN
        v_clean_mobile := SUBSTRING(v_clean_mobile FROM 4);
    END IF;
    
    IF v_clean_mobile LIKE '0%' AND LENGTH(v_clean_mobile) = 11 THEN
        v_clean_mobile := SUBSTRING(v_clean_mobile FROM 2);
    END IF;

    IF LENGTH(v_clean_mobile) != 10 OR (v_clean_mobile NOT LIKE '98%' AND v_clean_mobile NOT LIKE '97%') THEN
        RAISE EXCEPTION 'Invalid Nepal mobile number (%). Must be a valid 10-digit number starting with 98 or 97.', v_clean_mobile;
    END IF;

    SELECT id, uhid INTO v_patient_id, v_patient_uhid
    FROM public.patients
    WHERE mobile = v_clean_mobile
    FOR UPDATE;

    IF v_patient_id IS NULL THEN
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
    -- 2. SERVER-SIDE FINANCIAL MATH
    -- ------------------------------------------------------------------------
    v_gross_paisa := 0;
    
    FOREACH v_item IN ARRAY p_items_data LOOP
        SELECT id, code, name, price_paisa, reporting_type, outsource_lab_name, sample_type, container, allow_manual_price, requires_sample_tracking
        INTO v_test
        FROM public.tests
        WHERE id = (v_item->>'test_id')::UUID;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Test item ID % does not exist in master catalogue.', v_item->>'test_id';
        END IF;

        IF v_test.allow_manual_price = TRUE THEN
            v_item_unit_price := COALESCE((v_item->>'unit_price_paisa')::BIGINT, (v_item->>'manual_price_paisa')::BIGINT, v_test.price_paisa);
            IF v_item_unit_price < 0 THEN
                RAISE EXCEPTION 'Manual price for % cannot be negative.', v_test.name;
            END IF;
        ELSE
            v_item_unit_price := v_test.price_paisa;
        END IF;

        v_gross_paisa := v_gross_paisa + v_item_unit_price;

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

    -- Insert Bill Items & Auto-Create Outsource Tracking Records
    FOREACH v_item IN ARRAY p_items_data LOOP
        SELECT id, code, name, price_paisa, reporting_type, outsource_lab_name, sample_type, container, allow_manual_price, requires_sample_tracking
        INTO v_test
        FROM public.tests
        WHERE id = (v_item->>'test_id')::UUID;

        IF v_test.allow_manual_price = TRUE THEN
            v_item_unit_price := COALESCE((v_item->>'unit_price_paisa')::BIGINT, (v_item->>'manual_price_paisa')::BIGINT, v_test.price_paisa);
        ELSE
            v_item_unit_price := v_test.price_paisa;
        END IF;

        v_item_discount := COALESCE((v_item->>'discount_paisa')::BIGINT, 0);
        v_item_desc := NULLIF(TRIM(COALESCE(v_item->>'item_description', v_item->>'description', '')), '');

        INSERT INTO public.bill_items (
            bill_id,
            test_id,
            test_code_snapshot,
            test_name_snapshot,
            reporting_type,
            outsource_lab_name,
            unit_price_paisa,
            discount_paisa,
            net_price_paisa,
            item_description
        ) VALUES (
            v_bill_id,
            v_test.id,
            v_test.code,
            v_test.name,
            v_test.reporting_type,
            v_test.outsource_lab_name,
            v_item_unit_price,
            v_item_discount,
            v_item_unit_price - v_item_discount,
            v_item_desc
        ) RETURNING id INTO v_bill_item_id;

        -- Create Outsource Sample Tracking Record for physical samples sent out
        IF v_test.requires_sample_tracking = TRUE OR v_test.code = 'IHC' THEN
            v_outsource_tracking_no := 'OUT-' || v_current_year || '-' || LPAD(NEXTVAL('outsource_tracking_seq')::TEXT, 5, '0');

            INSERT INTO public.outsource_samples (
                tracking_number,
                bill_id,
                bill_item_id,
                patient_id,
                test_id,
                service_description,
                specimen_type,
                specimen_description,
                quantity_received,
                reference_lab_name,
                status,
                received_by,
                received_by_name
            ) VALUES (
                v_outsource_tracking_no,
                v_bill_id,
                v_bill_item_id,
                v_patient_id,
                v_test.id,
                COALESCE(v_item_desc, v_test.name),
                COALESCE(v_item->>'specimen_type', v_test.sample_type, 'Paraffin Block'),
                COALESCE(v_item->>'specimen_description', 'Histopathology Specimen'),
                COALESCE(v_item->>'quantity_received', '1 Block'),
                COALESCE(v_test.outsource_lab_name, 'External Reference Lab'),
                'ReceivedAtBimal',
                auth.uid(),
                v_user_name
            ) RETURNING id INTO v_outsource_sample_id;

            -- Initial Event Log
            INSERT INTO public.outsource_sample_events (
                outsource_sample_id,
                event_type,
                from_status,
                to_status,
                notes,
                performed_by,
                performed_by_name
            ) VALUES (
                v_outsource_sample_id,
                'SAMPLE_RECEIVED_AT_BIMAL',
                NULL,
                'ReceivedAtBimal',
                'Physical specimen received at Bimal Pathology reception & registered for outsourced testing.',
                auth.uid(),
                v_user_name
            );

            v_outsource_tracking_list := v_outsource_tracking_list || to_jsonb(v_outsource_tracking_no);
        END IF;
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
    -- 4. CLINICAL ORDER & SAMPLE ACCESSIONING (SKIPPED FOR NoReporting ITEMS)
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
        v_user_name,
        'BILL_CREATED',
        'bills',
        v_bill_id::TEXT,
        jsonb_build_object(
            'bill_number', v_bill_number,
            'uhid', v_patient_uhid,
            'gross_amount_paisa', v_gross_paisa,
            'net_amount_paisa', v_net_paisa,
            'paid_amount_paisa', v_paid_paisa,
            'payment_status', v_pay_status,
            'order_number', v_order_number,
            'outsource_tracking', v_outsource_tracking_list
        )
    );

    RETURN jsonb_build_object(
        'bill_id', v_bill_id,
        'bill_number', v_bill_number,
        'patient_id', v_patient_id,
        'uhid', v_patient_uhid,
        'order_id', v_order_id,
        'order_number', v_order_number,
        'gross_amount_paisa', v_gross_paisa,
        'net_amount_paisa', v_net_paisa,
        'paid_amount_paisa', v_paid_paisa,
        'payment_status', v_pay_status,
        'outsource_tracking_numbers', v_outsource_tracking_list
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient_bill_and_order(JSONB, JSONB, JSONB[], JSONB) TO authenticated;

COMMENT ON FUNCTION public.create_patient_bill_and_order IS 'Authoritative billing RPC with 1 Mobile = 1 Patient, automatic Outsource Sample tracking creation for IHC/referrals, and financial integrity';
