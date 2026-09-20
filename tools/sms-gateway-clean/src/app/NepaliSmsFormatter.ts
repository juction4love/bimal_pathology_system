// Canonical Nepali Digits and Sparrow SMS Formatter for Bimal Pathology LIS Gateway
// Exact Approved Template: Bimal Pathology: {TEST} रिपोर्ट तयार भयो। रु {AMOUNT} भुक्तानको लागि धन्यवाद।
// Fits within ONE Unicode SMS segment (<= 70 characters)

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

interface TestAliasTiers {
  primary: string;
  compact: string;
}

export function getSmsTestAliases(testName: string | null | undefined): TestAliasTiers {
  if (!testName) {
    return { primary: 'Lab', compact: 'Lab' };
  }
  const raw = testName.trim();
  const normalized = raw.toLowerCase();

  if (/complete\s+blood\s+count|^cbc\b/i.test(normalized)) return { primary: 'CBC', compact: 'CBC' };
  if (/lipid\s+profile|^lipid\b/i.test(normalized)) return { primary: 'Lipid', compact: 'LP' };
  if (/liver\s+function\s+test|^lft\b/i.test(normalized)) return { primary: 'LFT', compact: 'LFT' };
  if (/kidney\s+function|renal\s+function|^kft\b|^rft\b/i.test(normalized)) return { primary: 'KFT', compact: 'KFT' };
  if (/thyroid\s+profile|thyroid\s+function|^tft\b|^thyroid\b/i.test(normalized)) return { primary: 'Thyroid', compact: 'TFT' };
  if (/urine\s+routine|urine\s+r\/?e|^urine\b/i.test(normalized)) return { primary: 'Urine', compact: 'UR' };
  if (/vitamin\s+d\b|25-oh|vit\s*d/i.test(normalized)) return { primary: 'Vit D', compact: 'VD' };
  if (/vitamin\s+b12\b|vit\s*b12|\bb12\b/i.test(normalized)) return { primary: 'Vit B12', compact: 'B12' };
  if (/d-dimer/i.test(normalized)) return { primary: 'D-Dimer', compact: 'DD' };
  if (/ferritin/i.test(normalized)) return { primary: 'Ferritin', compact: 'FER' };
  if (/hba1c|glycated\s+hemoglobin/i.test(normalized)) return { primary: 'HbA1c', compact: 'A1c' };

  if (raw.length <= 6 && /^[A-Za-z0-9+ -]+$/.test(raw)) {
    return { primary: raw, compact: raw.slice(0, 3) };
  }

  return { primary: 'Lab', compact: 'Lab' };
}

export function countUnicodeSmsLength(text: string): number {
  return text.length;
}

export interface NepaliSmsParams {
  testNames?: string[];
  amountPaisa?: number | bigint | null;
  amountRupees?: number | string | null;
}

export function formatSingleCreditNepaliSms(params: NepaliSmsParams): string {
  let paisa = 0;
  if (params.amountPaisa != null) {
    paisa = Number(params.amountPaisa);
  } else if (params.amountRupees != null) {
    paisa = Math.round(Number(params.amountRupees) * 100);
  }

  const nepaliAmount = formatCompactNepaliAmount(paisa);
  const tests = (params.testNames || []).map(t => t.trim()).filter(Boolean);

  let candidateAlias: string;
  if (tests.length === 1) {
    const aliasTiers = getSmsTestAliases(tests[0]);
    const primaryCandidate = `Bimal Pathology: ${aliasTiers.primary} रिपोर्ट तयार भयो। रु ${nepaliAmount} भुक्तानको लागि धन्यवाद।`;
    if (countUnicodeSmsLength(primaryCandidate) <= 70) {
      return primaryCandidate;
    }
    candidateAlias = aliasTiers.compact;
  } else {
    candidateAlias = 'Lab';
  }

  const compactCandidate = `Bimal Pathology: ${candidateAlias} रिपोर्ट तयार भयो। रु ${nepaliAmount} भुक्तानको लागि धन्यवाद।`;
  if (countUnicodeSmsLength(compactCandidate) <= 70) {
    return compactCandidate;
  }

  const ultraCompactCandidate = `Bimal Pathology: Lab रिपोर्ट तयार भयो। रु ${nepaliAmount} भुक्तानको लागि धन्यवाद।`;
  if (countUnicodeSmsLength(ultraCompactCandidate) <= 70) {
    return ultraCompactCandidate;
  }

  return `Bimal Pathology: ${candidateAlias.slice(0, 2)} रिपोर्ट तयार भयो। रु ${nepaliAmount} भुक्तानको लागि धन्यवाद।`;
}
