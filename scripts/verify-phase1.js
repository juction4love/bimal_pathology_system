/** RETIRED_REMOTE_MUTATION_HARNESS
 *
 * The former phase-one script loaded .env.local and attempted anonymous writes
 * as an RLS test. Security acceptance now runs only against guarded staging.
 */
console.error(
  'Retired for release safety. Run scripts/staging-00051-runtime.js against explicitly guarded isolated staging.',
)
process.exitCode = 1
