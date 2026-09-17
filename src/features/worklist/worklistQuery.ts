export const WORKLIST_PAGE_SIZE = 50;

export interface WorklistCursor {
  createdAt: string;
  id: string;
}

export function worklistCursor(item: { created_at: string; id: string }): WorklistCursor {
  return { createdAt: item.created_at, id: item.id };
}

export function splitWorklistPage<T>(rows: T[], pageSize = WORKLIST_PAGE_SIZE) {
  return { rows: rows.slice(0, pageSize), hasNext: rows.length > pageSize };
}

export function isReportableWorklistItem(item: {
  clinical_reporting_enabled?: boolean;
  reporting_type: string;
}) {
  return ['InHouse', 'OutsourceWithBimalReport'].includes(item.reporting_type);
}

