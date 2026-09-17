import type { TestMaster } from '@/types/database';

export interface SelectedBillTest {
  test: TestMaster;
  unitPricePaisa: number;
  discountPaisa: number;
  description?: string;
  rateResolved: boolean;
  isManuallyEdited?: boolean;
}

export const PROVISIONAL_DEFAULT_RATE_PAISA = 10000; // NPR 100.00 provisional default for unpriced catalogue items

/** Adds a catalogue identity once; reporting metadata remains internal. */
export const addSelectedBillTest = (current: SelectedBillTest[], test: TestMaster): SelectedBillTest[] => {
  if (current.some((item) => item.test.id === test.id)) return current;
  const isConfigured = Boolean(test.priceConfigured && (test.pricePaisa > 0 || test.allowZeroPriceBilling));
  const initialPricePaisa = isConfigured ? test.pricePaisa : PROVISIONAL_DEFAULT_RATE_PAISA;

  return [...current, {
    test,
    unitPricePaisa: initialPricePaisa,
    discountPaisa: 0,
    description: test.code === 'IHC' ? 'IHC Panel' : '',
    rateResolved: true,
    isManuallyEdited: false,
  }];
};

export const removeSelectedBillTest = (current: SelectedBillTest[], testId: string): SelectedBillTest[] =>
  current.filter((item) => item.test.id !== testId);
