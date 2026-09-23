-- Migration: 00095_android_patient_auth_reports.sql
-- Description: Server-authoritative Android patient Supabase Auth OTP, patient identity mapping, My Reports access, and short-lived PDF delivery authorization.

-- 1. Mobile Normalizer
CREATE OR REPLACE FUNCTION public.normalize_nepal_mobile(p_mobile TEXT) RETURNS TEXT
LANGUAGE plpgsql IMMUTABLE STRICT AS $$
DECLARE
  clean_digits TEXT;
BEGIN
  IF p_mobile IS NULL THEN
    RETURN NULL;
  END IF;

  clean_digits := regexp_replace(p_mobile, '[^0-9]', '', 'g');

  IF length(clean_digits) = 13 AND clean_digits LIKE '977%' THEN
    clean_digits := substring(clean_digits FROM 4);
  ELSIF length(clean_digits) = 14 AND clean_digits LIKE '0977%' THEN
    clean_digits := substring(clean_digits FROM 5);
  ELSIF length(clean_digits) = 11 AND clean_digits LIKE '0%' THEN
    clean_digits := substring(clean_digits FROM 2);
  END IF;

  IF length(clean_digits) = 10 AND (clean_digits LIKE '98%' OR clean_digits LIKE '97%') THEN
    RETURN clean_digits;
  END IF;

  RETURN NULL;
END;
$$;

-- 2. Patient App Identities Table
CREATE TABLE IF NOT EXISTS public.patient_app_identities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  phone TEXT NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('LINKED', 'NO_MATCH', 'REQUIRES_REVIEW')),
  patient_id UUID REFERENCES public.patients(id) ON DELETE SET NULL,
  match_count INT NOT NULL DEFAULT 0,
  linked_at TIMESTAMPTZ,
  last_synced_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT check_patient_id_linked CHECK (
    (status = 'LINKED' AND patient_id IS NOT NULL) OR
    (status <> 'LINKED' AND patient_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_patient_app_identities_auth ON public.patient_app_identities(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_patient_app_identities_patient ON public.patient_app_identities(patient_id) WHERE patient_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_patient_app_identities_phone ON public.patient_app_identities(phone);

ALTER TABLE public.patient_app_identities ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "patient_app_identities_select_own" ON public.patient_app_identities;
CREATE POLICY "patient_app_identities_select_own" ON public.patient_app_identities
  FOR SELECT TO authenticated
  USING (auth_user_id = auth.uid());

REVOKE ALL ON public.patient_app_identities FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.patient_app_identities TO authenticated;

-- 3. Dedicated Short-Lived Patient App PDF Tokens Table
CREATE TABLE IF NOT EXISTS public.patient_app_pdf_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  patient_id UUID NOT NULL REFERENCES public.patients(id) ON DELETE CASCADE,
  diagnostic_report_id UUID NOT NULL REFERENCES public.diagnostic_reports(id) ON DELETE CASCADE,
  report_version INT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL,
  consumed_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_patient_app_pdf_tokens_lookup ON public.patient_app_pdf_tokens(token_hash) WHERE consumed_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_patient_app_pdf_tokens_expiry ON public.patient_app_pdf_tokens(expires_at);

ALTER TABLE public.patient_app_pdf_tokens ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.patient_app_pdf_tokens FROM PUBLIC, anon, authenticated;

-- 4. Server-Authoritative Patient Identity Sync
CREATE OR REPLACE FUNCTION public.sync_my_patient_identity() RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_raw_phone TEXT;
  v_clean_phone TEXT;
  v_matches UUID[];
  v_match_count INT;
  v_patient_id UUID;
  v_status TEXT;
  v_patient_name TEXT;
  v_identity_id UUID;
  v_linked_at TIMESTAMPTZ;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  -- Derive phone STRICTLY from auth.users verified phone or auth.jwt()
  -- Do NOT trust user_metadata / raw_user_meta_data
  SELECT phone INTO v_raw_phone
  FROM auth.users
  WHERE id = v_uid;

  IF v_raw_phone IS NULL OR v_raw_phone = '' THEN
    v_raw_phone := coalesce(
      auth.jwt() ->> 'phone',
      auth.jwt() -> 'app_metadata' ->> 'phone'
    );
  END IF;

  v_clean_phone := public.normalize_nepal_mobile(v_raw_phone);

  IF v_clean_phone IS NULL THEN
    v_status := 'NO_MATCH';
    v_match_count := 0;
    v_patient_id := NULL;
    v_linked_at := NULL;
  ELSE
    SELECT coalesce(array_agg(p.id), ARRAY[]::UUID[])
    INTO v_matches
    FROM public.patients p
    WHERE public.normalize_nepal_mobile(p.mobile) = v_clean_phone;

    v_match_count := coalesce(array_length(v_matches, 1), 0);

    IF v_match_count = 1 THEN
      v_status := 'LINKED';
      v_patient_id := v_matches[1];
      v_linked_at := now();
      SELECT full_name INTO v_patient_name FROM public.patients WHERE id = v_patient_id;
    ELSIF v_match_count > 1 THEN
      v_status := 'REQUIRES_REVIEW';
      v_patient_id := NULL;
      v_linked_at := NULL;
    ELSE
      v_status := 'NO_MATCH';
      v_patient_id := NULL;
      v_linked_at := NULL;
    END IF;
  END IF;

  INSERT INTO public.patient_app_identities (
    auth_user_id,
    phone,
    status,
    patient_id,
    match_count,
    linked_at,
    last_synced_at
  ) VALUES (
    v_uid,
    coalesce(v_clean_phone, coalesce(v_raw_phone, 'UNKNOWN')),
    v_status,
    v_patient_id,
    v_match_count,
    v_linked_at,
    now()
  )
  ON CONFLICT (auth_user_id) DO UPDATE SET
    phone = EXCLUDED.phone,
    status = EXCLUDED.status,
    patient_id = EXCLUDED.patient_id,
    match_count = EXCLUDED.match_count,
    linked_at = CASE
      WHEN EXCLUDED.status = 'LINKED' THEN coalesce(public.patient_app_identities.linked_at, now())
      ELSE NULL
    END,
    last_synced_at = now()
  RETURNING id INTO v_identity_id;

  RETURN jsonb_build_object(
    'identity_id', v_identity_id,
    'auth_user_id', v_uid,
    'mobile', coalesce(v_clean_phone, v_raw_phone),
    'status', v_status,
    'match_count', v_match_count,
    'patient_id', CASE WHEN v_status = 'LINKED' THEN v_patient_id ELSE NULL END,
    'linked_patient_name', CASE WHEN v_status = 'LINKED' THEN v_patient_name ELSE NULL END,
    'linked_at', v_linked_at
  );
END;
$$;

-- 5. Minimal PHI Patient Profile Getter
CREATE OR REPLACE FUNCTION public.get_my_patient_profile() RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_identity public.patient_app_identities%ROWTYPE;
  v_patient_name TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_identity
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid;

  IF NOT FOUND THEN
    RETURN public.sync_my_patient_identity();
  END IF;

  IF v_identity.status = 'LINKED' AND v_identity.patient_id IS NOT NULL THEN
    SELECT full_name INTO v_patient_name
    FROM public.patients
    WHERE id = v_identity.patient_id;
  END IF;

  RETURN jsonb_build_object(
    'identity_id', v_identity.id,
    'auth_user_id', v_uid,
    'mobile', v_identity.phone,
    'status', v_identity.status,
    'match_count', v_identity.match_count,
    'patient_id', CASE WHEN v_identity.status = 'LINKED' THEN v_identity.patient_id ELSE NULL END,
    'linked_patient_name', v_patient_name,
    'linked_at', v_identity.linked_at,
    'last_synced_at', v_identity.last_synced_at
  );
END;
$$;

-- 6. My Report Orders List (Order Cards)
CREATE OR REPLACE FUNCTION public.list_my_report_orders(p_limit INT DEFAULT 50, p_offset INT DEFAULT 0) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_orders JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  p_limit := least(greatest(coalesce(p_limit, 50), 1), 100);
  p_offset := greatest(coalesce(p_offset, 0), 0);

  SELECT coalesce(jsonb_agg(x.row_data), '[]'::jsonb)
  INTO v_orders
  FROM (
    SELECT
      jsonb_build_object(
        'order_id', o.id,
        'order_number', o.order_number,
        'order_date_ad', o.order_date_ad,
        'order_date_bs', o.order_date_bs,
        'created_at', o.created_at,
        'total_groups', coalesce(grp.total_groups, 0),
        'ready_groups', coalesce(grp.ready_groups, 0),
        'overall_status', CASE
          WHEN coalesce(grp.total_groups, 0) = 0 THEN 'Pending'
          WHEN grp.ready_groups = grp.total_groups THEN 'Ready'
          WHEN grp.ready_groups > 0 THEN 'Partially Ready'
          ELSE 'Pending'
        END
      ) AS row_data
    FROM public.clinical_orders o
    LEFT JOIN LATERAL (
      SELECT
        count(g.id)::int AS total_groups,
        count(g.id) FILTER (
          WHERE EXISTS (
            SELECT 1 FROM public.diagnostic_reports dr
            JOIN public.report_pdf_artifacts a ON a.diagnostic_report_id = dr.id
            WHERE dr.report_group_id = g.id
              AND dr.status IN ('SignedOff', 'Amended')
                            AND a.generation_status = 'Ready'
          )
        )::int AS ready_groups
      FROM public.clinical_report_groups g
      WHERE g.order_id = o.id
    ) grp ON true
    WHERE o.patient_id = v_patient_id
    ORDER BY o.order_date_ad DESC, o.created_at DESC
    LIMIT p_limit OFFSET p_offset
  ) x;

  RETURN v_orders;
END;
$$;

-- 7. My Report Groups List (Ready / Pending Isolation)
CREATE OR REPLACE FUNCTION public.list_my_report_groups(p_order_id UUID) RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_groups JSONB;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RETURN '[]'::jsonb; END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN RETURN '[]'::jsonb; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.clinical_orders WHERE id = p_order_id AND patient_id = v_patient_id
  ) THEN
    RETURN '[]'::jsonb;
  END IF;

  SELECT coalesce(jsonb_agg(
    jsonb_build_object(
      'report_group_id', g.id,
      'group_key', g.group_key,
      'title', g.title,
      'clinical_section', g.clinical_section,
      'status', CASE WHEN art.generation_status = 'Ready' THEN 'Ready' ELSE 'Pending' END,
      'report_id', CASE WHEN art.generation_status = 'Ready' THEN rep.id ELSE NULL END,
      'version', CASE WHEN art.generation_status = 'Ready' THEN rep.version ELSE NULL END,
      'signed_at', CASE WHEN art.generation_status = 'Ready' THEN rep.signed_at ELSE NULL END,
      'is_amendment', CASE WHEN art.generation_status = 'Ready' THEN (rep.status = 'Amended') ELSE false END,
      'pdf_sha256', CASE WHEN art.generation_status = 'Ready' THEN art.pdf_sha256 ELSE NULL END,
      'byte_size', CASE WHEN art.generation_status = 'Ready' THEN art.byte_size ELSE NULL END
    ) ORDER BY g.created_at
  ), '[]'::jsonb)
  INTO v_groups
  FROM public.clinical_report_groups g
  LEFT JOIN LATERAL (
    SELECT dr.id, dr.version, dr.status, dr.signed_at
    FROM public.diagnostic_reports dr
    WHERE dr.report_group_id = g.id
      AND dr.status IN ('SignedOff', 'Amended')
    ORDER BY dr.version DESC
    LIMIT 1
  ) rep ON true
  LEFT JOIN LATERAL (
    SELECT a.generation_status, a.pdf_sha256, a.byte_size
    FROM public.report_pdf_artifacts a
    WHERE a.diagnostic_report_id = rep.id
            AND a.generation_status = 'Ready'
    LIMIT 1
  ) art ON true
  WHERE g.order_id = p_order_id;

  RETURN v_groups;
END;
$$;

-- 8. Authorize Android Patient App PDF Delivery (Short-Lived, Patient/Report/Version/Ready Scoped)
CREATE OR REPLACE FUNCTION public.authorize_my_report_pdf(p_report_id UUID, p_version INT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_uid UUID;
  v_patient_id UUID;
  v_report public.diagnostic_reports%ROWTYPE;
  v_artifact public.report_pdf_artifacts%ROWTYPE;
  v_order public.clinical_orders%ROWTYPE;
  v_group public.clinical_report_groups%ROWTYPE;
  v_raw_token TEXT;
  v_token_hash TEXT;
  v_expires_at TIMESTAMPTZ;
  v_download_url TEXT;
  v_filename TEXT;
  v_clean_title TEXT;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Authentication required.' USING ERRCODE = '42501';
  END IF;

  SELECT patient_id INTO v_patient_id
  FROM public.patient_app_identities
  WHERE auth_user_id = v_uid AND status = 'LINKED';

  IF v_patient_id IS NULL THEN
    RAISE EXCEPTION 'Access denied: patient identity not linked.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_report
  FROM public.diagnostic_reports
  WHERE id = p_report_id
    AND version = p_version
    AND patient_id = v_patient_id
    AND status IN ('SignedOff', 'Amended');

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Access denied or report not found.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_artifact
  FROM public.report_pdf_artifacts
  WHERE diagnostic_report_id = v_report.id
    AND report_version = v_report.version
        AND generation_status = 'Ready';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Report PDF artifact is not ready.' USING ERRCODE = 'P0002';
  END IF;

  SELECT * INTO v_order FROM public.clinical_orders WHERE id = v_report.order_id;
  IF v_report.report_group_id IS NOT NULL THEN
    SELECT * INTO v_group FROM public.clinical_report_groups WHERE id = v_report.report_group_id;
  END IF;

  v_clean_title := regexp_replace(coalesce(v_group.title, 'Report'), '[^a-zA-Z0-9]+', '-', 'g');
  v_filename := 'Bimal-Pathology-' || v_order.order_number || '-' || v_clean_title || '-v' || v_report.version || '.pdf';

  -- Generate Short-Lived Android Delivery Token (15 minute TTL)
  v_raw_token := encode(extensions.gen_random_bytes(32), 'hex');
  v_token_hash := encode(extensions.digest(convert_to(v_raw_token, 'UTF8'), 'sha256'), 'hex');
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO public.patient_app_pdf_tokens (
    auth_user_id,
    patient_id,
    diagnostic_report_id,
    report_version,
    token_hash,
    created_at,
    expires_at
  ) VALUES (
    v_uid,
    v_patient_id,
    v_report.id,
    v_report.version,
    v_token_hash,
    now(),
    v_expires_at
  );

  v_download_url := 'https://dashboard.bimalpathology.com.np/api/patient-app/reports/' || v_raw_token || '/pdf?filename=' || v_filename;

  RETURN jsonb_build_object(
    'authorized', true,
    'report_id', v_report.id,
    'order_id', v_report.order_id,
    'order_number', v_order.order_number,
    'group_title', coalesce(v_group.title, 'Diagnostic Report'),
    'version', v_report.version,
    'sha256', v_artifact.pdf_sha256,
    'byte_size', v_artifact.byte_size,
    'delivery_url', v_download_url,
    'filename', v_filename,
    'expires_at', v_expires_at
  );
END;
$$;

-- 9. Worker Authorization RPC for Patient App PDF Delivery
CREATE OR REPLACE FUNCTION public.authorize_patient_app_pdf_artifact(p_token_hash TEXT) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public, pg_temp AS $$
DECLARE
  v_token public.patient_app_pdf_tokens%ROWTYPE;
  v_artifact public.report_pdf_artifacts%ROWTYPE;
  v_report public.diagnostic_reports%ROWTYPE;
BEGIN
  IF NOT public.is_report_artifact_worker() THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_token
  FROM public.patient_app_pdf_tokens
  WHERE token_hash = p_token_hash
    AND consumed_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_report
  FROM public.diagnostic_reports
  WHERE id = v_token.diagnostic_report_id
    AND version = v_token.report_version
    AND status IN ('SignedOff', 'Amended');

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  SELECT * INTO v_artifact
  FROM public.report_pdf_artifacts
  WHERE diagnostic_report_id = v_token.diagnostic_report_id
    AND report_version = v_token.report_version
        AND generation_status = 'Ready';

  IF NOT FOUND THEN
    RETURN jsonb_build_object('authorized', false);
  END IF;

  -- Mark token consumed
  UPDATE public.patient_app_pdf_tokens
  SET consumed_at = now()
  WHERE id = v_token.id;

  RETURN jsonb_build_object(
    'authorized', true,
    'object_key', v_artifact.object_key,
    'sha256', v_artifact.pdf_sha256,
    'byte_size', v_artifact.byte_size,
    'report_id', v_report.id,
    'version', v_report.version
  );
END;
$$;

-- Permissions & Grants
REVOKE ALL ON FUNCTION public.normalize_nepal_mobile(TEXT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.normalize_nepal_mobile(TEXT) TO authenticated, anon;

REVOKE ALL ON FUNCTION public.sync_my_patient_identity() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.sync_my_patient_identity() TO authenticated;

REVOKE ALL ON FUNCTION public.get_my_patient_profile() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.get_my_patient_profile() TO authenticated;

REVOKE ALL ON FUNCTION public.list_my_report_orders(INT, INT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_report_orders(INT, INT) TO authenticated;

REVOKE ALL ON FUNCTION public.list_my_report_groups(UUID) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.list_my_report_groups(UUID) TO authenticated;

REVOKE ALL ON FUNCTION public.authorize_my_report_pdf(UUID, INT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_my_report_pdf(UUID, INT) TO authenticated;

REVOKE ALL ON FUNCTION public.authorize_patient_app_pdf_artifact(TEXT) FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.authorize_patient_app_pdf_artifact(TEXT) TO authenticated;
