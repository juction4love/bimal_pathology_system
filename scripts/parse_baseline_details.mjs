import fs from 'node:fs';
import path from 'node:path';

// 1. Load Live Audit Dump
const live = JSON.parse(fs.readFileSync('scripts/output/live_audit_dump.json', 'utf8'));

// 2. Parse Baseline SQL
const baselineSql = fs.readFileSync('supabase/migrations/00001_bimal_pathology_clean_baseline.sql', 'utf8');

console.log('=== LIVE AUDIT MASTER SUMMARY ===');
console.log(`Live Tests: ${live.tests.length} (Active: ${live.tests.filter(t => t.is_active).length})`);
console.log(`Live Parameters: ${live.parameters.length} (Active: ${live.parameters.filter(p => p.is_active).length})`);
console.log(`Live Panel Components: ${live.panel_components.length}`);
console.log(`Live Reference Ranges: ${live.reference_ranges.length} (Active: ${live.reference_ranges.filter(r => r.is_active).length})`);
console.log(`Live Analyzers: ${live.analyzers.length}`);
console.log(`Live Analyzer Mappings: ${live.analyzer_mappings.length}`);
console.log(`Live Active Rates: ${live.rates.length}`);

// Let's write helper to extract inserts from baseline SQL
// Tests
const testMatches = [...baselineSql.matchAll(/INSERT INTO public\.tests\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Test insert statements: ${testMatches.length}`);

// Parameters
const paramMatches = [...baselineSql.matchAll(/INSERT INTO public\.parameters\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Parameter insert statements: ${paramMatches.length}`);

// Panel Components
const panelMatches = [...baselineSql.matchAll(/INSERT INTO public\.catalogue_panel_components\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Panel Component insert statements: ${panelMatches.length}`);

// Reference Ranges
const rrMatches = [...baselineSql.matchAll(/INSERT INTO public\.reference_ranges\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Reference Range insert statements: ${rrMatches.length}`);

// Analyzers
const anMatches = [...baselineSql.matchAll(/INSERT INTO public\.analyzers\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Analyzer insert statements: ${anMatches.length}`);

// Analyzer Mappings
const apmMatches = [...baselineSql.matchAll(/INSERT INTO public\.analyzer_parameter_mappings\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Analyzer Mapping insert statements: ${apmMatches.length}`);

// Rates
const rateMatches = [...baselineSql.matchAll(/INSERT INTO public\.catalogue_rate_versions\s*\(([^)]+)\)\s*VALUES\s*([\s\S]*?);/g)];
console.log(`Baseline Rate insert statements: ${rateMatches.length}`);
