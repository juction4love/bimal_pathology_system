import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');
const csvPath = path.join(rootDir, 'approved-data', 'Bimal_Pathology_Master_Test_Catalogue_1122.csv');
const migrationPath = path.join(rootDir, 'supabase', 'migrations', '00098_master_catalogue_1122_rebuild_and_convergence.sql');

fs.mkdirSync(path.dirname(csvPath), { recursive: true });
fs.mkdirSync(path.dirname(migrationPath), { recursive: true });

console.log('Building normalized Master Test Catalogue 1122 dataset...');
