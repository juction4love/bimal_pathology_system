SELECT
    (SELECT count(*) FROM public.tests) as total_tests_count,
    (SELECT count(*) FROM public.tests WHERE test_type = 'Panel') as panel_tests_count,
    (SELECT count(*) FROM public.tests WHERE test_type = 'Single') as single_tests_count,
    (SELECT count(*) FROM public.catalogue_panel_components) as panel_components_count,
    (SELECT count(*) FROM public.test_aliases) as test_aliases_count,
    (SELECT count(*) FROM public.parameters) as parameters_count,
    (SELECT count(*) FROM public.reference_ranges) as reference_ranges_count,
    (SELECT count(*) FROM public.health_packages) as health_packages_count;
