export interface PaginatedInvestigationPage {
  pageNumber: number;
  isFirstPage: boolean;
  isFinalPage: boolean;
  investigations: any[];
  usedMm: number;
  capacityMm: number;
}
export const REPORT_PAGINATION_MM: Readonly<Record<string, number>>;
export function resultHeightMm(result: any): number;
export function interpretationHeightMm(value?: string | null): number;
export function investigationHeaderHeightMm(investigation: any, continued: boolean): number;
export function signatoryReserveMm(): number;
export function paginateInvestigations(investigations: any[]): PaginatedInvestigationPage[];
