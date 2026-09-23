/**
 * BIMAL PATHOLOGY - Granular Permissions and Role Definitions
 */

export const PERMISSION_KEYS = {
  CAN_VIEW_DASHBOARD: 'can_view_dashboard',
  CAN_CREATE_BILL: 'can_create_bill',
  CAN_EDIT_PATIENT: 'can_edit_patient',
  CAN_COLLECT_SAMPLE: 'can_collect_sample',
  CAN_RECEIVE_SAMPLE: 'can_receive_sample',
  CAN_REJECT_SAMPLE: 'can_reject_sample',
  CAN_ENTER_RESULTS: 'can_enter_results',
  CAN_VERIFY_RESULTS: 'can_verify_results',
  CAN_ACKNOWLEDGE_CRITICAL: 'can_acknowledge_critical',
  CAN_SIGN_REPORTS: 'can_sign_reports',
  CAN_AMEND_REPORTS: 'can_amend_reports',
  CAN_PRINT_REPORTS: 'can_print_reports',
  CAN_MANAGE_CATALOGUE: 'can_manage_catalogue',
  CAN_CONFIGURE_CATALOGUE_TECHNICAL: 'can_configure_catalogue_technical',
  CAN_MANAGE_AST_BREAKPOINTS: 'can_manage_ast_breakpoints',
  CAN_MANAGE_REFERRING_DOCTORS: 'can_manage_referring_doctors',
  CAN_MANAGE_PERSONNEL: 'can_manage_personnel',
  CAN_VIEW_FINANCIALS: 'can_view_financials',
  CAN_MANAGE_USERS: 'can_manage_users',
  CAN_MANAGE_ROLES: 'can_manage_roles',
  CAN_VIEW_AUDIT_LOGS: 'can_view_audit_logs',
  CAN_MANAGE_OUTSOURCE_TRACKING: 'can_manage_outsource_tracking',
  CAN_VIEW_HMIS_REPORTS: 'can_view_hmis_reports',
  CAN_EDIT_HMIS_REPORTS: 'can_edit_hmis_reports',
  CAN_FINALIZE_HMIS_REPORTS: 'can_finalize_hmis_reports',
} as const;

export type PermissionKey = typeof PERMISSION_KEYS[keyof typeof PERMISSION_KEYS];

export const ACTIVE_ROLE_CODES = ['lab_technician'] as const;
export const LAB_TECHNICIAN_PERMISSION_ALLOWLIST: PermissionKey[] = [
  PERMISSION_KEYS.CAN_VIEW_DASHBOARD,
  PERMISSION_KEYS.CAN_CREATE_BILL,
  PERMISSION_KEYS.CAN_EDIT_PATIENT,
  PERMISSION_KEYS.CAN_COLLECT_SAMPLE,
  PERMISSION_KEYS.CAN_RECEIVE_SAMPLE,
  PERMISSION_KEYS.CAN_REJECT_SAMPLE,
  PERMISSION_KEYS.CAN_ENTER_RESULTS,
  PERMISSION_KEYS.CAN_VERIFY_RESULTS,
  PERMISSION_KEYS.CAN_ACKNOWLEDGE_CRITICAL,
  PERMISSION_KEYS.CAN_SIGN_REPORTS,
  PERMISSION_KEYS.CAN_AMEND_REPORTS,
  PERMISSION_KEYS.CAN_PRINT_REPORTS,
  PERMISSION_KEYS.CAN_MANAGE_OUTSOURCE_TRACKING,
];

export const ADMIN_PERMISSION_ALLOWLIST: PermissionKey[] = Object.values(PERMISSION_KEYS);

export interface RoleDefinition {
  id: string;
  name: string;
  code: string;
  description: string;
  isSystem: boolean;
  permissions: PermissionKey[];
}

export const SYSTEM_ROLES: Record<string, { code: string; name: string; description: string; defaultPermissions: PermissionKey[] }> = {
  ADMIN: {
    code: 'admin',
    name: 'Administrator',
    description: 'Complete system, clinical master, security, and financial administration with full operational access.',
    defaultPermissions: ADMIN_PERMISSION_ALLOWLIST,
  },
  LAB_TECHNICIAN: {
    code: 'lab_technician',
    name: 'Lab Technician',
    description: 'Complete day-to-day pathology operations: patients, billing and payments, samples, results, verification, report authorization, and controlled amendments.',
    defaultPermissions: LAB_TECHNICIAN_PERMISSION_ALLOWLIST,
  },
  VERIFIER: {
    code: 'verifier',
    name: 'Verifier',
    description: 'Legacy compatibility role; consolidated into Lab Technician in the two-role workflow.',
    defaultPermissions: [
      PERMISSION_KEYS.CAN_VIEW_DASHBOARD,
      PERMISSION_KEYS.CAN_VERIFY_RESULTS,
      PERMISSION_KEYS.CAN_ACKNOWLEDGE_CRITICAL,
      PERMISSION_KEYS.CAN_PRINT_REPORTS,
    ],
  },
  SIGNATORY: {
    code: 'signatory',
    name: 'Signatory',
    description: 'Legacy compatibility role; consolidated into Lab Technician in the two-role workflow.',
    defaultPermissions: [
      PERMISSION_KEYS.CAN_VIEW_DASHBOARD,
      PERMISSION_KEYS.CAN_SIGN_REPORTS,
      PERMISSION_KEYS.CAN_AMEND_REPORTS,
      PERMISSION_KEYS.CAN_PRINT_REPORTS,
    ],
  },
};
