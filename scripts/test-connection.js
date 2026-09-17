/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Supabase Connection Health Test (ES Module)
 * Safely verifies publishable key connectivity and PostgREST catalogue read.
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createClient } from '@supabase/supabase-js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const envPath = path.resolve(__dirname, '../.env.local');

if (!fs.existsSync(envPath)) {
  console.error('[Error] .env.local file not found.');
  process.exit(1);
}

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

if (!supabaseUrl || !supabaseAnonKey) {
  console.error('[Error] VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY is missing in .env.local');
  process.exit(1);
}

const keyType = supabaseAnonKey.startsWith('sb_publishable_')
  ? 'sb_publishable'
  : supabaseAnonKey.startsWith('eyJ')
  ? 'legacy_jwt'
  : 'unknown';

const projectRefMatch = supabaseUrl.match(/https:\/\/([^.]+)\.supabase\.co/);
const projectRef = projectRefMatch ? projectRefMatch[1] : 'unknown';

console.log(`[Supabase Health Check] Key type: ${keyType}`);
console.log(`[Supabase Health Check] Project ref: ${projectRef}`);
console.log(`[Supabase Health Check] Target Endpoint: ${supabaseUrl}`);

const supabase = createClient(supabaseUrl, supabaseAnonKey);

async function verifyConnection() {
  try {
    // 1. Auth check
    const { data: authData, error: authError } = await supabase.auth.getSession();
    if (authError) {
      console.error('[Supabase Health Check] Auth API error:', authError.message);
      process.exit(1);
    }
    console.log('[Supabase Health Check] Auth session state:', authData.session ? 'Active Session' : 'No Active Session (Unauthenticated - Normal)');

    // 2. PostgREST API Key check on public catalogue table
    const { data: catalogueData, error: catError } = await supabase
      .from('tests')
      .select('id, code, name')
      .limit(3);

    if (catError) {
      console.error('[Supabase Health Check] PostgREST query error:', catError.message);
      process.exit(1);
    }

    console.log(`[Supabase Health Check] PostgREST Tests Query: SUCCESS (${catalogueData.length} records read)`);
    console.log('[Supabase Health Check] Result: SUCCESS - Connected and authenticated to Supabase live endpoint.');
  } catch (err) {
    console.error('[Supabase Health Check] Unexpected error:', err.message);
    process.exit(1);
  }
}

verifyConnection();
