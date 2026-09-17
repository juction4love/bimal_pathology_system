-- The active workflow may be operated by one qualified Lab Technician. Keep
-- every existing sign-off, snapshot, revision and audit control, but remove
-- the historical two-person identity requirement from the final report RPC.
DO $single_operator_report_authorization$
DECLARE
  v_signature CONSTANT REGPROCEDURE := 'public.sign_and_freeze_diagnostic_report(uuid,uuid,uuid,text,uuid)'::REGPROCEDURE;
  v_definition TEXT;
  v_old CONSTANT TEXT := $old$
        IF p_signed_by_id = p_performed_by_id THEN
            RAISE EXCEPTION 'Authorizing signatory must be distinct from performed-by reporting personnel.';
        END IF;

$old$;
  v_new CONSTANT TEXT := $new$
        -- A single qualified operator may perform and authorize the report.
        -- The selected personnel identity must still pass every active,
        -- registration and can_sign_reports check below.
$new$;
BEGIN
  SELECT pg_get_functiondef(v_signature) INTO v_definition;
  IF v_definition IS NULL OR strpos(v_definition,v_old)=0 THEN
    RAISE EXCEPTION 'Expected single-operator sign-off guard was not found; refusing an unverified function rewrite.'
      USING ERRCODE='55000';
  END IF;
  EXECUTE replace(v_definition,v_old,v_new);
END $single_operator_report_authorization$;

COMMENT ON FUNCTION public.sign_and_freeze_diagnostic_report(UUID,UUID,UUID,TEXT,UUID) IS
  'Creates an immutable signed report. One qualified active reporting-personnel identity may be both performer and authorizer for the approved single-Technician workflow.';
