import assert from 'node:assert/strict';
import fs from 'node:fs';

const finalAuthorization=fs.readFileSync('supabase/migrations/00087_production_catalogue_rate_management.sql','utf8');
const permissions=fs.readFileSync('src/types/permissions.ts','utf8');
const userManagement=fs.readFileSync('src/features/admin/UserManagementPage.tsx','utf8');

assert.match(finalAuthorization,/Lab Technician is the only normally assignable role/);
assert.match(finalAuthorization,/Administrator, Verifier and Signatory rows are retained for historical compatibility/);
assert.match(permissions,/ACTIVE_ROLE_CODES = \['lab_technician'\]/);
assert.match(permissions,/VERIFIER:[\s\S]*Legacy compatibility role/);
assert.match(permissions,/SIGNATORY:[\s\S]*Legacy compatibility role/);
assert.doesNotMatch(userManagement,/option value=["'](?:admin|verifier|signatory)/i);
assert.match(userManagement,/role\.code === 'lab_technician'/);

console.log('Compatibility-role non-assignment contract: PASS');
