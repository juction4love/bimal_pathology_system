/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Financial Math & Currency Utilities (Strict Paisa Representation)
 * 1 NPR = 100 Paisa. All database amounts stored as integer paisa.
 */

/**
 * Converts integer paisa to formatted Nepali Rupees string (e.g. 15000 paisa -> "NPR 150.00")
 */
export function formatPaisa(paisa: number | null | undefined, includeSymbol = true): string {
  if (paisa === null || paisa === undefined || isNaN(paisa)) {
    return includeSymbol ? 'NPR 0.00' : '0.00';
  }
  const rupees = (paisa / 100).toFixed(2);
  return includeSymbol ? `NPR ${rupees}` : rupees;
}

/**
 * Converts user entered rupee amount (e.g. 150.50) into integer paisa (15050)
 * Safely handles floating point inaccuracies via rounding.
 */
export function rupeesToPaisa(rupees: number | string): number {
  const num = typeof rupees === 'string' ? parseFloat(rupees) : rupees;
  if (isNaN(num) || num < 0) return 0;
  return Math.round(num * 100);
}

/** Strict form parser: accepts at most two decimal places and never persists a float. */
export function parseRupeesToPaisa(value: string): number | null {
  let normalized = value.trim();
  if (normalized.startsWith('.')) normalized = '0' + normalized;
  if (!/^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,2})?$/.test(normalized)) return null;
  const [whole, fraction = ''] = normalized.split('.');
  const paisa = Number(whole) * 100 + Number(fraction.padEnd(2, '0'));
  return Number.isSafeInteger(paisa) ? paisa : null;
}

/**
 * Validates intermediate user typing for money inputs (digits, optional one dot, at most 2 decimal places).
 * Allows intermediate states such as "", "0", "3", "3.", "3.0", "3.00", "500", "500.00".
 */
export function isValidMoneyIntermediate(value: string): boolean {
  return value === '' || /^\d*(\.\d{0,2})?$/.test(value);
}

/**
 * Validates committed money string on blur/submit and returns validation outcome + integer paisa.
 */
export function validateMoneyCommitted(
  value: string,
  options: { required?: boolean; fieldName?: string; allowZero?: boolean; maxPaisa?: number } = {}
): { isValid: boolean; paisa: number | null; error: string | null; normalizedText: string } {
  const { required = false, fieldName = 'Rate', allowZero = true, maxPaisa } = options;
  const trimmed = value.trim();

  if (trimmed === '') {
    if (required) {
      return { isValid: false, paisa: null, error: `${fieldName} is required.`, normalizedText: '' };
    }
    return { isValid: true, paisa: 0, error: null, normalizedText: '' };
  }

  let cleanVal = trimmed;
  if (cleanVal.startsWith('.')) cleanVal = '0' + cleanVal;
  if (cleanVal.endsWith('.')) cleanVal = cleanVal.slice(0, -1);
  if (cleanVal === '') cleanVal = '0';
  const paisa = parseRupeesToPaisa(cleanVal);
  if (paisa === null || paisa < 0) {
    return {
      isValid: false,
      paisa: null,
      error: `${fieldName} must be a non-negative amount with no more than two decimal places.`,
      normalizedText: trimmed,
    };
  }

  if (!allowZero && paisa === 0) {
    return {
      isValid: false,
      paisa: null,
      error: `NPR 0 is not authorized for ${fieldName.toLowerCase()}. Enter the agreed rate.`,
      normalizedText: '0.00',
    };
  }

  if (maxPaisa !== undefined && paisa > maxPaisa) {
    return {
      isValid: false,
      paisa,
      error: `${fieldName} cannot exceed ${formatPaisa(maxPaisa)}.`,
      normalizedText: (paisa / 100).toFixed(2),
    };
  }

  return {
    isValid: true,
    paisa,
    error: null,
    normalizedText: (paisa / 100).toFixed(2),
  };
}


/**
 * Converts integer paisa to rupees number for form input display
 */
export function paisaToRupees(paisa: number | null | undefined): number {
  if (!paisa || isNaN(paisa)) return 0;
  return Math.round(paisa) / 100;
}

/**
 * Calculates bill financial totals atomically in integer paisa
 */
export function calculateBillTotals(
  items: Array<{ unitPricePaisa: number; discountPaisa?: number }>,
  customDiscountPaisa = 0,
  paidPaisa = 0
): {
  grossPaisa: number;
  itemDiscountPaisa: number;
  totalDiscountPaisa: number;
  netPaisa: number;
  paidPaisa: number;
  duePaisa: number;
  paymentStatus: 'Paid' | 'Partial' | 'Due';
} {
  let grossPaisa = 0;
  let itemDiscountPaisa = 0;

  for (const item of items) {
    grossPaisa += Math.round(item.unitPricePaisa || 0);
    itemDiscountPaisa += Math.round(item.discountPaisa || 0);
  }

  const totalDiscountPaisa = Math.min(grossPaisa, itemDiscountPaisa + Math.round(customDiscountPaisa));
  const netPaisa = Math.max(0, grossPaisa - totalDiscountPaisa);
  const validatedPaidPaisa = Math.min(netPaisa, Math.max(0, Math.round(paidPaisa)));
  const duePaisa = Math.max(0, netPaisa - validatedPaidPaisa);

  let paymentStatus: 'Paid' | 'Partial' | 'Due' = 'Due';
  if (duePaisa === 0 && netPaisa > 0) {
    paymentStatus = 'Paid';
  } else if (validatedPaidPaisa > 0 && duePaisa > 0) {
    paymentStatus = 'Partial';
  }

  return {
    grossPaisa,
    itemDiscountPaisa,
    totalDiscountPaisa,
    netPaisa,
    paidPaisa: validatedPaidPaisa,
    duePaisa,
    paymentStatus,
  };
}
