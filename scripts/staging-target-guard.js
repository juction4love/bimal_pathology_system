import { execFileSync } from 'node:child_process'
import { validateHostedIdentity } from './foundation-candidate-contract.js'

export const ISOLATED_STAGING_PROJECT_REF = 'ilcnctiaumrjbnlmnise'
export const RETIRED_STAGING_PROJECT_REF = 'qvuidmgddjoircheapzk'
export const STAGING_CONFIRMATION_VALUE = `I_CONFIRM_SYNTHETIC_STAGING_${ISOLATED_STAGING_PROJECT_REF}`

function migrationVersions(output) {
  const jsonLine = output.split(/\r?\n/).reverse().find(line => line.trim().startsWith('{"migrations"'))
  if (!jsonLine) throw new Error('Could not read the staging migration ledger response')
  const parsed = JSON.parse(jsonLine)
  return parsed.migrations.filter(row => row.remote).map(row => row.remote).sort()
}

export function assertSyntheticStagingTarget({ expectedHead } = {}) {
  if (process.env.FOUNDATION_TARGET_ENVIRONMENT === 'isolated-acceptance') {
    const target = validateHostedIdentity({ mode: 'acceptance' })
    if (process.env.STAGING_PROJECT_REF !== target.ref || process.env.STAGING_SUPABASE_URL !== target.url) {
      throw new Error('Legacy STAGING_* aliases must exactly match the guarded foundation acceptance target')
    }
    if (!['00056','00057','00058','00059','00060'].includes(expectedHead)) throw new Error('Hosted acceptance requires approved head 00056 through Technician-convergence head 00060')
    const output = process.platform === 'win32'
      ? execFileSync(process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', ['/d','/s','/c',`npx --yes supabase@latest migration list --project-ref ${target.ref}`], { cwd:process.cwd(),encoding:'utf8',stdio:['ignore','pipe','pipe'] })
      : execFileSync('npx', ['--yes','supabase@latest','migration','list','--project-ref',target.ref], { cwd:process.cwd(),encoding:'utf8',stdio:['ignore','pipe','pipe'] })
    const actualHead = migrationVersions(output).at(-1)
    if (actualHead !== expectedHead) throw new Error(`Foundation acceptance head ${actualHead || '<none>'} does not match ${expectedHead}`)
    console.log(`[FOUNDATION ACCEPTANCE TARGET] ${JSON.stringify({ project_ref:target.ref,migration_head:actualHead,legacy_staging_quarantined:RETIRED_STAGING_PROJECT_REF })}`)
    return { environment:target.environment,project_ref:target.ref,migration_head:actualHead,mutation_guard:'PASS' }
  }
  const environment = process.env.STAGING_ENVIRONMENT
  const projectRef = process.env.STAGING_PROJECT_REF
  const confirmation = process.env.STAGING_CONFIRMATION
  const url = process.env.STAGING_SUPABASE_URL

  if (environment !== 'isolated-staging') throw new Error('STAGING_ENVIRONMENT must equal isolated-staging')
  if (projectRef === RETIRED_STAGING_PROJECT_REF) throw new Error('Retired staging project is permanently refused')
  if (projectRef !== ISOLATED_STAGING_PROJECT_REF) throw new Error(`Refusing target ${projectRef || '<unset>'}; expected ${ISOLATED_STAGING_PROJECT_REF}`)
  if (confirmation !== STAGING_CONFIRMATION_VALUE) throw new Error('Explicit synthetic-staging confirmation is missing or invalid')
  if (!url) throw new Error('STAGING_SUPABASE_URL is required')
  const parsedUrl = new URL(url)
  const expectedHostname = `${ISOLATED_STAGING_PROJECT_REF}.supabase.co`
  if (parsedUrl.protocol !== 'https:' || parsedUrl.hostname !== expectedHostname) throw new Error(`URL must be exactly https://${expectedHostname}`)
  if (!expectedHead) throw new Error('An expected staging migration head is required')

  const ledgerOutput = process.platform === 'win32'
    ? execFileSync(process.env.ComSpec || 'C:\\Windows\\System32\\cmd.exe', ['/d', '/s', '/c', `npx supabase migration list --project-ref ${ISOLATED_STAGING_PROJECT_REF}`], {
        cwd: process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      })
    : execFileSync('npx', ['supabase', 'migration', 'list', '--project-ref', ISOLATED_STAGING_PROJECT_REF], {
        cwd: process.cwd(), encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
      })
  const versions = migrationVersions(ledgerOutput)
  const actualHead = versions.at(-1)
  if (actualHead !== expectedHead) throw new Error(`Staging migration head ${actualHead || '<none>'} does not match expected ${expectedHead}`)

  const proof = {
    environment,
    project_ref: projectRef,
    expected_project_ref: ISOLATED_STAGING_PROJECT_REF,
    migration_head: actualHead,
    expected_migration_head: expectedHead,
    mutation_guard: 'PASS',
  }
  console.log(`[STAGING TARGET GUARD] ${JSON.stringify(proof)}`)
  return proof
}
