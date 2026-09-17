import { readFileSync } from 'node:fs';

const data = JSON.parse(readFileSync('scripts/full_catalogue_dump.json', 'utf8'));
const tests = data.tests;

function getHighestCode(prefix) {
  const matching = tests
    .filter(t => t.code.startsWith(prefix))
    .map(t => {
      const numPart = t.code.substring(prefix.length);
      const num = parseInt(numPart, 10);
      return { code: t.code, num: isNaN(num) ? 0 : num, name: t.name };
    })
    .sort((a, b) => b.num - a.num);
  return matching.slice(0, 5);
}

console.log('Highest BIO codes:', getHighestCode('BIO-'));
console.log('Highest IMM codes:', getHighestCode('IMM-'));
console.log('Highest SER codes:', getHighestCode('SER-'));
console.log('Highest PRO codes:', getHighestCode('PRO-'));
console.log('Highest END codes:', getHighestCode('END-'));
console.log('Highest TUM codes:', getHighestCode('TUM-'));

console.log('\n--- Scrub Typhus tests ---');
const scrub = tests.filter(t => t.code.includes('SCRUB') || t.name.toLowerCase().includes('scrub'));
console.log(scrub);

console.log('\n--- Interleukin tests ---');
const il = tests.filter(t => t.code.includes('IL') || t.name.toLowerCase().includes('interleukin'));
console.log(il);

console.log('\n--- Cystatin tests ---');
const cys = tests.filter(t => t.code.includes('CYS') || t.name.toLowerCase().includes('cystatin'));
console.log(cys);
