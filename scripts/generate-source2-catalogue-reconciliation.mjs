import fs from 'node:fs'
import path from 'node:path'

const [source2Path, source1Path, outputDir = 'docs/audits'] = process.argv.slice(2)
if (!source2Path || !source1Path) throw new Error('usage: node generate-source2-catalogue-reconciliation.mjs <source2.txt> <source1.csv> [output-dir]')

const csvParse = (text) => {
  const rows=[]; let row=[], cell='', quoted=false
  for(let i=0;i<text.length;i++){const c=text[i]; if(c==='"'){if(quoted&&text[i+1]==='"'){cell+='"';i++}else quoted=!quoted}else if(c===','&&!quoted){row.push(cell);cell=''}else if((c==='\n'||c==='\r')&&!quoted){if(c==='\r'&&text[i+1]==='\n')i++;row.push(cell);if(row.some(Boolean))rows.push(row);row=[];cell=''}else cell+=c}
  if(cell||row.length){row.push(cell);rows.push(row)} const [header,...body]=rows
  return body.map(r=>Object.fromEntries(header.map((h,i)=>[h,r[i]??''])))
}
const norm = (s='') => s.toLowerCase().replace(/haem/g,'hem').replace(/leucocyte/g,'leukocyte').replace(/\bserum\b/g,'').replace(/\btest\b/g,'').replace(/\bcount\b/g,'').replace(/[^a-z0-9]+/g,' ').trim()
const words=s=>new Set(norm(s).split(' ').filter(x=>x.length>1))
const jaccard=(a,b)=>{const A=words(a),B=words(b);if(!A.size||!B.size)return 0;const n=[...A].filter(x=>B.has(x)).length;return n/(A.size+B.size-n)}
const q=s=>'"'+String(s??'').replaceAll('"','""')+'"'
const canonicalCode=s=>norm(s).toUpperCase().replaceAll(' ','_').slice(0,64)

const sectionMap = new Map([
  ['Biochemistry & Clinical Chemistry','Routine LIS / Clinical Biochemistry'],['Hematology','Routine LIS / Hematology'],['Hormones & Endocrinology','Routine LIS / Endocrinology'],
  ['Serology & Immunology','Routine LIS / Serology-Immunology'],['Molecular & PCR Tests','MolecularWorkflow'],['Microbiology & Culture','MicrobiologyWorkflow'],
  ['Hepatitis & HIV Panel','Routine LIS / Serology-Immunology'],['Tumor Markers & Cancer Screening','Routine or Pathology/IHC review'],['Histopathology & Biopsy','Histopathology/CytologyWorkflow'],
  ['Allergy Testing','Outsource/Immunology review'],['Vitamins & Minerals','Routine or Outsource review'],['Genetic Testing & Karyotyping','Molecular/CytogeneticsWorkflow'],
  ['Drug Testing & Toxicology','Toxicology/TDM'],['General & Other Tests','Routine/Structured/Specialist review']
])
const headerFor = section => section.includes('Molecular')||section.includes('Hepatitis')||section.includes('Tumor')||section.includes('Vitamins')||section.includes('Allergy') ? 'Method' : section.includes('Culture')||section.includes('Histopathology')||section.includes('Genetic') ? 'ReportSchedule' : 'SampleVolume'
const methodVariant = /\b(clia|elisa|rapid|ict|confirmatory|neutralization|ifa|flowcytometry|flow cytometry|western blot|hplc|electrophoresis|pcr|rt pcr|igm|igg|total ab|combi)\b/i
const specialist = /culture|biopsy|cytology|fnac|pap smear|lbc|karyotyp|mutation|viral load|genotyp|\bpcr\b|bcr\/abl|brca|cftr|autism panel|glycogen storage|duchenne|respiratory|meningitis|std |neuro virus|ihc|breast cancer panel/i
const structured = /urine routine|stool routine|semen analysis|csf routine|gram stain|afb stain|sputum afb|koh preparation/i
const packageLike = /profile|panel|function test|cbc|complete haemogram|dengue combo|thyroid autoantibodies|immunoglobulin g\/a\/m|urine drug analysis/i

let section=''; const rows=[]; let packageRow=null; let ihcEvidence=null
for(const line of fs.readFileSync(source2Path,'utf8').split(/\r?\n/)){
  if(!line.includes('\t')){const m=line.match(/^(?:\d[^ ]*|🔟)\s+(.+)$/u);if(m)section=m[1].trim();continue}
  const c=line.split('\t'); if(['Test Name','Markers Available','Price Range','Package Name'].includes(c[0]))continue
  if(section==='Health Packages'){if(c[0]==='Basic Health Package')packageRow={name:c[0],externalPrice:c[1],components:c[2]};continue}
  if(c[0].startsWith('ER, PR, HER2')){ihcEvidence={markerText:c[0],externalPrice:c[1]};continue}
  rows.push({number:rows.length+1,section,name:c[0],externalPrice:c[1]||'',specimen:c[2]||'',detail:c[3]||'',detailType:headerFor(section)})
}

const source1=csvParse(fs.readFileSync(source1Path,'utf8'))
const manual = new Map([
  ['blood sugar fasting','FBS'],['blood sugar pp','PPBS'],['blood sugar random','RBS'],['kidney function','KFT'],['liver function','LFT'],['lipid profile','LIPID_PROFILE'],
  ['cbc complete hemogram','CBC'],['hemoglobin','HB'],['pcv','HCT'],['platelets','PLT'],['tlc','TLC'],['dlc','DLC'],['free t3','FT3'],['free t4','FT4'],
  ['pap smear','PAP_SMEAR'],['fnac','FNAC'],['hcv viral load quantitative','HCV_RNA'],['brca 1 2','BRCA'],['urine routine','URINE_RE'],['stool routine','STOOL_RE']
])
const results=rows.map(r=>{
  const key=norm(r.name), manualCode=manual.get(key)
  const scored=source1.map(s=>({s,score:Math.max(jaccard(r.name,s['Source Name']),jaccard(r.name,s['Source Alias']),jaccard(r.name,s['Canonical Proposed Identity']))})).sort((a,b)=>b.score-a.score)
  let hit=scored[0]?.score>=0.72?scored[0]:null
  if(manualCode) hit=source1.map(s=>({s,score:s['Canonical Proposed Identity'].startsWith(manualCode+' ')||s['Canonical Proposed Identity'].startsWith(manualCode+' —')?1:0})).sort((a,b)=>b.score-a.score)[0]
  const variant=methodVariant.test(r.name)
  let relation=hit?.score>=0.72?'Existing256Match':'AdditionalCandidate'
  if(hit&&variant) relation='MethodOrAssayVariantReview'
  if(specialist.test(r.name)) relation=hit?'SpecialistExistingOrVariant':'SpecialistNewCandidate'
  else if(structured.test(r.name)) relation=hit?'StructuredExistingOrVariant':'StructuredNewCandidate'
  else if(packageLike.test(r.name)&&!hit) relation='ProfileCandidate'
  const canonical=hit?.s['Canonical Proposed Identity']||`${canonicalCode(r.name)} — ${r.name}`
  const conflict = variant?'Method/assay identity versus configuration decision required': hit&&hit.score<0.9?'Semantic match requires operator confirmation':''
  return {...r,source1Match:hit?.s['Source Name']||'',productionMatch:hit?.s['Existing LIS Match']||'',canonical,relation,conflict,workflow:sectionMap.get(r.section)||'Review',priceAuthority:'ExternalReferencePrice'}
})

const normalizedGroups=Object.values(results.reduce((a,r)=>{(a[norm(r.name)]??=[]).push(r);return a},{}))
const duplicates=normalizedGroups.filter(g=>g.length>1)
const counts=Object.fromEntries([...new Set(results.map(r=>r.relation))].sort().map(k=>[k,results.filter(r=>r.relation===k).length]))
const sectionCounts=Object.fromEntries([...new Set(results.map(r=>r.section))].map(k=>[k,results.filter(r=>r.section===k).length]))
const uniqueAdditional=new Set(results.filter(r=>['AdditionalCandidate','SpecialistNewCandidate','StructuredNewCandidate','ProfileCandidate'].includes(r.relation)).map(r=>norm(r.name))).size
const methodVariants=results.filter(r=>r.relation==='MethodOrAssayVariantReview').length

fs.mkdirSync(outputDir,{recursive:true})
const columns=['Source #2 #','Category','Source #2 Name','External Reference Price','Supplied Specimen','Supplied Volume/Schedule/Method','Evidence Field','Existing 256 Match','Existing Production Match','Canonical Proposed Identity','Relationship','Workflow Boundary','Conflict','Price Authority']
const csv=[columns.map(q).join(','),...results.map(r=>[r.number,r.section,r.name,r.externalPrice,r.specimen,r.detail,r.detailType,r.source1Match,r.productionMatch,r.canonical,r.relation,r.workflow,r.conflict,r.priceAuthority].map(q).join(','))].join('\n')+'\n'
fs.writeFileSync(path.join(outputDir,'master-catalogue-source2-reconciliation.csv'),csv)
const evidence={source2ServiceRows:results.length,source2UniqueNormalized:normalizedGroups.length,exactDuplicateGroups:duplicates.length,additionalUniqueCandidates:uniqueAdditional,methodVariantReviews:methodVariants,counts,sectionCounts,duplicates:duplicates.map(g=>({name:g[0].name,count:g.length,sections:g.map(x=>x.section)})),package:packageRow,ihcEvidence,source1Rows:source1.length}
fs.writeFileSync(path.join(outputDir,'master-catalogue-source2-summary.json'),JSON.stringify(evidence,null,2)+'\n')
console.log(JSON.stringify(evidence,null,2))
