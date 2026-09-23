-- Production-safe patient profile management. Historical transaction snapshots
-- are deliberately untouched; all patient mutations are permission-checked RPCs.

ALTER TABLE public.patients
  ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN archived_at TIMESTAMPTZ,
  ADD COLUMN archived_by UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;

CREATE INDEX idx_patients_active_created_at
  ON public.patients (is_active, created_at DESC);

-- Browser clients must not bypass validation/audit by writing the table directly.
DROP POLICY IF EXISTS "patients_insert" ON public.patients;
DROP POLICY IF EXISTS "patients_update" ON public.patients;
DROP POLICY IF EXISTS "patients_delete" ON public.patients;

CREATE OR REPLACE FUNCTION public.patient_normalize_mobile(p_mobile TEXT)
RETURNS TEXT LANGUAGE plpgsql IMMUTABLE SET search_path = public, pg_temp AS $$
DECLARE v_mobile TEXT := regexp_replace(COALESCE(p_mobile, ''), '[^0-9]', '', 'g');
BEGIN
  IF v_mobile LIKE '977%' AND length(v_mobile) = 13 THEN v_mobile := substring(v_mobile FROM 4); END IF;
  IF v_mobile LIKE '0%' AND length(v_mobile) = 11 THEN v_mobile := substring(v_mobile FROM 2); END IF;
  IF v_mobile !~ '^(97|98)[0-9]{8}$' THEN
    RAISE EXCEPTION 'Please enter a valid 10-digit Nepal mobile number starting with 98 or 97.' USING ERRCODE = '22023';
  END IF;
  RETURN v_mobile;
END;
$$;

CREATE OR REPLACE FUNCTION public.patient_clean_text(p_value TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp AS $$
  SELECT regexp_replace(btrim(COALESCE(p_value, '')), '[[:space:]]+', ' ', 'g')
$$;

CREATE OR REPLACE FUNCTION public.patient_actor_name()
RETURNS TEXT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp AS $$
  SELECT COALESCE((SELECT full_name FROM public.user_profiles WHERE id = auth.uid()), 'Authenticated user')
$$;

CREATE OR REPLACE FUNCTION public.create_patient(p_patient_data JSONB)
RETURNS public.patients LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp AS $$
DECLARE
  v_patient public.patients%ROWTYPE;
  v_mobile TEXT := public.patient_normalize_mobile(p_patient_data->>'mobile');
  v_name TEXT := public.patient_clean_text(p_patient_data->>'full_name');
  v_address TEXT := public.patient_clean_text(p_patient_data->>'address');
  v_now TIMESTAMPTZ := clock_timestamp();
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to create patients.' USING ERRCODE = '42501'; END IF;
  IF v_name = '' OR v_address = '' THEN RAISE EXCEPTION 'Patient name and address are required.' USING ERRCODE = '22023'; END IF;
  IF COALESCE((p_patient_data->>'gender'), '') NOT IN ('Male','Female','Other') THEN RAISE EXCEPTION 'Invalid patient gender.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_years','')::INT NOT BETWEEN 0 AND 120 AND NULLIF(p_patient_data->>'age_years','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age years must be from 0 to 120.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_months','')::INT NOT BETWEEN 0 AND 11 AND NULLIF(p_patient_data->>'age_months','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age months must be from 0 to 11.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_days','')::INT NOT BETWEEN 0 AND 31 AND NULLIF(p_patient_data->>'age_days','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age days must be from 0 to 31.' USING ERRCODE = '22023'; END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended('patient-mobile:' || v_mobile, 0));
  IF EXISTS (SELECT 1 FROM public.patients WHERE mobile = v_mobile) THEN RAISE EXCEPTION 'A patient with this mobile number already exists. Open the existing patient; patients are never auto-merged.' USING ERRCODE = '23505'; END IF;

  INSERT INTO public.patients(uhid,mobile,title,full_name,gender,dob,age_years,age_months,age_days,address,email,identification_no,created_at)
  VALUES(public.allocate_patient_uhid(v_mobile,v_now),v_mobile,NULLIF(public.patient_clean_text(p_patient_data->>'title'),''),v_name,p_patient_data->>'gender',NULLIF(p_patient_data->>'dob','')::DATE,NULLIF(p_patient_data->>'age_years','')::INT,NULLIF(p_patient_data->>'age_months','')::INT,NULLIF(p_patient_data->>'age_days','')::INT,v_address,NULLIF(public.patient_clean_text(p_patient_data->>'email'),''),NULLIF(public.patient_clean_text(p_patient_data->>'identification_no'),''),v_now)
  RETURNING * INTO v_patient;

  RETURN v_patient;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_patient_demographics(p_patient_id UUID, p_patient_data JSONB)
RETURNS public.patients LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE
  v_old public.patients%ROWTYPE; v_new public.patients%ROWTYPE;
  v_mobile TEXT := public.patient_normalize_mobile(p_patient_data->>'mobile');
  v_name TEXT := public.patient_clean_text(p_patient_data->>'full_name');
  v_address TEXT := public.patient_clean_text(p_patient_data->>'address');
  v_changed TEXT[] := ARRAY[]::TEXT[];
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to edit patients.' USING ERRCODE = '42501'; END IF;
  SELECT * INTO v_old FROM public.patients WHERE id=p_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE = 'P0002'; END IF;
  IF NOT v_old.is_active THEN RAISE EXCEPTION 'Archived patients must be restored before editing.' USING ERRCODE = '55000'; END IF;
  IF v_name='' OR v_address='' THEN RAISE EXCEPTION 'Patient name and address are required.' USING ERRCODE = '22023'; END IF;
  IF COALESCE(p_patient_data->>'gender','') NOT IN ('Male','Female','Other') THEN RAISE EXCEPTION 'Invalid patient gender.' USING ERRCODE = '22023'; END IF;
  IF NULLIF(p_patient_data->>'age_years','')::INT NOT BETWEEN 0 AND 120 AND NULLIF(p_patient_data->>'age_years','') IS NOT NULL THEN RAISE EXCEPTION 'Patient age years must be from 0 to 120.' USING ERRCODE = '22023'; END IF;
  IF EXISTS(SELECT 1 FROM public.patients WHERE mobile=v_mobile AND id<>p_patient_id) THEN RAISE EXCEPTION 'A different patient with this mobile number already exists. Patients are never auto-merged.' USING ERRCODE = '23505'; END IF;

  IF v_old.full_name IS DISTINCT FROM v_name THEN v_changed:=array_append(v_changed,'full_name'); END IF;
  IF v_old.mobile IS DISTINCT FROM v_mobile THEN v_changed:=array_append(v_changed,'mobile'); END IF;
  IF v_old.address IS DISTINCT FROM v_address THEN v_changed:=array_append(v_changed,'address'); END IF;
  IF v_old.dob IS DISTINCT FROM NULLIF(p_patient_data->>'dob','')::DATE THEN v_changed:=array_append(v_changed,'dob'); END IF;
  IF v_old.gender IS DISTINCT FROM p_patient_data->>'gender' THEN v_changed:=array_append(v_changed,'gender'); END IF;
  IF v_old.age_years IS DISTINCT FROM NULLIF(p_patient_data->>'age_years','')::INT OR v_old.age_months IS DISTINCT FROM NULLIF(p_patient_data->>'age_months','')::INT OR v_old.age_days IS DISTINCT FROM NULLIF(p_patient_data->>'age_days','')::INT THEN v_changed:=array_append(v_changed,'age'); END IF;

  UPDATE public.patients SET mobile=v_mobile,title=NULLIF(public.patient_clean_text(p_patient_data->>'title'),''),full_name=v_name,gender=p_patient_data->>'gender',dob=NULLIF(p_patient_data->>'dob','')::DATE,age_years=NULLIF(p_patient_data->>'age_years','')::INT,age_months=NULLIF(p_patient_data->>'age_months','')::INT,age_days=NULLIF(p_patient_data->>'age_days','')::INT,address=v_address,email=NULLIF(public.patient_clean_text(p_patient_data->>'email'),''),identification_no=NULLIF(public.patient_clean_text(p_patient_data->>'identification_no'),''),updated_at=NOW() WHERE id=p_patient_id RETURNING * INTO v_new;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data,new_data)
  VALUES(auth.uid(),public.patient_actor_name(),'PATIENT_DEMOGRAPHICS_UPDATED','Patient',p_patient_id::TEXT,jsonb_build_object('changed_fields',v_changed),jsonb_build_object('changed_fields',v_changed));
  RETURN v_new;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_patient_archived(p_patient_id UUID, p_archived BOOLEAN)
RETURNS public.patients LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_patient public.patients%ROWTYPE;
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to archive patients.' USING ERRCODE='42501'; END IF;
  UPDATE public.patients SET is_active=NOT p_archived,archived_at=CASE WHEN p_archived THEN NOW() ELSE NULL END,archived_by=CASE WHEN p_archived THEN auth.uid() ELSE NULL END,updated_at=NOW() WHERE id=p_patient_id RETURNING * INTO v_patient;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE='P0002'; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data) VALUES(auth.uid(),public.patient_actor_name(),CASE WHEN p_archived THEN 'PATIENT_ARCHIVED' ELSE 'PATIENT_RESTORED' END,'Patient',p_patient_id::TEXT,jsonb_build_object('uhid',v_patient.uhid));
  RETURN v_patient;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_unused_patient(p_patient_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
DECLARE v_patient public.patients%ROWTYPE; v_has_history BOOLEAN;
BEGIN
  IF NOT public.has_permission('can_edit_patient') THEN RAISE EXCEPTION 'Not authorized to delete patients.' USING ERRCODE='42501'; END IF;
  SELECT * INTO v_patient FROM public.patients WHERE id=p_patient_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Patient not found.' USING ERRCODE='P0002'; END IF;
  SELECT EXISTS(SELECT 1 FROM public.bills WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.clinical_orders WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.samples WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.diagnostic_reports WHERE patient_id=p_patient_id) OR EXISTS(SELECT 1 FROM public.outsource_samples WHERE patient_id=p_patient_id) INTO v_has_history;
  IF v_has_history THEN RAISE EXCEPTION 'This patient has transactional history and cannot be deleted. Archive the patient instead.' USING ERRCODE='23503'; END IF;
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,old_data) VALUES(auth.uid(),public.patient_actor_name(),'PATIENT_HARD_DELETED','Patient',p_patient_id::TEXT,jsonb_build_object('uhid',v_patient.uhid));
  DELETE FROM public.patients WHERE id=p_patient_id;
  RETURN jsonb_build_object('deleted',TRUE,'patient_id',p_patient_id);
END;
$$;

REVOKE ALL ON FUNCTION public.patient_normalize_mobile(TEXT), public.patient_clean_text(TEXT), public.patient_actor_name(), public.create_patient(JSONB), public.update_patient_demographics(UUID,JSONB), public.set_patient_archived(UUID,BOOLEAN), public.delete_unused_patient(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_patient(JSONB), public.update_patient_demographics(UUID,JSONB), public.set_patient_archived(UUID,BOOLEAN), public.delete_unused_patient(UUID) TO authenticated;

COMMENT ON COLUMN public.patients.is_active IS 'Archived patients remain linked to immutable billing, clinical, report, SMS and audit history.';

CREATE OR REPLACE FUNCTION public.prevent_archived_patient_transaction()
RETURNS TRIGGER LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.patients WHERE id=NEW.patient_id AND is_active) THEN
    RAISE EXCEPTION 'Archived patients must be restored before creating a new transaction.' USING ERRCODE='55000';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_bills_active_patient BEFORE INSERT ON public.bills FOR EACH ROW EXECUTE FUNCTION public.prevent_archived_patient_transaction();
REVOKE ALL ON FUNCTION public.prevent_archived_patient_transaction() FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.audit_patient_created()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
BEGIN
  INSERT INTO public.audit_logs(user_id,user_name,action,entity_type,entity_id,new_data)
  VALUES(auth.uid(),public.patient_actor_name(),'PATIENT_CREATED','Patient',NEW.id::TEXT,jsonb_build_object('uhid',NEW.uhid));
  RETURN NEW;
END;
$$;
CREATE TRIGGER trg_patients_audit_created AFTER INSERT ON public.patients FOR EACH ROW EXECUTE FUNCTION public.audit_patient_created();
REVOKE ALL ON FUNCTION public.audit_patient_created() FROM PUBLIC, anon, authenticated;
