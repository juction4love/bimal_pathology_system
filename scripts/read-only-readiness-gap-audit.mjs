import fs from 'node:fs';
import { createClient } from '@supabase/supabase-js';

const env = Object.fromEntries(fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)
  .filter((line) => line && !line.startsWith('#'))
  .map((line) => {
    const separator = line.indexOf('=');
    return [line.slice(0, separator), line.slice(separator + 1).replace(/^['"]|['"]$/g, '')];
  }));
const key = fs.readFileSync('.local-secrets/supabase-service-role.txt', 'utf8').trim();
const client = createClient(env.VITE_SUPABASE_URL, key, { auth: { persistSession: false } });

const [{ count: tests, error: testsError }, { count: readinessRows, error: readinessError }, { data: testIds, error: idsError }, { data: readinessIds, error: readinessIdsError }] = await Promise.all([
  client.from('tests').select('*', { count: 'exact', head: true }),
  client.from('catalogue_service_readiness').select('*', { count: 'exact', head: true }),
  client.from('tests').select('id'),
  client.from('catalogue_service_readiness').select('test_id'),
]);
if (testsError || readinessError || idsError || readinessIdsError) throw testsError || readinessError || idsError || readinessIdsError;
const governed = new Set((readinessIds || []).map((row) => row.test_id));
const testsMissingReadiness = (testIds || []).filter((row) => !governed.has(row.id)).length;
console.log(JSON.stringify({ tests, readinessRows, testsMissingReadiness }));
