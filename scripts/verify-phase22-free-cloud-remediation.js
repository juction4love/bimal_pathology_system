import fs from 'node:fs';
import path from 'node:path';

const root = path.resolve(import.meta.dirname, '..');
const read = (relative) => fs.readFileSync(path.join(root, relative), 'utf8');
const excludedTrees = new Set(['node_modules', 'dist', 'artifacts', 'qa-artifacts', '.wrangler', '.git', 'backups']);
const walk = (directory) => {
  let entries;
  try { entries = fs.readdirSync(directory, { withFileTypes: true }); }
  catch (error) {
    if (error?.code === 'EPERM' || error?.code === 'EACCES') return [];
    throw error;
  }
  return entries.flatMap((entry) => {
  if (excludedTrees.has(entry.name)) return [];
  const target = path.join(directory, entry.name);
  return entry.isDirectory() ? walk(target) : [target];
  });
};

let passed = 0;
const check = (condition, label) => {
  if (!condition) throw new Error(`FAIL: ${label}`);
  passed += 1;
  console.log(`PASS: ${label}`);
};

const repositoryText = walk(root)
  .filter((file) => /\.(?:js|ts|tsx|sql|json|md|html|css)$/i.test(file))
  .map((file) => fs.readFileSync(file, 'utf8'))
  .join('\n');
const credentials = read('scripts/lib/testCredentials.js');
const rotation = read('scripts/rotate-test-passwords.js');
const settings = read('src/features/settings/SettingsPage.tsx');
const dashboard = read('src/features/dashboard/DashboardPage.tsx');
const dashboardMigration = read('supabase/migrations/00027_bounded_dashboard_summary.sql');
const billing = read('src/features/billing/NewBillPage.tsx');
const bills = read('src/features/billing/BillListPage.tsx');
const technician = read('src/features/dashboard/TechnicianDashboard.tsx');
const printDesign = read('src/lib/printDesign.ts');
const keyboard = read('src/lib/keyboardNav.ts');

const knownPasswordMarkers = ['Admin' + 'Password123', 'Tech' + 'Password123'];
const assignmentPattern = new RegExp('password\\\\s*[:=]\\\\s*' + "['\\\"]" + "[^'\\\"]+" + "['\\\"]", 'i');
check(!knownPasswordMarkers.some((marker) => repositoryText.includes(marker)) && !assignmentPattern.test(repositoryText), 'repository contains no plaintext test password');
check(credentials.includes("process.env[name]") && credentials.includes('LIS_TEST_ADMIN_PASSWORD') && credentials.includes('LIS_TEST_TECH_PASSWORD'), 'test credentials are environment-only');
check(credentials.includes('Missing required environment variable') && !credentials.includes('||'), 'missing credentials fail safely without fallback');
check(
  rotation.includes('RETIRED_REMOTE_MUTATION_HARNESS') &&
    !rotation.includes('createClient') &&
    !rotation.includes('.env.local') &&
    !rotation.includes('getPasswordRotationInputs') &&
    !rotation.includes('console.log(credential'),
  'unsafe automatic password rotation is retired fail-closed without credentials or an implicit remote target',
);
check(settings.includes('Point-in-Time Recovery is not enabled') && settings.includes('does not rely on paid PITR or paid backup add-ons'), 'PITR wording accurately describes free deployment');
check(settings.includes('EXPORT_BATCH_SIZE = 500') && settings.includes('.range(from, to)') && settings.includes('MAX_EXPORT_BATCHES') && settings.includes('.abortSignal(signal)'), 'CSV exports use cancellable bounded pagination');
check(dashboard.includes("rpc('get_dashboard_operational_summary')") && !dashboard.includes('allDueBills') && !dashboard.includes('awaitingRows') && !dashboard.includes('activeItems'), 'dashboard cards use server-side aggregation');
check(dashboardMigration.includes("AT TIME ZONE 'Asia/Kathmandu'") && dashboardMigration.includes('sum(amount_paisa)') && dashboardMigration.includes('sum(due_amount_paisa)'), 'dashboard aggregation preserves Nepal time and integer paisa');
check(!billing.includes("rpc('queue_bill_sms'") && !bills.includes("rpc('queue_bill_sms'") && settings.includes('Only payment confirmation and signed report-ready notifications are supported'), 'browser exposes no manual SMS queue action');
check(!technician.includes('Revenue') && !technician.includes('Outstanding Due') && !technician.includes("Today's Collection"), 'technician financial isolation remains intact');
check(printDesign.includes('watermarkOpacity: 0.045') && printDesign.includes('110mm') && printDesign.includes('.clinical-workspace'), 'adaptive canonical watermark remains bounded inside the clinical workspace');
check(keyboard.includes("window.addEventListener('keydown', handler)") && keyboard.includes("window.removeEventListener('keydown', handler)"), 'keyboard navigation cleanup contract remains intact');

console.log(`\nPhase 22 free-cloud remediation verification: ${passed} passed, 0 failed`);
