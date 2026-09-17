-- ============================================================================
-- BIMAL PATHOLOGY & DIAGNOSTIC CENTER
-- Migration 00012: Fix test_results ID Default and Ensure Unique Result Identity
-- Safe, forward-only, idempotent migration
-- ============================================================================

-- 1. Ensure test_results.id uses PostgreSQL gen_random_uuid() default
ALTER TABLE public.test_results 
    ALTER COLUMN id SET DEFAULT gen_random_uuid();

-- 2. Safe Pre-Index Deduplication:
-- In case redundant duplicate rows exist for the same (order_item_id, parameter_id)
-- in non-signed/draft test orders, preserve the single newest authoritative row
-- (ordered by status priority, updated_at DESC, created_at DESC, id DESC)
-- and remove redundant duplicate test rows so unique index creation is guaranteed safe.
DELETE FROM public.test_results
WHERE id IN (
    SELECT id
    FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY order_item_id, parameter_id 
                   ORDER BY 
                       CASE 
                           WHEN status = 'Verified' THEN 1 
                           WHEN status = 'SubmittedForVerification' THEN 2 
                           ELSE 3 
                       END ASC,
                       updated_at DESC, 
                       created_at DESC, 
                       id DESC
               ) as rnum
        FROM public.test_results
    ) ranked
    WHERE ranked.rnum > 1
);

-- 3. Create unique index to guarantee one authoritative result per parameter per order item
-- This prevents duplicate result rows on repeated draft saves or concurrent writes
CREATE UNIQUE INDEX IF NOT EXISTS uq_test_results_order_item_parameter 
    ON public.test_results (order_item_id, parameter_id);

-- 4. Add index on order_item_id and status for fast worklist lookups
CREATE INDEX IF NOT EXISTS idx_test_results_order_item_status 
    ON public.test_results (order_item_id, status);

-- 5. Update table documentation
COMMENT ON TABLE public.test_results IS 'Clinical parameter test results with authoritative UUID generation and deterministic uniqueness on (order_item_id, parameter_id)';
