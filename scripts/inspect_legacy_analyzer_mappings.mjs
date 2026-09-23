import fs from 'node:fs';

function inspectFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  console.log(`\n================ ${filePath} ================`);
  const regex = /INSERT INTO public\.analyzer_parameter_mappings\s*\(([^)]+)\)\s*VALUES\s*\(([^;]+)\)/gi;
  let match;
  while ((match = regex.exec(content)) !== null) {
    console.log(match[0].slice(0, 300));
  }
}

inspectFile('supabase/migrations_legacy_archive/00107_coralab_ace_biochemistry_integration.sql');
inspectFile('supabase/migrations_legacy_archive/00109_fiacheck_analyzer_integration.sql');
