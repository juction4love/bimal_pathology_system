SELECT indexname, indexdef
FROM pg_indexes
WHERE tablename = 'reference_ranges';
