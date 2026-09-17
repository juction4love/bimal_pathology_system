import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations/00061_cbc_v3_clinical_source_governance.sql', 'utf8');
const hardening = fs.readFileSync('supabase/migrations/00062_cbc_source_approval_hardening.sql', 'utf8');
const ui = fs.readFileSync('src/features/catalogue/ClinicalSourceReviewPanel.tsx', 'utf8');
const catalogue = fs.readFileSync('src/features/catalogue/CataloguePage.tsx', 'utf8');
const deferred = fs.readdirSync('supabase/deferred_migrations');

const checks = [];
const check = (condition, message) => {
  if (!condition) throw new Error(message);
  checks.push(message);
};

check(migration.includes("'CBC-V1'") && migration.includes("'CBC-V2'") && migration.includes("'CBC-V3'"), 'V1/V2/V3 imports are preserved');
check(migration.includes("'150,000–350,000'") && migration.includes("'150,000–400,000'"), 'platelet source-version conflict is preserved');
check(migration.includes("'AuthorizedContextDependent'") && migration.includes("'AuthorizedApproximateReviewRequired'"), 'context-dependent and approximate evidence remain review-blocked');
check(migration.includes("'SeparateCandidateParameter'") && migration.includes("'ALC'") && migration.includes("'AMC'"), 'absolute counts remain separate candidates');
check(migration.includes('Clinical source evidence is immutable') && migration.includes('Imported clinical source content is immutable'), 'source evidence is immutable');
check(migration.includes('catalogue_record_clinical_source_decision') && migration.includes('catalogue_approve_clinical_source_decision') && migration.includes('catalogue_materialize_clinical_source_decision'), 'review, approval, and materialization RPCs exist');
check(migration.includes("FALSE,TRUE,'Draft'") && !/UPDATE public\.tests[\s\S]*clinical_reporting_enabled\s*=\s*TRUE/i.test(migration), 'materialization stays Draft and CBC is never enabled');
check(migration.includes("IF v_count<>48") && migration.includes("source_decision_id IS NOT NULL"), '48-item seed and no-auto-materialization assertions exist');
check(migration.includes('CBC_SOURCE_CONFLICT') && migration.includes('CBC_APPLICABILITY_INCOMPLETE') && migration.includes('CBC_TECHNICAL_DECISION_REQUIRED'), 'CBC completeness returns stable blocker codes');
check(migration.includes('ENABLE ROW LEVEL SECURITY') && migration.includes("has_permission('can_manage_catalogue')"), 'review tables are manager-only under RLS');
check(ui.includes('Review / Correct') && ui.includes('Approve decision') && ui.includes('Version as Draft range'), 'technical review UI exposes governed workflow');
check(ui.includes('critical_limits_reviewed') && ui.includes('method_or_analyzer_context') && ui.includes('applicability_basis'), 'approval UI requires applicability and safety review');
check(catalogue.includes('<ClinicalSourceReviewPanel />'), 'review UI is integrated into Catalogue');
check(hardening.includes('explicit non-null age bounds') && hardening.includes('Approximate source evidence requires a corrected laboratory policy'), 'forward hardening rejects null applicability and direct approximate-source approval');
check(hardening.includes('catalogue_require_manager') && hardening.includes('CBC_APPLICABILITY_INCOMPLETE'), 'completeness is manager-only and fail-closed');
check(deferred.includes('00070_cloud_sms_dispatch_coordination.sql') && !fs.readdirSync('supabase/migrations').some((name) => /cloud[_-]sms/i.test(name)), 'cloud SMS is deferred at 00070 outside the deployable chain');

console.log(JSON.stringify({ suite: 'CBC V3 governance contracts', checks: checks.length, status: 'PASS' }));
