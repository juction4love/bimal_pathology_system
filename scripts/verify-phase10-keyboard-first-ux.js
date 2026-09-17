/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Phase 10 Automated Keyboard-First UX & Title Casing Test Suite
 */

import { toTitleCase } from '../src/lib/stringUtils.ts';
import fs from 'node:fs';

const keyboard = fs.readFileSync('src/lib/keyboardNav.ts', 'utf8');
const billing = fs.readFileSync('src/features/billing/NewBillPage.tsx', 'utf8');
const resultEntry = fs.readFileSync('src/features/worklist/ResultEntryPage.tsx', 'utf8');
const samples = fs.readFileSync('src/features/samples/SampleAccessioningPage.tsx', 'utf8');
const catalogue = fs.readFileSync('src/features/catalogue/CataloguePage.tsx', 'utf8');
const doctors = fs.readFileSync('src/features/personnel/ReferringDoctorsPage.tsx', 'utf8');

let passedCount = 0;
let failedCount = 0;

function assert(condition, testCode, description) {
  if (condition) {
    console.log(`  ✅ [PASS] ${testCode}: ${description}`);
    passedCount++;
  } else {
    console.error(`  ❌ [FAIL] ${testCode}: ${description}`);
    failedCount++;
  }
}

async function runKeyboardUxSuite() {
  console.log('================================================================');
  console.log(' BIMAL PATHOLOGY - PHASE 10 KEYBOARD-FIRST & TITLE CASING SUITE');
  console.log('================================================================\n');

  console.log('--- TEST GROUP 1: SMART TITLE-CASING NORMALIZATION ---');

  // Test 1: Patient Full Name
  const name1 = toTitleCase('bimal lamichhane');
  assert(name1 === 'Bimal Lamichhane', '1. TitleCase_PatientName', `bimal lamichhane -> ${name1}`);

  // Test 2: Address
  const addr1 = toTitleCase('bharatpur, chitwan');
  assert(addr1 === 'Bharatpur, Chitwan', '2. TitleCase_Address', `bharatpur, chitwan -> ${addr1}`);

  // Test 3: Signatory Name
  const name2 = toTitleCase('aliza thapa magar');
  assert(name2 === 'Aliza Thapa Magar', '3. TitleCase_SignatoryName', `aliza thapa magar -> ${name2}`);

  // Test 4: Clinician Name with Dr. Prefix
  const name3 = toTitleCase('dr. sunil shrestha');
  assert(name3 === 'Dr. Sunil Shrestha', '4. TitleCase_DoctorName', `dr. sunil shrestha -> ${name3}`);

  console.log('\n--- TEST GROUP 2: MEDICAL & PROFESSIONAL ACRONYM PRESERVATION ---');

  // Test 5: Medical Acronyms in Investigations
  const testCbc = toTitleCase('CBC');
  assert(testCbc === 'CBC', '5. Preserve_Acronym_CBC', `CBC remains ${testCbc}`);

  const testLft = toTitleCase('complete blood count (CBC) and LFT');
  assert(testLft.includes('CBC') && testLft.includes('LFT'), '6. Preserve_Acronyms_InText', `Acronyms preserved: ${testLft}`);

  // Test 6: Professional Medical Degrees and Councils
  const degree = toTitleCase('MBBS, MD (pathology)');
  assert(degree.includes('MBBS') && degree.includes('MD'), '7. Preserve_Degrees_MBBS_MD', `Degrees preserved: ${degree}`);

  const council = toTitleCase('NMC and NHPC council');
  assert(council.includes('NMC') && council.includes('NHPC'), '8. Preserve_Councils_NMC_NHPC', `Councils preserved: ${council}`);

  // Test 7: Hyphenated and Slash Acronyms
  const ckmb = toTitleCase('ck-mb and pt/inr');
  assert(ckmb.includes('CK-MB') || ckmb.includes('PT/INR'), '9. Preserve_Hyphenated_Slash_Acronyms', `Hyphenated/Slash handled: ${ckmb}`);

  console.log('\n--- TEST GROUP 3: UNICODE / NEPALI TEXT PRESERVATION ---');

  // Test 8: Nepali Unicode Text is untouched
  const nepaliText = 'बिमल प्याथोलोजी एण्ड डायग्नोस्टिक सेन्टर';
  const formattedNepali = toTitleCase(nepaliText);
  assert(formattedNepali === nepaliText, '10. Preserve_NepaliUnicode', `Nepali script preserved untouched: ${formattedNepali}`);

  console.log('\n--- TEST GROUP 4: INVOICE NEPALI BS DATE FORMATTING ---');

  const { toNepaliDigits, formatNepaliBsDate } = await import('../src/lib/dateTime.ts');

  // Test 9: toNepaliDigits converts 0-9 to ०-९
  const convertedDigits = toNepaliDigits('2083-05-03');
  assert(convertedDigits === '२०८३-०५-०३', '11. ToNepaliDigits_Conversion', `2083-05-03 -> ${convertedDigits}`);

  // Test 10: formatNepaliBsDate converts AD date to Nepali BS with Nepali digits
  const adDate = new Date('2026-08-21T02:45:00Z');
  const formattedBs = formatNepaliBsDate(adDate);
  assert(formattedBs === '२०८३ भदौ ५', '12. FormatNepaliBsDate_AdInput', `2026-08-21 -> ${formattedBs}`);

  // Test 11: formatNepaliBsDate converts string BS to Nepali digits
  const formattedFromBs = formatNepaliBsDate('2083-05-03 BS');
  assert(formattedFromBs === '२०८३ भदौ ३', '13. FormatNepaliBsDate_BsInput', `2083-05-03 BS -> ${formattedFromBs}`);

  // Test 12: formatNepaliBsDate has NO AD date beside it
  assert(!formattedBs.includes('2026') && !formattedBs.includes('Aug'), '14. FormatNepaliBsDate_NoAdDate', `BS formatter contains actual BS only`);

  console.log('\n--- TEST GROUP 5: SCIENTIFIC & TECHNICAL VALUE SAFETY ---');
  for (const [input, expected, code] of [
    ['HbA1c', 'HbA1c', '15'], ['FT3', 'FT3', '16'], ['eGFR', 'eGFR', '17'], ['pH', 'pH', '18'], ['anti-HCV', 'anti-HCV', '19'], ['β-hCG', 'β-hCG', '20'],
  ]) {
    assert(toTitleCase(input) === expected, `${code}. Preserve_Scientific_${expected}`, `${input} remains ${expected}`);
  }
  assert(toTitleCase('patient@example.com') === 'patient@example.com', '21. Preserve_Email', 'email remains byte-stable');
  assert(toTitleCase('9845012345') === '9845012345', '22. Preserve_Mobile', 'mobile remains byte-stable');
  assert(toTitleCase('550e8400-e29b-41d4-a716-446655440000') === '550e8400-e29b-41d4-a716-446655440000', '23. Preserve_UUID', 'UUID remains byte-stable');
  assert(!catalogue.includes("toTitleCase(paramForm.code)") && !catalogue.includes("toTitleCase(testForm.code)"), '24. Preserve_TestParameterCodes', 'catalogue codes are never auto-title-cased');

  console.log('\n--- TEST GROUP 6: FORM-SCOPED ENTER/TAB NAVIGATION ---');
  assert(keyboard.includes("target.closest<HTMLElement>('[data-keyboard-form=\"true\"]')"), '25. Keyboard_FormScoped', 'Enter navigation is scoped to opted-in forms');
  assert(keyboard.includes("target.tagName === 'TEXTAREA'") && keyboard.includes("target.tagName === 'BUTTON'"), '26. TextareaButton_EnterNative', 'textarea newline and deliberate button activation remain native');
  assert(keyboard.includes("e.key === 'Enter' && !e.shiftKey") && !keyboard.includes("e.key === 'Tab'"), '27. TabShiftTab_Native', 'Tab and Shift+Tab are not hijacked');
  assert(billing.includes('handleEnterKeyNavigation(e, () => ageYearsInputRef.current?.focus())'), '28. Billing_NameToAge', 'Patient Name Enter advances to Age Years');
  assert(billing.includes('ageMonthsInputRef') && billing.includes('ageDaysInputRef') && billing.includes('genderInputRef'), '29. Billing_LogicalDemographicOrder', 'age years, months, days, then sex use explicit focus order');
  assert(billing.includes("e.key === 'ArrowDown'") && billing.includes("e.key === 'ArrowUp'") && billing.includes("e.key === 'Escape'"), '30. TestSearch_ArrowEscape', 'test search supports arrows and Escape');
  assert(billing.includes('const match = searchResults[highlightedTestIndex]') && billing.includes('testSearchInputRef.current?.focus()'), '31. TestSearch_EnterAddRestore', 'highlighted catalogue result adds and restores search focus');
  assert(billing.includes('Price not configured — enter agreed rate') && billing.includes('!item.rateResolved'), '32. TestSearch_MissingPriceSafe', 'unconfigured pricing requires an explicitly resolved agreed bill-line rate');
  assert(billing.includes('parseRupeesToPaisa') && billing.includes('no more than two decimal places'), '33. ManualRate_IntegerPaisa', 'manual rate entry is validated and converted once to integer paisa');
  assert(!billing.includes('Configure catalogue price') && billing.includes('setTestSearchTerm(\'\')'), '34. Billing_NoCatalogueMutation', 'billing never edits catalogue pricing and restores the fast-search loop');
  assert(resultEntry.includes("results[i].value_type !== 'Calculated'") && resultEntry.includes("results[i].value_type !== 'Heading'"), '35. Results_SkipCalculatedHeading', 'calculated and heading rows are skipped');
  assert(resultEntry.includes('saveDraftButtonRef.current?.focus()') && !resultEntry.includes('saveDraftButtonRef.current?.click()'), '36. Results_FinalFocusNoSubmit', 'final parameter focuses Save Draft without automatic submit/sign');
  assert(samples.includes('highlightedSampleIndex') && samples.includes('data-sample-action'), '37. Samples_SearchToActionFocus', 'sample search selects and focuses an available action without invoking it');
  assert(catalogue.includes('data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation}'), '38. Catalogue_FormNavigation', 'catalogue dialogs opt into scoped Enter navigation');
  assert(doctors.includes('setForm({ ...form, full_name: toTitleCase(form.full_name) })'), '39. DoctorName_BlurNormalization', 'doctor name normalizes on blur');

  console.log('\n================================================================');
  console.log(` SUMMARY: ${passedCount} PASSED, ${failedCount} FAILED`);
  console.log('================================================================\n');

  if (failedCount > 0) {
    process.exit(1);
  }
}

runKeyboardUxSuite();
