// Canonical Nepali Digits and Sparrow SMS Formatter for Bimal Pathology LIS
// Exact Approved Template: Bimal Pathology: {TEST} रिपोर्ट तयार भयो। रु {AMOUNT} भुक्तानको लागि धन्यवाद।
// Fits within ONE Unicode SMS segment (<= 70 UCS-2 code units)

export const NEPALI_DIGITS = ['०', '१', '२', '३', '४', '५', '६', '७', '८', '९'];

export function toNepaliDigits(input: number | string): string {
  return String(input).replace(/[0-9]/g, digit => NEPALI_DIGITS[Number(digit)] || digit);
}

export function formatCompactNepaliAmount(paisa: number | bigint): string {
  const totalPaisa = typeof paisa === 'bigint' ? Number(paisa) : paisa;
  if (!Number.isFinite(totalPaisa) || totalPaisa < 0) {
    return '०';
  }
  const rupees = Math.floor(totalPaisa / 100);
  const remainderPaisa = totalPaisa % 100;

  if (remainderPaisa === 0) {
    return toNepaliDigits(rupees);
  }
  if (remainderPaisa % 10 === 0) {
    return `${toNepaliDigits(rupees)}.${toNepaliDigits(remainderPaisa / 10)}`;
  }
  const paddedPaisa = String(remainderPaisa).padStart(2, '0');
  return `${toNepaliDigits(rupees)}.${toNepaliDigits(paddedPaisa)}`;
}

/**
 * Count UCS-2 code units used by Sparrow/Unicode SMS transport.
 * BMP characters (U+0000–U+FFFF) cost 1 unit. Devanagari is fully in the BMP.
 * Supplementary characters (U+10000+) cost 2 units (surrogate pairs).
 */
export function countUcs2Length(text: string): number {
  let len = 0;
  for (let i = 0; i < text.length; i++) {
    const cp = text.codePointAt(i)!;
    if (cp > 0xffff) {
      len += 2;
      i++;
    } else {
      len += 1;
    }
  }
  return len;
}

/** @deprecated Use countUcs2Length. Kept for backward compatibility. */
export function countUnicodeSmsLength(text: string): number {
  return countUcs2Length(text);
}

interface TestAliasTiers {
  primary: string;
  compact: string;
}

/**
 * Resolve the 2-tier alias for a known test name.
 *
 * Approved primary aliases (per lab specification):
 *   CBC, LFT, KFT, LP, TFT, B12, VD, DD, FER, A1c
 */
export function getSmsTestAliases(testName: string | null | undefined): TestAliasTiers {
  if (!testName) return { primary: 'Lab', compact: 'Lab' };
  const raw = testName.trim();
  const n = raw.toLowerCase();

  if (/complete\s+blood\s+count|^cbc\b/i.test(n))                      return { primary: 'CBC',   compact: 'CBC'  };
  if (/lipid\s+profile|^lipid\b/i.test(n))                              return { primary: 'LP',    compact: 'LP'   };
  if (/liver\s+function\s+test|^lft\b/i.test(n))                        return { primary: 'LFT',   compact: 'LFT'  };
  if (/kidney\s+function|renal\s+function|^kft\b|^rft\b/i.test(n))     return { primary: 'KFT',   compact: 'KFT'  };
  if (/thyroid\s+profile|thyroid\s+function|^tft\b|^thyroid\b/i.test(n)) return { primary: 'TFT',  compact: 'TFT'  };
  if (/urine\s+routine|urine\s+r\/?e|^urine\b/i.test(n))               return { primary: 'Urine', compact: 'UR'   };
  if (/vitamin\s+d\b|25-oh|vit\s*d/i.test(n))                           return { primary: 'VD',    compact: 'VD'   };
  if (/vitamin\s+b12\b|vit\s*b12|\bb12\b/i.test(n))                    return { primary: 'B12',   compact: 'B12'  };
  if (/d-dimer/i.test(n))                                                return { primary: 'DD',    compact: 'DD'   };
  if (/ferritin/i.test(n))                                               return { primary: 'FER',   compact: 'FER'  };
  if (/hba1c|glycated\s+hemoglobin/i.test(n))                           return { primary: 'A1c',   compact: 'A1c'  };

  if (raw.length <= 6 && /^[A-Za-z0-9+ -]+$/.test(raw)) {
    return { primary: raw, compact: raw.slice(0, 3) };
  }
  return { primary: 'Lab', compact: 'Lab' };
}

/** Thrown when no alias tier fits within 70 UCS-2 code units. */
export class SmsSingleSegmentLimitExceeded extends Error {
  readonly code = 'SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED' as const;
  constructor(public readonly messageLength: number) {
    super(
      `SMS_SINGLE_SEGMENT_LIMIT_EXCEEDED: resolved message is ${messageLength} UCS-2 code units (max 70). ` +
      `Message will NOT be sent as multipart and will NOT be truncated.`
    );
    this.name = 'SmsSingleSegmentLimitExceeded';
  }
}

export interface NepaliSmsParams {
  testNames?: string[];
  amountPaisa?: number | bigint | null;
  amountRupees?: number | string | null;
}

/**
 * Build the canonical single-credit Nepali SMS.
 *
 * Template (LOCKED): Bimal Pathology: {TEST} रिपोर्ट तयार भयो। रु {AMOUNT} भुक्तानको लागि धन्यवाद।
 *
 * Alias tier resolution (deterministic):
 *   Tier 1 — primary alias  (CBC, LFT, KFT, LP, TFT, B12, VD, DD, FER, A1c)
 *   Tier 2 — compact alias  (shorter fallback where applicable)
 *   Tier 3 — generic        "Lab"
 *   Tier 4 — emergency      "L"
 *   Tier 5 — REJECT: SmsSingleSegmentLimitExceeded — NEVER multipart, NEVER truncate
 */
export function formatSingleCreditNepaliSms(params: NepaliSmsParams): string {
  let paisa = 0;
  if (params.amountPaisa != null) {
    paisa = Number(params.amountPaisa);
  } else if (params.amountRupees != null) {
    paisa = Math.round(Number(params.amountRupees) * 100);
  }

  const nepaliAmount = formatCompactNepaliAmount(paisa);
  const tests = (params.testNames || []).map(t => t.trim()).filter(Boolean);

  const buildMsg = (alias: string) =>
    `Bimal Pathology: ${alias} रिपोर्ट तयार भयो। रु ${nepaliAmount} भुक्तानको लागि धन्यवाद।`;

  const tryAlias = (alias: string): string | null => {
    const msg = buildMsg(alias);
    return countUcs2Length(msg) <= 70 ? msg : null;
  };

  // Tiers 1 & 2 — test-specific (only for single-test orders)
  if (tests.length === 1) {
    const tiers = getSmsTestAliases(tests[0]);
    const t1 = tryAlias(tiers.primary);
    if (t1) return t1;
    const t2 = tryAlias(tiers.compact);
    if (t2) return t2;
  }

  // Tier 3 — generic "Lab"
  const t3 = tryAlias('Lab');
  if (t3) return t3;

  // Tier 4 — emergency "L"
  const t4 = tryAlias('L');
  if (t4) return t4;

  // Tier 5 — hard rejection
  throw new SmsSingleSegmentLimitExceeded(countUcs2Length(buildMsg('L')));
}
