import { expect } from '@playwright/test';

export const IDS = {
  user:'10000000-0000-4000-8000-000000000001', role:'10000000-0000-4000-8000-000000000002', patient:'20000000-0000-4000-8000-000000000001',
  order:'30000000-0000-4000-8000-000000000001', personnel:'40000000-0000-4000-8000-000000000001',
};
const defs=[['cbc','CBC','Hematology','hematology','INTERNAL'],['lft','LFT','Biochemistry','biochemistry','INTERNAL'],['kft','KFT','Biochemistry','biochemistry','INTERNAL'],['thyroid','THYROID_PROFILE','Endocrinology','endocrinology','INTERNAL'],['urine','URINE_RE','Clinical Pathology','clinical_pathology','INTERNAL']];
const uuid=(n)=>`50000000-0000-4000-8000-${String(n).padStart(12,'0')}`;
export function makeState(){
 const items=defs.map((d,i)=>({id:uuid(i+1),test_id:uuid(101+i),test_name:d[1],department:d[2],status:d[0]==='thyroid'?'Received':'Verified',reporting_type:'InHouse',clinical_reporting_enabled:true,order_id:IDS.order,execution_route:d[4],group_key:d[3],group_id:uuid(201+['hematology','biochemistry','endocrinology','clinical_pathology'].indexOf(d[3])),results:[{id:uuid(301+i),status:d[0]==='thyroid'?'Draft':'Verified'}]}));
 const samples = [
  { id: uuid(401), order_id: IDS.order, barcode: 'B-SYN-EDTA-1', status: 'Received', specimen_type: 'Whole Blood', container_type: 'EDTA', collection_required: true, collected_at: '2026-09-01T00:30:00Z', received_at: '2026-09-01T00:45:00Z', order: { order_number: 'LAB-SYN-0001', patient: { uhid: '2609010001', full_name: 'Synthetic Acceptance' } }, patient: { uhid: '2609010001', full_name: 'Synthetic Acceptance' } },
  { id: uuid(402), order_id: IDS.order, barcode: 'B-SYN-SST-1', status: 'Received', specimen_type: 'Serum', container_type: 'SST', collection_required: true, collected_at: '2026-09-01T00:30:00Z', received_at: '2026-09-01T00:45:00Z', order: { order_number: 'LAB-SYN-0001', patient: { uhid: '2609010001', full_name: 'Synthetic Acceptance' } }, patient: { uhid: '2609010001', full_name: 'Synthetic Acceptance' } },
 ];
 return {items, samples, signed:new Map(), reports:[], existingPatient:false, billCount:0, outsource:[
  {id:uuid(601),order_item_id:uuid(611),tracking_number:'OUT-HCV',service_description:'HCV RNA Quantitative',specimen_type:'Serum',status:'PreparedForDispatch',received_at:'2026-09-01T01:00:00Z',reference_lab_name:null,reference_laboratory_id:null,patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'},bill:{bill_number:'B-SYN-1',created_at:'2026-09-01T00:00:00Z'},order_item:{order_id:IDS.order,outsource_state:'AwaitingDispatch'}},
  {id:uuid(602),order_item_id:uuid(612),tracking_number:'OUT-IHC',service_description:'IHC',specimen_type:'Tissue Block',status:'PreparedForDispatch',received_at:'2026-09-01T01:00:00Z',reference_lab_name:null,reference_laboratory_id:null,patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'},bill:{bill_number:'B-SYN-1',created_at:'2026-09-01T00:00:00Z'},order_item:{order_id:IDS.order,outsource_state:'AwaitingDispatch'}}
 ], rpcCalls:[], issues:[]};
}
const permissions=['can_view_dashboard','can_create_bill','can_edit_patient','can_collect_sample','can_receive_sample','can_reject_sample','can_enter_results','can_verify_results','can_acknowledge_critical','can_sign_reports','can_amend_reports','can_print_reports','can_manage_catalogue','can_configure_catalogue_technical','can_manage_ast_breakpoints','can_manage_referring_doctors','can_manage_personnel','can_view_financials','can_view_audit_logs','can_manage_outsource_tracking','can_view_hmis_reports','can_edit_hmis_reports','can_finalize_hmis_reports'];
const billTests=[
 {id:uuid(1001),code:'PANEL_CBC',name:'CBC Panel Component',short_name:'CBC Panel',department:'Hematology',category:'Hematology',reporting_type:'InHouse',price_paisa:120000,clinical_reporting_enabled:true,collection_required:true,workflow_type:'Routine',workflow_supported:true,sample_type:'Whole Blood',container:'EDTA',is_active:true,display_order:1},
 {id:uuid(1002),code:'PANEL_ESR',name:'ESR Panel Component',short_name:'ESR Panel',department:'Hematology',category:'Hematology',reporting_type:'InHouse',price_paisa:0,clinical_reporting_enabled:true,collection_required:true,workflow_type:'Routine',workflow_supported:true,sample_type:'Whole Blood',container:'EDTA',is_active:true,display_order:2},
 {id:uuid(1003),code:'CREATININE',name:'Serum Creatinine',short_name:'Creatinine',department:'Biochemistry',category:'Biochemistry',reporting_type:'InHouse',price_paisa:50000,clinical_reporting_enabled:true,collection_required:true,workflow_type:'Routine',workflow_supported:true,sample_type:'Serum',container:'SST',is_active:true,display_order:3},
 {id:uuid(1004),code:'THYROID_PROFILE',name:'Thyroid Profile',short_name:'Thyroid',department:'Endocrinology',category:'Endocrinology',reporting_type:'InHouse',price_paisa:150000,clinical_reporting_enabled:true,collection_required:true,workflow_type:'Routine',workflow_supported:true,sample_type:'Serum',container:'SST',is_active:true,display_order:4},
];
const jwt=()=>{const b=(v)=>Buffer.from(JSON.stringify(v)).toString('base64url');return `${b({alg:'HS256',typ:'JWT'})}.${b({sub:IDS.user,role:'authenticated',exp:1999999999})}.synthetic`;};
function json(route,data,status=200,extra={}){return route.fulfill({status,contentType:'application/json',headers:{'access-control-allow-origin':'*','content-range':'0-0/1',...extra},body:JSON.stringify(data)});}
function itemDetail(item){return {...item,test:{code:item.test_name,workflow_type:'Routine'},sample:{barcode:item.test_name==='URINE_RE'?'U-SYN':'S-SYN',status:'Received',specimen_type:item.test_name==='CBC'?'Whole Blood':item.test_name==='URINE_RE'?'Urine':'Serum',container_type:item.test_name==='CBC'?'EDTA':item.test_name==='URINE_RE'?'Sterile Container':'SST'},order:{id:IDS.order,bill_id:uuid(701),order_number:'LAB-SYN-0001',order_date_ad:'2026-09-01',order_date_bs:'2083-05-16',patient:{id:IDS.patient,uhid:'2609010001',full_name:'Synthetic Acceptance',mobile:'9800000000',address:'Acceptance Only',dob:'1990-01-01',gender:'Female',age_years:36,age_months:0,age_days:0}}};}
function workspace(state){return state.items.map((i,n)=>({order_id:IDS.order,order_item_id:i.id,report_group_id:i.group_id,group_key:i.group_key,title:i.department,clinical_section:i.department,display_order:n,item_display_order:n,execution_route:i.execution_route,outsource_state:null,outsource_lab_name:null,report_state:state.signed.has(i.group_id)?'SignedOff':'Pending',pdf_state:state.signed.has(i.group_id)?'Ready':null,latest_report_id:state.signed.has(i.group_id)?uuid(951):null}));}
function parseEq(url,key){const v=url.searchParams.get(key);return v?.startsWith('eq.')?v.slice(3):null;}
function tableResponse(state,table,url){
 if(table==='user_profiles')return {id:IDS.user,email:'technician@acceptance.invalid',full_name:'Synthetic Lab Technician',phone:null,is_active:true,is_super_admin:false,created_at:'2026-09-01T00:00:00Z',updated_at:'2026-09-01T00:00:00Z'};
 if(table==='user_roles')return [{role_id:IDS.role,role:{id:IDS.role,code:'lab_technician',name:'Lab Technician'}}];
 if(table==='role_permissions')return permissions.map(permission_key=>({permission_key}));
 if(table==='user_direct_permissions')return [];
 if(table==='referring_doctors')return [];
 if(table==='patients')return state.existingPatient?{id:IDS.patient,uhid:'2609010001',title:'Ms.',full_name:'Synthetic Returning Patient',gender:'Female',age_years:36,age_months:0,age_days:0,address:'Acceptance Only',email:null,identification_no:null,mobile:'9800000002'}:null;
 if(table==='tests'){const filter=url.searchParams.get('id')||'';if(filter.startsWith('in.(')){const ids=filter.slice(4,-1).split(',');return billTests.filter(test=>ids.includes(test.id));}return billTests;}
 if(table==='catalogue_test_operational_state')return billTests.map(test=>({test_id:test.id,readiness:'Ready',operational_state:'Ready & Reportable'}));
 if(table==='catalogue_panel_services')return {panel_id:uuid(1101),catalogue_panels:{row_version:1}};
 if(table==='clinical_orders')return [{id:IDS.order,bill_id:uuid(701),order_number:'LAB-SYN-0001',order_date_ad:'2026-09-01',order_date_bs:'2083-05-16',patient:{id:IDS.patient,uhid:'2609010001',full_name:'Synthetic Acceptance'}}];
 if(table==='samples'){
  const id=parseEq(url,'id'); const orderId=parseEq(url,'order_id');
  if(id)return state.samples?.find(s=>s.id===id)||null;
  if(orderId)return (state.samples||[]).filter(s=>s.order_id===orderId);
  return state.samples||[];
 }
 if(table==='clinical_order_items'){
  const id=parseEq(url,'id'); const order=parseEq(url,'order_id');
  if(id){const found=state.items.find(i=>i.id===id);return found?itemDetail(found):null;}
  if(order){if((url.searchParams.get('select')||'')==='id')return [{id:state.items[0].id}];return state.items;}
  return state.items;
 }
 if(table==='order_report_group_workspace')return workspace(state);
 if(table==='diagnostic_reports'){
  const repGroupId=parseEq(url,'report_group_id');
  const repId=parseEq(url,'id');
  if(repGroupId)return state.reports.filter(r=>r.report_group_id===repGroupId);
  if(repId)return state.reports.filter(r=>r.id===repId);
  return state.reports;
 }
  if(table==='parameters'){
    const testId=parseEq(url,'test_id');
    if(testId===uuid(102)){
      return [
        {id:uuid(811),code:'TBIL',name:'Bilirubin Total',value_type:'Numeric',unit:'mg/dL',formula:null,calculation_identifier:null,display_order:1,options:[],interpretation_config:{}},
        {id:uuid(812),code:'DBIL',name:'Bilirubin Direct',value_type:'Numeric',unit:'mg/dL',formula:null,calculation_identifier:null,display_order:2,options:[],interpretation_config:{}},
        {id:uuid(813),code:'IBIL',name:'Bilirubin Indirect',value_type:'Calculated',unit:'mg/dL',formula:'Total Bilirubin - Direct Bilirubin',calculation_identifier:'LFT_INDIRECT_BILIRUBIN_V1',display_order:3,options:[],interpretation_config:{}},
        {id:uuid(814),code:'SGOT',name:'AST / SGOT',value_type:'Numeric',unit:'U/L',formula:null,calculation_identifier:null,display_order:4,options:[],interpretation_config:{}},
        {id:uuid(815),code:'SGPT',name:'ALT / SGPT',value_type:'Numeric',unit:'U/L',formula:null,calculation_identifier:null,display_order:5,options:[],interpretation_config:{}},
        {id:uuid(816),code:'ALP',name:'Alkaline Phosphatase',value_type:'Numeric',unit:'U/L',formula:null,calculation_identifier:null,display_order:6,options:[],interpretation_config:{}},
        {id:uuid(817),code:'TP',name:'Total Protein',value_type:'Numeric',unit:'g/dL',formula:null,calculation_identifier:null,display_order:7,options:[],interpretation_config:{}},
        {id:uuid(818),code:'ALB',name:'Albumin',value_type:'Numeric',unit:'g/dL',formula:null,calculation_identifier:null,display_order:8,options:[],interpretation_config:{}},
        {id:uuid(819),code:'GLOB',name:'Globulin',value_type:'Calculated',unit:'g/dL',formula:'Total Protein - Albumin',calculation_identifier:'LFT_GLOBULIN_V1',display_order:9,options:[],interpretation_config:{}},
        {id:uuid(820),code:'AG_RATIO',name:'A:G Ratio',value_type:'Calculated',unit:'ratio',formula:'Albumin / Globulin',calculation_identifier:'LFT_AG_RATIO_V1',display_order:10,options:[],interpretation_config:{}},
      ];
    }
    return [{id:uuid(801),code:'RESULT',name:'Result',value_type:'Numeric',unit:'mg/dL',formula:null,calculation_identifier:null,display_order:1,options:[],interpretation_config:{}}];
  }
  if(table==='reference_ranges'){
    const paramId=parseEq(url,'parameter_id');
    return [{id:uuid(802),parameter_id:paramId||uuid(801),is_active:true,is_approved:true,sex:'All',min_age_days:0,max_age_days:50000,normal_min:1,normal_max:200,critical_low:null,critical_high:null,normal_text:null,reference_text:'Normal',unit:'mg/dL'}];
  }
  if(table==='test_results'){
    const orderItemId=parseEq(url,'order_item_id');
    const item=state.items.find(i=>i.id===orderItemId);
    const status=item?.status==='Received'?'Draft':item?.status==='SignedOff'?'Verified':item?.status||'Draft';
    if(item?.test_name==='LFT'){
      return state.lftResults || [
        {id:uuid(831),parameter_id:uuid(811),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(832),parameter_id:uuid(812),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(833),parameter_id:uuid(813),order_item_id:orderItemId,display_value:'Pending calculation',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(834),parameter_id:uuid(814),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(835),parameter_id:uuid(815),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(836),parameter_id:uuid(816),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(837),parameter_id:uuid(817),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(838),parameter_id:uuid(818),order_item_id:orderItemId,display_value:'',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(839),parameter_id:uuid(819),order_item_id:orderItemId,display_value:'Pending calculation',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
        {id:uuid(840),parameter_id:uuid(820),order_item_id:orderItemId,display_value:'Pending calculation',numeric_value:null,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status},
      ];
    }
    return [{id:uuid(803),parameter_id:uuid(801),order_item_id:orderItemId,display_value:'42',numeric_value:42,text_value:null,flag:'Normal',is_critical:false,critical_acknowledged:false,status,verified_by_name:status==='Verified'?'Synthetic Lab Technician':null,verified_at:status==='Verified'?'2026-09-01T02:00:00Z':null}];
  };
 if(table==='reporting_personnel')return [{id:IDS.personnel,user_id:IDS.user,full_name:'Synthetic Signatory',professional_type:'Pathologist',qualification:'MD',registration_council:'NMC',registration_number:'SYN-1',specialization:'Pathology',phone:null,email:null,signature_url:null,can_enter_results:true,can_verify_results:true,can_acknowledge_critical:true,can_sign_reports:true,is_active:true,display_order:1,created_at:'2026-09-01T00:00:00Z',updated_at:'2026-09-01T00:00:00Z'}];
 if(table==='outsource_samples')return state.outsource;
 if(table==='reference_laboratories')return [{id:uuid(901),name:'Reference Lab A'},{id:uuid(902),name:'Reference Lab B'}];
 if(table==='outsource_sample_events')return [];
 return [];
}
function rpc(state,name,body){
 state.rpcCalls.push(name);
 if(name==='get_dashboard_operational_summary')return {};
 if(name==='search_billable_catalogue'){
  const q=String(body.p_query||'').toLowerCase();
  if(q.includes('panel'))return [{entity_type:'Panel',entity_id:uuid(1102),code:'HEM_PANEL',name:'Hematology Bundle',short_name:'Hematology Bundle',category:'Hematology',department:'Hematology',reporting_type:'InHouse',specimen:'Whole Blood',container:'EDTA',price_paisa:120000,price_configured:true,allow_zero_price_billing:false,pricing_policy:'Fixed'}];
  const test=q.includes('cre')?billTests[2]:billTests[3];return [{entity_type:'Test',entity_id:test.id,code:test.code,name:test.name,short_name:test.short_name,category:test.category,department:test.department,reporting_type:test.reporting_type,specimen:test.sample_type,container:test.container,price_paisa:test.price_paisa,price_configured:true,allow_zero_price_billing:false,pricing_policy:'Fixed'}];
 }
 if(name==='catalogue_panel_service_components')return [{test_id:billTests[0].id,display_order:1,readiness:'Ready'},{test_id:billTests[1].id,display_order:2,readiness:'Ready'}];
 if(name==='create_patient_bill_order_mixed_catalogue'||name==='create_patient_bill_order_with_packages'){
  state.existingPatient=true;state.billCount+=1;
  const newOrderId=uuid(1300+state.billCount);
  const newSampleId=uuid(1400+state.billCount);
  (state.samples||(state.samples=[])).push({
    id:newSampleId,
    order_id:newOrderId,
    barcode:`B-SYN-${state.billCount}`,
    status:'Pending',
    specimen_type:'Serum',
    container_type:'SST',
    collection_required:true,
    order:{order_number:`LAB-SYN-000${state.billCount}`,patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'}},
    patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'}
  });
  return {patient_id:IDS.patient,uhid:'2609010001',bill_id:uuid(1200+state.billCount),bill_number:`B-SYN-000${state.billCount}`,order_id:newOrderId,order_number:`LAB-SYN-000${state.billCount}`,samples_created:1};
 }
 if(name==='calculation_dependency_blockers')return [];
 if(name==='search_sample_accessioning')return (state.samples||[]).map(item=>({item}));
 if(name==='transition_sample_lifecycle'){
  const s=(state.samples||[]).find(x=>x.id===body.p_sample_id);
  if(s){s.status=body.p_to_status;if(body.p_to_status==='Collected')s.collected_at=new Date().toISOString();if(body.p_to_status==='Received')s.received_at=new Date().toISOString();}
  return {ok:true,barcode:s?.barcode||'SYN-BARCODE'};
 }
 if(name==='check_report_group_readiness'){
  const group=body.p_report_group_id; const members=state.items.filter(i=>i.group_id===group); const ready=members.every(i=>i.status==='Verified'||i.status==='SignedOff');
  return {is_ready:ready,verified_count:members.filter(i=>i.status==='Verified'||i.status==='SignedOff').length,reportable_count:members.length,blockers:ready?[]:['Results awaiting verification']};
 }
 if(name==='save_test_results'){const i=state.items.find(x=>x.id===body.p_order_item_id);if(i)i.status=body.p_target_status;return {saved:true};}
 if(name==='sign_and_queue_report_group'){
  const version=body.p_amended_from_report_id?2:1; state.signed.set(body.p_report_group_id,version); state.items.filter(i=>i.group_id===body.p_report_group_id).forEach(i=>i.status='SignedOff');
  const rep={id:uuid(950+state.reports.length),order_id:IDS.order,patient_id:IDS.patient,report_group_id:body.p_report_group_id,report_number:`R-SYN-${state.reports.length+1}`,version,is_amendment:version>1,amendment_reason:body.p_amendment_reason||null,amended_from_report_id:body.p_amended_from_report_id||null,status:'SignedOff',integrity_hash:'synthash123',performed_by_personnel_name:'Synthetic Performer',signed_by_personnel_name:'Synthetic Signatory',signed_at:'2026-09-01T02:00:00Z',pdf_storage_path:`reports/${IDS.order}/R-SYN-1.pdf`,clinical_snapshot_json:{patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'},order:{order_number:'LAB-SYN-0001'},report_group:{title:'Hematology',clinical_section:'Hematology'}}};
  state.reports.push(rep);
  return {report_id:rep.id,report_number:rep.report_number,version,sms_status:state.reports.length>1?'No additional automatic SMS':'Order notification queued'};
 }
 if(name==='search_report_registry')return state.reports.map(item=>({item}));
 if(name==='get_report_secure_link_status')return {report_id:body.p_report_id,report_version:1,public_url:'https://dashboard.bimalpathology.com.np/r/synthtoken123',state:'Active'};
 if(name==='transition_outsource_order_item'){
  const sample=state.outsource.find(s=>s.order_item_id===body.p_order_item_id&&s.status!=='Rejected'); if(sample){sample.order_item.outsource_state=body.p_to_state;sample.reference_laboratory_id=body.p_destination_id||sample.reference_laboratory_id;sample.reference_lab_name=sample.reference_laboratory_id===uuid(901)?'Reference Lab A':sample.reference_laboratory_id===uuid(902)?'Reference Lab B':sample.reference_lab_name;if(body.p_to_state==='RecollectionRequired'){sample.status='Rejected';state.outsource.push({...sample,id:uuid(699),tracking_number:'OUT-RECOLLECT',status:'ReceivedAtBimal',received_at:'2026-09-01T03:00:00Z',order_item:{outsource_state:'RecollectionRequired'}});}else sample.status=body.p_to_state==='Dispatched'?'DispatchedToReferenceLab':body.p_to_state==='ResultReceived'?'ResultReceived':body.p_to_state==='Verified'?'Completed':sample.status;} return {ok:true};
 }
 return {};
}
export async function installSyntheticBackend(context,state){
 await context.route('https://fonts.googleapis.com/**',route=>route.fulfill({status:200,contentType:'text/css',body:''}));
 await context.route('https://fonts.gstatic.com/**',route=>route.fulfill({status:200,contentType:'font/woff2',body:''}));
 await context.route('http://127.0.0.1:54329/**',async route=>{
  const req=route.request(),url=new URL(req.url());
  if(req.method()==='OPTIONS')return route.fulfill({status:204,headers:{'access-control-allow-origin':'*','access-control-allow-headers':'*'}});
  if(url.pathname==='/auth/v1/token')return json(route,{access_token:jwt(),token_type:'bearer',expires_in:3600,expires_at:1999999999,refresh_token:'synthetic-refresh',user:{id:IDS.user,aud:'authenticated',role:'authenticated',email:'technician@acceptance.invalid',email_confirmed_at:'2026-09-01T00:00:00Z',created_at:'2026-09-01T00:00:00Z',updated_at:'2026-09-01T00:00:00Z',app_metadata:{provider:'email'},user_metadata:{full_name:'Synthetic Lab Technician'},identities:[]}});
  if(url.pathname==='/auth/v1/user')return json(route,{id:IDS.user,aud:'authenticated',role:'authenticated',email:'technician@acceptance.invalid',app_metadata:{provider:'email'},user_metadata:{full_name:'Synthetic Lab Technician'},created_at:'2026-09-01T00:00:00Z'});
  if(url.pathname==='/auth/v1/logout')return json(route,{});
  const rpcMatch=/^\/rest\/v1\/rpc\/([^/]+)$/.exec(url.pathname); if(rpcMatch){let body={};try{body=req.postDataJSON()||{}}catch{}return json(route,rpc(state,decodeURIComponent(rpcMatch[1]),body));}
  const tableMatch=/^\/rest\/v1\/([^/]+)$/.exec(url.pathname); if(tableMatch){const data=tableResponse(state,decodeURIComponent(tableMatch[1]),url);const wantsObject=(req.headers()['accept']||'').includes('object+json');return json(route,data===null?null:(wantsObject&&Array.isArray(data)?(data[0]??null):data));}
  state.issues.push(`unexpected backend request ${req.method()} ${url.pathname}`);return json(route,{message:'unexpected synthetic contract request'},404);
 });
}
export function observe(page,state){page.on('pageerror',e=>state.issues.push(`pageerror:${e.message}`));page.on('console',m=>{if(m.type()==='error')state.issues.push(`console:${m.text()}`)});page.on('requestfailed',r=>state.issues.push(`requestfailed:${r.method()} ${r.url()}`));}
export async function login(page){await page.goto('/login');await page.locator('#login-email').fill('technician@acceptance.invalid');await page.locator('#login-password').fill('Synthetic-Only-Password!');await page.locator('#login-submit').click();await expect(page).toHaveURL(/\/$/);}
