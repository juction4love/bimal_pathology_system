/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Public Patient Diagnostic Report Gateway (Phase 4)
 * Secure, read-only patient portal accessible via unguessable 256-bit token
 */

import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Card,
  Typography,
  Button,
  CircularProgress,
  Alert,
  Container,
} from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import DownloadIcon from '@mui/icons-material/Download';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import { useParams } from 'react-router-dom';

import { supabase } from '@/lib/supabase';
import { hashToken } from '@/lib/sms/tokenHelper';
import { ClinicalSnapshot } from '@/lib/reportRenderer';
import { ReportDocument } from '@/features/reports/ReportDocument';
import { ORG_CONFIG } from '@/config/constants';
import { formatAdDateTime } from '@/lib/dateTime';
import { printReportDocument } from '@/lib/reportPrint';

export const PublicReportPage: React.FC = () => {
  const { token } = useParams<{ token: string }>();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [reportData, setReportData] = useState<{
    report_number: string;
    version: number;
    is_amendment: boolean;
    amendment_reason?: string | null;
    signed_at: string;
    integrity_hash: string;
    snapshot: ClinicalSnapshot;
  } | null>(null);

  const loadPublicReport = useCallback(async () => {
    if (!token || token.trim().length < 16) {
      setError('Invalid or incomplete report link token.');
      setLoading(false);
      return;
    }

    setLoading(true);
    setError(null);

    try {
      // 1. Calculate SHA-256 of raw token
      const tokenHash = await hashToken(token.trim());

      // 2. Call Security Definer public resolver RPC
      const { data, error: rpcErr } = await supabase.rpc('resolve_public_report_by_token', {
        p_token_hash: tokenHash,
      });

      if (rpcErr) throw rpcErr;

      if (!data || !data.valid) {
        setError(data?.error || 'This report link is invalid, expired, or has been revoked.');
        return;
      }

      setReportData(data);
    } catch {
      // Do not expose PostgREST, SQL, or network internals on a public route.
      setError('This report could not be verified. Please contact the laboratory if the problem continues.');
    } finally {
      setLoading(false);
    }
  }, [token]);

  useEffect(() => {
    loadPublicReport();
  }, [loadPublicReport]);

  if (loading) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', bgcolor: '#f8fafc', p: { xs: 2, sm: 3 }, textAlign: 'center' }}>
        <CircularProgress size={48} sx={{ color: '#0284c7', mb: 2 }} />
        <Typography variant="body1" fontWeight={600} color="text.secondary">
          Verifying report security token & integrity...
        </Typography>
      </Box>
    );
  }

  if (error || !reportData) {
    return (
      <Container maxWidth="sm" sx={{ py: { xs: 3, sm: 8 }, px: { xs: 1.5, sm: 3 } }}>
        <Card sx={{ textAlign: 'center', p: { xs: 2, sm: 4 }, borderRadius: { xs: 2, sm: 3 }, boxShadow: '0 10px 25px -5px rgba(0, 0, 0, 0.1)' }}>
          <ErrorOutlineIcon sx={{ fontSize: 64, color: '#dc2626', mb: 2 }} />
          <Typography variant="h5" fontWeight={800} color="#0f172a" gutterBottom>
            Report Unavailable
          </Typography>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 3 }}>
            {error || 'The requested diagnostic report could not be accessed.'}
          </Typography>
          <Alert severity="info" sx={{ textAlign: 'left', mb: 3 }}>
            If you received this link via SMS, please ensure the URL is complete or contact our laboratory reception at <strong>{ORG_CONFIG.phone}</strong>.
          </Alert>
          <Typography variant="caption" color="text.secondary">
            {ORG_CONFIG.nameEn} • {ORG_CONFIG.addressEn}
          </Typography>
        </Card>
      </Container>
    );
  }

  const patientName = reportData.snapshot?.patient?.full_name || 'Patient';
  const labNo = reportData.snapshot?.order?.order_number || '-';

  return (
    <Box sx={{ minHeight: '100vh', bgcolor: { xs: '#f1f5f9', md: '#525659' }, py: { xs: 0, sm: 2, md: 3 }, px: { xs: 0, sm: 2 } }}>
      {/* Top Patient Control Banner */}
      <Container maxWidth="md" sx={{ mb: { xs: 1.5, md: 3 }, px: { xs: 1.5, sm: 3 } }}>
        <Card sx={{ bgcolor: '#ffffff', p: { xs: 1.5, sm: 2 }, borderRadius: { xs: 0, sm: 2 }, boxShadow: '0 4px 12px rgba(0,0,0,0.15)' }}>
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', flexWrap: 'wrap', gap: 2 }}>
            <Box>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 0.5 }}>
                <CheckCircleIcon sx={{ color: '#16a34a', fontSize: 20 }} />
                <Typography variant="subtitle1" fontWeight={800} color="#0f172a">
                  Verified Electronic Report
                </Typography>
              </Box>
              <Typography variant="body2" color="text.secondary">
                Patient: <strong>{patientName}</strong> • Lab No: <strong>{labNo}</strong> • Issued: {formatAdDateTime(reportData.signed_at)}
              </Typography>
            </Box>

            <Box sx={{ display: 'flex', gap: 1, width: { xs: '100%', sm: 'auto' } }}>
              <Button
                variant="contained"
                color="primary"
                startIcon={<PrintIcon />}
                onClick={() => printReportDocument()}
                sx={{ minHeight: 44, flex: { xs: 1, sm: '0 0 auto' } }}
              >
                Print
              </Button>
              <Button
                variant="outlined"
                startIcon={<DownloadIcon />}
                onClick={() => printReportDocument()}
                sx={{ minHeight: 44, flex: { xs: 1, sm: '0 0 auto' } }}
              >
                Download PDF
              </Button>
            </Box>
          </Box>
        </Card>
      </Container>

      {/* The secure route uses the same canonical A4 document at every viewport. */}
      <Box
        sx={{
          display: 'flex',
          justifyContent: { xs: 'flex-start', md: 'center' },
          width: '100%',
          overflowX: 'auto',
        }}
      >
        <ReportDocument
          snapshot={reportData.snapshot}
          version={reportData.version}
          isAmended={reportData.is_amendment}
          amendmentReason={reportData.amendment_reason}
          reportNumber={reportData.report_number}
          publicToken={token}
        />
      </Box>
    </Box>
  );
};
