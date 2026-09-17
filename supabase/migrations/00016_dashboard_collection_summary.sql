-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00016: Admin Dashboard Real-Time Collection Summary
-- Computes Today's Collection, This Month's Collection, and Lifetime Total Collection
-- from authoritative payment_transactions in Asia/Kathmandu timezone.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_dashboard_collection_summary()
RETURNS TABLE (
    today_collection_paisa BIGINT,
    month_collection_paisa BIGINT,
    total_collection_paisa BIGINT,
    today_count INT,
    month_count INT,
    total_count INT,
    month_label TEXT
) AS $$
DECLARE
    v_auth_user_id UUID;
    v_today_start TIMESTAMPTZ;
    v_month_start TIMESTAMPTZ;
    v_month_name TEXT;
BEGIN
    -- 1. Authentication & Permission Check
    v_auth_user_id := auth.uid();
    IF v_auth_user_id IS NULL THEN
        RAISE EXCEPTION 'Authentication required to view collection summary';
    END IF;

    IF NOT (
        public.has_permission('can_view_financials')
        OR EXISTS (
            SELECT 1 
            FROM public.user_profiles 
            WHERE id = v_auth_user_id 
              AND (is_super_admin = TRUE OR email = 'admin@bimalpathology.com.np')
        )
    ) THEN
        RAISE EXCEPTION 'Access Denied: User lacks can_view_financials permission';
    END IF;

    -- 2. Timezone Boundary Calculation (Asia/Kathmandu: UTC+05:45)
    -- Today starts at 00:00:00 Nepal local time
    v_today_start := (DATE_TRUNC('day', NOW() AT TIME ZONE 'Asia/Kathmandu')) AT TIME ZONE 'Asia/Kathmandu';
    -- Month starts at 1st day 00:00:00 Nepal local time
    v_month_start := (DATE_TRUNC('month', NOW() AT TIME ZONE 'Asia/Kathmandu')) AT TIME ZONE 'Asia/Kathmandu';
    -- Month label in Nepal time e.g. "August 2026"
    v_month_name := TO_CHAR(NOW() AT TIME ZONE 'Asia/Kathmandu', 'FMMonth YYYY');

    -- 3. Return aggregated collections from authoritative payment_transactions table
    RETURN QUERY
    SELECT
        COALESCE(SUM(CASE WHEN pt.created_at >= v_today_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT AS today_collection_paisa,
        COALESCE(SUM(CASE WHEN pt.created_at >= v_month_start THEN pt.amount_paisa ELSE 0 END), 0)::BIGINT AS month_collection_paisa,
        COALESCE(SUM(pt.amount_paisa), 0)::BIGINT AS total_collection_paisa,
        COALESCE(COUNT(CASE WHEN pt.created_at >= v_today_start THEN 1 END), 0)::INT AS today_count,
        COALESCE(COUNT(CASE WHEN pt.created_at >= v_month_start THEN 1 END), 0)::INT AS month_count,
        COALESCE(COUNT(*), 0)::INT AS total_count,
        v_month_name AS month_label
    FROM public.payment_transactions pt;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;

-- Grant execution permissions
GRANT EXECUTE ON FUNCTION public.get_dashboard_collection_summary() TO authenticated, anon;
