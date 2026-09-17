import assert from 'node:assert/strict'
import fs from 'node:fs'
import path from 'node:path'

const scriptsDirectory = path.resolve('scripts')
const retired = [
  'diagnose-save-test.js',
  'diagnose-signoff.js',
  'verify-phase1.js',
  'verify-production-null-authorizer.js',
  'verify-live-clinical-report.js',
  'rotate-test-passwords.js',
]
const productionProjectRef = 'rncjxstujioagcezvfkb'
let passed = 0
const check = (condition, message) => {
  assert.ok(condition, message)
  passed += 1
  console.log(`PASS: ${message}`)
}

for (const filename of retired) {
  const source = fs.readFileSync(path.join(scriptsDirectory, filename), 'utf8')
  check(source.includes('RETIRED_REMOTE_MUTATION_HARNESS'), `${filename} is explicitly retired`)
  check(
    !/from\s+['"]@supabase\/supabase-js['"]|\bcreateClient\s*\(|\bfetch\s*\(|\.rpc\s*\(|\.(?:insert|update|upsert|delete)\s*\(|auth\.(?:admin\.)?(?:createUser|deleteUser|updateUser)/.test(source),
    `${filename} contains no executable remote access or mutation path`,
  )
}

const runtimeImport = /^\s*import\s+.+from\s+['"]@supabase\/supabase-js['"]/m
const mutationCall = /\.rpc\s*\(|\.(?:insert|update|upsert|delete)\s*\(|auth\.admin\.(?:createUser|deleteUser|updateUserById)\s*\(|auth\.updateUser\s*\(/
const mutationHarnesses = fs.readdirSync(scriptsDirectory)
  .filter((filename) => filename.endsWith('.js'))
  .filter((filename) => !retired.includes(filename))
  .filter((filename) => {
    const source = fs.readFileSync(path.join(scriptsDirectory, filename), 'utf8')
    return runtimeImport.test(source) && mutationCall.test(source)
  })
  .sort()

check(mutationHarnesses.length > 0, 'remote mutation harness inventory is non-empty and actively inspected')
for (const filename of mutationHarnesses) {
  const source = fs.readFileSync(path.join(scriptsDirectory, filename), 'utf8')
  const guardCall = source.indexOf('assertSyntheticStagingTarget(')
  const clientCreation = source.indexOf('createClient(')
  check(
    source.includes("from './staging-target-guard.js'")
      && guardCall >= 0
      && clientCreation > guardCall,
    `${filename} proves the shared staging target before creating a remote client`,
  )
  check(!source.includes('.env.local'), `${filename} cannot inherit the deployed endpoint from .env.local`)
  check(!source.includes(productionProjectRef), `${filename} contains no production project target`)
  check(
    source.includes('STAGING_SUPABASE_URL') && source.includes('STAGING_EXPECTED_MIGRATION_HEAD'),
    `${filename} requires explicit staging endpoint and migration-head inputs`,
  )
}

const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'))
const packageCommands = Object.entries(packageJson.scripts || {})
for (const filename of retired) {
  check(
    packageCommands.every(([, command]) => !command.includes(filename)),
    `package scripts do not invoke retired ${filename}`,
  )
}

console.log(`Remote mutation harness safety: ${passed} passed, 0 failed.`)
