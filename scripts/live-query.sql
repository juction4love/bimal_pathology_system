SELECT json_build_object(
    'test', row_to_json(t.*),
    'params', (SELECT json_agg(p.*) FROM public.parameters p WHERE p.test_id = t.id),
    'ranges', (SELECT json_agg(r.*) FROM public.reference_ranges r WHERE r.parameter_id IN (SELECT p.id FROM public.parameters p WHERE p.test_id = t.id)),
    'aliases', (SELECT json_agg(a.*) FROM public.test_aliases a WHERE a.test_id = t.id),
    'specimen_rule', (SELECT row_to_json(sr.*) FROM public.assay_specimen_governance_rules sr WHERE sr.test_id = t.id)
) as test_detail
FROM public.tests t
WHERE t.code IN ('SER-0001', 'SER-0004', 'SER-0010')
ORDER BY t.code;
