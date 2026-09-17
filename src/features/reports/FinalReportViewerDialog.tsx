import React from 'react';
import { Box, Button, Dialog, DialogContent, DialogTitle, Typography } from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import DownloadIcon from '@mui/icons-material/Download';
import LinkIcon from '@mui/icons-material/Link';
import { ClinicalSnapshot } from '@/lib/reportRenderer';
import { downloadReportPdf } from '@/lib/reportDownload';
import { printReportDocument } from '@/lib/reportPrint';
import { ReportDocument } from './ReportDocument';

export interface CanonicalReportRecord {
  id?: string;
  report_number: string;
  version: number;
  is_amendment: boolean;
  amendment_reason?: string | null;
  integrity_hash?: string | null;
  pdf_storage_path?: string | null;
  clinical_snapshot_json: ClinicalSnapshot;
}

interface FinalReportViewerDialogProps {
  open: boolean;
  report: CanonicalReportRecord | null;
  onClose: () => void;
  publicToken?: string | null;
  secureLinkState?: string;
  canGenerateSecureLink?: boolean;
  generatingSecureLink?: boolean;
  onGenerateSecureLink?: () => void;
}

/**
 * The single final-report presentation surface used by operational modules.
 * Header, patient data, investigations, signatories, footer, QR and pagination
 * remain exclusively owned by ReportDocument.
 */
export const FinalReportViewerDialog: React.FC<FinalReportViewerDialogProps> = ({
  open,
  report,
  onClose,
  publicToken,
  secureLinkState,
  canGenerateSecureLink = false,
  generatingSecureLink = false,
  onGenerateSecureLink,
}) => (
  <Dialog
    open={open}
    onClose={onClose}
    maxWidth="lg"
    fullWidth
    PaperProps={{ sx: { bgcolor: '#525659', p: 1 } }}
  >
    <DialogTitle sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', color: '#fff', py: 1 }}>
      <Typography variant="h6" fontWeight={700}>
        Diagnostic Pathology Report — {report?.report_number || '-'} (v{report?.version || 1})
      </Typography>
      <Box className="screen-only" sx={{ display: 'flex', gap: 1 }}>
        <Button variant="contained" size="small" startIcon={<PrintIcon />} onClick={() => printReportDocument()}>
          Print Report (A4)
        </Button>
        <Button variant="outlined" color="inherit" size="small" startIcon={<DownloadIcon />} onClick={() => downloadReportPdf(report)}>
          Download PDF
        </Button>
        <Button variant="text" color="inherit" size="small" onClick={onClose}>
          Close
        </Button>
      </Box>
    </DialogTitle>
    <DialogContent sx={{ display: 'flex', justifyContent: 'center', p: 2, overflowY: 'auto' }}>
      <Box sx={{ width: '100%' }}>
      {report && secureLinkState !== 'Active' && secureLinkState !== 'Loading' && (
        <Box className="screen-only" sx={{ maxWidth: '210mm', mx: 'auto', mb: 1.5, p: 1.5, bgcolor: '#fff8e1', border: '1px solid #d8a722', color: '#594300' }}>
          <Typography variant="body2" fontWeight={700}>Secure QR is not currently available for this report.</Typography>
          <Typography variant="caption" component="div" sx={{ mb: 1 }}>
            {secureLinkState === 'Expired' ? 'The previous secure link expired.' : secureLinkState === 'Revoked' ? 'The previous secure link was revoked.' : 'This historical report has no recoverable active secure link.'}
            {' '}The signed clinical snapshot and integrity hash remain unchanged.
          </Typography>
          {canGenerateSecureLink && onGenerateSecureLink && (
            <Button size="small" variant="contained" startIcon={<LinkIcon />} disabled={generatingSecureLink} onClick={onGenerateSecureLink}>
              {generatingSecureLink ? 'Generating…' : 'Generate Secure Report Link'}
            </Button>
          )}
        </Box>
      )}
      {report?.clinical_snapshot_json && (
        <ReportDocument
          snapshot={report.clinical_snapshot_json}
          reportNumber={report.report_number}
          version={report.version}
          isAmended={report.is_amendment}
          amendmentReason={report.amendment_reason}
          integrityHash={report.integrity_hash}
          publicToken={publicToken}
        />
      )}
      </Box>
    </DialogContent>
  </Dialog>
);
