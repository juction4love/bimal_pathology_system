/** RETIRED_REMOTE_MUTATION_HARNESS
 *
 * This historical diagnostic could sign the latest deployed clinical order
 * through an obsolete worker RPC. Use the guarded synthetic staging lifecycle
 * and sign-off concurrency harnesses instead.
 */
console.error(
  'Retired for release safety. Run scripts/staging-phase2-clinical-lifecycle.js or scripts/staging-phase2-signoff-concurrency.js.',
)
process.exitCode = 1
