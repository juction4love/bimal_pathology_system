/**
 * Verify Catalogue in New Bill Selection
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';
import { getAdminCredential } from './lib/testCredentials.js';

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
  console.log('Testing catalogue selection query with the operator-supplied admin test account...');
  const adminCredential = getAdminCredential();

  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email: adminCredential.email,
    password: adminCredential.password,
  });

  if (authError) {
    console.error('Sign in failed:', authError);
    process.exit(1);
  }

  console.log('Sign in successful. User ID:', authData.user.id);

  const { data: tests, error } = await supabase
    .from('tests')
    .select('id, code, name, department, reporting_type, price_paisa, is_active')
    .eq('is_active', true)
    .order('display_order', { ascending: true })
    .order('department', { ascending: true })
    .order('name', { ascending: true });

  if (error) {
    console.error('Error fetching tests:', error);
    process.exit(1);
  }

  console.log(`Total Active Tests Fetched for Billing: ${tests.length}`);
  const depts = {};
  const types = {};
  tests.forEach((t) => {
    depts[t.department] = (depts[t.department] || 0) + 1;
    types[t.reporting_type] = (types[t.reporting_type] || 0) + 1;
  });

  console.log('Breakdown by Department:', depts);
  console.log('Breakdown by Reporting Type:', types);
  console.log('Sample Tests:');
  tests.slice(0, 10).forEach((t) => {
    console.log(`  - [${t.code}] ${t.name} (${t.department}) - Rate: NPR ${t.price_paisa / 100} [${t.reporting_type}]`);
  });
}

run();
