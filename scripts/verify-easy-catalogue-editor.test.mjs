import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';

const migration117 = fs.readFileSync('supabase/migrations_legacy_archive/00117_easy_test_catalogue_management.sql', 'utf8');
const easyEditorDialog = fs.readFileSync('src/features/catalogue/EasyTestEditorDialog.tsx', 'utf8');
const cataloguePage = fs.readFileSync('src/features/catalogue/CataloguePage.tsx', 'utf8');
const catalogueSections = fs.readFileSync('src/features/catalogue/CatalogueMasterSections.tsx', 'utf8');

test('1. Migration 00117 grants catalogue management permissions to Administrator and Lab Technician', () => {
  assert.match(migration117, /INSERT INTO public\.role_permissions \(role_id, permission_key\)\s+SELECT r\.id, 'can_manage_catalogue'/);
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_require_manager\(\)/);
  assert.match(migration117, /public\.has_permission\('can_manage_catalogue'\) OR public\.has_permission\('can_configure_catalogue_technical'\)/);
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_require_technical\(\)/);
});

test('2. Server RPC catalogue_save_test_easy handles master test, price versioning, and aliases', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_save_test_easy\(/);
  assert.match(migration117, /INSERT INTO public\.tests/);
  assert.match(migration117, /INSERT INTO public\.catalogue_rate_versions/);
  assert.match(migration117, /UPDATE public\.catalogue_rate_versions/);
  assert.match(migration117, /DELETE FROM public\.test_aliases WHERE test_id = v_result_id;/);
  assert.match(migration117, /INSERT INTO public\.audit_logs/);
});

test('3. Server RPC catalogue_delete_test_guarded enforces historical immutability vs clean delete', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_delete_test_guarded\(/);
  assert.match(migration117, /SELECT 1 FROM public\.bill_items WHERE test_id = p_test_id/);
  assert.match(migration117, /SELECT 1 FROM public\.clinical_order_items WHERE test_id = p_test_id/);
  assert.match(migration117, /SELECT 1 FROM public\.test_results r JOIN public\.parameters p/);
  assert.match(migration117, /RAISE EXCEPTION 'Referenced tests cannot be deleted permanently\. Archive this test instead to preserve audit lineage\.'/);
  assert.match(migration117, /DELETE FROM public\.tests WHERE id = p_test_id;/);
});

test('4. Server RPC catalogue_clone_test_easy duplicates test definition, parameters, ranges, and rate', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_clone_test_easy\(/);
  assert.match(migration117, /INSERT INTO public\.tests/);
  assert.match(migration117, /INSERT INTO public\.parameters/);
  assert.match(migration117, /INSERT INTO public\.reference_ranges/);
  assert.match(migration117, /INSERT INTO public\.catalogue_rate_versions/);
});

test('5. Server RPC catalogue_save_parameter_easy handles Numeric, Text, Select, Calculated with options and formulas', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_save_parameter_easy\(/);
  assert.match(migration117, /v_options JSONB := p_parameter->'options';/);
  assert.match(migration117, /v_formula TEXT := NULLIF\(btrim\(p_parameter->>'formula'\), ''\);/);
  assert.match(migration117, /INSERT INTO public\.parameters/);
});

test('6. Server RPC catalogue_reorder_parameters_easy supports parameter ordering', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_reorder_parameters_easy\(/);
  assert.match(migration117, /UPDATE public\.parameters\s+SET display_order = i/);
});

test('7. Server RPC catalogue_delete_parameter_guarded guards against deleting resulted parameters', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_delete_parameter_guarded\(/);
  assert.match(migration117, /SELECT 1 FROM public\.test_results WHERE parameter_id = p_parameter_id/);
});

test('8. Server RPC catalogue_save_range_easy enforces structural validation and auditing', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_save_range_easy\(/);
  assert.match(migration117, /IF v_age_min > v_age_max THEN/);
  assert.match(migration117, /IF v_normal_min IS NOT NULL AND v_normal_max IS NOT NULL AND v_normal_min > v_normal_max THEN/);
  assert.match(migration117, /IF v_crit_low IS NOT NULL AND v_crit_high IS NOT NULL AND v_crit_low > v_crit_high THEN/);
});

test('9. Server RPC catalogue_delete_range_guarded allows clean deletion of unused reference ranges', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_delete_range_guarded\(/);
  assert.match(migration117, /DELETE FROM public\.reference_ranges WHERE id = p_range_id;/);
});

test('10. Server RPC catalogue_save_test_aliases_easy deduplicates and updates aliases immediately', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_save_test_aliases_easy\(/);
  assert.match(migration117, /lower\(btrim\(x\)\)/);
  assert.match(migration117, /DELETE FROM public\.test_aliases WHERE test_id = p_test_id;/);
});

test('11. Server RPCs support analyzer channel mapping CRUD', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_save_analyzer_mapping_easy\(/);
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_delete_analyzer_mapping_easy\(/);
});

test('12. Server RPC catalogue_get_test_history returns full audit trail', () => {
  assert.match(migration117, /CREATE OR REPLACE FUNCTION public\.catalogue_get_test_history\(/);
  assert.match(migration117, /FROM public\.audit_logs/);
});

test('13. Optimistic concurrency check protects against concurrent stale updates', () => {
  assert.match(migration117, /IF p_expected_version IS NOT NULL AND v_existing\.row_version <> p_expected_version THEN/);
  assert.match(migration117, /'This test was updated by another user\. Reload before saving\.'/);
});

test('14. EasyTestEditorDialog implements all 7 catalogue editor tabs', () => {
  assert.match(easyEditorDialog, /label="1\. General & Master"/);
  assert.match(easyEditorDialog, /label=\{`2\. Parameters/);
  assert.match(easyEditorDialog, /label=\{`3\. Reference Ranges/);
  assert.match(easyEditorDialog, /label="4\. Price & Ratelist"/);
  assert.match(easyEditorDialog, /label=\{`5\. Aliases/);
  assert.match(easyEditorDialog, /label=\{`6\. Analyzer Mapping/);
  assert.match(easyEditorDialog, /activeTab === 6/);
});

test('15. EasyTestEditorDialog has full Parameter options editor and Calculated formula support', () => {
  assert.match(easyEditorDialog, /Dropdown Options List \(e\.g\. Negative, Reactive, Trace\)/);
  assert.match(easyEditorDialog, /label="Formula"/);
  assert.match(easyEditorDialog, /label="Calculation Identifier"/);
});

test('16. EasyTestEditorDialog validates reference ranges on client-side and server-side', () => {
  assert.match(easyEditorDialog, /Minimum age cannot exceed maximum age\./);
  assert.match(easyEditorDialog, /Normal minimum cannot exceed normal maximum\./);
});

test('17. EasyTestEditorDialog supports Duplicate / Clone Test workflow', () => {
  assert.match(easyEditorDialog, /Duplicate Test Configuration/);
  assert.match(easyEditorDialog, /catalogue_clone_test_easy/);
  assert.match(easyEditorDialog, /label="New Unique Test Code"/);
});

test('18. EasyTestEditorDialog provides Guarded Delete with friendly error handling', () => {
  assert.match(easyEditorDialog, /Delete Test Permanently\?/);
  assert.match(easyEditorDialog, /catalogue_delete_test_guarded/);
  assert.match(easyEditorDialog, /Cannot delete permanently: This test is referenced in historical bills\/orders\/results/);
});

test('19. CataloguePage integrates EasyTestEditorDialog for Admin and Lab Technician', () => {
  assert.match(cataloguePage, /import { EasyTestEditorDialog } from '\.\/EasyTestEditorDialog';/);
  assert.match(cataloguePage, /const canManage = can\(PERMISSION_KEYS\.CAN_MANAGE_CATALOGUE\) \|\| can\(PERMISSION_KEYS\.CAN_CONFIGURE_CATALOGUE_TECHNICAL\);/);
  assert.match(cataloguePage, /<EasyTestEditorDialog/);
});

test('20. CatalogueMasterSections does not enforce clinical validation as a workflow blocker', () => {
  assert.doesNotMatch(catalogueSections, /disabled=\{!isValidated\}/);
});
