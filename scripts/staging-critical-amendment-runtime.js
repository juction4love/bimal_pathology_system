import { readFile, writeFile } from 'node:fs/promises'
import { assertSyntheticStagingTarget } from './staging-target-guard.js'
import { bootstrapAdminClient } from './hosted-synthetic-actors.js'

const {
  STAGING_SUPABASE_URL: url,
  STAGING_ANON_KEY: anonKey,
  STAGING_SERVICE_KEY: serviceKey,
  STAGING_TEST_PASSWORD: password,
  STAGING_EXPECTED_MIGRATION_HEAD: expectedHead,
} = process.env
if (!url || !anonKey || !serviceKey || !password || !expectedHead) {
  throw new Error('Staging environment variables are required')
}
const target = assertSyntheticStagingTarget({ expectedHead })
const service = await bootstrapAdminClient(url, anonKey)
const actor = service
const lifecycle = JSON.parse(await readFile('artifacts/phase2-clinical-lifecycle.json', 'utf8'))
const { order_item_id: orderItemId, parameter_id: parameterId, report_id: reportId } = lifecycle.ids
if (!orderItemId || !parameterId || !reportId) throw new Error('A synthetic signed lifecycle artifact is required')

const actorUser = await actor.auth.getUser()
if (actorUser.error) throw actorUser.error

const before = await service.from('test_results').select('*')
  .eq('order_item_id', orderItemId).eq('parameter_id', parameterId).single()
if (before.error || !before.data.is_critical || !before.data.critical_acknowledged) {
  throw before.error || new Error('The synthetic fixture is not an acknowledged critical result')
}
const frozenBefore = await service.from('diagnostic_reports')
  .select('integrity_hash,clinical_snapshot_json').eq('id', reportId).single()
if (frozenBefore.error) throw frozenBefore.error

const amendedNumeric = Number(before.data.numeric_value) + 1
const resultPayload = [{
  parameter_id: parameterId,
  numeric_value: amendedNumeric,
  text_value: null,
  display_value: String(amendedNumeric),
  flag: 'CriticalLow',
  is_critical: true,
  critical_acknowledged: true,
  normal_range_text: before.data.normal_range_text,
  normal_min: before.data.normal_min,
  normal_max: before.data.normal_max,
  critical_low: before.data.critical_low,
  critical_high: before.data.critical_high,
}]
const revisionRow = await service.from('clinical_order_items').select('result_revision').eq('id', orderItemId).single()
if (revisionRow.error) throw revisionRow.error
const startingRevision = revisionRow.data.result_revision
const amendmentArgs = {
  p_order_item_id: orderItemId,
  p_results: resultPayload,
  p_target_status: 'SubmittedForVerification',
  p_amended_from_report_id: reportId,
  p_amendment_reason: 'Synthetic critical-value re-acknowledgement proof',
  p_expected_revision: startingRevision,
}

const staleAttempt = await actor.rpc('save_test_results', amendmentArgs)
const afterDenied = await service.from('test_results').select('numeric_value,critical_acknowledged,updated_at')
  .eq('order_item_id', orderItemId).eq('parameter_id', parameterId).single()
const staleDenied = Boolean(staleAttempt.error)
  && Number(afterDenied.data?.numeric_value) === Number(before.data.numeric_value)

const unacknowledgedPayload = resultPayload.map((result) => ({
  ...result,
  critical_acknowledged: false,
}))
const amendmentOpened = await actor.rpc('save_test_results', {
  ...amendmentArgs,
  p_results: unacknowledgedPayload,
})
if (amendmentOpened.error) throw amendmentOpened.error
const afterOpen = await service.from('test_results')
  .select('numeric_value,critical_acknowledged,status')
  .eq('order_item_id', orderItemId).eq('parameter_id', parameterId).single()
const openedWithoutStaleAcknowledgement = Number(afterOpen.data?.numeric_value) === amendedNumeric
  && afterOpen.data?.critical_acknowledged === false

const documented = await actor.rpc('record_critical_value_acknowledgement', {
  p_order_item_id: orderItemId,
  p_notification_method: 'Direct Phone Call',
  p_notified_person: 'Synthetic Duty Clinician',
  p_comment: 'Fresh synthetic amendment notification',
})
if (documented.error) throw documented.error
const freshAttempt = await actor.rpc('save_test_results', { ...amendmentArgs, p_expected_revision: startingRevision + 1 })
const afterFresh = await service.from('test_results')
  .select('numeric_value,critical_acknowledged,critical_acknowledged_by,status')
  .eq('order_item_id', orderItemId).eq('parameter_id', parameterId).single()
const frozenAfter = await service.from('diagnostic_reports')
  .select('integrity_hash,clinical_snapshot_json').eq('id', reportId).single()

const freshAccepted = !freshAttempt.error
  && Number(afterFresh.data?.numeric_value) === amendedNumeric
  && afterFresh.data?.critical_acknowledged === true
  && afterFresh.data?.critical_acknowledged_by === actorUser.data.user.id
const frozenUnchanged = !frozenAfter.error
  && frozenAfter.data.integrity_hash === frozenBefore.data.integrity_hash
  && JSON.stringify(frozenAfter.data.clinical_snapshot_json) === JSON.stringify(frozenBefore.data.clinical_snapshot_json)

const evidence = {
  target,
  summary: {
    stale_acknowledgement_rejected: staleDenied,
    amendment_opened_unacknowledged: openedWithoutStaleAcknowledgement,
    fresh_server_audit_accepted: freshAccepted,
    frozen_v1_unchanged: frozenUnchanged,
    pass: staleDenied && openedWithoutStaleAcknowledgement && freshAccepted && frozenUnchanged,
    real_patient_data_used: false,
    sms_provider_send_attempted: false,
  },
  rejection: { code: staleAttempt.error?.code, message: staleAttempt.error?.message },
  fresh_error: freshAttempt.error?.message || null,
}
await writeFile('artifacts/staging-critical-amendment-runtime.json', JSON.stringify(evidence, null, 2))
console.log(JSON.stringify(evidence.summary))
if (!evidence.summary.pass) process.exitCode = 1
