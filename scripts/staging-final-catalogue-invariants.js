import { createClient } from '@supabase/supabase-js'
import { writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const {
  STAGING_SUPABASE_URL: url,
  STAGING_SERVICE_KEY: serviceKey,
  STAGING_EXPECTED_MIGRATION_HEAD: expectedHead,
} = process.env
if (!url || !serviceKey || !expectedHead) throw new Error('Staging environment variables are required')
const target = assertSyntheticStagingTarget({ expectedHead })
const service = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
const reviewedCodes = [
  'AFP', 'BT_CT', 'PT_INR', 'LDH', 'CHOL_TOTAL', 'HDL_CHOL', 'LDL_CHOL',
  'TRIGLYCERIDES', 'BILIRUBIN_TD', 'AST', 'ALT', 'ALP', 'GGT', 'LIPASE',
  'AMYLASE', 'CK_TOTAL', 'CK_MB', 'BICARBONATE', 'GLOBULIN', 'EGFR',
  'RETIC_COUNT', 'AEC', 'ANC',
]
const priorityCodes = ['AFP', 'BT_CT', 'PT_INR', 'LDH']

const reviewed = await service.from('tests')
  .select('id,code,lifecycle_status,is_active,clinical_configuration_status,price_paisa,price_configured')
  .in('code', reviewedCodes)
if (reviewed.error) throw reviewed.error
const priorityIds = reviewed.data.filter((test) => priorityCodes.includes(test.code)).map((test) => test.id)
const parameters = await service.from('parameters')
  .select('id,test_id,code,lifecycle_status,is_active,formula,calculation_identifier,clinical_configuration_status')
  .in('test_id', priorityIds)
if (parameters.error) throw parameters.error
const parameterIds = parameters.data.map((parameter) => parameter.id)
const ranges = parameterIds.length
  ? await service.from('reference_ranges').select('id').in('parameter_id', parameterIds)
  : { data: [], error: null }
if (ranges.error) throw ranges.error
const legacy = await service.from('reference_ranges')
  .select('id', { count: 'exact', head: true })
  .eq('validation_state', 'LegacyDefaultRequiresValidation')
if (legacy.error) throw legacy.error
const activeReviewed = reviewed.data.filter((test) => test.lifecycle_status === 'Active' || test.is_active)
const pendingReviewed = reviewed.data.filter((test) =>
  test.lifecycle_status === 'Draft'
  && !test.is_active
  && test.price_paisa === 0
  && test.price_configured === false,
)
const priorityFormulaRows = parameters.data.filter((parameter) => parameter.formula || parameter.calculation_identifier)
const expectedParameters = new Set([
  'AFP:AFP', 'BT_CT:BLEEDING_TIME', 'BT_CT:CLOTTING_TIME',
  'PT_INR:PATIENT_PT', 'PT_INR:CONTROL_PT', 'PT_INR:ISI', 'PT_INR:INR',
  'LDH:LDH',
])
const testCodeById = new Map(reviewed.data.map((test) => [test.id, test.code]))
const actualParameters = new Set(parameters.data.map((parameter) => `${testCodeById.get(parameter.test_id)}:${parameter.code}`))
const parameterShapeMatches = expectedParameters.size === actualParameters.size
  && [...expectedParameters].every((key) => actualParameters.has(key))

const summary = {
  reviewed_draft_identities: reviewed.data.length,
  reviewed_draft_price_pending: pendingReviewed.length,
  reviewed_active_imports: activeReviewed.length,
  priority_draft_parameters: parameters.data.length,
  priority_parameter_shape_matches: parameterShapeMatches,
  priority_reference_ranges: ranges.data.length,
  priority_formulas: priorityFormulaRows.length,
  legacy_default_requires_validation: legacy.count,
  pass: reviewed.data.length === 23
    && pendingReviewed.length === 23
    && activeReviewed.length === 0
    && parameters.data.length === 8
    && parameterShapeMatches
    && parameters.data.every((parameter) => parameter.lifecycle_status === 'Draft'
      && !parameter.is_active
      && parameter.clinical_configuration_status === 'Requires Clinical Validation')
    && ranges.data.length === 0
    && priorityFormulaRows.length === 0
    && legacy.count === 105,
}
const evidence = { target, summary, reviewed_codes: reviewed.data.map((test) => test.code).sort() }
await writeFile('artifacts/staging-final-catalogue-invariants.json', JSON.stringify(evidence, null, 2))
console.log(JSON.stringify(summary))
if (!summary.pass) process.exitCode = 1
