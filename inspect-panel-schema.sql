SELECT
  table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND (
    table_name ILIKE '%panel%'
    OR table_name ILIKE '%package%'
  )
ORDER BY table_name;

SELECT
  p.proname
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND (
    p.proname ILIKE '%panel%'
    OR p.proname ILIKE '%package%'
  )
ORDER BY p.proname;
