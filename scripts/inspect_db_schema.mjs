// scripts/inspect_db_schema.mjs
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const sql = `
SELECT jsonb_build_object(
  'tables', (
    SELECT jsonb_agg(table_name ORDER BY table_name)
    FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_type = 'BASE TABLE'
  ),
  'enums', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'enum_name', t.typname,
        'enum_values', (
          SELECT jsonb_agg(e.enumlabel ORDER BY e.enumsortorder)
          FROM pg_enum e
          WHERE e.enumtypid = t.oid
        )
      ) ORDER BY t.typname
    )
    FROM pg_type t
    JOIN pg_namespace n ON n.oid = t.typnamespace
    WHERE n.nspname = 'public' AND t.typtype = 'e'
  ),
  'functions', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'routine_name', routine_name,
        'routine_type', routine_type
      ) ORDER BY routine_name
    )
    FROM information_schema.routines
    WHERE routine_schema = 'public'
  ),
  'triggers', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'trigger_name', trigger_name,
        'event_object_table', event_object_table,
        'action_timing', action_timing,
        'event_manipulation', event_manipulation
      ) ORDER BY event_object_table, trigger_name
    )
    FROM information_schema.triggers
    WHERE trigger_schema = 'public'
  ),
  'policies', (
    SELECT jsonb_agg(
      jsonb_build_object(
        'tablename', tablename,
        'policyname', policyname,
        'permissive', permissive,
        'roles', roles,
        'cmd', cmd
      ) ORDER BY tablename, policyname
    )
    FROM pg_policies
    WHERE schemaname = 'public'
  )
) AS schema_info;
`;

const tmp = path.resolve('tmp_inspect_schema.sql');
writeFileSync(tmp, sql, 'utf8');

const raw = execSync(`npx supabase db query --linked -f "${tmp}"`, { encoding: 'utf8', maxBuffer: 50 * 1024 * 1024 });
const jsonStart = raw.indexOf('{');
const jsonEnd = raw.lastIndexOf('}');
const parsed = JSON.parse(raw.slice(jsonStart, jsonEnd + 1));
const info = (parsed.rows || [])[0]?.schema_info;

console.log('Tables:', info.tables);
console.log('Enums Count:', info.enums.length);
console.log('Functions Count:', info.functions.length);
console.log('Triggers Count:', info.triggers?.length || 0);
console.log('Policies Count:', info.policies?.length || 0);

writeFileSync(path.resolve('scripts/output/live_schema_inventory.json'), JSON.stringify(info, null, 2), 'utf8');
