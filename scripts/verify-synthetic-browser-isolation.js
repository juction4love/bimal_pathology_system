import fs from 'node:fs';
const production=[...fs.readdirSync('src',{recursive:true}).filter(x=>String(x).endsWith('.ts')||String(x).endsWith('.tsx')).map(x=>`src/${x}`),'vite.config.ts'];
const forbidden=['synthetic00092Adapter','synthetic-00092-lifecycle','VITE_SYNTHETIC','acceptance.invalid'];
const offenders=[];
for(const file of production){const text=fs.readFileSync(file,'utf8');for(const token of forbidden)if(text.includes(token))offenders.push(`${file}:${token}`);}
if(offenders.length)throw new Error(`Synthetic browser harness leaked into production source: ${offenders.join(', ')}`);
if(fs.existsSync('dist')&&forbidden.some(token=>fs.readdirSync('dist',{recursive:true}).some(file=>{try{return fs.statSync(`dist/${file}`).isFile()&&fs.readFileSync(`dist/${file}`,'utf8').includes(token)}catch{return false}})))throw new Error('Synthetic browser harness leaked into dist');
console.log('Synthetic browser isolation: PASS (test-only adapter absent from src and dist).');
