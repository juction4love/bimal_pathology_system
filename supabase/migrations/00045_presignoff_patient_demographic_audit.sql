-- Preserve the existing patient correction boundary while adding the stable UHID
-- to its privacy-minimized audit event. Signed report snapshots are untouched.

CREATE OR REPLACE FUNCTION public.update_patient_demographics(p_patient_id UUID, p_patient_data JSONB)
RETURNS public.patients
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old public.patients%ROWTYPE;
  v_new public.patients%ROWTYPE;
  v_mobile TEXT := public.patient_normalize_mobile(p_patient_data->>'mobile');
  v_name TEXT := public.patient_clean_text(p_patient_data->>'full_name');
  v_address TEXT := public.patient_clean_text(p_patient_data->>'address');
  v_changed TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN
    RAISE EXCEPTION 'Not authorized to edit patients.' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_old FROM public.patients WHERE id = p_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE = 'P0002'; END IF;
  IF NOT v_old.is_active THEN RAISE EXCEPTION 'Archived patients must be restored before editing.' USING ERRCODE = '55000'; END IF;
  IF v_name = '' OR v_address = '' THEN RAISE EXCEPTION 'Patient name and address are required.' USING ERRCODE = '22023'; END IF;
  IF COALESCE(p_patient_data->>'gender','') NOT IN ('Male','Female','Other') THEN RAISE EXCEPTION 'Invalid patient gender.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_years','')::INT NOT BETWEEN 0 AND 120 AND NULLIF(p_patient_data->>'age_years','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age years must be from 0 to 120.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('patient-mobile:' || v_mobile, 0));
  IF EXISTS (SELECT 1 FROM public.patients WHERE mobile = v_mobile AND id <> p_patient_id) THEN
    RAISE EXCEPTION 'A different patient with this mobile number already exists. Patients are never auto-merged.' USING ERRCODE = '23505';
  END IF;

  IF v_old.full_name IS DISTINCT FROM v_name THEN v_changed := array_append(v_changed,'full_name'); END IF;
  IF v_old.mobile IS DISTINCT FROM v_mobile THEN v_changed := array_append(v_changed,'mobile'); END IF;
  IF v_old.address IS DISTINCT FROM v_address THEN v_changed := array_append(v_changed,'address'); END IF;
  IF v_old.dob IS DISTINCT FROM NULLIF(p_patient_data->>'dob','')::DATE THEN v_changed := array_append(v_changed,'dob'); END IF;
  IF v_old.gender IS DISTINCT FROM p_patient_data->>'gender' THEN v_changed := array_append(v_changed,'gender'); END IF;
  IF v_old.age_years IS DISTINCT FROM NULLIF(p_patient_data->>'age_years','')::INT
     OR v_old.age_months IS DISTINCT FROM NULLIF(p_patient_data->>'age_months','')::INT
     OR v_old.age_days IS DISTINCT FROM NULLIF(p_patient_data->>'age_days','')::INT THEN
    v_changed := array_append(v_changed,'age');
  END IF;

  UPDATE public.patients
  SET mobile = v_mobile,
      title = NULLIF(public.patient_clean_text(p_patient_data->>'title'),''),
      full_name = v_name,
      gender = p_patient_data->>'gender',
      dob = NULLIF(p_patient_data->>'dob','')::DATE,
      age_years = NULLIF(p_patient_data->>'age_years','')::INT,
      age_months = NULLIF(p_patient_data->>'age_months','')::INT,
      age_days = NULLIF(p_patient_data->>'age_days','')::INT,
      address = v_address,
      email = NULLIF(public.patient_clean_text(p_patient_data->>'email'),''),
      identification_no = NULLIF(public.patient_clean_text(p_patient_data->>'identification_no'),''),
      updated_at = NOW()
  WHERE id = p_patient_id
  RETURNING * INTO v_new;

  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES (
    auth.uid(), public.patient_actor_name(), 'PATIENT_DEMOGRAPHICS_UPDATED', 'Patient', p_patient_id::TEXT,
    jsonb_build_object('uhid',v_old.uhid,'changed_fields',v_changed),
    jsonb_build_object('uhid',v_old.uhid,'changed_fields',v_changed)
  );
  RETURN v_new;
END;
$$;

REVOKE ALL ON FUNCTION public.update_patient_demographics(UUID,JSONB) FROM PUBLIC,anon;
GRANT EXECUTE ON FUNCTION public.update_patient_demographics(UUID,JSONB) TO authenticated;

COMMENT ON FUNCTION public.update_patient_demographics(UUID,JSONB) IS
'Permission-checked patient-master correction with normalized validation and privacy-minimized UHID/changed-field audit; historical snapshots remain immutable.';
