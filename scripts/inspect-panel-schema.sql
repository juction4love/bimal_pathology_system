-- Inspect tables and functions related to panels in public schema
SELECT json_build_object(
  'tables', (
    SELECT json_agg(table_name) FROM information_schema.tables 
    WHERE table_schema = 'public' 
      AND (table_name LIKE '%panel%' OR table_name LIKE '%package%' OR table_name LIKE '%catalogue%')
  ),
  'catalogue_panel_services_cols', (
    SELECT json_agg(json_build_object('column', column_name, 'type', data_type))
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'catalogue_panel_services'
  ),
  'catalogue_panel_components_cols', (
    SELECT json_agg(json_build_object('column', column_name, 'type', data_type))
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'catalogue_panel_components'
  ),
  'bill_panel_selections_cols', (
    SELECT json_agg(json_build_object('column', column_name, 'type', data_type))
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bill_panel_selections'
  ),
  'bill_panel_components_cols', (
    SELECT json_agg(json_build_object('column', column_name, 'type', data_type))
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'bill_panel_components'
  ),
  'func_catalogue_panel_service_components', (
    SELECT prosrc FROM pg_proc WHERE proname = 'catalogue_panel_service_components' LIMIT 1
  ),
  'func_create_patient_bill_order_with_panel_service', (
    SELECT prosrc FROM pg_proc WHERE proname = 'create_patient_bill_order_with_panel_service' LIMIT 1
  )
) AS inspect_result;
