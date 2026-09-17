type ErrorLike = {
  code?: unknown;
  status?: unknown;
  message?: unknown;
};

export type SafeMessageVariant = 'success' | 'info' | 'warning' | 'error' | 'confirm';

export type SafeUserMessage = {
  variant: SafeMessageVariant;
  message: string;
  guidance?: string;
};

const includesAny = (value: string, terms: string[]) => terms.some((term) => value.includes(term));

export function mapSafeError(error: unknown, fallback = 'Something went wrong. Please try again.'): SafeUserMessage {
  const candidate = (error && typeof error === 'object' ? error : {}) as ErrorLike;
  const code = typeof candidate.code === 'string' ? candidate.code : '';
  const message = typeof candidate.message === 'string' ? candidate.message.toLowerCase() : '';

  if (message.includes('result_revision_conflict')) {
    return { variant: 'warning', message: 'Results changed in another session.', guidance: 'Reload Latest before trying again.' };
  }
  if (message.includes('result_collection_not_ready')) {
    return { variant: 'warning', message: 'Result entry is blocked until the required sample is ready.', guidance: 'Complete collection or accessioning, then reload the work item.' };
  }

  if (code === '42501' || includesAny(message, ['permission denied', 'access denied', 'row-level security'])) {
    return { variant: 'error', message: 'You do not have permission to perform this action.', guidance: 'Contact the Super Admin if you believe access is required.' };
  }
  if (includesAny(message, ['account is inactive', 'account is deactivated', 'user inactive'])) {
    return { variant: 'warning', message: 'Your account is inactive.', guidance: 'Contact the Super Admin to restore access.' };
  }
  if (includesAny(message, ['mobile number is already', 'duplicate mobile', 'uq_patients_mobile'])) {
    return { variant: 'warning', message: 'This mobile number is already registered.', guidance: 'Please verify the patient or use the existing patient record.' };
  }
  if (includesAny(message, ['already processed', 'idempotency', 'duplicate payment'])) {
    return { variant: 'info', message: 'This payment has already been processed.', guidance: 'Refresh the bill to view the latest balance.' };
  }
  if (includesAny(message, ['fully paid', 'exceeds the outstanding', 'overpayment'])) {
    return { variant: 'warning', message: 'Payment amount is greater than the outstanding balance.', guidance: 'Refresh the bill and enter an amount no greater than the balance due.' };
  }
  if (includesAny(message, ['can no longer be modified', 'signedoff', 'signed off', 'immutable'])) {
    return { variant: 'warning', message: 'This report can no longer be modified.', guidance: 'The report has already been signed.' };
  }
  if (includesAny(message, ['patient details changed', 'stale patient', 'stale mobile', 'patient binding', 'expected mobile'])) {
    return { variant: 'warning', message: 'Patient details changed. Refresh and try again.', guidance: 'Re-select the existing patient before continuing.' };
  }
  if (includesAny(message, ['invalid mobile', 'valid nepal mobile', 'malformed mobile'])) {
    return { variant: 'warning', message: 'Enter a valid Nepal mobile number.', guidance: 'Check the number and try again.' };
  }
  if (includesAny(message, ['calculation_dependencies_block_verification', 'calculation_dependency_missing'])) {
    return { variant: 'warning', message: 'Required clinical inputs are missing for calculated parameters.', guidance: 'Please enter all required measurements before verifying.' };
  }
  if (includesAny(message, ['calculation_direct_bilirubin_exceeds_total', 'direct_bilirubin_exceeds_total'])) {
    return { variant: 'warning', message: 'Direct Bilirubin cannot exceed Total Bilirubin.', guidance: 'Please review and correct the bilirubin values before verifying.' };
  }
  if (includesAny(message, ['calculation_division_by_zero', 'division_by_zero'])) {
    return { variant: 'warning', message: 'A mathematical calculation error occurred (division by zero).', guidance: 'Please check the denominator input value before verifying.' };
  }
  if (includesAny(message, ['critical results must', 'critical panic'])) {
    return { variant: 'warning', message: 'Critical results must be acknowledged before verification.', guidance: 'Document the clinical notification before continuing.' };
  }
  if (includesAny(message, ['must be submitted before verification'])) {
    return { variant: 'warning', message: 'Results must be submitted before verification.', guidance: 'Submit the completed results, then verify them.' };
  }
  if (includesAny(message, ['network', 'fetch failed', 'failed to fetch'])) {
    return { variant: 'error', message: 'Unable to connect. Check your internet connection and try again.', guidance: 'If the problem continues, contact the Super Admin.' };
  }
  return { variant: 'error', message: fallback };
}

export function safeErrorMessage(error: unknown, fallback = 'Something went wrong. Please try again.'): string {
  return mapSafeError(error, fallback).message;
}

export function safeDiagnostic(error: unknown): { code?: string; status?: number } {
  const candidate = (error && typeof error === 'object' ? error : {}) as ErrorLike;
  return {
    code: typeof candidate.code === 'string' ? candidate.code : undefined,
    status: typeof candidate.status === 'number' ? candidate.status : undefined,
  };
}

export type BillingDiagnosticCode =
  | 'BILL-AUTH'
  | 'BILL-VALIDATION'
  | 'BILL-DUPLICATE'
  | 'BILL-CATALOGUE'
  | 'BILL-CONNECTIVITY'
  | 'BILL-TRANSACTION';

/** Stable, patient-safe classification only; never includes server error text. */
export function safeBillingDiagnosticCode(error: unknown): BillingDiagnosticCode {
  const candidate = (error && typeof error === 'object' ? error : {}) as ErrorLike;
  const code = typeof candidate.code === 'string' ? candidate.code : '';
  const status = typeof candidate.status === 'number' ? candidate.status : undefined;
  const message = typeof candidate.message === 'string' ? candidate.message.toLowerCase() : '';

  if (status === 401 || status === 403 || code === '42501') return 'BILL-AUTH';
  if (status === 409 || code === '23505' || code === 'PT409' || includesAny(message, ['idempotency', 'already processed', 'duplicate'])) return 'BILL-DUPLICATE';
  if (includesAny(message, ['catalogue', 'panel definition', 'package definition', 'billing-enabled', 'result structure incomplete', 'price not specified'])) return 'BILL-CATALOGUE';
  if (status === 0 || includesAny(message, ['network', 'fetch failed', 'failed to fetch'])) return 'BILL-CONNECTIVITY';
  if (code.startsWith('22') || code.startsWith('23') || includesAny(message, ['invalid mobile', 'paid amount', 'discount amount', 'payment details'])) return 'BILL-VALIDATION';
  return 'BILL-TRANSACTION';
}
