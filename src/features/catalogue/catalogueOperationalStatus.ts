export const CATALOGUE_OPERATIONAL_STATES = [
  'Ready & Reportable',
  'Requires Validation',
  'Validated (Inactive)',
  'Needs Attention',
  'Suspended',
  'Non-Reportable Service',
  'Inactive / Retired',
  'Inactive',
] as const;

export type CatalogueOperationalStatus = typeof CATALOGUE_OPERATIONAL_STATES[number];

type CatalogueStatusInput = {
  operational_state?: string | null;
  is_active: boolean;
  lifecycle_status: string;
  reporting_type: string;
  validation_status?: 'REQUIRES_VALIDATION' | 'VALIDATED' | string | null;
  clinical_reporting_enabled?: boolean;
};

export function catalogueOperationalStatus(test: CatalogueStatusInput): CatalogueOperationalStatus {
  if (test.validation_status === 'REQUIRES_VALIDATION') {
    return 'Requires Validation';
  }
  if (CATALOGUE_OPERATIONAL_STATES.includes(test.operational_state as CatalogueOperationalStatus)) {
    return test.operational_state as CatalogueOperationalStatus;
  }
  if (!test.is_active || test.lifecycle_status !== 'Active') {
    return test.validation_status === 'VALIDATED' ? 'Validated (Inactive)' : 'Inactive';
  }
  if (test.reporting_type === 'NoReporting') return 'Non-Reportable Service';
  return test.clinical_reporting_enabled ? 'Ready & Reportable' : 'Needs Attention';
}

export function catalogueOperationalStatusColor(status: CatalogueOperationalStatus): 'success' | 'default' | 'warning' | 'info' {
  if (status === 'Ready & Reportable') return 'success';
  if (status === 'Validated (Inactive)') return 'info';
  if (status === 'Requires Validation') return 'warning';
  if (status === 'Inactive' || status === 'Inactive / Retired') return 'default';
  return 'warning';
}

