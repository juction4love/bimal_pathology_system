export const REGISTRY_PAGE_SIZE = 50;

export interface RegistryCursor {
  timestamp: string;
  id: string;
}

export function splitServerPage<T>(rows: T[], pageSize = REGISTRY_PAGE_SIZE) {
  return { rows: rows.slice(0, pageSize), hasNext: rows.length > pageSize };
}

export function registryCursor(row: { created_at?: string; signed_at?: string; id: string }): RegistryCursor {
  const timestamp = row.signed_at || row.created_at;
  if (!timestamp) throw new Error('Registry row has no cursor timestamp.');
  return { timestamp, id: row.id };
}
