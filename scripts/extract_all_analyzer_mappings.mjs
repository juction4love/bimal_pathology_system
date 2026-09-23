import fs from 'node:fs';

function extractMappings(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const results = [];
  // Find INSERT INTO public.analyzer_parameter_mappings ... VALUES (v_analyzer_id, 'channel_code', 'channel_name', v_test_id, v_param_id, 'measurement_type', 'analytical_method', 'unit', ...)
  const blocks = content.split(/INSERT INTO public\.analyzer_parameter_mappings/i);
  for (let i = 1; i < blocks.length; i++) {
    const block = blocks[i];
    const valMatch = block.match(/VALUES\s*\(\s*v_analyzer_id\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*v_test_id\s*,\s*v_param_id\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*'([^']+)'\s*,\s*(FALSE|TRUE)/i);
    if (valMatch) {
      // Find the preceding SELECT id INTO v_test_id FROM public.tests WHERE code = '...'
      const prev = block.slice(0, block.indexOf('VALUES'));
      const fullPrev = blocks[i-1];
      const testMatch = fullPrev.match(/WHERE\s+code\s*=\s*'([^']+)'/i) || block.match(/WHERE\s+code\s*=\s*'([^']+)'/i);
      results.push({
        channel_code: valMatch[1],
        channel_name: valMatch[2],
        measurement_type: valMatch[3],
        analytical_method: valMatch[4],
        unit: valMatch[5],
        differential_type: valMatch[6],
        is_automated_5part_supported: valMatch[7],
        test_code: testMatch ? testMatch[1] : 'UNKNOWN'
      });
    }
  }
  return results;
}

console.log('--- 00107 CORALAB ACE ---');
const coralab = extractMappings('supabase/migrations_legacy_archive/00107_coralab_ace_biochemistry_integration.sql');
console.log(`Extracted ${coralab.length} mappings`);
console.log(JSON.stringify(coralab, null, 2));

console.log('--- 00109 FIACHECK ---');
const fiacheck = extractMappings('supabase/migrations_legacy_archive/00109_fiacheck_analyzer_integration.sql');
console.log(`Extracted ${fiacheck.length} mappings`);
console.log(JSON.stringify(fiacheck, null, 2));
