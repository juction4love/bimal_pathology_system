/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Clinical Report Snapshot, Date Formatting & Cryptographic Integrity Engine
 */

export interface ClinicalSnapshot {
  organization: {
    name_en: string;
    name_ne: string;
    address_en: string;
    address_ne: string;
    reg_no: string;
    pan_no: string;
    phone: string;
  };
  patient: {
    uhid: string;
    full_name: string;
    title?: string | null;
    mobile: string;
    gender: string;
    dob?: string | null;
    age_years?: number | null;
    age_months?: number | null;
    age_days?: number | null;
    address: string;
  };
  order: {
    order_number: string;
    bill_number: string;
    registered_date_ad: string;
    registered_date_bs: string;
    collected_at?: string | null;
    received_at?: string | null;
    reported_at?: string | null;
    referring_doctor_name: string;
  };
  signatories: {
    performed_by: {
      id: string;
      full_name: string;
      qualification: string;
      professional_type: string;
      registration_council: string;
      registration_number: string;
      signature_url?: string | null;
    };
    authorized_by: {
      id: string;
      full_name: string;
      qualification: string;
      professional_type: string;
      specialization?: string | null;
      registration_council: string;
      registration_number: string;
      signature_url?: string | null;
    } | null;
  };
  investigations: Array<{
    order_item_id: string;
    test_id: string;
    test_name: string;
    department: string;
    reporting_type: string;
    outsource_lab_name?: string | null;
    method?: string | null;
    interpretation_template?: string | null;
    specimen_type: string;
    container_type: string;
    results: Array<{
      parameter_id: string;
      code: string;
      name: string;
      value_type: string;
      display_value: string;
      numeric_value?: number | null;
      unit?: string | null;
      formula?: string | null;
      flag: string;
      is_critical: boolean;
      reference_range?: string | null;
      normal_min?: number | null;
      normal_max?: number | null;
      critical_low?: number | null;
      critical_high?: number | null;
    }>;
    ast_isolates?: Array<{
      isolate_number: number;
      organism: string;
      organism_group?: string | null;
      growth_state: 'Positive' | 'NoGrowth';
      breakpoint_reference?: string | null;
      observations: Array<{
        antibiotic: string;
        method: 'Disk' | 'MIC';
        metric_value: string | number;
        metric_secondary_value?: string | number | null;
        interpretation: 'S' | 'I' | 'R' | 'SDD';
        breakpoint_version?: string | null;
      }>;
    }>;
    pus_culture_worksheet?: {
      specimen_source:string; specimen_source_other?:string|null; gram_stain_pus_cells:string;
      direct_smear_organisms:string; culture_status:string; final_remarks:string; status:string; row_version:number;
    } | null;
  }>;
  meta: {
    version: number;
    is_amendment: boolean;
    amendment_reason?: string | null;
    amended_from_report_id?: string | null;
    signed_at: string;
    signed_by_user_id?: string | null;
  };
}

/**
 * Format Result Flag to standard clinical shortcode
 */
export function formatResultFlag(flag: string): { label: string; isAbnormal: boolean; isCritical: boolean } {
  switch (flag) {
    case 'CriticalLow':
      return { label: 'LL', isAbnormal: true, isCritical: true };
    case 'CriticalHigh':
      return { label: 'HH', isAbnormal: true, isCritical: true };
    case 'Low':
      return { label: 'L', isAbnormal: true, isCritical: false };
    case 'High':
      return { label: 'H', isAbnormal: true, isCritical: false };
    case 'Abnormal':
      return { label: 'A', isAbnormal: true, isCritical: false };
    case 'NoRange':
      return { label: '-', isAbnormal: false, isCritical: false };
    case 'Normal':
    default:
      return { label: '', isAbnormal: false, isCritical: false };
  }
}

/**
 * Computes deterministic SHA-256 hex string from clinical snapshot JSON
 */
export async function calculateSnapshotSha256(snapshot: ClinicalSnapshot): Promise<string> {
  const jsonStr = JSON.stringify(snapshot);
  const encoder = new TextEncoder();
  const data = encoder.encode(jsonStr);

  if (typeof crypto === 'undefined' || !crypto.subtle) {
    throw new Error('Secure SHA-256 hashing is unavailable in this browser.');
  }

  const hashBuffer = await crypto.subtle.digest('SHA-256', data);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map((b) => b.toString(16).padStart(2, '0')).join('');
}
