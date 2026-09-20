// scripts/export-pending-tests.mjs
// Read-only audit and export of all configuration-pending tests

import { writeFileSync, mkdirSync, unlinkSync } from 'node:fs';
import { execSync } from 'node:child_process';
import path from 'node:path';

const outputDir = path.resolve('scripts/output');
mkdirSync(outputDir, { recursive: true });

const querySql = `
WITH test_details AS (
    SELECT 
        t.id,
        t.code,
        t.name,
        COALESCE(c.name, t.department, 'General') AS category,
        t.is_active,
        t.billing_enabled,
        t.clinical_reporting_enabled,
        t.method,
        t.sample_type AS specimen,
        t.test_kind,
        t.reporting_model,
        (
            SELECT COUNT(*) 
            FROM public.parameters p 
            WHERE p.test_id = t.id AND p.is_active = TRUE
        ) AS parameter_count,
        (
            SELECT COUNT(*) 
            FROM public.reference_ranges rr 
            JOIN public.parameters p ON p.id = rr.parameter_id 
            WHERE p.test_id = t.id AND rr.is_active = TRUE AND rr.is_approved = TRUE
        ) AS reference_range_count,
        (
            SELECT COUNT(*) 
            FROM public.analyzer_parameter_mappings apm 
            WHERE apm.test_id = t.id
        ) AS analyzer_mapping_count,
        (
            SELECT json_agg(DISTINCT a.name) 
            FROM public.analyzer_parameter_mappings apm
            JOIN public.analyzers a ON a.id = apm.analyzer_id
            WHERE apm.test_id = t.id
        ) AS analyzer_names,
        (
            SELECT r.price_paisa 
            FROM public.catalogue_rate_versions r 
            WHERE r.test_id = t.id AND r.status = 'Active' AND (r.effective_to IS NULL OR r.effective_to > NOW())
            ORDER BY r.effective_from DESC 
            LIMIT 1
        ) AS active_rate_paisa,
        EXISTS (
            SELECT 1 
            FROM public.catalogue_panel_components cpc 
            WHERE cpc.component_test_id = t.id
        ) AS is_profile_member,
        EXISTS (
            SELECT 1 
            FROM public.catalogue_panel_components cpc 
            WHERE cpc.panel_id = t.id
        ) AS is_profile_container
    FROM public.tests t
    LEFT JOIN public.test_categories c ON c.id = t.category_id
    WHERE t.is_active = TRUE
)
SELECT json_agg(
    json_build_object(
        'code', code,
        'name', name,
        'category', category,
        'is_active', is_active,
        'billing_enabled', billing_enabled,
        'clinical_reporting_enabled', clinical_reporting_enabled,
        'method', method,
        'specimen', specimen,
        'parameter_count', parameter_count,
        'reference_range_count', reference_range_count,
        'analyzer_mapping_count', analyzer_mapping_count,
        'analyzer_names', analyzer_names,
        'active_rate_paisa', active_rate_paisa,
        'is_profile_member', is_profile_member,
        'is_profile_container', is_profile_container
    )
) AS results
FROM test_details;
`;

const tmp = path.resolve('tmp_export_query.sql');
writeFileSync(tmp, querySql, 'utf8');

try {
    const rawOutput = execSync(`npx supabase db query --linked -f "${tmp}"`, {
        encoding: 'utf8',
        stdio: ['pipe', 'pipe', 'pipe'],
        shell: true
    });
    
    const jsonStart = rawOutput.indexOf('{');
    const jsonEnd = rawOutput.lastIndexOf('}');
    if (jsonStart === -1 || jsonEnd === -1) {
        console.error('Failed to parse JSON output:', rawOutput);
        process.exit(1);
    }
    
    const parsed = JSON.parse(rawOutput.slice(jsonStart, jsonEnd + 1));
    const tests = parsed.rows?.[0]?.results || [];
    console.log(`Auditing ${tests.length} active catalogue tests from production database...`);

    let fullyConfiguredCount = 0;
    let partiallyConfiguredCount = 0;
    let _pendingCount = 0;

    let _missingParamsTotal = 0;
    let _missingRangesTotal = 0;
    let _missingMethodsTotal = 0;
    let _missingSpecimensTotal = 0;
    let _missingMappingsTotal = 0;
    let _missingRatesTotal = 0;

    const classifiedTests = tests.map(t => {
        const paramCount = t.parameter_count || 0;
        const rrCount = t.reference_range_count || 0;
        const hasMethod = !!(t.method && t.method.trim().length > 0 && !t.method.toLowerCase().includes('unknown'));
        const hasSpecimen = !!(t.specimen && t.specimen.trim().length > 0 && !t.specimen.toLowerCase().includes('unknown'));
        const hasRate = t.active_rate_paisa !== null && t.active_rate_paisa !== undefined;
        const mappingCount = t.analyzer_mapping_count || 0;

        // Configured source determination
        let configuredSource = 'Unknown';
        if (mappingCount > 0 && t.analyzer_names && t.analyzer_names.length > 0) {
            configuredSource = t.analyzer_names.join('; ');
        } else if (hasMethod && (
            t.method.toLowerCase().includes('manual') ||
            t.method.toLowerCase().includes('westergren') ||
            t.method.toLowerCase().includes('tube') ||
            t.method.toLowerCase().includes('strip') ||
            t.method.toLowerCase().includes('microscopy') ||
            t.method.toLowerCase().includes('rapid') ||
            t.method.toLowerCase().includes('visual') ||
            t.method.toLowerCase().includes('agglutination')
        )) {
            configuredSource = 'Manual';
        } else if (
            (t.name && (t.name.toLowerCase().includes('ratio') || t.name.toLowerCase().includes('calculated') || t.name.toLowerCase().includes('indirect') || t.name.toLowerCase().includes('globulin'))) ||
            (t.code && (t.code === 'BIO-0015' || t.code === 'BIO-0016' || t.code === 'BIO-0019' || t.code === 'BIO-0031'))
        ) {
            configuredSource = 'Calculated';
        }

        const isFullyConfigured = (paramCount > 0 || t.is_profile_container) &&
                                  (rrCount > 0 || t.is_profile_container) &&
                                  hasMethod &&
                                  hasRate;

        const isPartiallyConfigured = !isFullyConfigured && (
            (paramCount > 0 || t.is_profile_container) && (rrCount > 0 || t.is_profile_container)
        );

        let status = 'CONFIGURATION_PENDING';
        if (isFullyConfigured) {
            status = 'CONFIGURED';
            fullyConfiguredCount++;
        } else if (isPartiallyConfigured) {
            status = 'PARTIALLY_CONFIGURED';
            partiallyConfiguredCount++;
        } else {
            status = 'CONFIGURATION_PENDING';
            _pendingCount++;
        }

        // Missing items calculation
        const missing = [];
        if (paramCount === 0 && !t.is_profile_container) {
            missing.push('PARAMETERS_MISSING');
            _missingParamsTotal++;
        }
        if (rrCount === 0 && !t.is_profile_container) {
            missing.push('REFERENCE_RANGE_MISSING');
            _missingRangesTotal++;
        }
        if (!hasMethod) {
            missing.push('METHOD_MISSING');
            _missingMethodsTotal++;
        }
        if (!hasSpecimen) {
            missing.push('SPECIMEN_MISSING');
            _missingSpecimensTotal++;
        }
        // Only mark analyzer mapping missing if not manual / calculated
        if (mappingCount === 0 && configuredSource !== 'Manual' && configuredSource !== 'Calculated') {
            missing.push('ANALYZER_MAPPING_MISSING');
            _missingMappingsTotal++;
        }
        if (!hasRate) {
            missing.push('RATE_MISSING');
            _missingRatesTotal++;
        }

        return {
            ...t,
            parameter_count: paramCount,
            reference_range_count: rrCount,
            active_rate: hasRate ? (t.active_rate_paisa / 100).toFixed(2) : 'RATE_PENDING',
            configured_source: configuredSource,
            configuration_status: status,
            missing_items: missing.join('; ')
        };
    });

    // Sort by CATEGORY then CODE
    classifiedTests.sort((a, b) => {
        const catCompare = a.category.localeCompare(b.category);
        if (catCompare !== 0) return catCompare;
        return a.code.localeCompare(b.code);
    });

    const pendingTests = classifiedTests.filter(t => t.configuration_status === 'CONFIGURATION_PENDING');

    console.log(`\nCatalogue Breakdown:`);
    console.log(`- TOTAL_ACTIVE_TESTS: ${classifiedTests.length}`);
    console.log(`- CONFIGURED: ${fullyConfiguredCount}`);
    console.log(`- PARTIALLY_CONFIGURED: ${partiallyConfiguredCount}`);
    console.log(`- CONFIGURATION_PENDING: ${pendingTests.length}`);

    // Helper to escape CSV field
    const escapeCsv = (val) => {
        if (val === null || val === undefined) return '""';
        const str = String(val).replace(/"/g, '""');
        return `"${str}"`;
    };

    // 1. Export configuration_pending_tests.csv
    const pendingCsvHeader = [
        'code',
        'name',
        'category',
        'parameter_count',
        'reference_range_count',
        'method',
        'specimen',
        'configured_source',
        'analyzer_mapping_count',
        'active_rate',
        'configuration_status',
        'missing_items'
    ].join(',');

    const pendingCsvRows = pendingTests.map(t => [
        escapeCsv(t.code),
        escapeCsv(t.name),
        escapeCsv(t.category),
        t.parameter_count,
        t.reference_range_count,
        escapeCsv(t.method || ''),
        escapeCsv(t.specimen || ''),
        escapeCsv(t.configured_source),
        t.analyzer_mapping_count,
        escapeCsv(t.active_rate),
        escapeCsv(t.configuration_status),
        escapeCsv(t.missing_items)
    ].join(','));

    const pendingCsvContent = [pendingCsvHeader, ...pendingCsvRows].join('\n');
    const pendingCsvPath = path.join(outputDir, 'configuration_pending_tests.csv');
    writeFileSync(pendingCsvPath, pendingCsvContent, 'utf8');
    console.log(`Exported ${pendingTests.length} tests to ${pendingCsvPath}`);

    // 2. Export configuration_pending_summary.csv (grouped by category)
    const categoryCounts = {};
    for (const t of pendingTests) {
        if (!categoryCounts[t.category]) {
            categoryCounts[t.category] = {
                category: t.category,
                pending_count: 0,
                missing_parameters: 0,
                missing_reference_ranges: 0,
                missing_methods: 0,
                missing_specimens: 0,
                missing_mappings: 0,
                missing_rates: 0
            };
        }
        const c = categoryCounts[t.category];
        c.pending_count++;
        if (t.missing_items.includes('PARAMETERS_MISSING')) c.missing_parameters++;
        if (t.missing_items.includes('REFERENCE_RANGE_MISSING')) c.missing_reference_ranges++;
        if (t.missing_items.includes('METHOD_MISSING')) c.missing_methods++;
        if (t.missing_items.includes('SPECIMEN_MISSING')) c.missing_specimens++;
        if (t.missing_items.includes('ANALYZER_MAPPING_MISSING')) c.missing_mappings++;
        if (t.missing_items.includes('RATE_MISSING')) c.missing_rates++;
    }

    const sortedCategories = Object.values(categoryCounts).sort((a, b) => b.pending_count - a.pending_count);

    const summaryCsvHeader = [
        'category',
        'pending_test_count',
        'missing_parameters',
        'missing_reference_ranges',
        'missing_methods',
        'missing_specimens',
        'missing_mappings',
        'missing_rates'
    ].join(',');

    const summaryCsvRows = sortedCategories.map(c => [
        escapeCsv(c.category),
        c.pending_count,
        c.missing_parameters,
        c.missing_reference_ranges,
        c.missing_methods,
        c.missing_specimens,
        c.missing_mappings,
        c.missing_rates
    ].join(','));

    const summaryCsvContent = [summaryCsvHeader, ...summaryCsvRows].join('\n');
    const summaryCsvPath = path.join(outputDir, 'configuration_pending_summary.csv');
    writeFileSync(summaryCsvPath, summaryCsvContent, 'utf8');
    console.log(`Exported category summary to ${summaryCsvPath}`);

    // Print summary stats
    console.log('\nTop 10 Categories with Most Pending Tests:');
    sortedCategories.slice(0, 10).forEach(c => {
        console.log(`- ${c.category}: ${c.pending_count} pending tests (missing ranges: ${c.missing_reference_ranges}, missing rates: ${c.missing_rates})`);
    });

} finally {
    try { unlinkSync(tmp); } catch {}
}
