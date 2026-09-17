/**
 * Compatibility entry point for the former Phase 7 live-style test.
 *
 * The maintained patient/UHID suite is staging-final-patient-runtime.js. Keep
 * this package-script entry point, but make it impossible to load an implicit
 * local target, call legacy billing, or perform ad-hoc destructive cleanup.
 */
import { assertSyntheticStagingTarget } from './staging-target-guard.js'

const EXPECTED_MIGRATION_HEAD = '00052'
if (process.env.STAGING_EXPECTED_MIGRATION_HEAD !== EXPECTED_MIGRATION_HEAD) {
  throw new Error(`STAGING_EXPECTED_MIGRATION_HEAD must equal ${EXPECTED_MIGRATION_HEAD}`)
}

assertSyntheticStagingTarget({ expectedHead: EXPECTED_MIGRATION_HEAD })
console.log('[PHASE 7] Delegating to guarded synthetic patient/UHID runtime acceptance.')
await import('./staging-final-patient-runtime.js')
