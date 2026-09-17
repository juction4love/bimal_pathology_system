/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Diagnostic Reports Registry, Live A4 Preview & Amendment Workflow (Phase 3)
 * Full PostgreSQL RLS Integration with Immutable Frozen Snapshots & Versioning
 */

import React, { useState, useEffect, useCallback, useRef } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Button,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  InputAdornment,
  MenuItem,
  CircularProgress,
  Alert,
  Snackbar,
  Chip,
} from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import VisibilityIcon from '@mui/icons-material/Visibility';
import DownloadIcon from '@mui/icons-material/Download';
import HistoryEduIcon from '@mui/icons-material/HistoryEdu';
import SearchIcon from '@mui/icons-material/Search';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { ClinicalSnapshot } from '@/lib/reportRenderer';
import { downloadReportPdf } from '@/lib/reportDownload';
import { printReportDocument } from '@/lib/reportPrint';
import { FinalReportViewerDialog } from './FinalReportViewerDialog';
import { formatAdDateTime } from '@/lib/dateTime';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { generateRawToken, hashToken } from '@/lib/sms/tokenHelper';
import { REGISTRY_PAGE_SIZE, registryCursor, splitServerPage, type RegistryCursor } from '@/lib/serverPagination';
import { subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';

interface DbReport {
  id: string;
  order_id: string;
  patient_id: string;
  report_number: string;
  version: number;
  is_amendment: boolean;
  amendment_reason?: string | null;
  amended_from_report_id?: string | null;
  status: string;
  integrity_hash: string;
  performed_by_personnel_name: string;
  signed_by_personnel_name?: string | null;
  signed_at: string;
  pdf_storage_path?: string | null;
  clinical_snapshot_json: ClinicalSnapshot;
  patient?: {
    uhid: string;
    full_name: string;
    mobile: string;
  };
  order?: {
    order_number: string;
  };
}

type SecureLinkState = 'Loading' | 'Active' | 'Missing' | 'Expired' | 'Revoked' | 'ActiveUnrecoverable' | 'Error';

function tokenFromCanonicalUrl(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const match = value.match(/^https:\/\/lis[.]bimalpathology[.]com[.]np\/r\/([A-Za-z0-9_-]{32,256})$/);
  return match?.[1] || null;
}

export const ReportsPage: React.FC = () => {
  const { can } = usePermissions();
  const navigate = useNavigate();
  const [routeParams] = useSearchParams();
  const openedRouteReport = useRef<string | null>(null);

  const [reports, setReports] = useState<DbReport[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState(routeParams.get('search') || '');
  const [serverSearch, setServerSearch] = useState(routeParams.get('search') || '');
  const [statusFilter, setStatusFilter] = useState(routeParams.get('status') || 'All');
  const [amendmentFilter, setAmendmentFilter] = useState(routeParams.get('amendment') || 'All');
  const [dateFilter, setDateFilter] = useState(routeParams.get('date') || '');
  const [cursor, setCursor] = useState<RegistryCursor | null>(null);
  const [cursorHistory, setCursorHistory] = useState<Array<RegistryCursor | null>>([]);

  useEffect(() => {
    const statusParam = routeParams.get('status');
    if (statusParam && statusParam !== statusFilter) {
      setStatusFilter(statusParam);
      setCursor(null);
      setCursorHistory([]);
    }
    const dateParam = routeParams.get('date');
    if (dateParam && dateParam !== dateFilter) {
      setDateFilter(dateParam);
      setCursor(null);
      setCursorHistory([]);
    }
  }, [dateFilter, routeParams, statusFilter]);
  const [hasNextPage,setHasNextPage]=useState(false);

  // Preview Modal
  const [previewOpen, setPreviewOpen] = useState(false);
  const [selectedReport, setSelectedReport] = useState<DbReport | null>(null);
  const [selectedPublicToken, setSelectedPublicToken] = useState<string | null>(null);
  const [secureLinkState, setSecureLinkState] = useState<SecureLinkState>('Loading');
  const [generatingSecureLink, setGeneratingSecureLink] = useState(false);

  // Amendment Dialog
  const [amendModalOpen, setAmendModalOpen] = useState(false);
  const [amendTargetReport, setAmendTargetReport] = useState<DbReport | null>(null);
  const [amendmentReason, setAmendmentReason] = useState('');
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  const loadReports = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const {data,error:fetchErr}=await supabase.rpc('search_report_registry',{
        p_search:serverSearch||null,p_status:statusFilter==='All'?null:statusFilter,p_amendment_state:amendmentFilter,p_date:dateFilter||null,
        p_cursor_signed_at:cursor?.timestamp||null,p_cursor_id:cursor?.id||null,p_limit:REGISTRY_PAGE_SIZE,
      });

      if (fetchErr) throw fetchErr;
      const page=splitServerPage(((data||[]) as Array<{item:DbReport}>).map(row=>row.item));setReports(page.rows);setHasNextPage(page.hasNext);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load diagnostic reports.'));
    } finally {
      setLoading(false);
    }
  }, [amendmentFilter,cursor,dateFilter,serverSearch,statusFilter]);

  useEffect(() => {
    loadReports();
  }, [loadReports]);
  useEffect(()=>{const timer=window.setTimeout(()=>{setCursor(null);setCursorHistory([]);setServerSearch(searchTerm.trim())},300);return()=>window.clearTimeout(timer)},[searchTerm]);
  useEffect(()=>subscribeWorkflowInvalidation('reports',loadReports),[loadReports]);

  const orderIdParam = routeParams.get('orderId');
  const [orderDeliverySummary, setOrderDeliverySummary] = useState<any[] | null>(null);
  const [orderInfo, setOrderInfo] = useState<{ orderNumber?: string; patientName?: string; uhid?: string } | null>(null);

  useEffect(() => {
    if (!orderIdParam) {
      setOrderDeliverySummary(null);
      return;
    }
    void Promise.all([
      supabase
        .from('order_report_group_workspace' as any)
        .select('*')
        .eq('order_id', orderIdParam)
        .order('display_order'),
      supabase
        .from('clinical_orders')
        .select('order_number,patient:patients(uhid,full_name)')
        .eq('id', orderIdParam)
        .maybeSingle(),
    ]).then(([{ data: wsData }, { data: ordData }]) => {
      if (wsData) {
        const uniqueGroups = [...new Map((wsData as any[]).map((r) => [r.report_group_id, r])).values()];
        setOrderDeliverySummary(uniqueGroups);
      }
      if (ordData) {
        setOrderInfo({
          orderNumber: ordData.order_number,
          patientName: (ordData.patient as any)?.full_name,
          uhid: (ordData.patient as any)?.uhid,
        });
      }
    });
  }, [orderIdParam]);

  useEffect(() => {
    const reportId = routeParams.get('reportId');
    if (!reportId || openedRouteReport.current === reportId || loading) return;
    const report = reports.find((candidate) => candidate.id === reportId);
    openedRouteReport.current = reportId;
    if (report) {
      void handleOpenPreview(report);
      return;
    }

    // A report deep link may point outside the current keyset page. Resolve it
    // directly through the existing authenticated SELECT/RLS contract.
    void supabase
      .from('diagnostic_reports')
      .select('id, order_id, patient_id, report_number, version, is_amendment, amendment_reason, amended_from_report_id, status, integrity_hash, performed_by_personnel_name, signed_by_personnel_name, signed_at, pdf_storage_path, clinical_snapshot_json, patient:patients(uhid, full_name, mobile), order:clinical_orders(order_number)')
      .eq('id', reportId)
      .maybeSingle()
      .then(({ data, error: lookupError }) => {
        if (lookupError) {
          setError(safeErrorMessage(lookupError, 'Unable to open the requested report.'));
          return;
        }
        if (!data) {
          setError('The requested report is unavailable or you do not have access.');
          return;
        }
        void handleOpenPreview(data as unknown as DbReport);
      });
  }, [loading, reports, routeParams]);

  const resolveSecureLink = async (report: DbReport): Promise<string | null> => {
    setSecureLinkState('Loading');
    const { data, error: statusError } = await supabase.rpc('get_report_secure_link_status', {
      p_report_id: report.id,
    });
    if (statusError) throw statusError;
    if (data?.report_id !== report.id || Number(data?.report_version) !== report.version) {
      throw new Error('STALE_REPORT_LINK_STATUS');
    }
    const token = tokenFromCanonicalUrl(data?.public_url);
    setSelectedPublicToken(token);
    setSecureLinkState(token ? 'Active' : (data?.state || 'Missing'));
    return token;
  };

  const handleOpenPreview = async (report: DbReport) => {
    setSelectedReport(report);
    setSelectedPublicToken(null);
    setPreviewOpen(true);
    try {
      await resolveSecureLink(report);
    } catch (err) {
      setSecureLinkState('Error');
      setError(safeErrorMessage(err, 'Unable to check the secure report link.'));
    }
  };

  const handleGenerateSecureLink = async () => {
    if (!selectedReport?.id) return;
    setGeneratingSecureLink(true);
    try {
      const rawToken = generateRawToken();
      const tokenHash = await hashToken(rawToken);
      const publicUrl = `https://dashboard.bimalpathology.com.np/r/${rawToken}`;
      const { data, error: provisionError } = await supabase.rpc('provision_historical_report_secure_link', {
        p_report_id: selectedReport.id,
        p_token_hash: tokenHash,
        p_public_url: publicUrl,
        p_expiry_days: 30,
      });
      if (provisionError) throw provisionError;
      if (data?.report_id !== selectedReport.id || Number(data?.report_version) !== selectedReport.version || data?.sms_queued !== false) {
        throw new Error('INVALID_REPORT_LINK_PROVISIONING_RESULT');
      }
      const provisionedToken = tokenFromCanonicalUrl(data?.public_url);
      if (!provisionedToken) throw new Error('INVALID_SECURE_REPORT_URL');
      setSelectedPublicToken(provisionedToken);
      setSecureLinkState('Active');
      setToastMsg(data?.reused ? 'Existing secure report link restored.' : 'Secure report link generated. No SMS was sent.');
    } catch (err) {
      setError(safeErrorMessage(err, 'Unable to generate the secure report link.'));
    } finally {
      setGeneratingSecureLink(false);
    }
  };

  const handleOpenAmend = (report: DbReport) => {
    setAmendTargetReport(report);
    setAmendmentReason('');
    setAmendModalOpen(true);
  };

  const handleConfirmAmend = async () => {
    if (!amendTargetReport || !amendmentReason.trim()) return;

    try {
      // Find the first clinical order item to navigate to for editing
      const snapshot = amendTargetReport.clinical_snapshot_json;
      const firstOrderItemId = snapshot?.investigations?.[0]?.order_item_id;

      if (firstOrderItemId) {
        setAmendModalOpen(false);
        navigate(`/worklist/order/${amendTargetReport.order_id}?item=${firstOrderItemId}&amendReportId=${amendTargetReport.id}&reason=${encodeURIComponent(amendmentReason.trim())}`);
      } else {
        setToastMsg('Order item reference not found for editing.');
      }
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to start amendment workflow.'));
    }
  };

  const filteredReports = reports;

  return (
    <Box>
      <PageHeader
        title="Diagnostic Pathology Reports"
        subtitle="Immutable signed clinical reports, cryptographic SHA-256 integrity, versioning, and amendments"
        action={
          <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadReports} disabled={loading}>
            Refresh
          </Button>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      {orderDeliverySummary && orderDeliverySummary.length > 0 && (
        <Paper
          elevation={0}
          sx={{
            p: 2.5,
            mb: 3,
            border: '1px solid #86efac',
            bgcolor: '#f0fdf4',
            borderRadius: 2,
          }}
        >
          <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1.5, flexWrap: 'wrap', gap: 1 }}>
            <Box>
              <Typography variant="subtitle1" fontWeight={800} color="success.dark">
                ✓ Order Delivery Summary: {orderInfo?.orderNumber || 'Lab Order'}
              </Typography>
              <Typography variant="body2" color="text.secondary">
                Patient: <strong>{orderInfo?.patientName || 'Patient'}</strong> &bull; UHID: <strong>{orderInfo?.uhid || '-'}</strong>
              </Typography>
            </Box>
            <Button
              size="small"
              variant="outlined"
              color="success"
              onClick={() => navigate('/worklist')}
            >
              Back to Worklist
            </Button>
          </Box>

          <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #dcfce7', bgcolor: '#ffffff' }}>
            <Table size="small">
              <TableHead>
                <TableRow sx={{ bgcolor: '#f0fdf4' }}>
                  <TableCell sx={{ fontWeight: 700 }}>Report Group</TableCell>
                  <TableCell sx={{ fontWeight: 700 }}>Sign-Off Status</TableCell>
                  <TableCell sx={{ fontWeight: 700 }}>PDF Delivery</TableCell>
                  <TableCell sx={{ fontWeight: 700 }}>Patient Portal</TableCell>
                  <TableCell align="center" sx={{ fontWeight: 700 }}>Action</TableCell>
                </TableRow>
              </TableHead>
              <TableBody>
                {orderDeliverySummary.map((group) => {
                  const isSigned = group.report_state === 'SignedOff' || group.report_state === 'Amended';
                  const pdfReady = group.pdf_state === 'Ready';
                  return (
                    <TableRow key={group.report_group_id || group.order_item_id} hover>
                      <TableCell>
                        <Typography variant="body2" fontWeight={700}>
                          {group.title || 'Diagnostic Report'}
                        </Typography>
                        <Typography variant="caption" color="text.secondary">
                          {group.clinical_section || 'Clinical Pathology'}
                        </Typography>
                      </TableCell>
                      <TableCell>
                        <StatusChip status={group.report_state || 'Pending'} />
                      </TableCell>
                      <TableCell>
                        <Chip
                          size="small"
                          label={pdfReady ? 'PDF Ready' : isSigned ? 'PDF Generating / Pending' : 'Awaiting Sign-off'}
                          color={pdfReady ? 'success' : isSigned ? 'info' : 'default'}
                          variant="outlined"
                          sx={{ fontWeight: 600, fontSize: '0.72rem' }}
                        />
                      </TableCell>
                      <TableCell>
                        <Typography variant="caption" color={isSigned ? 'success.main' : 'text.secondary'} fontWeight={600}>
                          {isSigned ? 'Portal Available • SMS Dispatched' : 'Pending completion'}
                        </Typography>
                      </TableCell>
                      <TableCell align="center">
                        {group.latest_report_id ? (
                          <Button
                            size="small"
                            variant="outlined"
                            startIcon={<VisibilityIcon />}
                            onClick={() => {
                              const found = reports.find((r) => r.id === group.latest_report_id);
                              if (found) void handleOpenPreview(found);
                              else navigate(`/reports?reportId=${group.latest_report_id}`);
                            }}
                          >
                            Preview
                          </Button>
                        ) : (
                          <Button
                            size="small"
                            variant="text"
                            onClick={() => navigate(`/worklist/order/${group.order_id}?item=${group.order_item_id}`)}
                          >
                            Open Worklist
                          </Button>
                        )}
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          </TableContainer>
        </Paper>
      )}

      <Card>
        <CardContent>
          <Box sx={{ display: 'flex', gap: 2, mb: 2, flexWrap: 'wrap' }}>
            <TextField
              size="small"
              placeholder="Search by Report No, Lab No, UHID, Patient..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              sx={{ minWidth: 320 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
            <TextField
              select
              size="small"
              label="Report Status"
              value={statusFilter}
              onChange={(e) => {setStatusFilter(e.target.value);setCursor(null);setCursorHistory([])}}
              sx={{ minWidth: 160 }}
            >
              <MenuItem value="All">All Reports</MenuItem>
              <MenuItem value="SignedOff">Signed Off (Active)</MenuItem>
              <MenuItem value="Amended">Amended (Superseded)</MenuItem>
            </TextField>
            <TextField select size="small" label="Version" value={amendmentFilter} onChange={(e)=>{setAmendmentFilter(e.target.value);setCursor(null);setCursorHistory([])}} sx={{minWidth:140}}>
              <MenuItem value="All">All Versions</MenuItem><MenuItem value="Original">Original</MenuItem><MenuItem value="Amended">Amended</MenuItem>
            </TextField>
            <TextField size="small" type="date" label="Signed Date" value={dateFilter} onChange={(e)=>{setDateFilter(e.target.value);setCursor(null);setCursorHistory([])}} InputLabelProps={{shrink:true}} />
          </Box>

          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress />
            </Box>
          ) : (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
              <Table size="small">
                <TableHead>
                  <TableRow>
                    <TableCell>Report No & Ver</TableCell>
                    <TableCell>Lab No / Bill No</TableCell>
                    <TableCell>Report Group</TableCell>
                    <TableCell>Patient Details</TableCell>
                    <TableCell>Authorized By</TableCell>
                    <TableCell>Signed Date</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredReports.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={8} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No signed diagnostic reports found.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredReports.map((rep) => {
                      const pName = rep.patient?.full_name || rep.clinical_snapshot_json?.patient?.full_name || 'Patient';
                      const pUhid = rep.patient?.uhid || rep.clinical_snapshot_json?.patient?.uhid || '-';
                      const orderNo = rep.order?.order_number || rep.clinical_snapshot_json?.order?.order_number || '-';

                      return (
                        <TableRow key={rep.id} hover>
                          <TableCell>
                            <Typography variant="body2" fontWeight={700} color="primary.main">
                              {rep.report_number}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              Version {rep.version} {rep.is_amendment && '(Amended)'}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2">{orderNo}</Typography>
                            <Typography variant="caption" color="text.secondary">
                              {rep.clinical_snapshot_json?.order?.bill_number || '-'}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" fontWeight={700}>{(rep.clinical_snapshot_json as any)?.report_group?.title || 'Legacy Whole Order'}</Typography>
                            <Typography variant="caption" color="text.secondary">{(rep.clinical_snapshot_json as any)?.report_group?.clinical_section || 'Historical report'}</Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" fontWeight={600}>
                              {pName}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {pUhid}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2">
                              {rep.signed_by_personnel_name || '—'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              Perf: {rep.performed_by_personnel_name}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2">{formatAdDateTime(rep.signed_at)}</Typography>
                          </TableCell>
                          <TableCell>
                            <StatusChip status={rep.status} />
                          </TableCell>
                          <TableCell align="center">
                            <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center', flexWrap: 'nowrap' }}>
                              <Button
                                size="small"
                                variant="contained"
                                color="primary"
                                startIcon={<VisibilityIcon />}
                                onClick={() => void handleOpenPreview(rep)}
                                sx={{ fontSize: '0.75rem', px: 1, py: 0.25 }}
                              >
                                Preview
                              </Button>
                              <Button
                                size="small"
                                variant="outlined"
                                color="primary"
                                startIcon={<PrintIcon />}
                                onClick={async () => {
                                  await handleOpenPreview(rep);
                                  setTimeout(() => printReportDocument(), 200);
                                }}
                                sx={{ fontSize: '0.75rem', px: 1, py: 0.25 }}
                              >
                                Print
                              </Button>
                              <Button
                                size="small"
                                variant="outlined"
                                color="success"
                                startIcon={<DownloadIcon />}
                                onClick={async () => {
                                  await handleOpenPreview(rep);
                                  setTimeout(() => downloadReportPdf(rep), 200);
                                }}
                                sx={{ fontSize: '0.75rem', px: 1, py: 0.25 }}
                              >
                                Download
                              </Button>
                              {can(PERMISSION_KEYS.CAN_AMEND_REPORTS) && rep.status === 'SignedOff' && (
                                <Button
                                  size="small"
                                  variant="outlined"
                                  color="warning"
                                  startIcon={<HistoryEduIcon />}
                                  onClick={() => handleOpenAmend(rep)}
                                  sx={{ fontSize: '0.75rem', px: 1, py: 0.25 }}
                                >
                                  Amend
                                </Button>
                              )}
                            </Box>
                          </TableCell>
                        </TableRow>
                      );
                    })
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          )}
          <Box sx={{display:'flex',justifyContent:'flex-end',gap:1,mt:2}}>
            <Button disabled={!cursorHistory.length||loading} onClick={()=>{setCursor(cursorHistory.at(-1)||null);setCursorHistory(h=>h.slice(0,-1))}}>Previous</Button>
            <Button disabled={!hasNextPage||loading||!reports.length} onClick={()=>{setCursorHistory(h=>[...h,cursor]);setCursor(registryCursor(reports.at(-1)!))}}>Next</Button>
          </Box>
        </CardContent>
      </Card>

      <FinalReportViewerDialog
        open={previewOpen}
        report={selectedReport}
        onClose={() => setPreviewOpen(false)}
        publicToken={selectedPublicToken}
        secureLinkState={secureLinkState}
        canGenerateSecureLink={can(PERMISSION_KEYS.CAN_PRINT_REPORTS)}
        generatingSecureLink={generatingSecureLink}
        onGenerateSecureLink={handleGenerateSecureLink}
      />

      {/* Report Amendment Dialog */}
      <Dialog open={amendModalOpen} onClose={() => setAmendModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'warning.main' }}>
          Issue Clinical Report Amendment ({amendTargetReport?.report_number})
        </DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2" sx={{ mb: 2 }}>
            You are creating an amendment revision for <strong>{amendTargetReport?.report_number} (Version {amendTargetReport?.version})</strong>.
            The current report will remain immutable in history as Version {amendTargetReport?.version}.
          </Typography>
          <TextField
            fullWidth
            multiline
            rows={3}
            size="small"
            required
            label="Mandatory Amendment Clinical Reason *"
            placeholder="e.g. Corrected Dilution Factor for Serum Amylase as per clinician request..."
            value={amendmentReason}
            onChange={(e) => setAmendmentReason(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setAmendModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="warning"
            disabled={!amendmentReason.trim()}
            onClick={handleConfirmAmend}
          >
            Start Amendment Revision
          </Button>
        </DialogActions>
      </Dialog>

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
