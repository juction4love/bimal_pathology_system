/**
 * Test Save Master Test into Live Database
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env.local');

const envContent = fs.readFileSync(envPath, 'utf8');
const envVars = {};

envContent.split('\n').forEach((line) => {
  const trimmed = line.trim();
  if (trimmed && !trimmed.startsWith('#')) {
    const match = trimmed.match(/^([^=]+)=(.*)$/);
    if (match) {
      const key = match[1].trim();
      let value = match[2].trim();
      if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
        value = value.slice(1, -1);
      }
      envVars[key] = value;
    }
  }
});

const supabaseUrl = envVars.VITE_SUPABASE_URL;
const supabaseAnonKey = envVars.VITE_SUPABASE_ANON_KEY;
const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function run() {
  console.log('Testing live tests query...');
  const { data: beforeList, error: beforeErr } = await supabase
    .from('tests')
    .select('id, code, name, department, price_paisa, sample_type, container, is_active');

  if (beforeErr) {
    console.error('Query error:', beforeErr);
    process.exit(1);
  }

  console.log(`Current tests in master catalogue: ${beforeList.length}`);
  beforeList.forEach(t => console.log(`  - [${t.code}] ${t.name} (NPR ${t.price_paisa / 100})`));
}

run();
