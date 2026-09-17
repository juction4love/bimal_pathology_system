import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fontkit from '@pdf-lib/fontkit';
import { PDFDocument } from 'pdf-lib';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const latinFont = fs.readFileSync(path.resolve(__dirname, '../cloudflare/report-artifacts/src/assets/noto-sans-latin.ttf'));
const devanagariFont = fs.readFileSync(path.resolve(__dirname, '../cloudflare/report-artifacts/src/assets/noto-sans-devanagari.ttf'));

console.log('Latin font size:', latinFont.length);
console.log('Devanagari font size:', devanagariFont.length);

const pdf = await PDFDocument.create();
pdf.registerFontkit(fontkit);

let t0 = performance.now();
await pdf.embedFont(latinFont, { subset: false });
let t1 = performance.now();
console.log(`Latin embed: ${(t1 - t0).toFixed(2)} ms`);

t0 = performance.now();
await pdf.embedFont(devanagariFont, { subset: false });
t1 = performance.now();
console.log(`Deva embed: ${(t1 - t0).toFixed(2)} ms`);

t0 = performance.now();
const bytes = await pdf.save({ useObjectStreams: false });
t1 = performance.now();
console.log(`PDF save: ${(t1 - t0).toFixed(2)} ms, bytes: ${bytes.length}`);
