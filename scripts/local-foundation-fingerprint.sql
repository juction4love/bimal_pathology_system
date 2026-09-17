WITH rows AS (
 SELECT 'patients' area,to_jsonb(t) data FROM patients t WHERE id='10000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'bills',to_jsonb(t) FROM bills t WHERE id='20000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'payments',to_jsonb(t) FROM payment_transactions t WHERE id='21000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'orders',to_jsonb(t) FROM clinical_orders t WHERE id='30000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'order_items',to_jsonb(t)-'workflow_type'-'clinical_reporting_enabled'-'collection_required'-'result_revision' FROM clinical_order_items t WHERE id='50000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'samples',to_jsonb(t) FROM samples t WHERE id='40000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'results',to_jsonb(t) FROM test_results t WHERE id='60000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'reports_snapshots_hashes_versions',to_jsonb(t) FROM diagnostic_reports t WHERE id='70000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'tokens',to_jsonb(t) FROM public_report_tokens t WHERE id='71000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'sms',to_jsonb(t) FROM sms_queue_items t WHERE id='72000000-0000-0000-0000-000000000001'
 UNION ALL SELECT 'audit',to_jsonb(t) FROM audit_logs t WHERE id='73000000-0000-0000-0000-000000000001'
)
SELECT area,count(*),encode(public.digest(convert_to(string_agg(data::text,E'\n' ORDER BY data::text),'UTF8'),'sha256'),'hex') hash
FROM rows GROUP BY area ORDER BY area;
