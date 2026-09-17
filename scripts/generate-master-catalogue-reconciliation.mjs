import fs from 'node:fs'
import path from 'node:path'

const [sourcePath, testsPath, parametersPath, packagesPath, outputPath] = process.argv.slice(2)
if (![sourcePath, testsPath, parametersPath, packagesPath, outputPath].every(Boolean)) {
  throw new Error('usage: node generate-master-catalogue-reconciliation.mjs source tests parameters packages output')
}

const clean = (value = '') => value.replace(/\u2013|\u2014/g, '-').replace(/&/g, ' and ').replace(/[^a-z0-9]+/gi, ' ').trim().toLowerCase()
const compact = (value = '') => clean(value).replace(/\b(serum|total|test|examination|value)\b/g, ' ').replace(/\s+/g, ' ').trim()
const csv = (value) => `"${String(value ?? '').replaceAll('"', '""')}"`
const parseTsv = (file) => {
  const rows = fs.readFileSync(file, 'utf8').replace(/^\uFEFF/, '').trim().split(/\r?\n/).map((line) => line.split('\t'))
  return { header: rows[0], rows: rows.slice(1) }
}

const source = fs.readFileSync(sourcePath, 'utf8').replace(/^\uFEFF/, '')
const sourcePattern = /(?:^|\r?\n)\s*(\d+)\.\s*\r?\n([^\r\n]+)\r?\n\s*(Single parameter|Multi parameter nested|Multi parameter|Document)[ ]*\t([^\t\r\n]*)\t([^\t\r\n]*)/g
const entries = [...source.matchAll(sourcePattern)].map((m) => ({
  number: Number(m[1]), name: m[2].trim(), type: m[3].trim(), alias: m[4].trim(), department: m[5].trim(),
}))
if (entries.length !== 256 || entries.some((entry, index) => entry.number !== index + 1)) {
  throw new Error(`source parse failed: expected sequential 256 rows, got ${entries.length}`)
}

const testRows = parseTsv(testsPath).rows.map((r) => ({
  id: r[0], code: r[1], name: r[2], shortName: r[3], aliases: r[4] ? r[4].split(';;') : [],
  category: r[5], department: r[6], kind: r[7], reportingType: r[8], lifecycle: r[9],
  billing: r[10] === 't', clinical: r[11] === 't', collection: r[12] === 't', workflow: r[13],
}))
const parameterRows = parseTsv(parametersPath).rows.map((r) => ({ id: r[0], testId: r[1], code: r[2], name: r[3], valueType: r[4], lifecycle: r[5] }))
const _packageRows = parseTsv(packagesPath).rows.filter((r) => r[0]).map((r) => ({ packageId: r[0], packageCode: r[1], packageName: r[2], aliases: r[3] ? r[3].split(';;') : [], testId: r[4], testCode: r[5], testName: r[6] }))

const identityTokens = (test) => [test.code, test.name, test.shortName, ...test.aliases].filter(Boolean)
const manualTestCodes = new Map([
  [1, ['HB']], [2, ['TLC']], [3, ['DLC']], [7, ['PLT']], [8, ['AEC']], [12, ['PBS']], [16, ['RBC_COUNT']], [17, ['PCV']], [22, ['RETIC_COUNT']], [24, ['PT_INR']], [26, ['TLC']], [42, ['TLC']], [43, ['DLC']],
  [44, ['PHOSPHORUS']], [45, ['CREATININE']], [46, ['UREA']], [47, ['FBS']], [48, ['PPBS']], [52, ['URIC_ACID']], [53, ['ALT']], [54, ['AST']], [57, ['ALP']], [58, ['CHOL_TOTAL']], [59, ['TRIGLYCERIDES']], [60, ['HDL_CHOL']], [61, ['LDL_CHOL']], [67, ['SODIUM']], [71, ['POTASSIUM']], [73, ['CALCIUM']], [74, ['CALCIUM']], [76, ['RBS']], [77, ['CHLORIDE']], [78, ['AMYLASE']], [79, ['HBA1C']], [81, ['GLOBULIN']], [82, ['LIPASE']], [83, ['FERRITIN']], [85, ['CK_MB']], [87, ['VITAMIN_D']], [88, ['VITAMIN_B12']], [89, ['GGT']], [109, ['CK_TOTAL']], [110, ['CK_MB']], [124, ['IRON']], [125, ['TIBC']], [129, ['EGFR']], [135, ['MAGNESIUM']], [147, ['LDH']],
])
const exactCandidates = (entry) => testRows.filter((test) => {
  if ((manualTestCodes.get(entry.number) ?? []).includes(test.code)) return true
  const sourceTokens = [entry.name, entry.alias].filter(Boolean).flatMap((v) => [clean(v), compact(v)])
  return identityTokens(test).some((v) => sourceTokens.includes(clean(v)) || sourceTokens.includes(compact(v)))
})
const componentCandidates = (entry) => parameterRows.filter((parameter) => {
  const tokens = [clean(entry.name), compact(entry.name), clean(entry.alias), compact(entry.alias)].filter(Boolean)
  return tokens.includes(clean(parameter.code)) || tokens.includes(clean(parameter.name)) || tokens.includes(compact(parameter.name))
})

const canonicalDepartment = (entry) => {
  const n = clean(`${entry.name} ${entry.alias}`)
  if (/hcv rna|brac|genetic|pcr|viral load/.test(n)) return 'Molecular Diagnostics'
  if (/fnac|pap smear/.test(n)) return 'Cytology'
  if (/culture|gram|acid fast|afb|fungal scraping/.test(n)) return 'Microbiology'
  if (/urine|stool|semen|fluid examination|occult blood/.test(n)) return 'Clinical Pathology'
  if (/tsh|thyroxine|triiodothyronine|ft3|ft4|prolactin|lutein|follicle stimulating|estradiol|progesterone|testosterone|cortisol|insulin|amh|mullerian|parathyroid|calcitonin|dhea|thyroglobulin/.test(n)) return 'Endocrinology / Hormone'
  if (/malaria|filaria|procalcitonin/.test(n)) return 'Serology & Immunology'
  if (/troponin|nt pro bnp|myoglobin/.test(n)) return 'Clinical Biochemistry / Immunoassay'
  return ({ Haematology: 'Hematology', Biochemistry: 'Clinical Biochemistry', 'Serology & Immunology': 'Serology & Immunology', 'Clinical Pathology': 'Clinical Pathology', Cytology: 'Cytology', Microbiology: 'Microbiology', Endocrinology: 'Endocrinology / Hormone', Others: 'Serology / Tumor Markers', Miscellaneous: 'Miscellaneous' })[entry.department] ?? entry.department
}

const specialistWorkflow = (entry) => {
  const n = clean(`${entry.name} ${entry.alias}`)
  if (/culture and sensitivity/.test(n)) return 'MicrobiologyCulture'
  if (/fnac|pap smear/.test(n)) return 'CytologyCase'
  if (/hcv rna|brac|genetic/.test(n)) return 'MolecularAssay'
  if (entry.type === 'Multi parameter nested' || /ascitic fluid examination|fluid examination/.test(n)) return 'StructuredClinicalPathology'
  if (/gram s stain|acid fast bacilli|skin smear for afb|fungal scraping smear/.test(n)) return 'StructuredMicroscopy'
  return null
}
const reportingWorkflow = (entry) => specialistWorkflow(entry) ?? ({ 'Single parameter': 'RoutineSingleParameter', 'Multi parameter': 'RoutineMultiParameter/Profile', 'Multi parameter nested': 'StructuredClinicalPathology', Document: 'Document/StructuredNarrativeReview' })[entry.type]

const manualCanonical = new Map([
  [1, 'HB — Hemoglobin'], [2, 'TLC — Total Leukocyte Count'], [3, 'DLC — Differential Leukocyte Count'],
  [5, 'ESR — method-specific Westergren service/configuration'], [6, 'ESR — method-specific Wintrobe service/configuration'],
  [16, 'RBC_COUNT — Red Blood Cell Count'], [17, 'PCV — Packed Cell Volume / Hematocrit'], [18, 'MCV standalone identity'], [19, 'MCH standalone identity'], [20, 'MCHC standalone identity'],
  [24, 'PT_INR — PT/INR (blocked pending authoritative configuration)'], [25, 'APTT — Activated Partial Thromboplastin Time'],
  [26, 'TLC — WBC Count alias candidate'], [42, 'TLC — TC alias candidate'], [43, 'DLC — duplicate source row requiring type review'],
  [63, 'LDL/HDL ratio — calculation candidate'], [64, 'Total Cholesterol/HDL ratio — calculation candidate'], [65, 'TG/HDL ratio — calculation candidate'],
  [69, 'BUN/Creatinine ratio — calculation candidate'], [70, 'Urea/Creatinine ratio — calculation candidate'], [80, 'Albumin/Globulin ratio — calculation candidate'],
  [85, 'CK_MB — CK-MB'], [110, 'CK_MB — CK-MB'], [126, 'Transferrin Saturation — calculation candidate'], [127, 'Non-HDL Cholesterol — calculation candidate'], [129, 'EGFR — calculation candidate'], [130, 'eGFR Category — derived interpretation'], [137, 'AST/ALT ratio — calculation candidate'],
  [140, 'Procalcitonin — reconcile with source #41'], [170, 'Dengue NS1 — distinct assay identity'], [171, 'Dengue card panel — method/panel identity'], [195, 'Dengue IgG — distinct assay identity'], [196, 'Dengue IgM — distinct assay identity'], [197, 'Dengue IgG/IgM panel'],
  [172, 'BETA_HCG — Beta-hCG'], [180, 'Anti-HAV — antibody identity requiring assay review'], [181, 'HAV IgM'], [203, 'Anti-HAV panel/identity requiring review'], [204, 'HAV IgM qualitative'], [205, 'HAV IgG qualitative'],
  [210, 'HCV RNA Quantitative — molecular assay'], [213, 'BRCA1/BRCA2 — molecular/genetic assay'], [223, 'Semen Analysis structured service'], [225, 'Stool R/E structured service'], [228, 'Urine R/E structured service'], [229, 'Fluid Examination structured service'], [235, 'FNAC cytology case'], [236, 'PAP Smear cytology case'], [242, 'Culture & Sensitivity microbiology case'], [243, 'Pus Culture & Sensitivity microbiology case'],
])

const knownConflict = (entry) => {
  const n = clean(`${entry.name} ${entry.alias}`)
  const reasons = []
  if ([2, 26, 42].includes(entry.number)) reasons.push('TLC/WBC/TC equivalence and duplicate billable identity')
  if ([3, 4, 35, 39, 40, 43].includes(entry.number)) reasons.push('DLC variant/duplicate and reporting-shape conflict')
  if ([5, 6].includes(entry.number)) reasons.push('Method-specific ESR must not be collapsed into generic ESR without approval')
  if ([7, 21, 27, 29, 37].includes(entry.number)) reasons.push('Platelet count versus platelet indices/profile boundary')
  if ([1, 2, 3, 7, 16, 17, 18, 19, 20, 28, 30, 36, 37, 38].includes(entry.number)) reasons.push('CBC component versus standalone billable service boundary')
  if (/cpk mb|ck mb/.test(n)) reasons.push('CPK-MB/CK-MB duplicate candidate')
  if (/procalcitonin/.test(n)) reasons.push('Duplicate Procalcitonin source identities across departments')
  if (/dengue/.test(n)) reasons.push('Dengue antigen/antibody/method variants are clinically and commercially distinct')
  if (/hav/.test(n)) reasons.push('HAV total/IgM/IgG and qualitative/panel variants require assay-level review')
  if (/beta.*hcg|chorionic/.test(n)) reasons.push('Multiple existing Beta-hCG identities/departments')
  if (/lipid profile/.test(n)) reasons.push('Existing LIPID versus LIPID_PROFILE conflict')
  if (/renal function|kidney function|rft|kft/.test(n)) reasons.push('Existing RFT versus KFT conflict')
  if (canonicalDepartment(entry) !== ({ Haematology: 'Hematology', Biochemistry: 'Clinical Biochemistry', 'Serology & Immunology': 'Serology & Immunology', 'Clinical Pathology': 'Clinical Pathology', Cytology: 'Cytology', Microbiology: 'Microbiology', Endocrinology: 'Endocrinology / Hormone', Others: 'Serology / Tumor Markers', Miscellaneous: 'Miscellaneous' })[entry.department]) reasons.push('Source department differs from proposed canonical discipline')
  return [...new Set(reasons)].join('; ')
}

const sourceDuplicateKeys = new Map()
for (const entry of entries) {
  const key = compact(entry.alias || entry.name)
  sourceDuplicateKeys.set(key, (sourceDuplicateKeys.get(key) ?? 0) + 1)
}

const results = entries.map((entry) => {
  const exact = exactCandidates(entry)
  const components = componentCandidates(entry)
  const specialist = specialistWorkflow(entry)
  const conflict = knownConflict(entry)
  let matchType
  if (specialist && !exact.length) matchType = 'SpecialistWorkflowRequired'
  else if (exact.length > 1) matchType = 'ConflictRequiresReview'
  else if (exact.length === 1) {
    const t = exact[0]
    const directName = clean(entry.name) === clean(t.name) || compact(entry.name) === compact(t.name)
    matchType = directName ? 'ExactExisting' : 'AliasExisting'
  } else if (components.length) matchType = 'ProfileComponentExisting'
  else matchType = specialist ? 'SpecialistWorkflowRequired' : 'MissingDraftCandidate'
  if (sourceDuplicateKeys.get(compact(entry.alias || entry.name)) > 1 && matchType === 'MissingDraftCandidate') matchType = 'DuplicateCandidate'
  const forcedReview = new Set([4, 5, 6, 26, 35, 36, 37, 38, 39, 40, 41, 42, 43, 63, 64, 65, 69, 70, 73, 74, 80, 85, 110, 126, 127, 129, 130, 137, 140, 170, 171, 172, 180, 181, 195, 196, 197, 203, 204, 205])
  if (forcedReview.has(entry.number) || exact.length > 1) matchType = 'ConflictRequiresReview'
  const matches = exact.map((t) => `${t.code} — ${t.name} [${t.lifecycle}/${t.workflow}; clinical=${t.clinical}]`)
  if (!matches.length && components.length) {
    for (const p of components.slice(0, 5)) {
      const t = testRows.find((candidate) => candidate.id === p.testId)
      matches.push(`${t?.code ?? p.testId}.${p.code} — ${p.name}`)
    }
  }
  const canonical = manualCanonical.get(entry.number) ?? (exact.length === 1 ? `${exact[0].code} — ${exact[0].name}` : entry.name)
  const calc = /ratio|egfr|non-hdl|transferrin saturation|sgot\/sgpt/i.test(entry.name) ? 'CalculationDefinitionRequired; ' : ''
  const next = matchType === 'ExactExisting' || matchType === 'AliasExisting'
    ? `${calc}confirm semantic/method equivalence; preserve existing identity; clinical configuration reviewed separately`
    : matchType === 'ProfileComponentExisting'
      ? `${calc}decide whether standalone billing identity is required; do not duplicate profile parameter automatically`
      : matchType === 'SpecialistWorkflowRequired'
        ? `create/complete dedicated ${reportingWorkflow(entry)} workflow before enabling reporting`
        : `${calc}review conflict/identity, then create Draft with billing/reporting disabled only if approved`
  return { ...entry, canonicalDepartment: canonicalDepartment(entry), matches: matches.join(' | '), matchType, canonical, workflow: reportingWorkflow(entry), conflict, next }
})

fs.mkdirSync(path.dirname(outputPath), { recursive: true })
const columns = ['Source #', 'Source Name', 'Source Alias', 'Source Type', 'Source Department', 'Canonical Department', 'Existing LIS Match', 'Match Type', 'Canonical Proposed Identity', 'Workflow', 'Conflict', 'Required Next Action']
const csvLines = [columns.map(csv).join(',')]
for (const r of results) csvLines.push([r.number, r.name, r.alias, r.type, r.department, r.canonicalDepartment, r.matches, r.matchType, r.canonical, r.workflow, r.conflict, r.next].map(csv).join(','))
fs.writeFileSync(outputPath, `${csvLines.join('\r\n')}\r\n`)

const counts = Object.entries(results.reduce((a, r) => ((a[r.matchType] = (a[r.matchType] ?? 0) + 1), a), {})).sort()
const departmentCounts = Object.entries(results.reduce((a, r) => ((a[r.department] = (a[r.department] ?? 0) + 1), a), {}))
const summaryPath = outputPath.replace(/\.csv$/i, '-summary.md')
const row = (r) => `| ${r.number} | ${r.name.replaceAll('|', '\\|')} | ${r.alias || '—'} | ${r.matchType} | ${r.matches.replaceAll('|', '\\|') || '—'} | ${r.canonical.replaceAll('|', '\\|')} | ${r.workflow} | ${r.conflict.replaceAll('|', '\\|') || '—'} |`
const section = (title, predicate) => `## ${title}\n\n| # | Source identity | Alias | Classification | Existing LIS match | Proposed identity | Workflow | Conflict |\n|---:|---|---|---|---|---|---|---|\n${results.filter(predicate).map(row).join('\n') || '| — | — | — | — | — | — | — | — |'}\n`
const summary = `# Bimal Pathology LIS — 256-test master reconciliation\n\nGenerated from the operator-provided identity reference and a read-only production catalogue export at migration head 00060. Source values are identity/provenance evidence only and do not authorize ranges, units, formulas, methods, analyzers, assays, activation, or reporting.\n\n- Parsed source rows: **${results.length}**\n- Source departments: ${departmentCounts.map(([k, v]) => `${k} ${v}`).join('; ')}\n- Classification totals: ${counts.map(([k, v]) => `${k} ${v}`).join('; ')}\n\n${section('Hematology reconciliation', (r) => r.department === 'Haematology')}\n${section('Biochemistry reconciliation', (r) => r.department === 'Biochemistry')}\n## Reporting-type mapping\n\n| Source type | Prospective LIS mapping | Safety boundary |\n|---|---|---|\n| Single parameter | Routine single typed parameter | Draft until configured and validated |\n| Multi parameter | Routine multi-parameter test/profile | Confirm profile-versus-standalone identity and parameter structure |\n| Multi parameter nested | Structured Clinical Pathology | Use ordered headings and typed parameters; no forced flat result |\n| Document | Document/structured narrative review | Cytology/culture/molecular entries use dedicated workflows |\n\n## Department normalization\n\nThe CSV retains the source department and adds a separate proposed canonical department. Hormones/immunoassays are routed by clinical discipline for review; no source department is overwritten.\n\n## Implementation batches\n\n1. Hematology identity decisions and Draft-only additions.\n2. Biochemistry identity/profile conflicts and calculation-definition candidates.\n3. Endocrinology/Hormone identities.\n4. Serology/Immunology assay and qualitative-value governance.\n5. Structured Clinical Pathology services.\n6. Dedicated Microbiology culture/microscopy workflows.\n7. Dedicated Cytology cases and sections.\n8. Molecular/Genetics assays and versions.\n\nEvery approved new identity must start Draft with billing and clinical reporting disabled. Clinical ranges, critical limits, formulas, methods, analyzers and assay configuration require separate authoritative approval.\n`
fs.writeFileSync(summaryPath, summary)

console.log(JSON.stringify({ rows: results.length, counts: Object.fromEntries(counts), outputPath, summaryPath }, null, 2))
