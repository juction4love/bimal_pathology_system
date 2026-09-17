SELECT table_name, column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name IN ('bill_panel_selections', 'bill_panel_components', 'catalogue_panel_components', 'catalogue_panel_services')
ORDER BY table_name, ordinal_position;
