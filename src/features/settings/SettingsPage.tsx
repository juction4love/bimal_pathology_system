/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Laboratory Settings, Organization Profile, SMS Status & Admin CSV Exports (Phase 5)
 */

import React, { useRef, useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Grid,
  Typography,
  TextField,
  Button,
  Alert,
  Chip,
  Snackbar,
} from '@mui/material';
import FileDownloadIcon from '@mui/icons-material/FileDownload';
import SmsIcon from '@mui/icons-material/Sms';
import CloudDoneIcon from '@mui/icons-material/CloudDone';
import BusinessIcon from '@mui/icons-material/Business';

import { PageHeader } from '@/components/common/PageHeader';
import { ORG_CONFIG } from '@/config/constants';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { formatNepalIso, getNepalTodayAd } from '@/lib/dateTime';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';

interface OrgSettings {
  nameEn: string;
  nameNp: string;
  addressEn: string;
  addressNp: string;
  regNo: string;
  panNo: string;
  phone: string;
  email: string;
}

export const SettingsPage: React.FC = () => {
  const { can } = usePermissions();

  const [orgState] = useState<OrgSettings>({
    nameEn: ORG_CONFIG.nameEn,
    nameNp: ORG_CONFIG.nameNp,
    addressEn: ORG_CONFIG.addressEn,
    addressNp: ORG_CONFIG.addressNp,
    regNo: ORG_CONFIG.regNo,
    panNo: ORG_CONFIG.panNo,
    phone: ORG_CONFIG.phone,
    email: ORG_CONFIG.email,
  });

  const [isExporting, setIsExporting] = useState(false);
  const [exportProgress, setExportProgress] = useState<string | null>(null);
  const [toastMsg, setToastMsg] = useState<string | null>(null);
  const [blockingError, setBlockingError] = useState<string | null>(null);
  const exportAbortRef = useRef<AbortController | null>(null);

  const EXPORT_BATCH_SIZE = 500;
  const MAX_EXPORT_BATCHES = 2000;

  const fetchExportBatch = async (
    type: 'patients' | 'bills' | 'reports' | 'catalogue',
    from: number,
    to: number,
    signal: AbortSignal,
  ) => {
    if (type === 'patients') {
      return supabase.from('patients').select('*').order('created_at', { ascending: false }).range(from, to).abortSignal(signal);
    }
    if (type === 'bills') {
      return supabase.from('bills').select('*').order('created_at', { ascending: false }).range(from, to).abortSignal(signal);
    }
    if (type === 'reports') {
      return supabase.from('diagnostic_reports')
        .select('id, report_number, version, is_amendment, status, signed_at, integrity_hash')
        .order('signed_at', { ascending: false }).range(from, to).abortSignal(signal);
    }
    return supabase.from('tests').select('*').order('name', { ascending: true }).range(from, to).abortSignal(signal);
  };

  const handleExportCsv = async (type: 'patients' | 'bills' | 'reports' | 'catalogue') => {
    setIsExporting(true);
    const controller = new AbortController();
    exportAbortRef.current = controller;
    try {
      const data: any[] = [];
      const filename = `bimal_${type}_${getNepalTodayAd()}.csv`;
      for (let batch = 0; batch < MAX_EXPORT_BATCHES; batch += 1) {
        const from = batch * EXPORT_BATCH_SIZE;
        const { data: rows, error: batchError } = await fetchExportBatch(
          type, from, from + EXPORT_BATCH_SIZE - 1, controller.signal,
        );
        if (batchError) throw batchError;
        const page = rows || [];
        data.push(...page);
        setExportProgress(`${data.length.toLocaleString()} rows prepared`);
        if (page.length < EXPORT_BATCH_SIZE) break;
        if (batch === MAX_EXPORT_BATCHES - 1) {
          throw new Error('Export safety limit reached. Narrow the dataset before retrying.');
        }
      }

      if (data.length === 0) {
        setToastMsg(`No ${type} records found to export.`);
        return;
      }

      // Convert JSON array to CSV format
      const fields = Object.keys(data[0]);
      const isTimestampField = (field: string) => field.endsWith('_at') || field === 'timestamp';
      const headers = fields.map((field) => isTimestampField(field) ? `${field} (Nepal ISO +05:45)` : field);
      const csvRows = [
        headers.join(','),
        ...data.map((row) =>
          fields
            .map((field) => {
              const raw = row[field];
              const val = isTimestampField(field) && raw ? formatNepalIso(raw) : raw;
              if (val === null || val === undefined) return '""';
              if (typeof val === 'object') return `"${JSON.stringify(val).replace(/"/g, '""')}"`;
              return `"${String(val).replace(/"/g, '""')}"`;
            })
            .join(',')
        ),
      ];

      const csvContent = new Blob([csvRows.join('\n')], { type: 'text/csv;charset=utf-8' });
      const downloadUrl = URL.createObjectURL(csvContent);
      const link = document.createElement('a');
      link.setAttribute('href', downloadUrl);
      link.setAttribute('download', filename);
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(downloadUrl);

      setToastMsg(`${type.toUpperCase()} exported successfully!`);
    } catch {
      if (controller.signal.aborted) setToastMsg('Export cancelled.');
      else setBlockingError('The export could not be completed.');
    } finally {
      exportAbortRef.current = null;
      setIsExporting(false);
      setExportProgress(null);
    }
  };

  return (
    <Box>
      <SmartMessageDialog
        open={Boolean(blockingError)}
        message={blockingError || ''}
        guidance="Please try again. If the problem continues, contact an administrator."
        onPrimary={() => setBlockingError(null)}
      />
      <PageHeader
        title="Laboratory & Organization Settings"
        subtitle="Clinic registration profiles, PDF report headers, SMS status, and administrative data exports"
      />

      {/* Cloud PostgreSQL Architecture Notice */}
      <Alert severity="info" icon={<CloudDoneIcon />} sx={{ mb: 3 }}>
        <strong>Free cloud deployment:</strong> Point-in-Time Recovery is not enabled. This deployment does not rely on paid PITR or paid backup add-ons. Database connections remain encrypted in transit.
      </Alert>

      <Grid container spacing={3}>
        {/* Organization Profile */}
        <Grid item xs={12} md={7}>
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                <BusinessIcon color="primary" />
                <Typography variant="h6" fontWeight={700}>
                  Official Organization Profile
                </Typography>
              </Box>
              <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 3 }}>
                These source-controlled legal details appear on receipts, the canonical diagnostic report, and SMS messages. Editing is disabled until persistent settings storage is introduced.
              </Typography>

              <Grid container spacing={2}>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Legal English Name"
                    value={orgState.nameEn}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Official Nepali Name"
                    value={orgState.nameNp}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Address (English)"
                    value={orgState.addressEn}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={6}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Address (Nepali)"
                    value={orgState.addressNp}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={4}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Registration Number"
                    value={orgState.regNo}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={4}>
                  <TextField
                    fullWidth
                    size="small"
                    label="PAN Number"
                    value={orgState.panNo}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
                <Grid item xs={12} sm={4}>
                  <TextField
                    fullWidth
                    size="small"
                    label="Primary Phone"
                    value={orgState.phone}
                    InputProps={{ readOnly: true }}
                  />
                </Grid>
              </Grid>

            </CardContent>
          </Card>
        </Grid>

        {/* SMS Status & Admin CSV Exports */}
        <Grid item xs={12} md={5}>
          {/* SMS Status Card */}
          <Card sx={{ mb: 3 }}>
            <CardContent>
              <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1 }}>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                  <SmsIcon color="primary" />
                  <Typography variant="subtitle1" fontWeight={700}>
                    SMS Gateway Status
                  </Typography>
                </Box>
                <Chip label="Optional / Server Configured" color="info" size="small" sx={{ fontWeight: 600 }} />
              </Box>

              <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
                Provider: <strong>Sparrow SMS Nepal</strong>
              </Typography>
              <Alert severity="warning" sx={{ fontSize: '0.8rem', mb: 1 }}>
                Only payment confirmation and signed report-ready notifications are supported. Delivery is asynchronous through the protected Windows SMS Gateway; Sparrow credentials never enter the browser or cloud runtime, and core LIS workflows never wait for delivery.
              </Alert>
            </CardContent>
          </Card>

          {/* Admin CSV Data Exports */}
          {can(PERMISSION_KEYS.CAN_VIEW_AUDIT_LOGS) && (
            <Card>
              <CardContent>
                <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 1 }}>
                  <FileDownloadIcon color="primary" />
                  <Typography variant="subtitle1" fontWeight={700}>
                    Administrative CSV Data Exports
                  </Typography>
                </Box>
                <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
                  Export raw master tables and registers for local reporting or compliance.
                </Typography>

                <Grid container spacing={1.5}>
                  <Grid item xs={6}>
                    <Button
                      fullWidth
                      size="small"
                      variant="outlined"
                      disabled={isExporting}
                      onClick={() => handleExportCsv('patients')}
                    >
                      Export Patients
                    </Button>
                  </Grid>
                  <Grid item xs={6}>
                    <Button
                      fullWidth
                      size="small"
                      variant="outlined"
                      disabled={isExporting}
                      onClick={() => handleExportCsv('bills')}
                    >
                      Export Bills
                    </Button>
                  </Grid>
                  <Grid item xs={6}>
                    <Button
                      fullWidth
                      size="small"
                      variant="outlined"
                      disabled={isExporting}
                      onClick={() => handleExportCsv('reports')}
                    >
                      Export Reports
                    </Button>
                  </Grid>
                  <Grid item xs={6}>
                    <Button
                      fullWidth
                      size="small"
                      variant="outlined"
                      disabled={isExporting}
                      onClick={() => handleExportCsv('catalogue')}
                    >
                      Export Catalogue
                    </Button>
                  </Grid>
                </Grid>
                {isExporting && (
                  <Box sx={{ mt: 2, display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 1 }}>
                    <Typography variant="caption" color="text.secondary">{exportProgress || 'Preparing export…'}</Typography>
                    <Button size="small" color="warning" onClick={() => exportAbortRef.current?.abort()}>Cancel</Button>
                  </Box>
                )}
              </CardContent>
            </Card>
          )}
        </Grid>
      </Grid>

      {/* Toast Notification */}
      <Snackbar
        open={Boolean(toastMsg)}
        autoHideDuration={3500}
        onClose={() => setToastMsg(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert onClose={() => setToastMsg(null)} severity="info" variant="filled" sx={{ width: '100%' }}>
          {toastMsg}
        </Alert>
      </Snackbar>
    </Box>
  );
};
