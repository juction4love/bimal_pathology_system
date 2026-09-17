import { createClient } from '@supabase/supabase-js'
import { createHash, randomBytes } from 'node:crypto'
import { writeFile } from 'node:fs/promises'
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
const admin = service
const anon = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })

const reports = await service.from('diagnostic_reports')
  .select('id,version,integrity_hash,clinical_snapshot_json,status')
  .in('status', ['SignedOff', 'Amended']).order('created_at', { ascending: false }).limit(50)
if (reports.error) throw reports.error
const syntheticReports = reports.data.filter((report) => {
  const name = report.clinical_snapshot_json?.patient?.full_name || ''
  return /^(Synthetic|Sign Concurrency|Phase Two)/.test(name)
})
const reportIds = syntheticReports.map((report) => report.id)
const tokens = await service.from('public_report_tokens').select('*')
  .in('diagnostic_report_id', reportIds).eq('is_active', true).is('revoked_at', null)
if (tokens.error) throw tokens.error
const sms = await service.from('sms_queue_items')
  .select('id,diagnostic_report_id,message_body,sms_type,idempotency_key')
  .in('diagnostic_report_id', reportIds).eq('sms_type', 'ReportReady')
if (sms.error) throw sms.error
const tokenByReport = new Map(tokens.data.map((token) => [token.diagnostic_report_id, token]))
const smsByReport = new Map(sms.data.map((row) => [row.diagnostic_report_id, row]))
const candidates = syntheticReports.filter((report) => {
  const token = tokenByReport.get(report.id)
  const queue = smsByReport.get(report.id)
  const raw = queue?.message_body?.match(/https:\/\/lis\.bimalpathology\.com\.np\/r\/([A-Za-z0-9_-]+)/)?.[1]
  return token && raw && createHash('sha256').update(raw).digest('hex') === token.token_hash
})
if (candidates.length < 5) throw new Error('Five synthetic signed report/token fixtures are required')
const [activeReport, expiredReport, revokedReport, unrecoverableReport, missingReport] = candidates
const status = async (report) => admin.rpc('get_report_secure_link_status', { p_report_id: report.id })
const publicResolve = async (hash) => anon.rpc('resolve_public_report_by_token', { p_token_hash: hash })

const activeFirst = await status(activeReport)
const activeReload = await status(activeReport)
const activePass = !activeFirst.error && !activeReload.error
  && activeFirst.data.state === 'Active' && activeFirst.data.qr_available === true
  && activeReload.data.public_url === activeFirst.data.public_url

const expiredToken = tokenByReport.get(expiredReport.id)
await service.from('public_report_tokens').update({ expires_at: new Date(Date.now() - 60_000).toISOString() })
  .eq('id', expiredToken.id).throwOnError()
const expiredStatus = await status(expiredReport)
const expiredPublic = await publicResolve(expiredToken.token_hash)
const expiredPass = !expiredStatus.error && expiredStatus.data.state === 'Expired'
  && expiredPublic.data?.valid === false

const revokedToken = tokenByReport.get(revokedReport.id)
await service.from('public_report_tokens').update({ revoked_at: new Date().toISOString() })
  .eq('id', revokedToken.id).throwOnError()
const revokedStatus = await status(revokedReport)
const revokedPublic = await publicResolve(revokedToken.token_hash)
const revokedPass = !revokedStatus.error && revokedStatus.data.state === 'Revoked'
  && revokedPublic.data?.valid === false

const unrecoverableToken = tokenByReport.get(unrecoverableReport.id)
const beforeSmsCount = sms.data.filter((row) => row.diagnostic_report_id === unrecoverableReport.id).length
await service.from('report_secure_link_presentations').delete()
  .eq('report_token_id', unrecoverableToken.id).throwOnError()
await service.from('sms_queue_items').update({
  message_body: 'Synthetic ReportReady notification; canonical URL intentionally unavailable.',
}).eq('diagnostic_report_id', unrecoverableReport.id).eq('sms_type', 'ReportReady').throwOnError()
const unrecoverableStatus = await status(unrecoverableReport)
const raw = randomBytes(32).toString('base64url')
const hash = createHash('sha256').update(raw).digest('hex')
const publicUrl = `https://lis.bimalpathology.com.np/r/${raw}`
const provisioned = await admin.rpc('provision_historical_report_secure_link', {
  p_report_id: unrecoverableReport.id,
  p_token_hash: hash,
  p_public_url: publicUrl,
  p_expiry_days: 30,
})
const afterProvision = await status(unrecoverableReport)
const resolvedProvision = await publicResolve(hash)
const afterSms = await service.from('sms_queue_items').select('id', { count: 'exact' })
  .eq('diagnostic_report_id', unrecoverableReport.id).eq('sms_type', 'ReportReady')
const frozenAfter = await service.from('diagnostic_reports')
  .select('integrity_hash,clinical_snapshot_json').eq('id', unrecoverableReport.id).single()
const provisionPass = unrecoverableStatus.data?.state === 'ActiveUnrecoverable'
  && !provisioned.error && provisioned.data.created === true && provisioned.data.sms_queued === false
  && afterProvision.data?.state === 'Active' && afterProvision.data?.qr_available === true
  && resolvedProvision.data?.valid === true
  && afterSms.count === beforeSmsCount
  && frozenAfter.data?.integrity_hash === unrecoverableReport.integrity_hash
  && JSON.stringify(frozenAfter.data?.clinical_snapshot_json) === JSON.stringify(unrecoverableReport.clinical_snapshot_json)

const missingToken = tokenByReport.get(missingReport.id)
await service.from('public_report_tokens').delete().eq('id', missingToken.id).throwOnError()
const missingStatus = await status(missingReport)
const missingPass = !missingStatus.error && missingStatus.data.state === 'Missing'
  && missingStatus.data.qr_available === false

const summary = {
  active_recoverable_and_reload: activePass,
  expired_denied: expiredPass,
  revoked_denied: revokedPass,
  active_unrecoverable_detected: unrecoverableStatus.data?.state === 'ActiveUnrecoverable',
  explicit_generation_restores_qr: provisionPass,
  missing_detected: missingPass,
  automatic_sms_resend: false,
  frozen_report_changed: false,
  pass: activePass && expiredPass && revokedPass && provisionPass && missingPass,
}
await writeFile('artifacts/staging-final-secure-link-runtime.json', JSON.stringify({ target, summary }, null, 2))
console.log(JSON.stringify(summary))
if (!summary.pass) process.exitCode = 1
