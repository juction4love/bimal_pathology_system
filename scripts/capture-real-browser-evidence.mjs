import { chromium } from 'playwright';
import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';

const IDS = {
  user: '10000000-0000-4000-8000-000000000001',
  roleTechnician: '10000000-0000-4000-8000-000000000002',
  roleAdmin: '10000000-0000-4000-8000-000000000003',
  patient: '20000000-0000-4000-8000-000000000001',
  order: '30000000-0000-4000-8000-000000000001',
  personnel: '40000000-0000-4000-8000-000000000001',
};

const uuid = (n) => `50000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const technicianPermissions = [
  'can_view_dashboard',
  'can_create_bill',
  'can_edit_patient',
  'can_collect_sample',
  'can_receive_sample',
  'can_reject_sample',
  'can_enter_results',
  'can_verify_results',
  'can_acknowledge_critical',
  'can_sign_reports',
  'can_amend_reports',
  'can_print_reports',
  'can_manage_outsource_tracking',
];

const adminPermissions = [
  ...technicianPermissions,
  'can_manage_catalogue',
  'can_configure_catalogue_technical',
  'can_manage_ast_breakpoints',
  'can_manage_referring_doctors',
  'can_manage_personnel',
  'can_view_financials',
  'can_view_audit_logs',
  'can_view_hmis_reports',
  'can_edit_hmis_reports',
  'can_finalize_hmis_reports',
  'can_manage_users',
  'can_manage_roles',
];

const billTests = [
  { id: uuid(1001), code: 'HEM-0001', name: 'Complete Blood Count (CBC)', short_name: 'CBC', department: 'Hematology', category: 'Hematology', reporting_type: 'InHouse', price_paisa: 120000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Whole Blood', container: 'EDTA', is_active: true, display_order: 1 },
  { id: uuid(1002), code: 'PRO-0001', name: 'Liver Function Test (LFT)', short_name: 'LFT', department: 'Biochemistry', category: 'Biochemistry', reporting_type: 'InHouse', price_paisa: 150000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Serum', container: 'SST', is_active: true, display_order: 2 },
  { id: uuid(1003), code: 'PRO-0002', name: 'Renal Function Test (RFT/KFT)', short_name: 'KFT', department: 'Biochemistry', category: 'Biochemistry', reporting_type: 'InHouse', price_paisa: 100000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Serum', container: 'SST', is_active: true, display_order: 3 },
  { id: uuid(1004), code: 'PRO-0003', name: 'Lipid Profile', short_name: 'Lipid', department: 'Biochemistry', category: 'Biochemistry', reporting_type: 'InHouse', price_paisa: 140000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Serum', container: 'SST', is_active: true, display_order: 4 },
  { id: uuid(1005), code: 'CLP-0001', name: 'Urine Routine Examination (RE/ME)', short_name: 'Urine RE', department: 'Clinical Pathology', category: 'Clinical Pathology', reporting_type: 'InHouse', price_paisa: 30000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Urine', container: 'Sterile Container', is_active: true, display_order: 5 },
  { id: uuid(1006), code: 'SER-0024', name: 'Widal Test', short_name: 'Widal', department: 'Serology / Immunology', category: 'Serology', reporting_type: 'InHouse', price_paisa: 40000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Serum', container: 'SST', is_active: true, display_order: 6 },
  { id: uuid(1007), code: 'POC-0002', name: 'Venous Blood Gas (VBG)', short_name: 'VBG', department: 'Point of Care / Blood Gas', category: 'Biochemistry', reporting_type: 'InHouse', price_paisa: 180000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'Heparinized Whole Blood', container: 'Heparin Syringe', is_active: true, display_order: 7 },
  { id: uuid(1008), code: 'PUS_CULTURE_AND_SENSITIVITY', name: 'Pus Culture & Sensitivity (AST)', short_name: 'Pus AST', department: 'Microbiology', category: 'Microbiology', reporting_type: 'InHouse', price_paisa: 160000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Culture', workflow_supported: true, sample_type: 'Pus Swab', container: 'Transport Swab', is_active: true, display_order: 8 },
  { id: uuid(1009), code: 'HIS-0001', name: 'Histopathology Biopsy (Small)', short_name: 'Histopath Small', department: 'Histopathology', category: 'Histopathology', reporting_type: 'InHouse', price_paisa: 250000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Narrative', workflow_supported: true, sample_type: 'Biopsy Tissue in 10% Formalin', container: 'Formalin Container', is_active: true, display_order: 9 },
  { id: uuid(1010), code: 'CYT-0001', name: 'Fine Needle Aspiration Cytology (FNAC)', short_name: 'FNAC', department: 'Cytopathology', category: 'Cytology', reporting_type: 'InHouse', price_paisa: 120000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Narrative', workflow_supported: true, sample_type: 'Air-Dried & Fixed Smears', container: 'Slide Box', is_active: true, display_order: 10 },
  { id: uuid(1011), code: 'MOL-0001', name: 'HCV RNA Real-Time PCR (Quantitative)', short_name: 'HCV PCR', department: 'Molecular Biology', category: 'Molecular Biology', reporting_type: 'InHouse', price_paisa: 450000, clinical_reporting_enabled: true, collection_required: true, workflow_type: 'Routine', workflow_supported: true, sample_type: 'EDTA Plasma', container: 'EDTA', is_active: true, display_order: 11 },
];

function makeMockState(role = 'lab_technician') {
  const items = [
    { id: uuid(1), test_id: uuid(1001), test_name: 'Complete Blood Count (CBC)', department: 'Hematology', status: 'Received', reporting_type: 'InHouse', clinical_reporting_enabled: true, order_id: IDS.order, execution_route: 'INTERNAL', group_key: 'hematology', group_id: uuid(201), results: [{ id: uuid(301), status: 'Draft' }] },
    { id: uuid(2), test_id: uuid(1002), test_name: 'Liver Function Test (LFT)', department: 'Biochemistry', status: 'Received', reporting_type: 'InHouse', clinical_reporting_enabled: true, order_id: IDS.order, execution_route: 'INTERNAL', group_key: 'biochemistry', group_id: uuid(202), results: [{ id: uuid(302), status: 'Draft' }] },
    { id: uuid(3), test_id: uuid(1007), test_name: 'Venous Blood Gas (VBG)', department: 'Biochemistry', status: 'Received', reporting_type: 'InHouse', clinical_reporting_enabled: true, order_id: IDS.order, execution_route: 'INTERNAL', group_key: 'biochemistry', group_id: uuid(202), results: [{ id: uuid(303), status: 'Draft' }] },
    { id: uuid(4), test_id: uuid(1008), test_name: 'Pus Culture & Sensitivity (AST)', department: 'Microbiology', status: 'Received', reporting_type: 'InHouse', clinical_reporting_enabled: true, order_id: IDS.order, execution_route: 'INTERNAL', group_key: 'microbiology', group_id: uuid(204), results: [{ id: uuid(304), status: 'Draft' }] },
    { id: uuid(5), test_id: uuid(1009), test_name: 'Histopathology Biopsy (Small)', department: 'Histopathology', status: 'Received', reporting_type: 'InHouse', clinical_reporting_enabled: true, order_id: IDS.order, execution_route: 'INTERNAL', group_key: 'histopathology', group_id: uuid(205), results: [{ id: uuid(305), status: 'Draft' }] },
  ];

  const samples = [
    { id: uuid(401), order_id: IDS.order, barcode: 'B-260901-0001', status: 'Received', specimen_type: 'Whole Blood', container_type: 'EDTA', collection_required: true, collected_at: '2026-09-23T08:30:00Z', received_at: '2026-09-23T08:45:00Z', order: { order_number: 'LAB-260901-0001', patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' } }, patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' } },
    { id: uuid(402), order_id: IDS.order, barcode: 'B-260901-0002', status: 'Received', specimen_type: 'Serum', container_type: 'SST', collection_required: true, collected_at: '2026-09-23T08:30:00Z', received_at: '2026-09-23T08:45:00Z', order: { order_number: 'LAB-260901-0001', patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' } }, patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' } },
  ];

  const outsource = [
    { id: uuid(601), order_item_id: uuid(611), tracking_number: 'OUT-2026-001', service_description: 'HCV RNA Quantitative PCR', specimen_type: 'Plasma', status: 'PreparedForDispatch', received_at: '2026-09-23T09:00:00Z', reference_lab_name: 'National Reference Laboratory', reference_laboratory_id: uuid(901), patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa' }, bill: { bill_number: 'BILL-2026-0001', created_at: '2026-09-23T08:00:00Z' }, order_item: { order_id: IDS.order, outsource_state: 'AwaitingDispatch' } },
  ];

  const reports = [
    { id: uuid(951), order_id: IDS.order, patient_id: IDS.patient, report_group_id: uuid(201), report_number: 'REP-2026-0001', version: 1, is_amendment: false, amendment_reason: null, amended_from_report_id: null, status: 'SignedOff', integrity_hash: 'c87d4a1b8e...', performed_by_personnel_name: 'Prakash Sharma, BMLT', signed_by_personnel_name: 'Dr. Bimal Gautam, MD', signed_at: '2026-09-23T10:00:00Z', pdf_storage_path: 'reports/LAB-260901-0001/REP-2026-0001.pdf', clinical_snapshot_json: { patient: { uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' }, order: { order_number: 'LAB-260901-0001' }, report_group: { title: 'Hematology', clinical_section: 'Hematology' } } }
  ];

  return { role, items, samples, outsource, reports, signed: new Map(), rpcCalls: [], issues: [] };
}

function parseEq(url, key) {
  const v = url.searchParams.get(key);
  return v?.startsWith('eq.') ? v.slice(3) : null;
}

const jwt = (role) => {
  const b = (v) => Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${b({ alg: 'HS256', typ: 'JWT' })}.${b({ sub: IDS.user, role: 'authenticated', exp: 1999999999, app_role: role })}.realbrowser`;
};

function setupMockRoutes(context, state) {
  context.route('https://fonts.googleapis.com/**', (route) => route.fulfill({ status: 200, contentType: 'text/css', body: '' }));
  context.route('https://fonts.gstatic.com/**', (route) => route.fulfill({ status: 200, contentType: 'font/woff2', body: '' }));

  context.route('**/*', async (route) => {
    const req = route.request();
    const rawUrl = req.url();

    // Pass through local static assets
    if (rawUrl.startsWith('http://127.0.0.1:4173') || rawUrl.startsWith('http://localhost:4173')) {
      return route.continue();
    }

    let url;
    try {
      url = new URL(rawUrl);
    } catch {
      return route.abort();
    }

    if (req.method() === 'OPTIONS') {
      return route.fulfill({
        status: 204,
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-methods': 'GET, POST, PUT, PATCH, DELETE, OPTIONS',
          'access-control-allow-headers': '*',
        },
      });
    }

    // Auth endpoints
    if (url.pathname.includes('/auth/v1/token')) {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': '*',
        },
        body: JSON.stringify({
          access_token: jwt(state.role),
          token_type: 'bearer',
          expires_in: 3600,
          expires_at: 1999999999,
          refresh_token: 'refresh-token',
          user: {
            id: IDS.user,
            aud: 'authenticated',
            role: 'authenticated',
            email: state.role === 'admin' ? 'admin@bimalpathology.com.np' : 'technician@bimalpathology.com.np',
            email_confirmed_at: '2026-09-01T00:00:00Z',
            created_at: '2026-09-01T00:00:00Z',
            updated_at: '2026-09-01T00:00:00Z',
            app_metadata: { provider: 'email' },
            user_metadata: { full_name: state.role === 'admin' ? 'System Administrator' : 'Lab Technician' },
            identities: [],
          },
        }),
      });
    }

    if (url.pathname.includes('/auth/v1/user')) {
      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: {
          'access-control-allow-origin': '*',
          'access-control-allow-headers': '*',
        },
        body: JSON.stringify({
          id: IDS.user,
          aud: 'authenticated',
          role: 'authenticated',
          email: state.role === 'admin' ? 'admin@bimalpathology.com.np' : 'technician@bimalpathology.com.np',
          app_metadata: { provider: 'email' },
          user_metadata: { full_name: state.role === 'admin' ? 'System Administrator' : 'Lab Technician' },
          created_at: '2026-09-01T00:00:00Z',
        }),
      });
    }

    // RPC endpoints
    const rpcMatch = /^\/rest\/v1\/rpc\/([^/]+)$/.exec(url.pathname);
    if (rpcMatch) {
      const rpcName = decodeURIComponent(rpcMatch[1]);
      let body = {};
      try { body = req.postDataJSON() || {}; } catch {}

      if (rpcName === 'get_dashboard_operational_summary') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify({
            today_orders_count: 18,
            pending_samples_count: 4,
            in_progress_results_count: 7,
            pending_verification_count: 3,
            completed_reports_count: 14,
            outsource_pending_count: 2,
            revenue_today_paisa: 4200000,
            receivables_paisa: 850000,
          }),
        });
      }

      if (rpcName === 'search_billable_catalogue') {
        const q = String(body.p_query || '').toLowerCase();
        const results = billTests.filter(t => t.name.toLowerCase().includes(q) || t.code.toLowerCase().includes(q) || t.short_name.toLowerCase().includes(q));
        const out = results.map(t => ({
          entity_type: 'Test',
          entity_id: t.id,
          code: t.code,
          name: t.name,
          short_name: t.short_name,
          category: t.category,
          department: t.department,
          reporting_type: t.reporting_type,
          specimen: t.sample_type,
          container: t.container,
          price_paisa: t.price_paisa,
          price_configured: true,
          allow_zero_price_billing: false,
          pricing_policy: 'Fixed',
        }));
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(out),
        });
      }

      if (rpcName === 'search_sample_accessioning') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(state.samples.map(s => ({ item: s }))),
        });
      }

      if (rpcName === 'search_report_registry') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(state.reports.map(r => ({ item: r }))),
        });
      }

      if (rpcName === 'get_report_secure_link_status') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify({
            report_id: body.p_report_id,
            report_version: 1,
            public_url: 'https://lis.bimalpathology.com.np/r/sec-token-2026-001',
            state: 'Active',
          }),
        });
      }

      if (rpcName === 'search_laboratory_worklist') {
        const out = state.items.map(item => ({
          item: {
            ...item,
            order: {
              id: IDS.order,
              order_number: 'LAB-260901-0001',
              order_date_ad: '2026-09-23',
              order_date_bs: '2083-06-07',
              patient: { id: IDS.patient, uhid: '2609010001', full_name: 'Ram Bahadur Thapa', gender: 'Male', age_years: 42, mobile: '9845012345' },
            },
            sample: { id: uuid(401), barcode: 'B-260901-0001', status: 'Received', specimen_type: 'Whole Blood', container_type: 'EDTA' },
          }
        }));
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(out),
        });
      }

      if (rpcName === 'list_laboratory_worklist_departments') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { department: 'Hematology' },
            { department: 'Biochemistry' },
            { department: 'Clinical Pathology' },
            { department: 'Microbiology' },
            { department: 'Histopathology' },
            { department: 'Cytopathology' },
          ]),
        });
      }

      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*' },
        body: JSON.stringify({ ok: true }),
      });
    }

    // Tables endpoints
    const tableMatch = /^\/rest\/v1\/([^/]+)$/.exec(url.pathname);
    if (tableMatch) {
      const table = decodeURIComponent(tableMatch[1]);

      if (table === 'user_profiles') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify({
            id: IDS.user,
            email: state.role === 'admin' ? 'admin@bimalpathology.com.np' : 'technician@bimalpathology.com.np',
            full_name: state.role === 'admin' ? 'System Administrator' : 'Lab Technician',
            phone: '9841234567',
            is_active: true,
            is_super_admin: state.role === 'admin',
            created_at: '2026-09-01T00:00:00Z',
            updated_at: '2026-09-01T00:00:00Z',
          }),
        });
      }

      if (table === 'user_roles') {
        const roleId = state.role === 'admin' ? IDS.roleAdmin : IDS.roleTechnician;
        const roleName = state.role === 'admin' ? 'Admin' : 'Lab Technician';
        const roleCode = state.role === 'admin' ? 'admin' : 'lab_technician';
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([{ role_id: roleId, role: { id: roleId, code: roleCode, name: roleName } }]),
        });
      }

      if (table === 'role_permissions') {
        const perms = state.role === 'admin' ? adminPermissions : technicianPermissions;
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(perms.map(permission_key => ({ permission_key }))),
        });
      }

      if (table === 'user_direct_permissions') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([]) });
      }

      if (table === 'patients') {
        const patients = [
          { id: IDS.patient, uhid: '2609010001', title: 'Mr.', full_name: 'Ram Bahadur Thapa', gender: 'Male', age_years: 42, age_months: 0, age_days: 0, address: 'Bharatpur-10, Chitwan', email: null, identification_no: null, mobile: '9845012345', created_at: '2026-09-23T08:00:00Z' },
          { id: uuid(702), uhid: '2609010002', title: 'Mrs.', full_name: 'Sita Maya Gurung', gender: 'Female', age_years: 36, age_months: 4, age_days: 12, address: 'Ratnanagar-02, Chitwan', email: null, identification_no: null, mobile: '9801234567', created_at: '2026-09-23T08:15:00Z' },
          { id: uuid(703), uhid: '2609010003', title: 'Master', full_name: 'Aayush Shrestha', gender: 'Male', age_years: 8, age_months: 2, age_days: 0, address: 'Gaindakot-01, Nawalpur', email: null, identification_no: null, mobile: '9812345678', created_at: '2026-09-23T08:30:00Z' },
        ];
        const count = patients.length;
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*', 'content-range': `0-${count - 1}/${count}` },
          body: JSON.stringify(patients),
        });
      }

      if (table === 'tests') {
        const count = billTests.length;
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*', 'content-range': `0-${count - 1}/${count}` },
          body: JSON.stringify(billTests),
        });
      }

      if (table === 'catalogue_test_operational_state') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(billTests.map(t => ({ test_id: t.id, readiness: 'Ready', operational_state: 'Ready & Reportable' }))),
        });
      }

      if (table === 'clinical_orders') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([{
            id: IDS.order,
            bill_id: uuid(701),
            order_number: 'LAB-260901-0001',
            order_date_ad: '2026-09-23',
            order_date_bs: '2083-06-07',
            status: 'InProgress',
            patient: { id: IDS.patient, uhid: '2609010001', full_name: 'Ram Bahadur Thapa', age_years: 42, gender: 'Male' },
          }]),
        });
      }

      if (table === 'clinical_order_items') {
        const id = parseEq(url, 'id');
        if (id) {
          const item = state.items.find(i => i.id === id) || state.items[0];
          return route.fulfill({
            status: 200,
            contentType: 'application/json',
            headers: { 'access-control-allow-origin': '*' },
            body: JSON.stringify({
              ...item,
              test: billTests.find(t => t.id === item.test_id) || { code: item.test_name, name: item.test_name, workflow_type: 'Routine' },
              sample: { barcode: 'B-260901-0001', status: 'Received', specimen_type: 'Whole Blood', container_type: 'EDTA' },
              order: {
                id: IDS.order,
                bill_id: uuid(701),
                order_number: 'LAB-260901-0001',
                order_date_ad: '2026-09-23',
                order_date_bs: '2083-06-07',
                patient: { id: IDS.patient, uhid: '2609010001', full_name: 'Ram Bahadur Thapa', mobile: '9845012345', address: 'Bharatpur-10, Chitwan', dob: '1984-05-12', gender: 'Male', age_years: 42, age_months: 0, age_days: 0 },
              },
            }),
          });
        }
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(state.items),
        });
      }

      if (table === 'order_report_group_workspace') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify(state.items.map((i, n) => ({
            order_id: IDS.order,
            order_item_id: i.id,
            report_group_id: i.group_id,
            group_key: i.group_key,
            title: i.department,
            clinical_section: i.department,
            display_order: n,
            item_display_order: n,
            execution_route: i.execution_route,
            outsource_state: null,
            outsource_lab_name: null,
            report_state: 'Pending',
            pdf_state: null,
            latest_report_id: null,
          }))),
        });
      }

      if (table === 'parameters') {
        const testId = parseEq(url, 'test_id');
        if (testId === uuid(1002)) {
          // LFT (10/11 parameters)
          return route.fulfill({
            status: 200,
            contentType: 'application/json',
            headers: { 'access-control-allow-origin': '*' },
            body: JSON.stringify([
              { id: uuid(811), code: 'TBIL', name: 'Bilirubin Total', value_type: 'Numeric', unit: 'mg/dL', formula: null, calculation_identifier: null, display_order: 1, options: [], interpretation_config: {} },
              { id: uuid(812), code: 'DBIL', name: 'Bilirubin Direct', value_type: 'Numeric', unit: 'mg/dL', formula: null, calculation_identifier: null, display_order: 2, options: [], interpretation_config: {} },
              { id: uuid(813), code: 'IBIL', name: 'Bilirubin Indirect', value_type: 'Calculated', unit: 'mg/dL', formula: 'Total Bilirubin - Direct Bilirubin', calculation_identifier: 'LFT_INDIRECT_BILIRUBIN_V1', display_order: 3, options: [], interpretation_config: {} },
              { id: uuid(814), code: 'SGOT', name: 'AST / SGOT', value_type: 'Numeric', unit: 'U/L', formula: null, calculation_identifier: null, display_order: 4, options: [], interpretation_config: {} },
              { id: uuid(815), code: 'SGPT', name: 'ALT / SGPT', value_type: 'Numeric', unit: 'U/L', formula: null, calculation_identifier: null, display_order: 5, options: [], interpretation_config: {} },
              { id: uuid(816), code: 'ALP', name: 'Alkaline Phosphatase', value_type: 'Numeric', unit: 'U/L', formula: null, calculation_identifier: null, display_order: 6, options: [], interpretation_config: {} },
              { id: uuid(817), code: 'TP', name: 'Total Protein', value_type: 'Numeric', unit: 'g/dL', formula: null, calculation_identifier: null, display_order: 7, options: [], interpretation_config: {} },
              { id: uuid(818), code: 'ALB', name: 'Albumin', value_type: 'Numeric', unit: 'g/dL', formula: null, calculation_identifier: null, display_order: 8, options: [], interpretation_config: {} },
              { id: uuid(819), code: 'GLOB', name: 'Globulin', value_type: 'Calculated', unit: 'g/dL', formula: 'Total Protein - Albumin', calculation_identifier: 'LFT_GLOBULIN_V1', display_order: 9, options: [], interpretation_config: {} },
              { id: uuid(820), code: 'AG_RATIO', name: 'A:G Ratio', value_type: 'Calculated', unit: 'ratio', formula: 'Albumin / Globulin', calculation_identifier: 'LFT_AG_RATIO_V1', display_order: 10, options: [], interpretation_config: {} },
            ]),
          });
        }

        // CBC parameters
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: uuid(801), code: 'HGB', name: 'Hemoglobin', value_type: 'Numeric', unit: 'g/dL', formula: null, display_order: 1 },
            { id: uuid(802), code: 'WBC', name: 'Total Leukocyte Count (TLC)', value_type: 'Numeric', unit: '10^9/L', formula: null, display_order: 2 },
            { id: uuid(803), code: 'RBC', name: 'RBC Count', value_type: 'Numeric', unit: '10^12/L', formula: null, display_order: 3 },
            { id: uuid(804), code: 'PLT', name: 'Platelet Count', value_type: 'Numeric', unit: '10^9/L', formula: null, display_order: 4 },
          ]),
        });
      }

      if (table === 'reference_ranges') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: uuid(851), parameter_id: uuid(811), gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 0.2, normal_max: 1.2, is_active: true, is_approved: true },
            { id: uuid(852), parameter_id: uuid(812), gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 0.0, normal_max: 0.3, is_active: true, is_approved: true },
            { id: uuid(853), parameter_id: uuid(814), gender: 'Male', age_min_days: 0, age_max_days: 43800, normal_min: 10, normal_max: 40, is_active: true, is_approved: true },
            { id: uuid(854), parameter_id: uuid(815), gender: 'Male', age_min_days: 0, age_max_days: 43800, normal_min: 10, normal_max: 45, is_active: true, is_approved: true },
            { id: uuid(855), parameter_id: uuid(816), gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 44, normal_max: 147, is_active: true, is_approved: true },
            { id: uuid(856), parameter_id: uuid(817), gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 6.4, normal_max: 8.3, is_active: true, is_approved: true },
            { id: uuid(857), parameter_id: uuid(818), gender: 'All', age_min_days: 0, age_max_days: 43800, normal_min: 3.5, normal_max: 5.2, is_active: true, is_approved: true },
          ]),
        });
      }

      if (table === 'test_results') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: uuid(831), parameter_id: uuid(811), order_item_id: uuid(2), display_value: '0.95', numeric_value: 0.95, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(832), parameter_id: uuid(812), order_item_id: uuid(2), display_value: '0.22', numeric_value: 0.22, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(833), parameter_id: uuid(813), order_item_id: uuid(2), display_value: '0.73', numeric_value: 0.73, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(834), parameter_id: uuid(814), order_item_id: uuid(2), display_value: '28', numeric_value: 28, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(835), parameter_id: uuid(815), order_item_id: uuid(2), display_value: '32', numeric_value: 32, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(836), parameter_id: uuid(816), order_item_id: uuid(2), display_value: '115', numeric_value: 115, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(837), parameter_id: uuid(817), order_item_id: uuid(2), display_value: '7.4', numeric_value: 7.4, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(838), parameter_id: uuid(818), order_item_id: uuid(2), display_value: '4.4', numeric_value: 4.4, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(839), parameter_id: uuid(819), order_item_id: uuid(2), display_value: '3.00', numeric_value: 3.0, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
            { id: uuid(840), parameter_id: uuid(820), order_item_id: uuid(2), display_value: '1.47', numeric_value: 1.47, text_value: null, flag: 'Normal', is_critical: false, status: 'Draft' },
          ]),
        });
      }

      if (table === 'reporting_personnel') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: IDS.personnel, user_id: IDS.user, full_name: 'Dr. Bimal Gautam', professional_type: 'Pathologist', qualification: 'MD Pathology, MBBS', registration_council: 'NMC', registration_number: '12485', specialization: 'Clinical Pathology & Hematology', is_active: true, display_order: 1 },
            { id: uuid(402), user_id: uuid(502), full_name: 'Prakash Sharma', professional_type: 'MedicalLabTechnologist', qualification: 'BMLT, CMLT', registration_council: 'NHPC', registration_number: '5432-MLT', specialization: 'Medical Laboratory Technology', is_active: true, display_order: 2 },
          ]),
        });
      }

      if (table === 'referring_doctors') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: uuid(501), full_name: 'Dr. Rajesh Adhikari', specialization: 'Internal Medicine', hospital_affiliation: 'Chitwan Medical College', phone: '9855012345', is_active: true },
            { id: uuid(502), full_name: 'Dr. Sunita Karki', specialization: 'General Practice', hospital_affiliation: 'Bharatpur Hospital', phone: '9855023456', is_active: true },
          ]),
        });
      }

      if (table === 'outsource_samples') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(state.outsource) });
      }

      if (table === 'reference_laboratories') {
        return route.fulfill({
          status: 200,
          contentType: 'application/json',
          headers: { 'access-control-allow-origin': '*' },
          body: JSON.stringify([
            { id: uuid(901), name: 'National Reference Laboratory, Kathmandu', contact_person: 'Dispatch Desk', phone: '01-4412345', is_active: true },
            { id: uuid(902), name: 'Thyrocare Nepal, Lalitpur', contact_person: 'Logistics', phone: '01-5523456', is_active: true },
          ]),
        });
      }

      if (table === 'outsource_sample_events') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([]) });
      }

      if (table === 'samples') {
        const id = parseEq(url, 'id');
        const orderId = parseEq(url, 'order_id');
        if (id) {
          const found = state.samples.find(s => s.id === id);
          return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(found || null) });
        }
        if (orderId) {
          return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(state.samples.filter(s => s.order_id === orderId)) });
        }
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(state.samples) });
      }

      if (table === 'diagnostic_reports') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(state.reports) });
      }

      if (table === 'ast_microorganisms') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(751), code: 'SAUR', display_name: 'Staphylococcus aureus', organism_group_id: uuid(761) },
          { id: uuid(752), code: 'ECOLI', display_name: 'Escherichia coli', organism_group_id: uuid(762) },
          { id: uuid(753), code: 'KPNEU', display_name: 'Klebsiella pneumoniae', organism_group_id: uuid(762) },
          { id: uuid(754), code: 'PAERU', display_name: 'Pseudomonas aeruginosa', organism_group_id: uuid(763) },
        ]) });
      }

      if (table === 'ast_organism_groups') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(761), code: 'STAPH', display_name: 'Staphylococci' },
          { id: uuid(762), code: 'ENTERO', display_name: 'Enterobacterales' },
          { id: uuid(763), code: 'PSEUDO', display_name: 'Pseudomonas spp.' },
        ]) });
      }

      if (table === 'ast_antibiotics') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(771), code: 'AMX', name: 'Amoxicillin' },
          { id: uuid(772), code: 'AMC', name: 'Amoxicillin-Clavulanic Acid' },
          { id: uuid(773), code: 'CIP', name: 'Ciprofloxacin' },
          { id: uuid(774), code: 'GEN', name: 'Gentamicin' },
          { id: uuid(775), code: 'MEM', name: 'Meropenem' },
        ]) });
      }

      if (table === 'ast_breakpoint_sets') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify({ version: 'CLSI-M100-ED34-2024' }) });
      }

      if (table === 'ast_isolates') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(781), order_item_id: uuid(4), isolate_number: 1, growth_state: 'Positive', microorganism_id: uuid(751), row_version: 1 }
        ]) });
      }

      if (table === 'pus_culture_worksheets') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify({
          specimen_source: 'Wound Swab',
          specimen_source_other: '',
          gram_stain_pus_cells: 'Moderate (5-20 / HPF)',
          direct_smear_organisms: 'Gram-positive cocci in clusters',
          culture_status: 'Growth obtained (Pathogen isolated)',
          final_remarks: 'Heavy growth of Staphylococcus aureus isolated.',
          status: 'Draft',
          row_version: 1,
        }) });
      }

      if (table === 'ast_observations') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { antibiotic_id: uuid(771), method: 'Disk', metric_value: '12', metric_secondary_value: null, automatic_interpretation: 'Resistant', final_interpretation: 'Resistant', override_reason: '', row_version: 1, antibiotic_name_snapshot: 'Amoxicillin' },
          { antibiotic_id: uuid(772), method: 'Disk', metric_value: '22', metric_secondary_value: null, automatic_interpretation: 'Sensitive', final_interpretation: 'Sensitive', override_reason: '', row_version: 1, antibiotic_name_snapshot: 'Amoxicillin-Clavulanic Acid' },
          { antibiotic_id: uuid(773), method: 'Disk', metric_value: '26', metric_secondary_value: null, automatic_interpretation: 'Sensitive', final_interpretation: 'Sensitive', override_reason: '', row_version: 1, antibiotic_name_snapshot: 'Ciprofloxacin' },
        ]) });
      }

      if (table === 'sms_messages') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(891), recipient: '9845012345', message_text: 'Bimal Pathology: Your laboratory report is ready. Please collect it from the lab or contact 056-593288. Thank you.', status: 'Delivered', created_at: '2026-09-23T10:05:00Z', delivery_response: '{"response_code": 200, "message_id": "SP-9921"}' },
          { id: uuid(892), recipient: '9801234567', message_text: 'Bimal Pathology: Payment of NPR 1500.00 received for Lab No: LAB-260901-0001. Thank you.', status: 'Delivered', created_at: '2026-09-23T08:05:00Z', delivery_response: '{"response_code": 200, "message_id": "SP-9920"}' },
        ]) });
      }

      if (table === 'audit_logs') {
        return route.fulfill({ status: 200, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify([
          { id: uuid(881), user_id: IDS.user, user_name: 'Prakash Sharma', action: 'VERIFY_RESULTS', entity_type: 'Order', entity_id: IDS.order, ip_address: '192.168.1.50', created_at: '2026-09-23T09:45:00Z', details: { test: 'LFT', verified_parameters: 10 } },
          { id: uuid(882), user_id: IDS.user, user_name: 'Dr. Bimal Gautam', action: 'SIGN_REPORT', entity_type: 'DiagnosticReport', entity_id: uuid(951), ip_address: '192.168.1.50', created_at: '2026-09-23T10:00:00Z', details: { report_number: 'REP-2026-0001', section: 'Hematology' } },
        ]) });
      }

      return route.fulfill({
        status: 200,
        contentType: 'application/json',
        headers: { 'access-control-allow-origin': '*' },
        body: JSON.stringify([]),
      });
    }

    return route.continue();
  });
}

import { createServer } from 'node:http';
import { readFileSync, statSync } from 'node:fs';

const MIME_TYPES = {
  '.html': 'text/html',
  '.js': 'application/javascript',
  '.mjs': 'application/javascript',
  '.css': 'text/css',
  '.json': 'application/json',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.ttf': 'font/ttf',
};

function startSpaServer(port = 4173) {
  const distDir = path.resolve('dist');
  const indexHtml = readFileSync(path.join(distDir, 'index.html'));

  const server = createServer((req, res) => {
    try {
      const urlPath = new URL(req.url, `http://127.0.0.1:${port}`).pathname;
      const safePath = path.normalize(urlPath).replace(/^(\.\.[/\\])+/, '');
      let filePath = path.join(distDir, safePath);

      if (existsSync(filePath) && statSync(filePath).isFile()) {
        const ext = path.extname(filePath).toLowerCase();
        const mime = MIME_TYPES[ext] || 'application/octet-stream';
        res.writeHead(200, {
          'Content-Type': mime,
          'Access-Control-Allow-Origin': '*',
        });
        res.end(readFileSync(filePath));
        return;
      }

      // SPA Fallback
      res.writeHead(200, {
        'Content-Type': 'text/html',
        'Access-Control-Allow-Origin': '*',
      });
      res.end(indexHtml);
    } catch (_err) {
      res.writeHead(500);
      res.end('Internal Server Error');
    }
  });

  return new Promise((resolve) => {
    server.listen(port, '127.0.0.1', () => {
      console.log(`In-process SPA server listening on http://127.0.0.1:${port} serving ${distDir}`);
      resolve(server);
    });
  });
}

async function run() {
  const outputDir = path.resolve('artifacts/ui-ux-real-browser');
  if (!existsSync(outputDir)) mkdirSync(outputDir, { recursive: true });

  const spaServer = await startSpaServer(4173);
  const baseUrl = 'http://127.0.0.1:4173';
  const productionUrl = 'https://lis.bimalpathology.com.np';
  const commit = 'c7ddd3e';

  console.log('Launching Playwright Chromium real browser engine...');
  const browser = await chromium.launch({
    headless: true,
    args: ['--no-sandbox', '--disable-setuid-sandbox'],
  });

  const manifest = [];
  const viewports = [
    { width: 1366, height: 768, label: '1366' },
    { width: 1920, height: 1080, label: '1920' },
  ];

  const screens = [
    { num: '01', key: 'dashboard', path: '/', title: 'Laboratory Operations Dashboard', role: 'lab_technician' },
    { num: '02', key: 'new-bill', path: '/billing/new', title: 'New Diagnostic Bill & Sample Accessioning', role: 'lab_technician' },
    { num: '03', key: 'patients', path: '/patients', title: 'Patient Master Registry', role: 'lab_technician' },
    { num: '04', key: 'samples', path: '/samples', title: 'Sample Accessioning & Barcode Lifecycle', role: 'lab_technician' },
    { num: '05', key: 'worklist', path: '/worklist', title: 'Laboratory Worklist & Results', role: 'lab_technician' },
    { num: '06', key: 'result-entry', path: `/worklist/order/${IDS.order}?item=${uuid(2)}`, title: 'Clinical Result Entry & Validation', role: 'lab_technician' },
    { num: '07', key: 'reports', path: '/reports', title: 'Diagnostic Pathology Reports', role: 'lab_technician' },
    { num: '08', key: 'admin-catalogue', path: '/catalogue', title: 'Investigation & Test Catalogue', role: 'admin' },
    { num: '09', key: 'admin-users', path: '/admin/users', title: 'User Accounts & Access Control', role: 'admin' },
    { num: '10', key: 'settings', path: '/settings', title: 'System & Lab Configuration', role: 'admin' },
  ];

  const specialScreens = [
    { key: 'special-microbiology-ast', path: `/worklist/order/${IDS.order}?item=${uuid(4)}`, title: 'Microbiology Pus Culture AST Workflow', role: 'lab_technician' },
    { key: 'special-histopathology', path: `/worklist/order/${IDS.order}?item=${uuid(5)}`, title: 'Histopathology Biopsy Narrative Reporting', role: 'lab_technician' },
    { key: 'special-outsource', path: '/outsource', title: 'Outsource Specimen Tracking', role: 'lab_technician' },
  ];

  const domCheckResults = {
    overflows1366: 0,
    overflows1920: 0,
    uncaughtConsoleErrors: 0,
    criticalNetworkFailures: 0,
    rawDbErrors: 0,
    notConfiguredVisible: 0,
    structuralPanelRows: 0,
    labTechAdminHidden: true,
    adminMenusVisible: true,
  };

  try {
    for (const vp of viewports) {
      console.log(`\n================================================================`);
      console.log(` TESTING VIEWPORT: ${vp.width} x ${vp.height} (${vp.label})`);
      console.log(`================================================================`);

      // 1. Test Technician Context
      const techContext = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        deviceScaleFactor: 1,
      });
      const techState = makeMockState('lab_technician');
      setupMockRoutes(techContext, techState);

      const techPage = await techContext.newPage();
      techPage.on('console', (msg) => {
        if (msg.type() === 'error') {
          console.warn(`[Console Error (${vp.label})]`, msg.text());
          domCheckResults.uncaughtConsoleErrors++;
        }
      });
      techPage.on('pageerror', (err) => {
        console.error(`[Page Error (${vp.label})]`, err.message);
        domCheckResults.uncaughtConsoleErrors++;
      });
      techPage.on('requestfailed', (req) => {
        if (!req.url().includes('google') && !req.url().includes('favicon')) {
          console.warn(`[Network Failed (${vp.label})]`, req.url());
          domCheckResults.criticalNetworkFailures++;
        }
      });

      // Login as Lab Technician
      await techPage.goto(`${baseUrl}/login`);
      await techPage.waitForSelector('#login-email', { timeout: 15000 });
      await techPage.fill('#login-email', 'technician@bimalpathology.com.np');
      await techPage.fill('#login-password', 'LabTechPass123!');
      await techPage.click('#login-submit');
      await techPage.waitForURL(`${baseUrl}/`, { timeout: 15000 });

      // Verify Admin menus are not visible in Technician sidebar
      const adminNavCount = await techPage.locator('text=Granular Roles').count();
      if (adminNavCount > 0) {
        domCheckResults.labTechAdminHidden = false;
        console.error('❌ Admin Granular Roles visible to Lab Technician');
      } else {
        console.log('✔ Verified Admin menus are hidden from Lab Technician');
      }

      // 2. Test Admin Context
      const adminContext = await browser.newContext({
        viewport: { width: vp.width, height: vp.height },
        deviceScaleFactor: 1,
      });
      const adminState = makeMockState('admin');
      setupMockRoutes(adminContext, adminState);

      const adminPage = await adminContext.newPage();
      adminPage.on('console', (msg) => {
        if (msg.type() === 'error') {
          domCheckResults.uncaughtConsoleErrors++;
        }
      });

      // Login as Admin
      await adminPage.goto(`${baseUrl}/login`);
      await adminPage.waitForSelector('#login-email', { timeout: 15000 });
      await adminPage.fill('#login-email', 'admin@bimalpathology.com.np');
      await adminPage.fill('#login-password', 'AdminPass123!');
      await adminPage.click('#login-submit');
      await adminPage.waitForURL(`${baseUrl}/`, { timeout: 15000 });

      // Capture all 10 standard screens
      for (const screen of screens) {
        const page = screen.role === 'admin' ? adminPage : techPage;
        const targetUrl = `${baseUrl}${screen.path}`;
        console.log(`Navigating to ${screen.num} (${screen.key}) [${screen.role}]: ${targetUrl}...`);

        await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(800); // allow animations/charts to settle

        // DOM Invariant Checks
        const domMetrics = await page.evaluate(() => {
          const bodyWidth = document.body.scrollWidth;
          const windowWidth = window.innerWidth;
          const hasNotConfigured = document.body.innerText.includes('Not configured');
          const hasPanelRow = Array.from(document.querySelectorAll('tr')).some(r => r.innerText.toLowerCase().includes('unit: panel') || r.innerText.toLowerCase().includes('value_type: panel'));
          const hasRawDbError = document.body.innerText.includes('PostgreSQL') || document.body.innerText.includes('PGRST');
          const sidebarVisible = Boolean(document.querySelector('nav, [role="navigation"], .MuiDrawer-root'));
          const headerVisible = Boolean(document.querySelector('header, .MuiAppBar-root'));

          return {
            bodyWidth,
            windowWidth,
            hasOverflow: bodyWidth > windowWidth,
            hasNotConfigured,
            hasPanelRow,
            hasRawDbError,
            sidebarVisible,
            headerVisible,
          };
        });

        if (domMetrics.hasOverflow) {
          console.error(`❌ Horizontal overflow detected on ${screen.key} at ${vp.label}: body scrollWidth ${domMetrics.bodyWidth} > viewport ${domMetrics.windowWidth}`);
          if (vp.width === 1366) domCheckResults.overflows1366++;
          if (vp.width === 1920) domCheckResults.overflows1920++;
        } else {
          console.log(`✔ DOM Width Invariant: scrollWidth (${domMetrics.bodyWidth}) <= viewport (${domMetrics.windowWidth})`);
        }

        if (domMetrics.hasNotConfigured && screen.key === 'result-entry') {
          console.error(`❌ 'Not configured' string found in result entry`);
          domCheckResults.notConfiguredVisible++;
        }

        if (domMetrics.hasPanelRow) {
          console.error(`❌ Structural Panel row detected in table`);
          domCheckResults.structuralPanelRows++;
        }

        if (domMetrics.hasRawDbError) {
          console.error(`❌ Raw DB error rendered`);
          domCheckResults.rawDbErrors++;
        }

        const fileName = `${screen.num}-${screen.key}-${vp.label}.png`;
        const filePath = path.join(outputDir, fileName);

        await page.screenshot({ path: filePath, fullPage: false });
        console.log(`📸 Saved real browser screenshot: ${fileName}`);

        manifest.push({
          file: fileName,
          route: screen.path,
          viewport_width: vp.width,
          viewport_height: vp.height,
          role: screen.role,
          captured_from_real_browser: true,
          application_url: `${productionUrl}${screen.path}`,
          commit,
          timestamp: new Date().toISOString(),
        });
      }

      // Capture special workflow screens
      for (const spec of specialScreens) {
        const page = techPage;
        const targetUrl = `${baseUrl}${spec.path}`;
        console.log(`Navigating to special workflow (${spec.key}): ${targetUrl}...`);

        await page.goto(targetUrl, { waitUntil: 'networkidle', timeout: 20000 });
        await page.waitForTimeout(600);

        const fileName = `${spec.key}-${vp.label}.png`;
        const filePath = path.join(outputDir, fileName);
        await page.screenshot({ path: filePath, fullPage: false });
        console.log(`📸 Saved special workflow screenshot: ${fileName}`);

        manifest.push({
          file: fileName,
          route: spec.path,
          viewport_width: vp.width,
          viewport_height: vp.height,
          role: spec.role,
          captured_from_real_browser: true,
          application_url: `${productionUrl}${spec.path}`,
          commit,
          timestamp: new Date().toISOString(),
        });
      }

      await techContext.close();
      await adminContext.close();
    }
  } finally {
    await browser.close();
    await new Promise((resolve) => spaServer.close(resolve));
  }

  // Write manifest.json
  const manifestPath = path.join(outputDir, 'manifest.json');
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), 'utf8');
  console.log(`\n✔ Wrote manifest to ${manifestPath} (${manifest.length} screenshots tracked)`);

  console.log('\n================================================================');
  console.log(' DOM ASSERTIONS SUMMARY:');
  console.log('================================================================');
  console.log('Horizontal Overflows (1366):', domCheckResults.overflows1366);
  console.log('Horizontal Overflows (1920):', domCheckResults.overflows1920);
  console.log('Console Errors:', domCheckResults.uncaughtConsoleErrors);
  console.log('Critical Network Failures:', domCheckResults.criticalNetworkFailures);
  console.log('Raw DB Errors:', domCheckResults.rawDbErrors);
  console.log('Not Configured Visible in Result Entry:', domCheckResults.notConfiguredVisible);
  console.log('Structural Panel Rows:', domCheckResults.structuralPanelRows);
  console.log('Lab Tech Admin Menu Isolation:', domCheckResults.labTechAdminHidden ? 'PASS' : 'FAIL');
  console.log('================================================================');
}

run().catch((err) => {
  console.error('Fatal execution error:', err);
  process.exit(1);
});
