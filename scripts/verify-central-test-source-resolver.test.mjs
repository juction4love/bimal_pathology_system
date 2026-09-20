import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildAnalyzerLookup,
  resolveConfiguredParameterSource,
  resolveConfiguredTestSource,
  resolveConfiguredProfileSource,
  resolveActualResultSource,
} from '../src/lib/testSourceResolver.ts';

test('Central Test Source Resolver Comprehensive Test Suite', async (t) => {

  await t.test('1. Single active analyzer mapping resolves to that analyzer', () => {
    const mappings = [
      {
        parameter_id: 'param-creatinine-001',
        is_active: true,
        analyzers: { name: 'CORALAB ACE', code: 'CORALAB_ACE', lifecycle_status: 'Active' },
      },
    ];

    const lookup = buildAnalyzerLookup(mappings);
    const result = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-creatinine-001',
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'ANALYZER');
    assert.equal(result.label, 'CORALAB ACE');
    assert.deepEqual(result.analyzerNames, ['CORALAB ACE']);
  });

  await t.test('2. Manual parameter resolves to MANUAL', () => {
    const result = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-esr-001',
      method: 'Manual Westergren Method',
      isManual: true,
    });

    assert.equal(result.kind, 'MANUAL');
    assert.equal(result.label, 'Manual');
  });

  await t.test('3. Calculated parameter resolves to CALCULATED', () => {
    const result = resolveConfiguredParameterSource({
      valueType: 'Calculated',
      parameterId: 'param-indirect-bili-001',
    });

    assert.equal(result.kind, 'CALCULATED');
    assert.equal(result.label, 'Calculated');
  });

  await t.test('4. Outsource parameter / test resolves to OUTSOURCE', () => {
    const paramResult = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-biopsy-001',
      isOutsource: true,
    });
    assert.equal(paramResult.kind, 'OUTSOURCE');
    assert.equal(paramResult.label, 'Outsource');

    const testResult = resolveConfiguredTestSource({
      isOutsource: true,
      parameters: [{ id: 'p1', value_type: 'Numeric' }],
    });
    assert.equal(testResult.kind, 'OUTSOURCE');
    assert.equal(testResult.label, 'Outsource');
  });

  await t.test('5. Unknown / missing configuration must NOT default to Manual', () => {
    const result = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-unconfigured-001',
      analyzerLookup: new Map(),
    });

    assert.equal(result.kind, 'UNKNOWN');
    assert.equal(result.label, 'Unknown');
    assert.notEqual(result.kind, 'MANUAL');
  });

  await t.test('6. Inactive analyzer mapping is ignored and resolves to UNKNOWN', () => {
    const mappings = [
      {
        parameter_id: 'param-inactive-001',
        is_active: false,
        analyzers: { name: 'CORALAB ACE', code: 'CORALAB_ACE', lifecycle_status: 'Active' },
      },
      {
        parameter_id: 'param-retired-analyzer-001',
        is_active: true,
        analyzers: { name: 'Old Analyzer', code: 'OLD_01', lifecycle_status: 'Retired' },
      },
    ];

    const lookup = buildAnalyzerLookup(mappings);
    const res1 = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-inactive-001',
      analyzerLookup: lookup,
    });
    const res2 = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-retired-analyzer-001',
      analyzerLookup: lookup,
    });

    assert.equal(res1.kind, 'UNKNOWN');
    assert.equal(res2.kind, 'UNKNOWN');
  });

  await t.test('7. Multiple active analyzer mappings resolve to MULTIPLE_ANALYZERS without map overwrite', () => {
    const mappings = [
      {
        parameter_id: 'param-glucose-001',
        is_active: true,
        analyzers: { name: 'CORALAB ACE', code: 'CORALAB_ACE', lifecycle_status: 'Active' },
      },
      {
        parameter_id: 'param-glucose-001',
        is_active: true,
        analyzers: { name: 'Beckman AU480', code: 'BECKMAN_AU480', lifecycle_status: 'Active' },
      },
    ];

    const lookup = buildAnalyzerLookup(mappings);
    assert.equal(lookup.get('param-glucose-001')?.length, 2);

    const result = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'param-glucose-001',
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'MULTIPLE_ANALYZERS');
    assert.equal(result.label, 'Multiple Analyzers');
    assert.deepEqual(result.analyzerNames, ['Beckman AU480', 'CORALAB ACE']);
  });

  await t.test('8. Test with analyzer + calculated parameters resolves to the analyzer (not Mixed)', () => {
    const lookup = new Map([
      ['p-tbil', ['CORALAB ACE']],
      ['p-dbil', ['CORALAB ACE']],
      ['p-ast', ['CORALAB ACE']],
      ['p-alt', ['CORALAB ACE']],
    ]);

    const result = resolveConfiguredTestSource({
      parameters: [
        { id: 'p-tbil', value_type: 'Numeric' },
        { id: 'p-dbil', value_type: 'Numeric' },
        { id: 'p-ibil', value_type: 'Calculated' },
        { id: 'p-ast', value_type: 'Numeric' },
        { id: 'p-alt', value_type: 'Numeric' },
      ],
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'ANALYZER');
    assert.equal(result.label, 'CORALAB ACE');
    assert.deepEqual(result.analyzerNames, ['CORALAB ACE']);
  });

  await t.test('9. Test with analyzer + manual parameters resolves to MIXED', () => {
    const lookup = new Map([
      ['p-analyzer', ['CounCell 23 Excel']],
    ]);

    const result = resolveConfiguredTestSource({
      parameters: [
        { id: 'p-analyzer', value_type: 'Numeric' },
        { id: 'p-manual', value_type: 'Numeric', method: 'Manual Microscopy' },
      ],
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'MIXED');
    assert.equal(result.label, 'Mixed');
  });

  await t.test('10. Multi-analyzer test resolves to MULTIPLE_ANALYZERS', () => {
    const lookup = new Map([
      ['p-cbc', ['CounCell 23 Excel']],
      ['p-crp', ['FIAcheck']],
    ]);

    const result = resolveConfiguredTestSource({
      parameters: [
        { id: 'p-cbc', value_type: 'Numeric' },
        { id: 'p-crp', value_type: 'Numeric' },
      ],
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'MULTIPLE_ANALYZERS');
    assert.equal(result.label, 'Multiple Analyzers');
    assert.deepEqual(result.analyzerNames, ['CounCell 23 Excel', 'FIAcheck']);
  });

  await t.test('11. Profile with one physical source resolves to that analyzer', () => {
    const lookup = new Map([
      ['p-urea', ['CORALAB ACE']],
      ['p-creat', ['CORALAB ACE']],
      ['p-uric', ['CORALAB ACE']],
    ]);

    const result = resolveConfiguredProfileSource({
      components: [
        {
          parameters: [{ id: 'p-urea', value_type: 'Numeric' }],
        },
        {
          parameters: [{ id: 'p-bun', value_type: 'Calculated' }],
        },
        {
          parameters: [{ id: 'p-creat', value_type: 'Numeric' }],
        },
        {
          parameters: [{ id: 'p-uric', value_type: 'Numeric' }],
        },
      ],
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'ANALYZER');
    assert.equal(result.label, 'CORALAB ACE');
  });

  await t.test('12. Profile with multiple physical sources resolves to MULTIPLE_SOURCES', () => {
    const lookup = new Map([
      ['p-cbc', ['CounCell 23 Excel']],
      ['p-lft', ['CORALAB ACE']],
      ['p-tsh', ['FIAcheck']],
    ]);

    const result = resolveConfiguredProfileSource({
      components: [
        { parameters: [{ id: 'p-cbc', value_type: 'Numeric' }] },
        { parameters: [{ id: 'p-lft', value_type: 'Numeric' }] },
        { parameters: [{ id: 'p-tsh', value_type: 'Numeric' }] },
      ],
      analyzerLookup: lookup,
    });

    assert.equal(result.kind, 'MULTIPLE_SOURCES');
    assert.equal(result.label, 'Multiple Sources');
    assert.deepEqual(result.analyzerNames, ['CORALAB ACE', 'CounCell 23 Excel', 'FIAcheck']);
  });

  await t.test('13. Actual result provenance MANUAL on analyzer-configured parameter', () => {
    const configuredSource = resolveConfiguredParameterSource({
      valueType: 'Numeric',
      parameterId: 'p-creat',
      analyzerLookup: new Map([['p-creat', ['CORALAB ACE']]]),
    });
    const actualProvenance = resolveActualResultSource('MANUAL');

    assert.equal(configuredSource.kind, 'ANALYZER');
    assert.equal(configuredSource.label, 'CORALAB ACE');

    assert.equal(actualProvenance.kind, 'MANUAL');
    assert.equal(actualProvenance.label, 'Manual');
  });

  await t.test('14. Actual result provenance ANALYZER / IMPORT / CALCULATED / UNKNOWN', () => {
    assert.equal(resolveActualResultSource('ANALYZER').kind, 'ANALYZER');
    assert.equal(resolveActualResultSource('IMPORT').kind, 'IMPORT');
    assert.equal(resolveActualResultSource('CALCULATED').kind, 'CALCULATED');
    assert.equal(resolveActualResultSource(null).kind, 'UNKNOWN');
    assert.equal(resolveActualResultSource(undefined).kind, 'UNKNOWN');
  });

  await t.test('15. Known verified cases resolution check', () => {
    const masterLookup = new Map([
      ['p-cbc-wbc', ['CounCell 23 Excel']],
      ['p-creat', ['CORALAB ACE']],
      ['p-na', ['CORALAB ACE']],
      ['p-alt', ['CORALAB ACE']],
      ['p-tsh', ['FIAcheck']],
      ['p-vitd', ['FIAcheck']],
      ['p-ferritin', ['FIAcheck']],
    ]);

    // CBC -> CounCell 23 Excel
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-cbc-wbc', analyzerLookup: masterLookup }).label,
      'CounCell 23 Excel'
    );
    // Creatinine -> CORALAB ACE
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-creat', analyzerLookup: masterLookup }).label,
      'CORALAB ACE'
    );
    // Sodium -> CORALAB ACE
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-na', analyzerLookup: masterLookup }).label,
      'CORALAB ACE'
    );
    // ALT -> CORALAB ACE
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-alt', analyzerLookup: masterLookup }).label,
      'CORALAB ACE'
    );
    // TSH -> FIAcheck
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-tsh', analyzerLookup: masterLookup }).label,
      'FIAcheck'
    );
    // Vitamin D -> FIAcheck
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-vitd', analyzerLookup: masterLookup }).label,
      'FIAcheck'
    );
    // Ferritin -> FIAcheck
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-ferritin', analyzerLookup: masterLookup }).label,
      'FIAcheck'
    );
    // ESR -> Manual
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Numeric', parameterId: 'p-esr', method: 'Westergren', isManual: true }).label,
      'Manual'
    );
    // Indirect Bilirubin -> Calculated
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Calculated', parameterId: 'p-ibil' }).label,
      'Calculated'
    );
    // Globulin -> Calculated
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Calculated', parameterId: 'p-glob' }).label,
      'Calculated'
    );
    // A/G Ratio -> Calculated
    assert.equal(
      resolveConfiguredParameterSource({ valueType: 'Calculated', parameterId: 'p-ag' }).label,
      'Calculated'
    );
  });
});
