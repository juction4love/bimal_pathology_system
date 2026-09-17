import fs from 'node:fs';
import path from 'node:path';

const root = process.cwd();
const migration = path.join(root, 'supabase/migrations/00075_catalogue_readiness_approval_workflow.sql');
const marker = '-- BEGIN GENERATED OPERATOR-APPROVED DATA RECONCILIATION';

function parseCsv(text) {
  const rows=[]; let row=[]; let cell=''; let quoted=false;
  for (let i=0;i<text.length;i++) {
    const c=text[i];
    if (quoted) { if (c==='"' && text[i+1]==='"') { cell+='"'; i++; } else if (c==='"') quoted=false; else cell+=c; }
    else if (c==='"') quoted=true;
    else if (c===',') { row.push(cell); cell=''; }
    else if (c==='\n') { row.push(cell.replace(/\r$/,'')); rows.push(row); row=[]; cell=''; }
    else cell+=c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const headers=rows.shift();
  return rows.filter(r=>r.some(Boolean)).map(r=>Object.fromEntries(headers.map((h,i)=>[h,r[i]??''])));
}
const q=(v)=>v==null||String(v).trim()===''?'NULL':`'${String(v).replaceAll("'","''")}'`;
const b=(v)=>String(v).toLowerCase()==='true'?'TRUE':'FALSE';
const n=(v)=>v===''?'NULL':String(Number(v));

const catalogue=parseCsv(fs.readFileSync(path.join(root,'approved-data/bimal_catalogue_2026-08-29.csv'),'utf8'))
  .filter(r=>r.lifecycle_status==='Active' && r.code!=='BETA HCG');
const ranges=parseCsv(fs.readFileSync(path.join(root,'approved-data/bimal_reference_ranges_2026-08-29.csv'),'utf8'));
const overrides=new Map(Object.entries({
  'CBC|HB|Male':['13.5','17.5'],'CBC|HB|Female':['12','15.5'],
  'CBC|PCV|Male':['41','53'],'CBC|PCV|Female':['36','46'],
  'CBC|TLC|All':['4500','11000'],'CBC|NEUT|All':['40','60'],
  'CBC|LYMPH|All':['20','40'],'CBC|MONO|All':['2','8'],
  'CBC|EOSIN|All':['1','4'],'CBC|BASO|All':['0.5','1']
}));
for (const r of ranges) {
  const o=overrides.get(`${r.test_code}|${r.parameter_code}|${r.sex}`);
  if (o) [r.normal_min,r.normal_max]=o;
}
const placeholder='Default reference interval - verify with analyzer/reagent';
const catValues=catalogue.map(r=>`(${q(r.code)},${q(r.name)},${q(r.short_name)},${q(r.department)},${q(r.category)},${q(r.reporting_type)},${n(r.price_paisa)},${q(r.sample_type)},${q(r.container)},${q(r.method)},${q(r.test_kind)},${q(r.pricing_policy)},${b(r.workflow_supported)},${b(r.billing_enabled)},${b(r.collection_required)},${q(r.workflow_type)},${b(r.analyzer_configuration_required)},${q(r.reporting_model)})`).join(',\n');
const rangeValues=ranges.map(r=>`(${q(r.test_code)},${q(r.parameter_code)},${q(r.sex)},${n(r.age_min_days)},${n(r.age_max_days)},${n(r.normal_min)},${n(r.normal_max)},${n(r.critical_low)},${n(r.critical_high)},${q(r.reference_text)},${q(r.qualitative_normal)},${q(r.method===placeholder?null:r.method)},${q(r.method===placeholder?placeholder:null)},${q(r.effective_from)},${q(r.effective_to)})`).join(',\n');

const generated=`${marker}
-- Inputs (SHA-256): catalogue e0fe28aef2c66ab07dc837dc142dab3085070e8ce6b0465edfd89c5672e43aa8;
-- ranges 3a9d9b4a06cba85ca963ef1b86c0a2f58d4ec6249fc2f056a55700c9e7d08806.
-- Existing canonical UUIDs are retained. BETA HCG aliases to BETA_HCG and is not inserted.
CREATE TEMP TABLE approved_catalogue_00075(code TEXT PRIMARY KEY,name TEXT,short_name TEXT,department TEXT,category TEXT,reporting_type TEXT,price_paisa BIGINT,sample_type TEXT,container TEXT,method TEXT,test_kind TEXT,pricing_policy TEXT,workflow_supported BOOLEAN,billing_enabled BOOLEAN,collection_required BOOLEAN,workflow_type TEXT,analyzer_configuration_required BOOLEAN,reporting_model TEXT) ON COMMIT DROP;
INSERT INTO approved_catalogue_00075 VALUES
${catValues};

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM approved_catalogue_00075 a LEFT JOIN public.tests t ON t.code=a.code WHERE t.id IS NULL) THEN
   RAISE EXCEPTION 'APPROVED_CATALOGUE_CANONICAL_IDENTITY_MISSING';
 END IF;
 IF (SELECT count(*) FROM public.tests WHERE code='CBC')<>1 OR (SELECT count(*) FROM public.tests WHERE code='BETA_HCG')<>1 THEN
   RAISE EXCEPTION 'CANONICAL_IDENTITY_ASSERTION_FAILED';
 END IF;
END $$;

UPDATE public.tests t SET
 name=a.name, short_name=NULLIF(a.short_name,''), reporting_type=a.reporting_type::public.reporting_type_enum,
 price_paisa=a.price_paisa, sample_type=NULLIF(a.sample_type,''), container=NULLIF(a.container,''), method=NULLIF(a.method,''),
 test_kind=a.test_kind::public.catalogue_test_kind_enum, pricing_policy=a.pricing_policy::public.catalogue_pricing_policy_enum,
 workflow_supported=a.workflow_supported, billing_enabled=(a.billing_enabled AND a.price_paisa>0), collection_required=a.collection_required,
 workflow_type=a.workflow_type::public.clinical_workflow_type_enum, analyzer_configuration_required=a.analyzer_configuration_required,
 reporting_model=a.reporting_model::public.catalogue_reporting_model_enum, lifecycle_status='Active', is_active=TRUE,
 price_configured=(a.price_paisa>0), row_version=t.row_version+1, updated_at=now()
FROM approved_catalogue_00075 a WHERE t.code=a.code;

-- The final approved CBC set reuses fourteen canonical identities and adds only genuinely absent MPV/PDW.
DO $$ DECLARE c UUID; BEGIN
 SELECT id INTO c FROM public.tests WHERE code='CBC';
 IF (SELECT count(*) FROM public.parameters WHERE test_id=c AND code IN ('RBC','HB','PCV','MCV','MCH','MCHC','RDW','TLC','NEUT','LYMPH','MONO','EOSIN','BASO','PLT') AND lifecycle_status='Active')<>14 THEN
   RAISE EXCEPTION 'CBC_CANONICAL_PARAMETER_ASSERTION_FAILED';
 END IF;
 INSERT INTO public.parameters(test_id,code,name,value_type,unit,display_order,is_mandatory,is_active,lifecycle_status,clinical_configuration_status,unit_validation_required,range_validation_required,method_validation_required)
 VALUES (c,'MPV','Mean Platelet Volume','Numeric','fL',15,TRUE,TRUE,'Active','Configured',TRUE,TRUE,FALSE),
        (c,'PDW','Platelet Distribution Width','Numeric','%',16,TRUE,TRUE,'Active','Configured',TRUE,TRUE,FALSE)
 ON CONFLICT(test_id,code) DO UPDATE SET name=EXCLUDED.name,unit=EXCLUDED.unit,display_order=EXCLUDED.display_order,is_active=TRUE,lifecycle_status='Active',range_validation_required=TRUE,row_version=public.parameters.row_version+1,updated_at=now();
END $$;

CREATE TEMP TABLE approved_ranges_00075(test_code TEXT,parameter_code TEXT,sex TEXT,age_min_days INT,age_max_days INT,normal_min NUMERIC,normal_max NUMERIC,critical_low NUMERIC,critical_high NUMERIC,reference_text TEXT,qualitative_normal TEXT,method TEXT,source_provenance TEXT,effective_from DATE,effective_to DATE) ON COMMIT DROP;
INSERT INTO approved_ranges_00075 VALUES
${rangeValues},
('CBC','MPV','All',6570,43800,7.5,11.5,NULL,NULL,NULL,NULL,NULL,'Explicit final CBC operator specification',DATE '2026-08-29',NULL),
('CBC','PDW','All',6570,43800,9,17,NULL,NULL,NULL,NULL,NULL,'Explicit final CBC operator specification',DATE '2026-08-29',NULL);

DO $$ BEGIN
 IF EXISTS(SELECT 1 FROM approved_ranges_00075 a JOIN public.tests t ON t.code=a.test_code LEFT JOIN public.parameters p ON p.test_id=t.id AND p.code=a.parameter_code WHERE p.id IS NULL AND a.test_code<>'THYROID_ECLIA') THEN
   RAISE EXCEPTION 'APPROVED_RANGE_PARAMETER_IDENTITY_MISSING';
 END IF;
END $$;

-- Supersede rather than overwrite active range evidence. Placeholder text is provenance only.
UPDATE public.reference_ranges rr SET lifecycle_status='Archived',is_active=FALSE,archived_at=now(),row_version=rr.row_version+1,updated_at=now()
FROM public.parameters p,public.tests t
WHERE rr.parameter_id=p.id AND p.test_id=t.id AND rr.lifecycle_status='Active'
AND EXISTS(SELECT 1 FROM approved_ranges_00075 a WHERE a.test_code=t.code AND a.parameter_code=p.code);

INSERT INTO public.reference_ranges(parameter_id,gender,age_min_days,age_max_days,normal_min,normal_max,critical_low,critical_high,normal_text,reference_text,method,unit,is_active,is_approved,lifecycle_status,validation_state,validation_source,effective_from,effective_to)
SELECT p.id,a.sex,a.age_min_days,a.age_max_days,a.normal_min,a.normal_max,a.critical_low,a.critical_high,
 NULLIF(a.qualitative_normal,''),NULLIF(a.reference_text,''),NULLIF(a.method,''),p.unit,TRUE,TRUE,'Active','ClinicallyValidated',
 concat_ws('; ','Operator-approved 2026-08-29 baseline',NULLIF(a.source_provenance,'')),a.effective_from,a.effective_to
FROM approved_ranges_00075 a JOIN public.tests t ON t.code=a.test_code JOIN public.parameters p ON p.test_id=t.id AND p.code=a.parameter_code;

-- Operator-approved supported services activate for future bookings only. Missing technical structure stays explicit.
UPDATE public.tests t SET clinical_reporting_enabled=TRUE,clinical_configuration_status='Configured',row_version=row_version+1,updated_at=now()
WHERE EXISTS(SELECT 1 FROM approved_catalogue_00075 a WHERE a.code=t.code)
 AND t.reporting_type IN ('InHouse','OutsourceWithBimalReport') AND t.workflow_supported AND t.billing_enabled
 AND EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active')
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.value_type IN ('Numeric','Calculated') AND btrim(COALESCE(p.unit,''))='')
 AND NOT EXISTS(SELECT 1 FROM public.parameters p WHERE p.test_id=t.id AND p.is_active AND p.lifecycle_status='Active' AND p.range_validation_required AND NOT EXISTS(SELECT 1 FROM public.reference_ranges rr WHERE rr.parameter_id=p.id AND rr.is_active AND rr.lifecycle_status='Active' AND rr.is_approved AND rr.validation_state='ClinicallyValidated'));
UPDATE public.tests SET clinical_reporting_enabled=FALSE WHERE code='THYROID_ECLIA';

UPDATE public.catalogue_service_readiness r SET state=CASE
 WHEN t.clinical_reporting_enabled THEN 'Approved'::public.catalogue_readiness_state_enum
 WHEN t.lifecycle_status='Draft' OR NOT t.is_active THEN 'Draft'::public.catalogue_readiness_state_enum
 ELSE 'NeedsConfiguration'::public.catalogue_readiness_state_enum END,
 decision_reason=CASE WHEN t.clinical_reporting_enabled THEN 'Final operator-approved catalogue/reference baseline reconciled for future bookings.' ELSE 'Exact missing configuration is available in the readiness checklist.' END,updated_at=now()
FROM public.tests t WHERE t.id=r.test_id;
-- END GENERATED OPERATOR-APPROVED DATA RECONCILIATION
`;

let sql=fs.readFileSync(migration,'utf8');
sql=sql.split(marker)[0].trimEnd()+`\n\n${generated}`;
fs.writeFileSync(migration,sql);
console.log(JSON.stringify({catalogueRows:catalogue.length,rangeRows:ranges.length,placeholderRows:ranges.filter(r=>r.method===placeholder).length}));
