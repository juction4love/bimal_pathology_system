import fs from 'node:fs';

const content107 = fs.readFileSync('supabase/migrations_legacy_archive/00107_coralab_ace_biochemistry_integration.sql', 'utf8');

// Let's parse all sections in 00107
const sections = content107.split(/--\s*==+\s*\n--\s*GROUP|--\s*([A-Z0-9\s/(),-]+)\s*\((BIO-[0-9]+|PRO-[0-9]+)\)/);

const matches = [];
const regex = /SELECT id INTO v_test_id FROM public\.tests WHERE code = '([^']+)';[\s\S]*?INSERT INTO public\.analyzer_parameter_mappings\s*\([^)]+\)\s*VALUES\s*\(\s*v_analyzer_id\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*v_test_id\s*,\s*v_param_id\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*(FALSE|TRUE)\s*\)/g;

let m;
while ((m = regex.exec(content107)) !== null) {
  matches.push({
    test_code: m[1],
    channel_code: m[2],
    channel_name: m[3],
    measurement_type: m[4],
    analytical_method: m[5],
    unit: m[6],
    differential_type: m[7],
    is_automated_5part_supported: m[8]
  });
}

console.log(`00107 regex matched ${matches.length} mappings:`);
for (const item of matches) {
  console.log(`- ${item.test_code.padEnd(10)} | Channel: ${item.channel_code.padEnd(15)} | Name: ${item.channel_name.padEnd(35)} | Type: ${item.measurement_type}`);
}
