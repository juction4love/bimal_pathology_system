/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Shared Diagnostic Report Print & Immutable PDF Download Helper
 */

import { ClinicalSnapshot } from './reportRenderer';
import { printReportDocument } from './reportPrint';

export interface DownloadableReport {
  id?: string;
  report_number?: string;
  pdf_storage_path?: string | null;
  clinical_snapshot_json?: ClinicalSnapshot | null;
  version?: number;
}

/**
 * Opens the exact canonical rendered document in the isolated print/save-as-PDF
 * flow. The immutable snapshot, hash, version and storage linkage remain on the
 * report record; visual delivery never bypasses the current canonical renderer.
 */
export async function downloadReportPdf(report: DownloadableReport | null): Promise<void> {
  if (!report) {
    printReportDocument();
    return;
  }

  printReportDocument();
}
