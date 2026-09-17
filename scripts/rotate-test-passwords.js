/** RETIRED_REMOTE_MUTATION_HARNESS
 *
 * This utility loaded an implicit deployed endpoint and mutated Auth identities.
 * Password changes must be performed through an explicitly approved
 * operator runbook, never an application release/test command.
 */
console.error(
  'Retired for release safety. Use the approved credential-rotation runbook with explicit target verification and operator approval.',
)
process.exitCode = 1
