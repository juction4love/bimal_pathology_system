-- Read-only 00090 production dry run. Execute only after confirming head 00089.
-- This reports the exact reconciliation population; it performs no DML.
SELECT r.state::TEXT readiness_state,t.reporting_type::TEXT reporting_type,t.workflow_type::TEXT workflow_type,
       count(*)::BIGINT affected_count
FROM public.catalogue_service_readiness r
JOIN public.tests t ON t.id=r.test_id
WHERE r.state='NeedsConfiguration'
  AND r.decision_reason='Catalogue test entered readiness governance.'
  AND t.is_active AND t.lifecycle_status='Active' AND t.workflow_supported
  AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport')
  AND NOT EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e WHERE e.test_id=t.id)
GROUP BY r.state,t.reporting_type,t.workflow_type
ORDER BY r.state,t.reporting_type,t.workflow_type;

SELECT count(*)::BIGINT AS preserved_explicit_or_historical_count
FROM public.catalogue_service_readiness r
JOIN public.tests t ON t.id=r.test_id
WHERE r.state IN ('Suspended','Approved','ReadyForReview')
   OR t.reporting_type='NoReporting' OR NOT t.is_active OR t.lifecycle_status<>'Active'
   OR EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e WHERE e.test_id=t.id);

SELECT category,count(*)::BIGINT AS row_count FROM (
 SELECT 'untouched_00089_default_blocker' category,r.test_id
 FROM public.catalogue_service_readiness r JOIN public.tests t ON t.id=r.test_id
 WHERE r.state='NeedsConfiguration' AND r.decision_reason='Catalogue test entered readiness governance.'
   AND t.is_active AND t.lifecycle_status='Active' AND t.workflow_supported
   AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport')
   AND NOT EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e WHERE e.test_id=t.id)
 UNION ALL
 SELECT 'explicit_suspended',r.test_id FROM public.catalogue_service_readiness r WHERE r.state='Suspended'
 UNION ALL
 SELECT 'explicit_non_reportable',r.test_id FROM public.catalogue_service_readiness r JOIN public.tests t ON t.id=r.test_id
  WHERE t.reporting_type='NoReporting' OR t.workflow_type='NoClinicalReport'
 UNION ALL
 SELECT 'reviewed_or_configured',r.test_id FROM public.catalogue_service_readiness r
  WHERE EXISTS(SELECT 1 FROM public.catalogue_configuration_evidence e WHERE e.test_id=r.test_id)
 UNION ALL
 SELECT 'inactive_or_archived',r.test_id FROM public.catalogue_service_readiness r JOIN public.tests t ON t.id=r.test_id
  WHERE NOT t.is_active OR t.lifecycle_status<>'Active'
) categories GROUP BY category ORDER BY category;
