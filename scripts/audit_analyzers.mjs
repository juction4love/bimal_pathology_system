import fs from 'node:fs';

const content = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');
const idx = content.indexOf('INSERT INTO public.analyzer_parameter_mappings');
const endIdx = content.indexOf('ON CONFLICT', idx);
const block = content.slice(idx, endIdx);
const lines = block.split('\n').filter(l => l.trim().startsWith('('));
console.log('Total analyzer mapping rows in VALUES:', lines.length);

const byAnalyzer = {};
for (const l of lines) {
  const parts = l.split(',').map(s => s.trim().replace(/^'|'$/g, '').replace(/::UUID$/, ''));
  const id = parts[0];
  const analyzer = parts[1];
  const channel = parts[2];
  const channelName = parts[3];
  const testCode = parts[4];
  const paramCode = parts[5];
  const measurementType = parts[6];

  byAnalyzer[analyzer] = (byAnalyzer[analyzer] || []);
  byAnalyzer[analyzer].push({ channel, channelName, testCode, paramCode, measurementType });
}

console.log('--- Breakdown By Analyzer ---');
let totalPhysicalMappings = 0;
const allUniqueTests = new Set();

for (const [analyzer, mappings] of Object.entries(byAnalyzer)) {
  const uniqueTests = new Set(mappings.map(m => m.testCode));
  for (const t of uniqueTests) allUniqueTests.add(t);
  const physicalOnly = mappings.filter(m => m.measurementType !== 'CALCULATED');
  console.log(`\nAnalyzer: ${analyzer}`);
  console.log(`  Total Channel Mappings: ${mappings.length}`);
  console.log(`  Physical Mappings: ${physicalOnly.length}`);
  console.log(`  Unique Tests (${uniqueTests.size}): ${Array.from(uniqueTests).join(', ')}`);
  for (const m of mappings) {
    console.log(`    Channel: ${m.channel.padEnd(15)} Test: ${m.testCode.padEnd(10)} Param: ${m.paramCode.padEnd(15)} Type: ${m.measurementType}`);
  }
}
