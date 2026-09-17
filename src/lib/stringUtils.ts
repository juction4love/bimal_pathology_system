/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * String and Text Formatting Utilities
 */

// Common medical and professional acronyms to preserve in uppercase
const KNOWN_ACRONYMS = new Set([
  'CBC', 'LFT', 'KFT', 'RFT', 'TFT', 'LP', 'ESR', 'CRP', 'ASO', 'RA', 'RF',
  'NMC', 'NHPC', 'BMLT', 'CMLT', 'MBBS', 'MD', 'MS', 'DM', 'MCH', 'BDS', 'MDS',
  'OPD', 'IPD', 'ICU', 'CCU', 'NICU', 'PICU', 'OT',
  'HIV', 'HBSAG', 'HCV', 'VDRL', 'TPHA', 'WIDAL', 'DENGUE', 'NS1', 'IGM', 'IGG',
  'PCR', 'ELISA', 'CLIA', 'ECLIA', 'HPLC', 'FIA',
  'AST', 'ALT', 'SGOT', 'SGPT', 'ALP', 'GGT', 'LDH', 'CPK', 'CK-MB', 'TROP-I', 'TROP-T',
  'TSH', 'FT3', 'FT4', 'T3', 'T4', 'FSH', 'LH', 'PRL', 'AMH', 'PSA', 'CEA', 'AFP', 'CA-125', 'CA-19-9',
  'PT', 'INR', 'APTT', 'ABG', 'FBS', 'PPBS', 'RBS', 'OGTT', 'HBA1C', 'URINE', 'STOOL', 'CSF',
  'EDTA', 'DNA', 'RNA', 'USG', 'CT', 'MRI', 'X-RAY', 'ECG', 'ECHO', 'PFT'
]);

// Minor words that can remain lowercase unless at start of string or after colon
const MINOR_WORDS = new Set(['and', 'or', 'the', 'of', 'in', 'at', 'by', 'for', 'with', 'to', 'on']);
const PRESERVED_SCIENTIFIC_TERMS = new Map([
  ['HBA1C', 'HbA1c'],
  ['EGFR', 'eGFR'],
  ['PH', 'pH'],
  ['ANTI-HCV', 'anti-HCV'],
  ['Β-HCG', 'β-hCG'],
]);

/**
 * Converts text to title case while preserving medical acronyms,
 * punctuation, abbreviations, and Unicode/Nepali scripts.
 */
export function toTitleCase(input?: string | null): string {
  if (!input) return '';
  const text = input.trim();
  if (!text) return '';

  const preservedWholeTerm = PRESERVED_SCIENTIFIC_TERMS.get(text.toUpperCase());
  if (preservedWholeTerm) return preservedWholeTerm;

  // This utility is intentionally safe if accidentally called for common
  // technical values. Proper-name fields opt in; identifiers stay byte-stable.
  if (/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(text) ||
      /^(?:https?:\/\/|www\.)/i.test(text) ||
      /^[0-9+()\-\s]+$/.test(text) ||
      /^[0-9a-f]{8}-[0-9a-f-]{27,}$/i.test(text)) {
    return text;
  }

  // If text contains Devanagari / Nepali characters, do not alter
  if (/[\u0900-\u097F]/.test(text)) {
    return text;
  }

  // Split by whitespace while preserving punctuation boundaries
  return text
    .split(/\s+/)
    .map((word, wordIndex) => {
      const match = word.match(/^([^a-zA-Z0-9]*)([a-zA-Z0-9'-/]+)([^a-zA-Z0-9]*)$/);
      if (match) {
        const [, leading, core, trailing] = match;
        const upper = core.toUpperCase();
        if (KNOWN_ACRONYMS.has(upper)) {
          return leading + upper + trailing;
        }
      }

      // Check for hyphenated words e.g. "Bharatpur-7"
      if (word.includes('-')) {
        return word
          .split('-')
          .map((part, partIdx) => formatWord(part, wordIndex === 0 && partIdx === 0))
          .join('-');
      }

      // Check for slash separated words e.g. "Age/Sex"
      if (word.includes('/')) {
        return word
          .split('/')
          .map((part, partIdx) => formatWord(part, wordIndex === 0 && partIdx === 0))
          .join('/');
      }

      return formatWord(word, wordIndex === 0);
    })
    .join(' ');
}

function formatWord(word: string, isFirstWord: boolean): string {
  if (!word) return '';

  // Extract leading and trailing punctuation (e.g. "(CBC)", "Dr.", "Bharatpur,")
  const match = word.match(/^([^a-zA-Z0-9]*)([a-zA-Z0-9'’]+)([^a-zA-Z0-9]*)$/);
  if (!match) return word;

  const [, leadingPunct, coreWord, trailingPunct] = match;
  const upper = coreWord.toUpperCase();

  const preservedScientificTerm = PRESERVED_SCIENTIFIC_TERMS.get(upper);
  if (preservedScientificTerm) {
    return leadingPunct + preservedScientificTerm + trailingPunct;
  }

  // If it's a known acronym, return it uppercase
  if (KNOWN_ACRONYMS.has(upper)) {
    return leadingPunct + upper + trailingPunct;
  }

  // If it's already an all-caps word with length >= 2 and all consonants or special pattern
  if (coreWord.length >= 2 && coreWord === upper && !/[AEIOUaeiou]/.test(coreWord)) {
    return leadingPunct + upper + trailingPunct;
  }

  const lower = coreWord.toLowerCase();

  // Handle minor words
  if (!isFirstWord && MINOR_WORDS.has(lower)) {
    return leadingPunct + lower + trailingPunct;
  }

  // Standard capitalization: First letter uppercase, rest lowercase
  const capitalized = lower.charAt(0).toUpperCase() + lower.slice(1);
  return leadingPunct + capitalized + trailingPunct;
}
