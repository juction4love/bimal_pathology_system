import type { TestMaster } from '@/types/database';

export interface SelectedBillTest {
  test: TestMaster;
  unitPricePaisa: number;
  discountPaisa: number;
  description?: string;
  rateResolved: boolean;
}

/** Adds a catalogue identity once; reporting metadata remains internal. */
export const addSelectedBillTest = (current: SelectedBillTest[], test: TestMaster): SelectedBillTest[] => {
  if (current.some((item) => item.test.id === test.id)) return current;
  return [...current, {
    test,
    unitPricePaisa: test.pricePaisa,
    discountPaisa: 0,
    description: test.code === 'IHC' ? 'IHC Panel' : '',
    rateResolved: Boolean(test.priceConfigured && (test.pricePaisa > 0 || test.allowZeroPriceBilling)),
  }];
};

export const removeSelectedBillTest = (current: SelectedBillTest[], testId: string): SelectedBillTest[] =>
  current.filter((item) => item.test.id !== testId);
