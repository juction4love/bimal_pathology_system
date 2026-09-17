import fs from 'node:fs'
import { createHash } from 'node:crypto'

const [matrixPath, outputPath] = process.argv.slice(2)
if (!matrixPath || !outputPath) throw new Error('usage: node generate-master-catalogue-implementation.mjs <reconciliation.csv> <migration.sql>')

const parseCsv = (text) => {
  const rows = []; let row = [], value = '', quoted = false
  for (let i = 0; i < text.length; i++) {
    const c = text[i]
    if (c === '"') { if (quoted && text[i + 1] === '"') { value += '"'; i++ } else quoted = !quoted }
    else if (c === ',' && !quoted) { row.push(value); value = '' }
    else if ((c === '\n' || c === '\r') && !quoted) {
      if (c === '\r' && text[i + 1] === '\n') i++
      row.push(value); value = ''; if (row.some(Boolean)) rows.push(row); row = []
    } else value += c
  }
  if (value || row.length) { row.push(value); rows.push(row) }
  const header = rows.shift()
  return rows.map((values) => Object.fromEntries(header.map((key, index) => [key, values[index] ?? ''])))
}
const q = (value) => `'${String(value ?? '').replaceAll("'", "''")}'`
const arr = (values) => `ARRAY[${values.map(q).join(',')}]::TEXT[]`
const slug = (value) => value.normalize('NFKD').replace(/[^A-Za-z0-9]+/g, '_').replace(/^_|_$/g, '').toUpperCase().slice(0, 48)
const rows = parseCsv(fs.readFileSync(matrixPath, 'utf8'))
if (rows.length !== 256 || rows.some((row, index) => Number(row['Source #']) !== index + 1)) throw new Error('Reconciliation matrix is not an exact sequential 256-row source')

const overrides = new Map(Object.entries({
  4:['CanonicalProfile','ABS_DLC','Absolute Differential Leukocyte Count','Absolute DLC','Profile'],
  5:['DraftNewIdentity','ESR_WESTERGREN','Erythrocyte Sedimentation Rate, Westergren','ESR-W','NumericSingle'],
  6:['DraftNewIdentity','ESR_WINTROBE','Erythrocyte Sedimentation Rate, Wintrobe','ESR-WI','NumericSingle'],
  26:['AliasOnly','TLC'],35:['DraftNewIdentity','LEUKEMIA_DLC','Leukemia Differential Assessment','Leukemia DLC','MixedTyped'],
  36:['CanonicalProfile','RBC_INDICES','Red Blood Cell Indices','RBC Indices','Profile'],
  37:['CanonicalProfile','PLATELET_INDICES','Platelet Indices','Platelet Indices','Profile'],
  38:['ProfileComponentOnly','CBC'],39:['DraftNewIdentity','DLC_3PART','Three-Part Differential Leukocyte Count','3-Part DLC','NumericMultiParameter'],
  40:['AliasOnly','LEUKEMIA_DLC'],41:['DraftNewIdentity','PROCALCITONIN','Procalcitonin','PCT','NumericSingle'],42:['AliasOnly','TLC'],43:['AliasOnly','DLC'],
  63:['ProfileComponentOnly','LIPID_PROFILE'],64:['ProfileComponentOnly','LIPID_PROFILE'],65:['ProfileComponentOnly','LIPID_PROFILE'],
  66:['ConflictNeedsOperatorDecision','LIPID_PROFILE'],69:['ProfileComponentOnly','KFT'],70:['ProfileComponentOnly','KFT'],
  73:['CanonicalStandaloneTest','CALCIUM'],74:['AliasOnly','CALCIUM'],80:['ProfileComponentOnly','LFT'],
  85:['CanonicalStandaloneTest','CK_MB'],110:['AliasOnly','CK_MB'],126:['ProfileComponentOnly','IRON_PROFILE'],127:['ProfileComponentOnly','LIPID_PROFILE'],
  129:['ProfileComponentOnly','KFT'],130:['ProfileComponentOnly','KFT'],137:['ProfileComponentOnly','LFT'],140:['AliasOnly','PROCALCITONIN'],
  154:['DraftNewIdentity','WIDAL_SLIDE','Widal Test, Slide Method','Widal Slide','MixedTyped'],155:['DuplicateDoNotCreate','WIDAL_SLIDE'],
  170:['CanonicalStandaloneTest','DENGUE_NS1'],171:['CanonicalProfile','DENGUE_PANEL','Dengue Antigen and Antibody Panel','Dengue Panel','Profile'],
  172:['ConflictNeedsOperatorDecision','BETA_HCG'],180:['DraftNewIdentity','HAV_TOTAL_AB','Hepatitis A Total Antibody','Anti-HAV Total','Qualitative'],
  181:['DraftNewIdentity','HAV_IGM','Hepatitis A IgM Antibody','HAV IgM','Qualitative'],195:['CanonicalStandaloneTest','DENGUE_IGG'],
  196:['CanonicalStandaloneTest','DENGUE_IGM'],197:['CanonicalProfile','DENGUE_IGM_IGG_PANEL','Dengue IgM and IgG Panel','Dengue IgM/IgG','Profile'],
  198:['DraftNewIdentity','CORTISOL_SERUM','Serum Cortisol','Cortisol','NumericSingle'],203:['ConflictNeedsOperatorDecision','HAV_PANEL'],
  204:['AliasOnly','HAV_IGM'],205:['DraftNewIdentity','HAV_IGG','Hepatitis A IgG Antibody','HAV IgG','Qualitative'],
  212:['ConflictNeedsOperatorDecision','CORTISOL_SERUM'],231:['DraftNewIdentity','CORTISOL_URINE','Urine Cortisol','Urine Cortisol','NumericSingle'],
}))

const existingCode = (row) => row['Existing LIS Match'].match(/(?:^|\| )([A-Z][A-Z0-9 _-]*) —/)?.[1]?.trim() || null
const specialistModel = (workflow) => workflow === 'MicrobiologyCulture' ? 'MicrobiologyWorkflow' : workflow === 'CytologyCase' ? 'CytologyWorkflow' : workflow === 'MolecularAssay' ? 'MolecularWorkflow' : workflow === 'StructuredClinicalPathology' ? 'StructuredNested' : workflow === 'StructuredMicroscopy' ? 'MixedTyped' : 'NarrativeDocument'
const sourceModel = (row) => {
  const text = `${row['Source Name']} ${row['Source Alias']}`.toLowerCase()
  if (row.Workflow.includes('Structured')) return 'StructuredNested'
  if (row.Workflow.includes('Document')) return 'NarrativeDocument'
  if (/antigen|antibody|hbsag|anti-hcv|hiv|vdrl|rpr|tpha|malaria|scrub typhus|pregnancy|occult blood|rapid/.test(text) && row['Source Type'] === 'Single parameter') return 'Qualitative'
  return row['Source Type'] === 'Multi parameter' ? 'NumericMultiParameter' : 'NumericSingle'
}
const aliasesByCode = new Map()
const identities = new Map()
const source = []
const conflicts = []
const usedCodes = new Map()

for (const row of rows) {
  const number = Number(row['Source #']); const override = overrides.get(String(number))
  let disposition, code, name = row['Canonical Proposed Identity'].replace(/^[A-Z0-9 _-]+ — /, '') || row['Source Name'], shortName = row['Source Alias'] || '', model
  if (override) [disposition, code, name = name, shortName = shortName, model] = override
  else {
    const match = row['Match Type']; code = existingCode(row)
    disposition = match === 'ExactExisting' ? 'CanonicalStandaloneTest' : match === 'AliasExisting' ? 'AliasOnly' : match === 'ProfileComponentExisting' ? 'ProfileComponentOnly' : match === 'DuplicateCandidate' ? 'DuplicateDoNotCreate' : match === 'SpecialistWorkflowRequired' ? 'SpecialistWorkflow' : match === 'ConflictRequiresReview' ? 'ConflictNeedsOperatorDecision' : 'DraftNewIdentity'
    model = disposition === 'SpecialistWorkflow' ? specialistModel(row.Workflow) : sourceModel(row)
    if (!code && ['DraftNewIdentity','SpecialistWorkflow','CanonicalProfile'].includes(disposition)) code = slug(row['Source Alias'] || row['Source Name'])
  }
  if (code && ['DraftNewIdentity','SpecialistWorkflow','CanonicalProfile'].includes(disposition)) {
    const original = code; let suffix = 2
    while (usedCodes.has(code) && usedCodes.get(code) !== name) code = `${original.slice(0,44)}_${suffix++}`
    usedCodes.set(code, name)
    identities.set(code, { code, name, shortName, department: row['Canonical Department'], model, specialist: disposition === 'SpecialistWorkflow', sourceType: row['Source Type'], sourceWorkflow: row.Workflow })
  }
  if (code && row['Source Alias']) aliasesByCode.set(code, new Set([...(aliasesByCode.get(code) ?? []), row['Source Alias']]))
  if (code && disposition === 'AliasOnly') aliasesByCode.set(code, new Set([...(aliasesByCode.get(code) ?? []), row['Source Name'], row['Source Alias']].filter(Boolean)))
  if (disposition === 'ConflictNeedsOperatorDecision') conflicts.push({ key: `TM256-${String(number).padStart(3,'0')}`, numbers: [number], title: row.Conflict || row['Source Name'], code, recommendation: row['Required Next Action'] })
  source.push({ number, row, disposition, code, model: model || sourceModel(row) })
}

const sql = []
sql.push(`-- Bimal Pathology complete 256-test identity master.\n-- Identity/profile structure only: no prices, ranges, formulas, methods, analyzers or clinical activation.\n`)
sql.push(`CREATE TYPE public.catalogue_reporting_model_enum AS ENUM ('NumericSingle','NumericMultiParameter','Qualitative','MixedTyped','StructuredNested','NarrativeDocument','Calculated','Profile','MicrobiologyWorkflow','CytologyWorkflow','MolecularWorkflow');`)
sql.push(`CREATE TYPE public.catalogue_source_disposition_enum AS ENUM ('CanonicalStandaloneTest','CanonicalProfile','ProfileComponentOnly','AliasOnly','DuplicateDoNotCreate','DraftNewIdentity','SpecialistWorkflow','ConflictNeedsOperatorDecision','RetireCandidate');`)
sql.push(`ALTER TABLE public.tests ADD COLUMN reporting_model public.catalogue_reporting_model_enum DEFAULT 'NumericSingle';`)
sql.push(`UPDATE public.tests t SET reporting_model=CASE WHEN t.test_kind='Profile' THEN 'Profile'::public.catalogue_reporting_model_enum WHEN t.workflow_type='MicrobiologyCulture' THEN 'MicrobiologyWorkflow'::public.catalogue_reporting_model_enum WHEN t.workflow_type='Cytology' THEN 'CytologyWorkflow'::public.catalogue_reporting_model_enum WHEN t.workflow_type='Molecular' THEN 'MolecularWorkflow'::public.catalogue_reporting_model_enum WHEN t.reporting_type='NoReporting' THEN 'NarrativeDocument'::public.catalogue_reporting_model_enum WHEN EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.value_type='Select') THEN 'Qualitative'::public.catalogue_reporting_model_enum WHEN (SELECT count(*) FROM public.parameters p WHERE p.test_id=t.id AND p.is_active)>1 THEN 'NumericMultiParameter'::public.catalogue_reporting_model_enum ELSE 'NumericSingle'::public.catalogue_reporting_model_enum END;`)
sql.push(`ALTER TABLE public.tests ALTER COLUMN reporting_model SET NOT NULL;`)
sql.push(`CREATE TABLE public.catalogue_master_sources(id UUID PRIMARY KEY,source_name TEXT NOT NULL,source_version TEXT NOT NULL,source_sha256 CHAR(64) NOT NULL,source_row_count INT NOT NULL CHECK(source_row_count=256),imported_at TIMESTAMPTZ NOT NULL DEFAULT now(),UNIQUE(source_name,source_version));`)
sql.push(`CREATE TABLE public.catalogue_identity_conflicts(id UUID PRIMARY KEY DEFAULT gen_random_uuid(),conflict_key TEXT NOT NULL UNIQUE,title TEXT NOT NULL,source_numbers INT[] NOT NULL,canonical_code TEXT,status TEXT NOT NULL DEFAULT 'Open' CHECK(status IN('Open','Resolved','Rejected')),recommendation TEXT NOT NULL,resolution JSONB,created_at TIMESTAMPTZ NOT NULL DEFAULT now(),resolved_at TIMESTAMPTZ,resolved_by UUID REFERENCES auth.users(id));`)
sql.push(`CREATE TABLE public.catalogue_master_source_rows(source_id UUID NOT NULL REFERENCES public.catalogue_master_sources(id),source_number INT NOT NULL CHECK(source_number BETWEEN 1 AND 256),source_name TEXT NOT NULL,source_alias TEXT,source_type TEXT NOT NULL,source_department TEXT NOT NULL,canonical_department TEXT NOT NULL,disposition public.catalogue_source_disposition_enum NOT NULL,reporting_model public.catalogue_reporting_model_enum NOT NULL,canonical_code TEXT,canonical_test_id UUID REFERENCES public.tests(id),canonical_parameter_id UUID REFERENCES public.parameters(id),conflict_id UUID REFERENCES public.catalogue_identity_conflicts(id),provenance JSONB NOT NULL,PRIMARY KEY(source_id,source_number));`)
sql.push(`CREATE TABLE public.catalogue_profile_components(profile_test_id UUID NOT NULL REFERENCES public.tests(id) ON DELETE RESTRICT,component_test_id UUID REFERENCES public.tests(id) ON DELETE RESTRICT,component_parameter_id UUID REFERENCES public.parameters(id) ON DELETE RESTRICT,component_role TEXT NOT NULL CHECK(component_role IN('Measured','Calculated','Qualitative','ComponentService')),display_order INT NOT NULL,is_required BOOLEAN NOT NULL DEFAULT true,source_numbers INT[] NOT NULL DEFAULT '{}',PRIMARY KEY(profile_test_id,display_order),CHECK((component_test_id IS NOT NULL)::INT+(component_parameter_id IS NOT NULL)::INT=1),UNIQUE(profile_test_id,component_test_id),UNIQUE(profile_test_id,component_parameter_id));`)
sql.push(`ALTER TABLE public.catalogue_master_sources ENABLE ROW LEVEL SECURITY; ALTER TABLE public.catalogue_master_source_rows ENABLE ROW LEVEL SECURITY; ALTER TABLE public.catalogue_identity_conflicts ENABLE ROW LEVEL SECURITY; ALTER TABLE public.catalogue_profile_components ENABLE ROW LEVEL SECURITY; REVOKE ALL ON public.catalogue_master_sources,public.catalogue_master_source_rows,public.catalogue_identity_conflicts,public.catalogue_profile_components FROM PUBLIC,anon,authenticated; GRANT SELECT ON public.catalogue_master_sources,public.catalogue_master_source_rows,public.catalogue_identity_conflicts,public.catalogue_profile_components TO authenticated; CREATE POLICY catalogue_master_manager_read ON public.catalogue_master_sources FOR SELECT TO authenticated USING(public.has_permission('can_manage_catalogue')); CREATE POLICY catalogue_rows_manager_read ON public.catalogue_master_source_rows FOR SELECT TO authenticated USING(public.has_permission('can_manage_catalogue')); CREATE POLICY catalogue_conflicts_manager_read ON public.catalogue_identity_conflicts FOR SELECT TO authenticated USING(public.has_permission('can_manage_catalogue')); CREATE POLICY catalogue_profile_components_read ON public.catalogue_profile_components FOR SELECT TO authenticated USING(public.is_active_user());`)
sql.push(`CREATE OR REPLACE FUNCTION public.reject_catalogue_master_evidence_mutation() RETURNS TRIGGER LANGUAGE plpgsql SET search_path=public,pg_temp AS $$ BEGIN RAISE EXCEPTION 'Catalogue master source evidence is immutable.' USING ERRCODE='55000'; END $$; CREATE TRIGGER catalogue_master_sources_immutable BEFORE UPDATE OR DELETE ON public.catalogue_master_sources FOR EACH ROW EXECUTE FUNCTION public.reject_catalogue_master_evidence_mutation(); CREATE TRIGGER catalogue_master_rows_immutable BEFORE UPDATE OR DELETE ON public.catalogue_master_source_rows FOR EACH ROW EXECUTE FUNCTION public.reject_catalogue_master_evidence_mutation();`)
sql.push(`INSERT INTO public.catalogue_master_sources(id,source_name,source_version,source_sha256,source_row_count) VALUES('25600000-0000-0000-0000-000000000001','Bimal Pathology operator-supplied 256-test master','TM256-V1','0ebdd7b041ff1a417fd96186992dd1b034ded5eb00a6dd192a9b2b251519e05e',256);`)
sql.push(`INSERT INTO public.test_categories(code,name,lifecycle_status,display_order) VALUES ('CLINICAL_PATHOLOGY','Clinical Pathology','Active',45),('CYTOLOGY','Cytology','Draft',65) ON CONFLICT(code) DO NOTHING;`)

for (const identity of identities.values()) {
  const categoryCode = identity.department === 'Hematology' ? 'HEMATOLOGY' : identity.department.includes('Biochemistry') ? 'BIOCHEMISTRY' : identity.department.includes('Endocrinology') ? 'ENDOCRINOLOGY' : identity.department.includes('Serology') ? 'SEROLOGY' : identity.department === 'Clinical Pathology' ? 'CLINICAL_PATHOLOGY' : identity.department === 'Microbiology' ? 'MICROBIOLOGY' : identity.department === 'Cytology' ? 'CYTOLOGY' : identity.department.includes('Molecular') ? 'MOLECULAR' : 'GENERAL'
  const workflow = identity.model === 'MicrobiologyWorkflow' ? 'MicrobiologyCulture' : identity.sourceWorkflow === 'StructuredMicroscopy' ? 'MicrobiologyMicroscopy' : identity.model === 'CytologyWorkflow' ? 'Cytology' : identity.model === 'MolecularWorkflow' ? 'Molecular' : identity.specialist || ['StructuredNested','NarrativeDocument'].includes(identity.model) ? 'NoClinicalReport' : 'Routine'
  const reporting = workflow === 'Routine' ? 'InHouse' : 'NoReporting'
  const kind = identity.model === 'Profile' ? 'Profile' : 'Individual'
  sql.push(`INSERT INTO public.tests(code,name,short_name,department,category,category_id,test_kind,reporting_type,price_paisa,price_configured,pricing_policy,sample_type,container,is_active,lifecycle_status,clinical_configuration_status,workflow_supported,billing_enabled,clinical_reporting_enabled,collection_required,workflow_type,reporting_model,configuration_notes,search_aliases) SELECT ${q(identity.code)},${q(identity.name)},${identity.shortName ? q(identity.shortName) : 'NULL'},${q(identity.department)},c.name,c.id,${q(kind)}::public.catalogue_test_kind_enum,${q(reporting)}::public.reporting_type_enum,0,false,'PricePending','','',false,'Draft','Requires Clinical Validation',${identity.specialist ? 'false' : 'true'},false,false,false,${q(workflow)}::public.clinical_workflow_type_enum,${q(identity.model)}::public.catalogue_reporting_model_enum,'TM256 identity only; clinical configuration, price and activation require separate approval.',${arr([...aliasesByCode.get(identity.code) ?? []].map((x)=>x.toLowerCase()))} FROM public.test_categories c WHERE c.code=${q(categoryCode)} AND NOT EXISTS(SELECT 1 FROM public.tests t WHERE t.code=${q(identity.code)});`)
}

const knownAliases = { TLC:['WBC_COUNT','WBC','TC','Total Leukocyte Count','White Blood Cell Count'],PCV:['HCT','Hematocrit','Packed Cell Volume'],HB:['Hb','Hemoglobin'],RBC_COUNT:['RBC','Red Blood Cell Count'],PLT:['Platelet','Platelet Count'],CK_MB:['CK-MB','CPK-MB'],LIPID_PROFILE:['LIPID','LP','Lipid Panel'],KFT:['RFT','Renal Function Test','Kidney Function Profile'],BETA_HCG:['Beta HCG','Beta-hCG','β-hCG'] }
for (const [code, aliases] of Object.entries(knownAliases)) sql.push(`UPDATE public.tests SET search_aliases=ARRAY(SELECT DISTINCT lower(btrim(x)) FROM unnest(search_aliases||${arr(aliases)})x WHERE btrim(x)<>'') WHERE code=${q(code)};`)
for (const [code, aliases] of aliasesByCode) sql.push(`UPDATE public.tests SET search_aliases=ARRAY(SELECT DISTINCT lower(btrim(x)) FROM unnest(search_aliases||${arr([...aliases])})x WHERE btrim(x)<>'') WHERE code=${q(code)};`)
sql.push(`UPDATE public.tests SET test_kind='Profile',reporting_model='Profile' WHERE code IN('CBC','DLC','LFT','KFT','LIPID_PROFILE','THYROID_PROFILE','THYROID_ECLIA','ABS_DLC','RBC_INDICES','PLATELET_INDICES','DENGUE_PANEL','DENGUE_IGM_IGG_PANEL');`)
sql.push(`UPDATE public.tests SET billing_enabled=false,clinical_reporting_enabled=false,clinical_configuration_status='Requires Clinical Validation',configuration_notes=concat_ws(' ',configuration_notes,'TM256 convergence: structurally incomplete legacy identity held non-operational pending canonical resolution.') WHERE code IN('AFP','BETA HCG','LIPID','RFT') AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=tests.id AND p.is_active AND p.lifecycle_status='Active');`)
sql.push(`UPDATE public.tests SET clinical_reporting_enabled=false,clinical_configuration_status=CASE WHEN clinical_configuration_status='Configured' THEN 'Requires Clinical Validation'::public.clinical_configuration_status_enum ELSE clinical_configuration_status END,configuration_notes=concat_ws(' ',configuration_notes,'TM256 safety convergence: clinical reporting is disabled until an active parameter structure exists.') WHERE clinical_reporting_enabled AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=tests.id AND p.is_active AND p.lifecycle_status='Active');`)
sql.push(`UPDATE public.tests t SET category_id=c.id,category=c.name FROM public.test_categories c WHERE c.code='CLINICAL_PATHOLOGY' AND t.code IN('STOOL_OB','STOOL_RE','URINE_RE') AND t.category_id IS NULL;`)

for (const profile of [
  ['IRON_PROFILE','Iron Profile','Iron Profile','Clinical Biochemistry','BIOCHEMISTRY'],
  ['COAG_PROFILE','Coagulation Profile','Coagulation','Hematology','HEMATOLOGY'],
  ['HAV_PANEL','Hepatitis A Antibody Panel','HAV Panel','Serology & Immunology','HEPATITIS_HIV'],
]) sql.push(`INSERT INTO public.tests(code,name,short_name,department,category,category_id,test_kind,reporting_type,price_paisa,price_configured,pricing_policy,sample_type,container,is_active,lifecycle_status,clinical_configuration_status,workflow_supported,billing_enabled,clinical_reporting_enabled,collection_required,workflow_type,reporting_model,configuration_notes) SELECT ${q(profile[0])},${q(profile[1])},${q(profile[2])},${q(profile[3])},c.name,c.id,'Profile','InHouse',0,false,'PricePending','','',false,'Draft','Requires Clinical Validation',true,false,false,false,'Routine','Profile','TM256 structural profile; composition and clinical configuration require approval.' FROM public.test_categories c WHERE c.code=${q(profile[4])} AND NOT EXISTS(SELECT 1 FROM public.tests WHERE code=${q(profile[0])});`)

sql.push(`INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required) SELECT t.id,v.code,v.name,v.value_type::public.parameter_value_type_enum,NULL,v.ord,true,false,'Draft','Requires Clinical Validation',true,true,true FROM public.tests t CROSS JOIN (VALUES ('ANC','Absolute Neutrophil Count','Calculated',1),('ALC','Absolute Lymphocyte Count','Calculated',2),('AMC','Absolute Monocyte Count','Calculated',3),('AEC','Absolute Eosinophil Count','Calculated',4),('ABC','Absolute Basophil Count','Calculated',5))v(code,name,value_type,ord) WHERE t.code='ABS_DLC' AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.code=v.code);`)
sql.push(`INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required) SELECT t.id,v.code,v.name,'Numeric',NULL,v.ord,true,false,'Draft','Requires Clinical Validation',true,true,true FROM public.tests t CROSS JOIN (VALUES ('MPV','Mean Platelet Volume',2),('PDW','Platelet Distribution Width',3),('P_LCR','Platelet Large Cell Ratio',4))v(code,name,ord) WHERE t.code='PLATELET_INDICES' AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.code=v.code);`)
sql.push(`INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required) SELECT t.id,v.code,v.name,v.value_type::public.parameter_value_type_enum,NULL,v.ord,true,false,'Draft','Requires Clinical Validation',true,true,true FROM public.tests t CROSS JOIN (VALUES ('UIBC','Unsaturated Iron Binding Capacity','Numeric',3),('TRANSFERRIN_SAT','Transferrin Saturation','Calculated',4))v(code,name,value_type,ord) WHERE t.code='IRON_PROFILE' AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.code=v.code);`)

const componentSql = (profile, componentTest, parameterTest, parameter, role, order, sourceNumbers=[]) => `INSERT INTO public.catalogue_profile_components(profile_test_id,component_test_id,component_parameter_id,component_role,display_order,source_numbers) SELECT pr.id,ct.id,cp.id,${q(role)},${order},ARRAY[${sourceNumbers.join(',')}]::INT[] FROM public.tests pr LEFT JOIN public.tests ct ON ct.code=${componentTest ? q(componentTest) : 'NULL'} LEFT JOIN public.tests pt ON pt.code=${parameterTest ? q(parameterTest) : 'NULL'} LEFT JOIN public.parameters cp ON cp.test_id=pt.id AND cp.code=${parameter ? q(parameter) : 'NULL'} WHERE pr.code=${q(profile)} AND ((ct.id IS NOT NULL AND cp.id IS NULL) OR (ct.id IS NULL AND cp.id IS NOT NULL)) ON CONFLICT DO NOTHING;`
const components = []
for (const [code,role,order,src] of [['HB','ComponentService',1,1],['TLC','ComponentService',2,2],['NEUT','Measured',3,3],['LYMPH','Measured',4,3],['EOSIN','Measured',5,3],['MONO','Measured',6,3],['BASO','Measured',7,3],['RBC','ComponentService',8,16],['PCV','ComponentService',9,17],['MCV','Calculated',10,18],['MCH','Calculated',11,19],['MCHC','Calculated',12,20],['RDW','Measured',13,28],['PLT','ComponentService',14,7]]) components.push(componentSql('CBC',null,'CBC',code,role,order,[src]))
for (const [code,order] of [['NEUT_VAL',1],['LYMPH_VAL',2],['EOSIN_VAL',3],['MONO_VAL',4],['BASO_VAL',5]]) components.push(componentSql('DLC',null,'DLC',code,'Measured',order,[3]))
for (const [code,order] of [['ANC',1],['ALC',2],['AMC',3],['AEC',4],['ABC',5]]) components.push(componentSql('ABS_DLC',null,'ABS_DLC',code,'Calculated',order,[4]))
for (const [code,role,order] of [['RBC','ComponentService',1],['PCV','ComponentService',2],['MCV','Calculated',3],['MCH','Calculated',4],['MCHC','Calculated',5],['RDW','Measured',6]]) components.push(componentSql('RBC_INDICES',null,'CBC',code,role,order,[36]))
components.push(componentSql('PLATELET_INDICES','PLT',null,null,'ComponentService',1,[37])); for (const [code,order] of [['MPV',2],['PDW',3],['P_LCR',4]]) components.push(componentSql('PLATELET_INDICES',null,'PLATELET_INDICES',code,'Measured',order,[37]))
for (const [code,role,order] of [['TBIL','ComponentService',1],['DBIL','ComponentService',2],['IBIL','Calculated',3],['SGOT','ComponentService',4],['SGPT','ComponentService',5],['ALP','ComponentService',6],['TP','ComponentService',7],['ALB','ComponentService',8],['GLOB','Calculated',9],['AG_RATIO','Calculated',10]]) components.push(componentSql('LFT',null,'LFT',code,role,order,[]))
for (const [code,order] of [['UREA',1],['CREAT',2],['NA',3],['K',4],['URIC',5]]) components.push(componentSql('KFT',null,'KFT',code,'ComponentService',order,[]))
for (const [code,role,order] of [['CHOL','ComponentService',1],['TRIG','ComponentService',2],['HDL','ComponentService',3],['LDL','Measured',4],['VLDL','Calculated',5]]) components.push(componentSql('LIPID_PROFILE',null,'LIPID_PROFILE',code,role,order,[]))
for (const [code,order] of [['T3',1],['T4',2],['TSH',3]]) components.push(componentSql('THYROID_PROFILE',null,'THYROID_PROFILE',code,'ComponentService',order,[]))
for (const [code,order] of [['FT3',1],['FT4',2],['TSH',3]]) components.push(componentSql('THYROID_ECLIA',null,'THYROID_ECLIA',code,'ComponentService',order,[]))
for (const [code,order] of [['IRON',1],['TIBC',2],['FERRITIN',5]]) components.push(componentSql('IRON_PROFILE',code,null,null,'ComponentService',order,[])); components.push(componentSql('IRON_PROFILE',null,'IRON_PROFILE','UIBC','Measured',3,[]),componentSql('IRON_PROFILE',null,'IRON_PROFILE','TRANSFERRIN_SAT','Calculated',4,[]))
for (const [code,order] of [['PT_INR',1],['APTT',2],['BT_CT',3]]) components.push(componentSql('COAG_PROFILE',code,null,null,'ComponentService',order,[]))
for (const [code,order] of [['DENGUE_NS1',1],['DENGUE_IGM',2],['DENGUE_IGG',3]]) components.push(componentSql('DENGUE_PANEL',code,null,null,'Qualitative',order,[170,196,195])); for (const [code,order] of [['DENGUE_IGM',1],['DENGUE_IGG',2]]) components.push(componentSql('DENGUE_IGM_IGG_PANEL',code,null,null,'Qualitative',order,[197]))
for (const [code,order] of [['HAV_TOTAL_AB',1],['HAV_IGM',2],['HAV_IGG',3]]) components.push(componentSql('HAV_PANEL',code,null,null,'Qualitative',order,[180,181,205]))
sql.push(...components)

for (const conflict of [
 ['IDENTITY-LIPID','LIPID versus LIPID_PROFILE canonical survivor',[66],'LIPID_PROFILE','Use structured LIPID_PROFILE; retain legacy LIPID only until compatibility cutover.'],
 ['IDENTITY-RFT-KFT','RFT versus KFT canonical survivor',[],'KFT','Use structured KFT; preserve RFT alias until compatibility cutover.'],
 ['IDENTITY-BETA-HCG','Beta-hCG quantitative/qualitative identity boundary',[172],'BETA_HCG','Retain numeric BETA_HCG as quantitative candidate; keep qualitative pregnancy testing separate.'],
 ['PROFILE-HAV','Anti-HAV total versus multi-parameter panel',[180,203,204,205],'HAV_PANEL','Technical authority must approve exact panel composition.'],
 ['PROFILE-CORTISOL','Single serum cortisol versus timed multi-parameter cortisol',[198,212],'CORTISOL_SERUM','Technical authority must define timing/profile composition.'],
 ['PROFILE-WIDAL','Widal slide document versus multi-parameter structure',[154,155],'WIDAL_SLIDE','Technical authority must approve one structured reporting model.'],
]) sql.push(`INSERT INTO public.catalogue_identity_conflicts(conflict_key,title,source_numbers,canonical_code,recommendation) VALUES(${q(conflict[0])},${q(conflict[1])},ARRAY[${conflict[2].join(',')}]::INT[],${q(conflict[3])},${q(conflict[4])}) ON CONFLICT(conflict_key) DO NOTHING;`)

for (const conflict of conflicts) sql.push(`INSERT INTO public.catalogue_identity_conflicts(conflict_key,title,source_numbers,canonical_code,recommendation) VALUES(${q(conflict.key)},${q(conflict.title)},ARRAY[${conflict.numbers.join(',')}],${conflict.code ? q(conflict.code) : 'NULL'},${q(conflict.recommendation)}) ON CONFLICT(conflict_key) DO NOTHING;`)
for (const item of source) {
  const r = item.row
  sql.push(`INSERT INTO public.catalogue_master_source_rows(source_id,source_number,source_name,source_alias,source_type,source_department,canonical_department,disposition,reporting_model,canonical_code,canonical_test_id,canonical_parameter_id,conflict_id,provenance) SELECT '25600000-0000-0000-0000-000000000001',${item.number},${q(r['Source Name'])},${r['Source Alias'] ? q(r['Source Alias']) : 'NULL'},${q(r['Source Type'])},${q(r['Source Department'])},${q(r['Canonical Department'])},${q(item.disposition)}::public.catalogue_source_disposition_enum,${q(item.model)}::public.catalogue_reporting_model_enum,${item.code ? q(item.code) : 'NULL'},t.id,p.id,c.id,jsonb_build_object('existing_lis_match',${q(r['Existing LIS Match'])},'reconciliation_match_type',${q(r['Match Type'])},'workflow',${q(r.Workflow)},'conflict',${q(r.Conflict)},'required_next_action',${q(r['Required Next Action'])}) FROM (SELECT 1) seed LEFT JOIN public.tests t ON t.code=${item.code ? q(item.code) : 'NULL'} LEFT JOIN LATERAL(SELECT px.id FROM public.parameters px WHERE px.test_id=t.id AND (lower(px.name)=lower(${q(r['Source Name'])}) OR lower(px.code)=lower(${q(r['Source Alias'] || r['Source Name'])})) ORDER BY px.display_order LIMIT 1)p ON true LEFT JOIN public.catalogue_identity_conflicts c ON c.conflict_key=${q(`TM256-${String(item.number).padStart(3,'0')}`)};`)
}

sql.push(`CREATE OR REPLACE FUNCTION public.catalogue_expand_profile(p_profile_test_id UUID) RETURNS TABLE(component_test_id UUID,component_parameter_id UUID,component_role TEXT,display_order INT,is_required BOOLEAN) LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public,pg_temp AS $$ SELECT c.component_test_id,c.component_parameter_id,c.component_role,c.display_order,c.is_required FROM public.catalogue_profile_components c JOIN public.tests p ON p.id=c.profile_test_id WHERE c.profile_test_id=p_profile_test_id AND p.test_kind='Profile' ORDER BY c.display_order $$; REVOKE ALL ON FUNCTION public.catalogue_expand_profile(UUID) FROM PUBLIC,anon; GRANT EXECUTE ON FUNCTION public.catalogue_expand_profile(UUID) TO authenticated;`)
sql.push(`DO $$ DECLARE n INT; BEGIN SELECT count(*) INTO n FROM public.catalogue_master_source_rows WHERE source_id='25600000-0000-0000-0000-000000000001'; IF n<>256 THEN RAISE EXCEPTION 'TM256_ACCOUNTING_FAILED: expected 256 rows, got %',n; END IF; IF EXISTS(SELECT 1 FROM public.tests GROUP BY upper(code) HAVING count(*)>1) THEN RAISE EXCEPTION 'TM256_DUPLICATE_CODE'; END IF; IF EXISTS(SELECT 1 FROM public.tests WHERE lifecycle_status='Draft' AND (is_active OR billing_enabled OR clinical_reporting_enabled)) THEN RAISE EXCEPTION 'TM256_DRAFT_OPERATIONAL'; END IF; IF EXISTS(SELECT 1 FROM public.tests t WHERE t.clinical_reporting_enabled AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')) THEN RAISE EXCEPTION 'TM256_REPORTING_WITHOUT_STRUCTURE'; END IF; IF EXISTS(SELECT 1 FROM public.tests WHERE reporting_model IN('MicrobiologyWorkflow','CytologyWorkflow','MolecularWorkflow','StructuredNested') AND workflow_supported AND clinical_reporting_enabled) THEN RAISE EXCEPTION 'TM256_SPECIALIST_GENERIC_REPORTING'; END IF; IF EXISTS(SELECT 1 FROM public.catalogue_profile_components c LEFT JOIN public.tests p ON p.id=c.profile_test_id WHERE p.id IS NULL) THEN RAISE EXCEPTION 'TM256_ORPHAN_PROFILE_COMPONENT'; END IF; END $$;`)

const content = `${sql.join('\n\n')}\n`
fs.writeFileSync(outputPath, content)
console.log(JSON.stringify({sourceRows: rows.length,newIdentityCandidates: identities.size,conflicts: conflicts.length,sha256:createHash('sha256').update(content).digest('hex'),outputPath},null,2))
