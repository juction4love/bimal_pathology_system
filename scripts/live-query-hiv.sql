SELECT row_to_json(t.*) as test, (SELECT json_agg(p.*) FROM public.parameters p WHERE p.test_id = t.id) as params
FROM public.tests t
WHERE t.code = 'SER-0001';
