import fs from 'node:fs';

const migration = fs.readFileSync('supabase/migrations_legacy_archive/00063_server_authoritative_calculation_engine.sql', 'utf8');
const resultEntry = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');
const deferred = fs.readdirSync('supabase/deferred_migrations');
let failures = 0;
function check(value, label) {
  if (value) console.log(`PASS ${label}`);
  else { console.error(`FAIL ${label}`); failures += 1; }
}

for (const role of ['Measured','Calculated','DerivedInterpretation','ReferencePolicy']) {
  check(migration.includes(`'${role}'`), `parameter classification ${role}`);
}
for (const formula of ['CBC_MCV','CBC_MCH','CBC_MCHC','CBC_ANC','CBC_ALC','CBC_AEC','CBC_AMC','CBC_ABC','CBC_NLR']) {
  check(migration.includes(`'${formula}'`), `governed formula ${formula}`);
}
for (const code of ['CALCULATION_NULL_INPUT','CALCULATION_DIVISION_BY_ZERO','CALCULATION_UNIT_MISMATCH','CALCULATION_OVERFLOW','CALCULATION_INVALID_INPUT']) {
  check(migration.includes(code), `stable guard ${code}`);
}
check(migration.includes("calculation_mode IN ('Result','ConsistencyCheck','CandidateDerivedResult')"), 'measured-versus-consistency separation');
check(migration.includes('clinical_calculation_tolerance_versions'), 'approved versioned tolerance model');
check(!/INSERT INTO public\.clinical_calculation_tolerance_versions/i.test(migration), 'no tolerance fabricated');
check(migration.includes("output_parameter_code IN ('RDW','MPV','PDW','P-LCR','PLCR','PT','INR')"), 'forbidden inferred outputs fail closed');
check(migration.includes('report_calculation_provenance'), 'signed report formula provenance frozen separately');
check(migration.includes('RESULT_SERVER_CALCULATION_REQUIRED'), 'browser calculated value rejected');
check(resultEntry.includes(".filter((r) => r.value_type !== 'Calculated' && r.value_type !== 'Heading')"), 'browser excludes calculated values from mutation payload');
check(resultEntry.includes('Server-calculated preview'), 'UI labels browser value as preview');
check(deferred.includes('00070_cloud_sms_dispatch_coordination.sql') && !fs.readdirSync('supabase/migrations').some((name) => /cloud[_-]sms/i.test(name)), 'cloud SMS remains deferred as 00070 outside deployable migrations');

if (failures) process.exit(1);
console.log('Server-authoritative calculation engine static contract PASS');
