-- Bimal Pathology final runtime closure.
-- Forward-only: production 00000-00050 and staging-applied 00051 remain immutable.

-- Administrator is documented as the complete application-administration role.
-- Outsource tracking was introduced after the original role seed and was the
-- only current permission not assigned to it.
INSERT INTO public.role_permissions(role_id, permission_key)
VALUES (
    '00000000-0000-0000-0000-000000000001',
    'can_manage_outsource_tracking'
)
ON CONFLICT (role_id, permission_key) DO NOTHING;

-- A critical-value acknowledgement describes a particular clinical result.
-- Verification-only updates preserve its original actor/time. A material
-- result or range change must instead be backed by a new same-actor server
-- acknowledgement event written after the previous result revision.
CREATE OR REPLACE FUNCTION public.enforce_critical_acknowledgement_authority()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_was_acknowledged BOOLEAN := FALSE;
    v_material_change BOOLEAN := FALSE;
    v_not_before TIMESTAMPTZ := '-infinity'::TIMESTAMPTZ;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        v_was_acknowledged := COALESCE(OLD.critical_acknowledged, FALSE);
        v_not_before := COALESCE(OLD.updated_at, '-infinity'::TIMESTAMPTZ);
        v_material_change :=
            NEW.numeric_value IS DISTINCT FROM OLD.numeric_value
            OR NEW.text_value IS DISTINCT FROM OLD.text_value
            OR NEW.display_value IS DISTINCT FROM OLD.display_value
            OR NEW.flag IS DISTINCT FROM OLD.flag
            OR NEW.is_critical IS DISTINCT FROM OLD.is_critical
            OR NEW.unit IS DISTINCT FROM OLD.unit
            OR NEW.normal_range_text IS DISTINCT FROM OLD.normal_range_text
            OR NEW.normal_min IS DISTINCT FROM OLD.normal_min
            OR NEW.normal_max IS DISTINCT FROM OLD.normal_max
            OR NEW.critical_low IS DISTINCT FROM OLD.critical_low
            OR NEW.critical_high IS DISTINCT FROM OLD.critical_high;

        IF NOT COALESCE(NEW.is_critical, FALSE)
           AND NEW.flag NOT IN ('CriticalLow', 'CriticalHigh') THEN
            NEW.critical_acknowledged := FALSE;
            NEW.critical_acknowledged_by := NULL;
            NEW.critical_acknowledged_at := NULL;
            RETURN NEW;
        END IF;

        IF v_was_acknowledged
           AND COALESCE(NEW.critical_acknowledged, FALSE)
           AND NOT v_material_change THEN
            NEW.critical_acknowledged_by := OLD.critical_acknowledged_by;
            NEW.critical_acknowledged_at := OLD.critical_acknowledged_at;
            RETURN NEW;
        END IF;
    END IF;

    IF COALESCE(NEW.critical_acknowledged, FALSE)
       AND (COALESCE(NEW.is_critical, FALSE)
            OR NEW.flag IN ('CriticalLow', 'CriticalHigh')) THEN
        IF NOT public.has_permission('can_acknowledge_critical') THEN
            RAISE EXCEPTION 'Critical acknowledgement permission is required.'
                USING ERRCODE = '42501';
        END IF;
        IF NEW.critical_acknowledged_by IS DISTINCT FROM auth.uid()
           OR NEW.critical_acknowledged_at IS NULL THEN
            RAISE EXCEPTION 'Critical acknowledgement actor metadata is invalid.'
                USING ERRCODE = '23514';
        END IF;
        IF NOT EXISTS (
            SELECT 1
            FROM public.audit_logs a
            WHERE a.action = 'CRITICAL_VALUE_ACKNOWLEDGED'
              AND a.entity_type = 'ClinicalOrderItem'
              AND a.entity_id = NEW.order_item_id::TEXT
              AND a.user_id = auth.uid()
              AND a.timestamp >= v_not_before
              AND a.timestamp <= clock_timestamp()
        ) THEN
            RAISE EXCEPTION 'Document the critical notification before saving its acknowledgement.'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.enforce_critical_acknowledgement_authority()
FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public.enforce_critical_acknowledgement_authority() IS
    'Preserves acknowledgement identity for non-clinical updates, clears it when a result is no longer critical, and requires fresh server-audited acknowledgement after any material critical result or range change.';
