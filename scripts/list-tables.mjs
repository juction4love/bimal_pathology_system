import { execSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';

function queryDb(sql) {
  const tmpFile = path.resolve('tmp_table_query.sql');
  fs.writeFileSync(tmpFile, sql, 'utf8');
  try {
    const raw = execSync(`npx supabase db query --linked --output json -f "${tmpFile}"`, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe'],
      shell: true,
    });
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    const jsonStart = raw.indexOf('[');
    const jsonStartObj = raw.indexOf('{');
    const start = jsonStart !== -1 && (jsonStartObj === -1 || jsonStart < jsonStartObj) ? jsonStart : jsonStartObj;
    if (start === -1) return [];
    const parsed = JSON.parse(raw.slice(start));
    if (Array.isArray(parsed) && parsed[0]?.rows) return parsed[0].rows;
    if (Array.isArray(parsed)) return parsed;
    return [parsed];
  } catch (err) {
    if (fs.existsSync(tmpFile)) fs.unlinkSync(tmpFile);
    throw err;
  }
}

const tables = queryDb(`
  SELECT table_name 
  FROM information_schema.tables 
  WHERE table_schema = 'public' 
  ORDER BY table_name;
`);

console.log('Tables in public schema:');
console.table(tables);
