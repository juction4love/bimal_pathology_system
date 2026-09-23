/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Sample Accessioning, Collection & Reception Lifecycle Management (Phase 2)
 * Full PostgreSQL Sample Lifecycle & Lineage Tracking
 */

import React, { useState, useEffect, useCallback } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import {
  Box,
  Card,
  CardContent,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  TextField,
  MenuItem,
  InputAdornment,
  Button,
  Typography,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  CircularProgress,
  Alert,
  Snackbar,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import AutorenewIcon from '@mui/icons-material/Autorenew';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { SAMPLE_STATUSES, SampleStatus } from '@/config/constants';
import { formatAdDateTime } from '@/lib/dateTime';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { REGISTRY_PAGE_SIZE, registryCursor, splitServerPage, type RegistryCursor } from '@/lib/serverPagination';
import { publishWorkflowInvalidation, subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';
import { getNextOrderAction, scheduleOrderNavigation } from '@/lib/orderWorkflowNavigation';

interface SampleWithOrder {
  id: string;
  barcode: string;
  order_id: string;
  patient_id: string;
  specimen_type: string;
  container_type: string;
  status: SampleStatus;
  collected_at?: string | null;
  collected_by_name?: string | null;
  received_at?: string | null;
  received_by_name?: string | null;
  rejected_at?: string | null;
  rejection_reason?: string | null;
  recollected_from_sample_id?: string | null;
  created_at: string;
  order?: {
    order_number: string;
    order_date_bs: string;
  };
  patient?: {
    uhid: string;
    full_name: string;
    mobile: string;
    gender: string;
    age_years?: number | null;
  };
  items?: Array<{
    id: string;
    test_name: string;
    department: string;
    reporting_type: string;
  }>;
}

export const SampleAccessioningPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const { can } = usePermissions();

  const initialSearch = searchParams.get('search') || searchParams.get('order_number') || searchParams.get('order_id') || searchParams.get('orderId') || '';
  const [searchTerm, setSearchTerm] = useState(initialSearch);
  const [serverSearch, setServerSearch] = useState(initialSearch);
  const [statusFilter, setStatusFilter] = useState(searchParams.get('status') || 'All');
  const [specimenFilter, setSpecimenFilter] = useState(searchParams.get('specimen') || '');
  const [dateFilter, setDateFilter] = useState(searchParams.get('date') || '');
  const [highlightedSampleIndex, setHighlightedSampleIndex] = useState(0);
  const [samples, setSamples] = useState<SampleWithOrder[]>([]);
  const [cursor, setCursor] = useState<RegistryCursor | null>(null);
  const [cursorHistory, setCursorHistory] = useState<Array<RegistryCursor | null>>([]);

  useEffect(() => {
    const statusParam = searchParams.get('status');
    if (statusParam && statusParam !== statusFilter) {
      setStatusFilter(statusParam);
      setCursor(null);
      setCursorHistory([]);
    }
  }, [searchParams, statusFilter]);
  const [hasNextPage,setHasNextPage]=useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Rejection Dialog State
  const [rejectModalOpen, setRejectModalOpen] = useState(false);
  const [selectedSample, setSelectedSample] = useState<SampleWithOrder | null>(null);
  const [rejectReason, setRejectReason] = useState('');
  const [rejectNotes, setRejectNotes] = useState('');

  // Toast State
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  const loadSamples = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase.rpc('search_sample_accessioning',{
        p_search:serverSearch||null,p_status:statusFilter==='All'?null:statusFilter,p_specimen:specimenFilter||null,p_date:dateFilter||null,
        p_cursor_created_at:cursor?.timestamp||null,p_cursor_id:cursor?.id||null,p_limit:REGISTRY_PAGE_SIZE,
      });

      if (fetchErr) throw fetchErr;
      const page=splitServerPage(((data||[]) as Array<{item:SampleWithOrder}>).map(row=>row.item));setSamples(page.rows);setHasNextPage(page.hasNext);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load samples.'));
    } finally {
      setLoading(false);
    }
  }, [cursor,dateFilter,serverSearch,specimenFilter,statusFilter]);

  useEffect(() => {
    loadSamples();
  }, [loadSamples]);
  useEffect(()=>{const timer=window.setTimeout(()=>{setCursor(null);setCursorHistory([]);setServerSearch(searchTerm.trim())},300);return()=>window.clearTimeout(timer)},[searchTerm]);
  useEffect(()=>subscribeWorkflowInvalidation('samples',loadSamples),[loadSamples]);

  useEffect(() => {
    const targetSampleId = searchParams.get('sampleId');
    if (!targetSampleId || loading || !samples.length) return;
    const idx = samples.findIndex((s) => s.id === targetSampleId);
    if (idx !== -1) {
      setHighlightedSampleIndex(idx);
      const timer = window.setTimeout(() => {
        document.querySelector<HTMLElement>(`[data-sample-action="${targetSampleId}"]`)?.focus();
      }, 100);
      return () => window.clearTimeout(timer);
    }
  }, [loading, samples, searchParams]);

  // Mark Sample Collected
  const handleMarkCollected = async (sample: SampleWithOrder) => {
    try {
      const { error: transitionError } = await supabase.rpc('transition_sample_lifecycle', {
        p_sample_id: sample.id,
        p_to_status: SAMPLE_STATUSES.COLLECTED,
        p_reason: 'Sample collected from patient',
      });
      if (transitionError) throw transitionError;

      setToastMsg(`Barcode ${sample.barcode} marked as Collected.`);
      publishWorkflowInvalidation('sample-changed',['samples','worklist','dashboard'],sample.id);
      await loadSamples();
      const nextAction = await getNextOrderAction(supabase, sample.order_id);
      setToastMsg(nextAction.message);
      scheduleOrderNavigation(navigate, nextAction);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to update collection status.'));
    }
  };

  // Receive Sample in Lab
  const handleReceiveSample = async (sample: SampleWithOrder) => {
    try {
      const { error: transitionError } = await supabase.rpc('transition_sample_lifecycle', {
        p_sample_id: sample.id,
        p_to_status: SAMPLE_STATUSES.RECEIVED,
        p_reason: 'Accessioned and received in laboratory',
      });
      if (transitionError) throw transitionError;

      setToastMsg(`Barcode ${sample.barcode} received in laboratory.`);
      publishWorkflowInvalidation('sample-changed',['samples','worklist','dashboard'],sample.id);
      await loadSamples();
      const nextAction = await getNextOrderAction(supabase, sample.order_id);
      setToastMsg(nextAction.message);
      scheduleOrderNavigation(navigate, nextAction);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to update reception status.'));
    }
  };

  // Open Rejection Dialog
  const handleOpenReject = (sample: SampleWithOrder) => {
    setSelectedSample(sample);
    setRejectReason('Grossly Hemolyzed specimen');
    setRejectNotes('');
    setRejectModalOpen(true);
  };

  // Confirm Rejection
  const handleConfirmReject = async () => {
    if (!selectedSample || !rejectReason.trim()) return;

    const fullReason = rejectNotes.trim() ? `${rejectReason.trim()} (${rejectNotes.trim()})` : rejectReason.trim();
    try {
      const { error: transitionError } = await supabase.rpc('transition_sample_lifecycle', {
        p_sample_id: selectedSample.id,
        p_to_status: SAMPLE_STATUSES.REJECTED,
        p_reason: fullReason,
      });
      if (transitionError) throw transitionError;

      setToastMsg(`Sample ${selectedSample.barcode} rejected.`);
      publishWorkflowInvalidation('sample-changed',['samples','worklist','dashboard'],selectedSample.id);
      setRejectModalOpen(false);
      loadSamples();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to record rejection.'));
    }
  };

  // Trigger Recollection (Creates child sample with lineage link)
  const handleRecollect = async (sample: SampleWithOrder) => {
    try {
      const { data, error: transitionError } = await supabase.rpc('transition_sample_lifecycle', {
        p_sample_id: sample.id,
        p_to_status: SAMPLE_STATUSES.PENDING,
        p_reason: `Recollection ordered due to rejection of ${sample.barcode}`,
      });
      if (transitionError) throw transitionError;
      setToastMsg(`Recollection sample ${data?.barcode || ''} created.`);
      publishWorkflowInvalidation('sample-changed',['samples','worklist','dashboard'],sample.id);
      await loadSamples();
      const nextAction = await getNextOrderAction(supabase, sample.order_id);
      setToastMsg(nextAction.message);
      scheduleOrderNavigation(navigate, nextAction);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to initiate recollection.'));
    }
  };

  const filteredSamples = samples;

  return (
    <Box data-keyboard-form="true">
      <PageHeader
        title="Sample Accessioning & Barcode Lifecycle"
        subtitle="Track phlebotomy collection, laboratory accessioning, barcode scanning, and rejection lineage"
        action={
          <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadSamples} disabled={loading}>
            Refresh
          </Button>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      <Card>
        <CardContent>
          <Box sx={{ display: 'flex', gap: 2, mb: 2, flexWrap: 'wrap' }}>
            <TextField
              size="small"
              placeholder="Scan Barcode or Search Lab No, Patient, UHID..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'ArrowDown') {
                  e.preventDefault();
                  setHighlightedSampleIndex((current) => Math.min(current + 1, filteredSamples.length - 1));
                } else if (e.key === 'ArrowUp') {
                  e.preventDefault();
                  setHighlightedSampleIndex((current) => Math.max(current - 1, 0));
                } else if (e.key === 'Escape') {
                  e.preventDefault();
                  setSearchTerm('');
                  setHighlightedSampleIndex(0);
                } else if (e.key === 'Enter' && filteredSamples[highlightedSampleIndex]) {
                  e.preventDefault();
                  const id = filteredSamples[highlightedSampleIndex].id;
                  document.querySelector<HTMLElement>(`[data-sample-action="${id}"]`)?.focus();
                }
              }}
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
              label="Sample Status"
              value={statusFilter}
              onChange={(e) => {setStatusFilter(e.target.value);setCursor(null);setCursorHistory([])}}
              sx={{ minWidth: 160 }}
            >
              <MenuItem value="All">All Statuses</MenuItem>
              <MenuItem value="Pending">Pending</MenuItem>
              <MenuItem value="Collected">Collected</MenuItem>
              <MenuItem value="Received">Received</MenuItem>
              <MenuItem value="Processing">Processing</MenuItem>
              <MenuItem value="Rejected">Rejected</MenuItem>
              <MenuItem value="Completed">Completed</MenuItem>
            </TextField>
            <TextField size="small" label="Specimen" value={specimenFilter} onChange={(e)=>{setSpecimenFilter(e.target.value);setCursor(null);setCursorHistory([])}} sx={{minWidth:150}} />
            <TextField size="small" type="date" label="Order Date" value={dateFilter} onChange={(e)=>{setDateFilter(e.target.value);setCursor(null);setCursorHistory([])}} InputLabelProps={{shrink:true}} />
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
                    <TableCell>Barcode & Specimen</TableCell>
                    <TableCell>Lab No / Patient</TableCell>
                    <TableCell>Grouped Tests</TableCell>
                    <TableCell>Status</TableCell>
                    <TableCell>Collection / Reception</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredSamples.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No sample accession records found.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredSamples.map((sample) => {
                      const testNames = (sample.items || []).map((i) => i.test_name).join(', ') || 'Standard Profile';
                      return (
                        <TableRow key={sample.id} hover selected={filteredSamples[highlightedSampleIndex]?.id === sample.id}>
                          <TableCell>
                            <Typography variant="body2" fontWeight={700} sx={{ fontFamily: 'monospace', color: 'primary.main' }}>
                              {sample.barcode}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {sample.specimen_type} • {sample.container_type}
                            </Typography>
                            {sample.recollected_from_sample_id && (
                              <Typography variant="caption" sx={{ display: 'block', color: 'warning.main', fontWeight: 600 }}>
                                Lineage: Recollection
                              </Typography>
                            )}
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" fontWeight={600}>
                              {sample.patient?.full_name || 'Patient'}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {sample.order?.order_number || 'Lab Order'} • UHID: {sample.patient?.uhid}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 260 }}>
                              {testNames}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <StatusChip status={sample.status} />
                            {sample.rejection_reason && (
                              <Typography variant="caption" sx={{ display: 'block', color: 'error.main', mt: 0.5 }}>
                                Reason: {sample.rejection_reason}
                              </Typography>
                            )}
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption" sx={{ display: 'block', color: 'text.secondary' }}>
                              Created: {formatAdDateTime(sample.created_at)}
                            </Typography>
                            {sample.collected_at ? (
                              <Typography variant="caption" sx={{ display: 'block' }}>
                                Coll: {formatAdDateTime(sample.collected_at)}
                              </Typography>
                            ) : (
                              <Typography variant="caption" color="text.secondary">Not collected</Typography>
                            )}
                            {sample.received_at && (
                              <Typography variant="caption" sx={{ display: 'block', color: 'primary.main' }}>
                                Recv: {formatAdDateTime(sample.received_at)}
                              </Typography>
                            )}
                            {sample.rejected_at && (
                              <Typography variant="caption" sx={{ display: 'block', color: 'error.main' }}>
                                Rejected: {formatAdDateTime(sample.rejected_at)}
                              </Typography>
                            )}
                          </TableCell>
                          <TableCell align="center">
                            <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center' }}>
                              {sample.status === SAMPLE_STATUSES.PENDING && can(PERMISSION_KEYS.CAN_COLLECT_SAMPLE) && (
                                <Button
                                  data-sample-action={sample.id}
                                  size="small"
                                  variant="outlined"
                                  color="info"
                                  onClick={() => handleMarkCollected(sample)}
                                >
                                  Collect
                                </Button>
                              )}
                              {sample.status === SAMPLE_STATUSES.COLLECTED && can(PERMISSION_KEYS.CAN_RECEIVE_SAMPLE) && (
                                <Button
                                  data-sample-action={sample.id}
                                  size="small"
                                  variant="contained"
                                  color="primary"
                                  startIcon={<CheckCircleIcon />}
                                  onClick={() => handleReceiveSample(sample)}
                                >
                                  Receive
                                </Button>
                              )}
                              {sample.status === SAMPLE_STATUSES.RECEIVED && (
                                <Button
                                  data-sample-action={sample.id}
                                  size="small"
                                  variant="contained"
                                  color="primary"
                                  onClick={() => navigate(`/worklist/order/${sample.order_id}`)}
                                  sx={{ fontWeight: 700 }}
                                >
                                  Open Worklist →
                                </Button>
                              )}
                              {[SAMPLE_STATUSES.PENDING, SAMPLE_STATUSES.COLLECTED, SAMPLE_STATUSES.RECEIVED].includes(sample.status as any) &&
                                can(PERMISSION_KEYS.CAN_REJECT_SAMPLE) && (
                                  <Button
                                    data-sample-action={sample.id}
                                    size="small"
                                    variant="outlined"
                                    color="error"
                                    onClick={() => handleOpenReject(sample)}
                                  >
                                    Reject
                                  </Button>
                                )}
                              {sample.status === SAMPLE_STATUSES.REJECTED && can(PERMISSION_KEYS.CAN_COLLECT_SAMPLE) && (
                                <Button
                                  data-sample-action={sample.id}
                                  size="small"
                                  variant="outlined"
                                  color="warning"
                                  startIcon={<AutorenewIcon />}
                                  onClick={() => handleRecollect(sample)}
                                >
                                  Recollect
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
            <Button disabled={!hasNextPage||loading||!samples.length} onClick={()=>{setCursorHistory(h=>[...h,cursor]);setCursor(registryCursor(samples.at(-1)!))}}>Next</Button>
          </Box>
        </CardContent>
      </Card>

      {/* Reject Specimen Dialog */}
      <Dialog open={rejectModalOpen} onClose={() => setRejectModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 700, color: 'error.main' }}>
          Reject Laboratory Specimen ({selectedSample?.barcode})
        </DialogTitle>
        <DialogContent dividers>
          <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
            Specimen rejection is an audited clinical event. Document the reason below.
          </Typography>
          <TextField
            select
            fullWidth
            size="small"
            label="Common Rejection Reason *"
            value={rejectReason}
            onChange={(e) => setRejectReason(e.target.value)}
            sx={{ mb: 2 }}
          >
            {[
              'Grossly Hemolyzed specimen',
              'Clotted EDTA whole blood',
              'Insufficient specimen volume (QNS)',
              'Improper collection container / Tube additive',
              'Unlabeled or Mislabeled specimen',
              'Lipemic specimen interfering with assay',
              'Delayed transit / Degraded specimen',
            ].map((reason) => (
              <MenuItem key={reason} value={reason}>
                {reason}
              </MenuItem>
            ))}
          </TextField>
          <TextField
            fullWidth
            size="small"
            multiline
            rows={2}
            label="Additional Notes / Clinical Observations"
            value={rejectNotes}
            onChange={(e) => setRejectNotes(e.target.value)}
            placeholder="e.g. Red blood cell lysis observed during centrifugation..."
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setRejectModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="error"
            onClick={handleConfirmReject}
            disabled={!rejectReason.trim()}
          >
            Confirm Rejection
          </Button>
        </DialogActions>
      </Dialog>

      {/* Compact Centered Toast */}
      <Snackbar
        open={Boolean(toastMsg)}
        autoHideDuration={3500}
        onClose={() => setToastMsg(null)}
        anchorOrigin={{ vertical: 'top', horizontal: 'center' }}
      >
        <Alert onClose={() => setToastMsg(null)} severity="success" variant="filled" sx={{ width: '100%' }}>
          {toastMsg}
        </Alert>
      </Snackbar>
    </Box>
  );
};
