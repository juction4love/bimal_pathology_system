/** RETIRED_REMOTE_MUTATION_HARNESS
 *
 * This historical diagnostic loaded the deployed endpoint from .env.local and
 * attempted a direct catalogue insert. Direct catalogue writes are retired.
 * Use staging-phase2-catalogue-runtime.js with the isolated-staging guard.
 */
console.error(
  'Retired for release safety. Run scripts/staging-phase2-catalogue-runtime.js against explicitly guarded isolated staging.',
)
process.exitCode = 1
