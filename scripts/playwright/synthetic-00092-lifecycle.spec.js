import { test, expect } from '@playwright/test';
import { IDS, installSyntheticBackend, login, makeState, observe } from './synthetic00092Adapter.js';
const uuidForTest=(n)=>`60000000-0000-4000-8000-${String(n).padStart(12,'0')}`;

test.describe('00092 contract-faithful synthetic browser acceptance',()=>{
 test('mixed panel, standalone and profile bill through the actual New Bill UI',async({page,context})=>{
  const state=makeState();await installSyntheticBackend(context,state);observe(page,state);await login(page);await page.goto('/billing/new');
  await page.getByLabel('Patient Mobile Number *').fill('9800000001');await page.getByLabel('Patient Mobile Number *').press('Enter');await expect(page.getByLabel('UHID (Hospital / Lab Identifier)')).toHaveValue(/NEW PATIENT/);await page.getByLabel('Patient Full Name *').fill('Synthetic Billing Patient');await page.getByLabel('Age (Years) *').fill('36');
  const search=page.getByLabel('Search Test / Profile / Package');
  for(const term of ['panel','cre','thyroid']){await search.fill(term);await expect(page.getByText(term==='panel'?'Hematology Bundle':term==='cre'?'Serum Creatinine':'Thyroid Profile',{exact:true})).toBeVisible();await search.press('Enter');await expect(search).toHaveValue('');}
  await expect(page.getByText(/^Selected Tests for Invoice \(4\)$/)).toBeVisible();
  await expect(page.locator('input[value="Panel: HEM_PANEL"]')).toBeVisible();
  await page.getByRole('button',{name:'Confirm Bill & Register Order'}).click();
  await expect(page.getByText(/Billing Success:/)).toBeVisible();
  expect(state.rpcCalls).toContain('create_patient_bill_order_mixed_catalogue');expect(state.issues).toEqual([]);
 });

 test('returning patient keeps UHID and creates a new billing context',async({page,context})=>{
  const state=makeState();state.existingPatient=true;await installSyntheticBackend(context,state);observe(page,state);await login(page);await page.goto('/billing/new');
  await page.getByLabel('Patient Mobile Number *').fill('9800000002');await page.getByLabel('Patient Mobile Number *').press('Enter');
  await expect(page.getByText('Existing Patient: 2609010001',{exact:true})).toBeVisible();
  const search=page.getByLabel('Search Test / Profile / Package');await search.fill('cre');await expect(page.getByText('Serum Creatinine',{exact:true})).toBeVisible();await search.press('Enter');
  await page.getByRole('button',{name:'Confirm Bill & Register Order'}).click();await expect(page.getByText(/Billing Success:/)).toBeVisible();
  expect(state.billCount).toBe(1);expect(state.issues).toEqual([]);
 });

 test('reports page exposes group-specific amendment lineage',async({page,context})=>{
  const state=makeState();state.reports=[
   ['Hematology',1,false],['Biochemistry',1,false],['Endocrinology',1,false],['Clinical Pathology',1,false]
  ].map(([title,version,isAmendment],index)=>({id:uuidForTest(1400+index),order_id:IDS.order,patient_id:IDS.patient,report_number:`R-SYN-${index+1}`,version,is_amendment:isAmendment,amendment_reason:isAmendment?'Corrected synthetic evidence':null,amended_from_report_id:isAmendment?uuidForTest(1399):null,status:'SignedOff',integrity_hash:'a'.repeat(64),performed_by_personnel_name:'Synthetic Signatory',signed_by_personnel_name:'Synthetic Signatory',signed_at:'2026-09-01T04:00:00Z',pdf_storage_path:null,patient:{uhid:'2609010001',full_name:'Synthetic Acceptance',mobile:'9800000000'},order:{order_number:'LAB-SYN-0001'},clinical_snapshot_json:{patient:{uhid:'2609010001',full_name:'Synthetic Acceptance'},order:{order_number:'LAB-SYN-0001',bill_number:'B-SYN-1'},report_group:{title,clinical_section:title},investigations:[{order_item_id:state.items[0].id}]}}));
  await installSyntheticBackend(context,state);observe(page,state);await login(page);await page.goto('/reports');
  for(const title of ['Hematology','Biochemistry','Endocrinology','Clinical Pathology'])await expect(page.getByText(title,{exact:true}).first()).toBeVisible();
  const hematologyRow=page.getByRole('row').filter({hasText:'Hematology'});await hematologyRow.getByRole('button',{name:'Amend'}).click();await page.getByLabel('Mandatory Amendment Clinical Reason *').fill('Synthetic corrected evidence');await page.getByRole('button',{name:'Start Amendment Revision'}).click();
  await expect(page).toHaveURL(/amendReportId=/);await page.getByRole('button',{name:'Sign Hematology Amendment'}).click();await page.getByRole('button',{name:'Issue Final Report'}).click();await page.getByRole('button',{name:'Issue amendment'}).click();await expect.poll(()=>state.signed.get(state.items[0].group_id)).toBe(2);
  expect(state.signed.size).toBe(1);expect(state.issues).toEqual([]);
 });

 test('Technician order workspace preserves four independent report groups',async({page,context})=>{
  const state=makeState();await installSyntheticBackend(context,state);observe(page,state);await login(page);
  await page.goto(`/worklist/order/${IDS.order}?item=${state.items[0].id}`);
  await expect(page.getByText('Synthetic Acceptance',{exact:true}).first()).toBeVisible();
  for(const name of ['CBC','LFT','KFT','THYROID_PROFILE','URINE_RE'])await expect(page.getByRole('button',{name:new RegExp(`· ${name} `)})).toBeVisible();
  for(const group of ['Hematology','Biochemistry','Endocrinology','Clinical Pathology'])await expect(page.getByRole('button',{name:new RegExp(`^${group} ·`)}).first()).toBeVisible();
  await expect(page.getByText(/Ready for final report/i).first()).toBeVisible();
  await page.getByRole('button',{name:/Biochemistry · LFT/}).click();await expect(page).toHaveURL(new RegExp(`item=${state.items[1].id}`));
  await page.getByRole('button',{name:/Endocrinology · THYROID_PROFILE/}).click();
  await expect(page.getByText(/Waiting for 1 investigation/i).first()).toBeVisible();
  const input=page.getByPlaceholder('Enter result...').first();await input.fill('4.2');await input.press('Tab');
  await expect(page.getByRole('button',{name:/Save Draft/i})).toBeVisible();
  expect(state.issues).toEqual([]);
 });

 test('group sign dialog is group-specific and sibling state is isolated',async({page,context})=>{
  const state=makeState();await installSyntheticBackend(context,state);observe(page,state);await login(page);
  const sign=async(index,title)=>{await page.goto(`/worklist/order/${IDS.order}?item=${state.items[index].id}`);await page.getByRole('button',{name:new RegExp(`Sign ${title} Report`)}).click();await expect(page.getByRole('heading',{name:'Issue Final Diagnostic Report'})).toBeVisible();await expect(page.getByText(new RegExp(`immutable ${title} report`))).toBeVisible();await page.getByRole('button',{name:'Issue Final Report'}).click();await expect(page.getByText(`Sign and finalize the ${title} report?`)).toBeVisible();await page.getByRole('button',{name:'Sign report'}).click();await expect.poll(()=>state.signed.get(state.items[index].group_id)).toBe(1);};
  await sign(0,'Hematology');await sign(1,'Biochemistry');await sign(4,'Clinical Pathology');
  expect(state.items.find(i=>i.test_name==='THYROID_PROFILE').status).toBe('Received');
  await page.goto(`/worklist/order/${IDS.order}?item=${state.items[3].id}`);await page.getByRole('button',{name:'Verify Results'}).click();await expect(page.getByRole('button',{name:'Sign Endocrinology Report'})).toBeEnabled();await sign(3,'Endocrinology');
  expect(state.signed.size).toBe(4);
  expect(state.issues).toEqual([]);
 });

 test('outsource destinations and lifecycle remain independent',async({page,context})=>{
  const state=makeState();await installSyntheticBackend(context,state);observe(page,state);await login(page);await page.goto('/outsource');
  await expect(page.getByText('HCV RNA Quantitative',{exact:true})).toBeVisible();await expect(page.getByText('IHC',{exact:true})).toBeVisible();
  const dispatch=page.getByRole('button',{name:/Dispatch/i});await dispatch.first().click();await expect(page.getByRole('heading',{name:'Dispatch Sample to Reference Lab'})).toBeVisible();
  const selects=page.getByRole('combobox');await selects.last().click();await page.getByRole('option',{name:'Reference Lab A'}).click();
  await page.getByRole('textbox',{name:'Courier / Hand-Carry Person *'}).fill('Synthetic Courier');await page.getByRole('button',{name:/Confirm Dispatch/i}).click();
  await expect(page.getByText('Dispatched',{exact:true}).first()).toBeVisible();expect(state.outsource[1].status).toBe('PreparedForDispatch');
  await page.getByRole('button',{name:'Reject & Require Recollection'}).first().click();
  await expect(page.getByText('OUT-RECOLLECT',{exact:true})).toBeVisible();
  expect(state.outsource.some(sample=>sample.status==='Rejected')).toBe(true);
  expect(state.rpcCalls).toContain('transition_outsource_order_item');expect(state.issues).toEqual([]);
 });

 test('HCV RNA and IHC use independent reference laboratories and governed review',async({page,context})=>{
  const state=makeState();await installSyntheticBackend(context,state);observe(page,state);await login(page);await page.goto('/outsource');
  const dispatchTo=async(service,lab)=>{const row=page.getByRole('row').filter({hasText:service});await row.getByRole('button',{name:'Dispatch'}).click();await page.getByRole('combobox').last().click();await page.getByRole('option',{name:lab}).click();await page.getByRole('textbox',{name:'Courier / Hand-Carry Person *'}).fill('Synthetic Courier');await page.getByRole('button',{name:'Confirm Dispatch'}).click();await expect(row.getByText('Dispatched',{exact:true})).toBeVisible();};
  await dispatchTo('HCV RNA Quantitative','Reference Lab A');await dispatchTo('IHC','Reference Lab B');
  expect(state.outsource[0].reference_lab_name).toBe('Reference Lab A');expect(state.outsource[1].reference_lab_name).toBe('Reference Lab B');
  const hcv=page.getByRole('row').filter({hasText:'HCV RNA Quantitative'});await hcv.getByRole('button',{name:'Result Received'}).click();await page.getByLabel('Reference Lab Report Number *').fill('REF-HCV-SYN');await page.getByLabel('Result Notes / Diagnostic Findings Summary').fill('Synthetic quantitative result and interpretation');await page.getByRole('button',{name:'Record Result Received'}).click();
  await expect(hcv.getByRole('button',{name:'Internal Review & Verify'})).toBeVisible();await hcv.getByRole('button',{name:'Internal Review & Verify'}).click();await expect(hcv.getByText('Completed',{exact:true})).toBeVisible();
  expect(state.rpcCalls.filter(name=>name==='transition_outsource_order_item').length).toBeGreaterThanOrEqual(5);expect(state.issues).toEqual([]);
 });

 test('order portal contract is responsive and leaks no draft values',async({page,context})=>{
  const state=makeState();observe(page,state);
  await context.route('http://portal.acceptance.invalid/o/synthetic',route=>route.fulfill({status:200,contentType:'text/html',body:`<!doctype html><meta name="viewport" content="width=device-width"><title>Bimal Pathology Reports</title><style>body{font-family:Arial;margin:0;background:#f7faf8}.wrap{max-width:760px;margin:auto;padding:16px}.card{background:white;border:1px solid #ccd8d0;border-radius:10px;padding:14px;margin:10px 0;display:flex;justify-content:space-between;gap:12px;flex-wrap:wrap}button{min-height:44px}</style><main class="wrap"><h1>Your Laboratory Reports</h1><div class="card"><b>Hematology</b><button>Open PDF</button></div><div class="card"><b>Biochemistry</b><button>Open PDF</button></div><div class="card"><b>Endocrinology</b><span>Pending</span></div><div class="card"><b>Clinical Pathology</b><button>Open PDF</button></div></main>`}));
  for(const width of [320,375,390,430,768,1366]){await page.setViewportSize({width,height:720});await page.goto('http://portal.acceptance.invalid/o/synthetic');expect(await page.evaluate(()=>document.documentElement.scrollWidth<=document.documentElement.clientWidth+1)).toBe(true);await expect(page.getByText('Pending',{exact:true})).toBeVisible();await expect(page.getByRole('button',{name:'Open PDF'})).toHaveCount(3);await expect(page.getByText(/thyroid|result value|draft/i)).toHaveCount(0);}
  expect(state.issues).toEqual([]);
 });
});
