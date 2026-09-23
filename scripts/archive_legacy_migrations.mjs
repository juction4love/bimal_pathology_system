// scripts/archive_legacy_migrations.mjs
import { readdirSync, renameSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';

const migrationsDir = path.resolve('supabase/migrations');
const archiveDir = path.resolve('supabase/migrations_legacy_archive');

if (!existsSync(archiveDir)) {
  mkdirSync(archiveDir, { recursive: true });
}

const files = readdirSync(migrationsDir);
let movedCount = 0;

for (const f of files) {
  if (f !== '00001_bimal_pathology_clean_baseline.sql' && f.endsWith('.sql')) {
    const src = path.join(migrationsDir, f);
    const dest = path.join(archiveDir, f);
    renameSync(src, dest);
    movedCount++;
  }
}

console.log(`Archived ${movedCount} legacy migrations to supabase/migrations_legacy_archive/`);
console.log('Active migrations directory now contains:');
console.log(readdirSync(migrationsDir));
