/** RETIRED_REMOTE_MUTATION_HARNESS
 *
 * This legacy live harness performed direct result/order mutations and invoked
 * obsolete sign/token workers. Use only the guarded server-authoritative staging
 * lifecycle and concurrency harnesses.
 */
console.error(
  'Retired for release safety. Run scripts/staging-phase2-clinical-lifecycle.js and scripts/staging-phase2-signoff-concurrency.js.',
)
process.exitCode = 1
