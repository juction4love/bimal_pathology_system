/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Outsource Sample Tracking Workspace (Phase 16)
 * End-to-End Chain-of-Custody Tracking for Outsourced Histopathology & IHC Specimens
 */

import React, { useState, useEffect, useCallback, useMemo } from 'react';
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
  InputAdornment,
  Button,
  Typography,
  Tabs,
  Tab,
  Chip,
  MenuItem,
  CircularProgress,
  Alert,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Grid,
  Divider,
  Drawer,
  List,
  ListItem,
  ListItemText,
  Snackbar,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import RefreshIcon from '@mui/icons-material/Refresh';
import LocalShippingIcon from '@mui/icons-material/LocalShipping';
import ReceiptLongIcon from '@mui/icons-material/ReceiptLong';
import InventoryIcon from '@mui/icons-material/Inventory';

import { PageHeader } from '@/components/common/PageHeader';
import { formatAdDateTime, getNepalDayBounds, getNepalTodayAd } from '@/lib/dateTime';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { OutsourceSample, OutsourceSampleEvent, OutsourceSampleStatus } from '@/types/database';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { getNextOrderAction, scheduleOrderNavigation } from '@/lib/orderWorkflowNavigation';

export const OutsourceTrackingPage: React.FC = () => {
  const [searchParams] = useSearchParams();
  const navigate = useNavigate();
  const [samples, setSamples] = useState<OutsourceSample[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [searchTerm, setSearchTerm] = useState('');
  const [tabValue, setTabValue] = useState(0);
  const [operationError, setOperationError] = useState<string | null>(null);
  const [referenceLabs, setReferenceLabs] = useState<Array<{ id: string; name: string }>>([]);
  const [referenceLabId, setReferenceLabId] = useState('');
  const [toastMsg, setToastMsg] = useState<string | null>(null);

  // Modal States
  const [selectedSample, setSelectedSample] = useState<OutsourceSample | null>(null);
  const [timelineDrawerOpen, setTimelineDrawerOpen] = useState(false);
  const [sampleEvents, setSampleEvents] = useState<OutsourceSampleEvent[]>([]);
  const [loadingEvents, setLoadingEvents] = useState(false);

  // Dispatch Dialog
  const [dispatchModalOpen, setDispatchModalOpen] = useState(false);
  const [refLabName, setRefLabName] = useState('');
  const [courierName, setCourierName] = useState('');
  const [courierTrackingNo, setCourierTrackingNo] = useState('');
  const [itemsSentCount, setItemsSentCount] = useState('');
  const [dispatchNotes, setDispatchNotes] = useState('');
  const [isSubmittingDispatch, setIsSubmittingDispatch] = useState(false);

  // Result Receipt Dialog
  const [resultModalOpen, setResultModalOpen] = useState(false);
  const [refReportNo, setRefReportNo] = useState('');
  const [externalReportDate, setExternalReportDate] = useState(getNepalTodayAd());
  const [resultNotes, setResultNotes] = useState('');
  const [isSubmittingResult, setIsSubmittingResult] = useState(false);

  // Material Return Dialog
  const [returnModalOpen, setReturnModalOpen] = useState(false);
  const [blocksReturned, setBlocksReturned] = useState<number | ''>('');
  const [slidesReturned, setSlidesReturned] = useState<number | ''>('');
  const [returnNotes, setReturnNotes] = useState('');
  const [isSubmittingReturn, setIsSubmittingReturn] = useState(false);

  // Generic Status Update Dialog
  const [statusModalOpen, setStatusModalOpen] = useState(false);
  const [targetStatus, setTargetStatus] = useState<OutsourceSampleStatus>('ProcessingAtReferenceLab');
  const [statusNotes, setStatusNotes] = useState('');
  const [isSubmittingStatus, setIsSubmittingStatus] = useState(false);

  // Fetch Samples
  const loadSamples = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase
        .from('outsource_samples')
        .select(`
          *,
          patient:patients(uhid, full_name, mobile, gender, age_years),
          bill:bills(bill_number, created_at),
          order_item:clinical_order_items!outsource_samples_order_item_id_fkey(order_id, outsource_state)
        `)
        .order('created_at', { ascending: false });

      if (fetchErr) throw fetchErr;
      setSamples(data || []);
      const { data: labs, error: labsErr } = await (supabase.from as any)('reference_laboratories').select('id,name').eq('is_active', true).order('name');
      if (labsErr) throw labsErr;
      setReferenceLabs(labs || []);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load outsource sample records.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadSamples();
  }, [loadSamples]);

  useEffect(() => {
    const targetItemId = searchParams.get('item');
    const targetAction = searchParams.get('action');
    if (!targetItemId || loading || !samples.length) return;
    const target = samples.find((s) => s.order_item_id === targetItemId);
    if (target) {
      setSelectedSample(target);
      if (targetAction === 'dispatch') {
        setDispatchModalOpen(true);
      }
    }
  }, [loading, samples, searchParams]);

  // Load Event History for Drawer
  const handleOpenTimeline = async (sample: OutsourceSample) => {
    setSelectedSample(sample);
    setTimelineDrawerOpen(true);
    setLoadingEvents(true);
    try {
      const { data, error: evErr } = await supabase
        .from('outsource_sample_events')
        .select('*')
        .eq('outsource_sample_id', sample.id)
        .order('created_at', { ascending: true });

      if (evErr) throw evErr;
      setSampleEvents(data || []);
    } catch (err) {
      console.warn('[Outsource Timeline Error]', err);
    } finally {
      setLoadingEvents(false);
    }
  };

  // Submit Dispatch
  const handleConfirmDispatch = async () => {
    if (!selectedSample) return;
    if ((!referenceLabId && selectedSample.order_item_id) || (!refLabName.trim() && !selectedSample.order_item_id) || !courierName.trim()) {
      setOperationError('Reference laboratory and courier / hand-carry person are required.');
      return;
    }
    setIsSubmittingDispatch(true);
    try {
      const selectedLab = referenceLabs.find((lab) => lab.id === referenceLabId);
      const { error: rpcErr } = selectedSample.order_item_id ? await (supabase.rpc as any)('transition_outsource_order_item', {
        p_order_item_id: selectedSample.order_item_id,
        p_to_state: 'Dispatched',
        p_destination_id: referenceLabId,
        p_external_reference: courierTrackingNo.trim() || null,
        p_payload: {},
        p_reason: dispatchNotes.trim() || `Dispatched to ${selectedLab?.name || 'reference laboratory'} via ${courierName.trim()}`,
      }) : await supabase.rpc('update_outsource_sample_status', {
        p_sample_id: selectedSample.id,
        p_to_status: 'DispatchedToReferenceLab',
        p_notes: dispatchNotes.trim() || `Dispatched to ${refLabName.trim()} via ${courierName.trim()}`,
        p_meta: {
          reference_lab_name: refLabName.trim(),
          courier_name: courierName.trim(),
          courier_tracking_no: courierTrackingNo.trim(),
          items_sent_count: itemsSentCount.trim(),
          dispatch_notes: dispatchNotes.trim(),
        },
      });

      if (rpcErr) throw rpcErr;
      setDispatchModalOpen(false);
      await loadSamples();

      if (selectedSample.order_item_id) {
        const { data: item } = await supabase.from('clinical_order_items').select('order_id').eq('id', selectedSample.order_item_id).maybeSingle();
        if (item?.order_id) {
          const nextAction = await getNextOrderAction(supabase, item.order_id);
          setToastMsg(nextAction.message);
          scheduleOrderNavigation(navigate, nextAction, 800);
        }
      }
    } catch {
      setOperationError('Failed to record sample dispatch. Please verify the transition and try again.');
    } finally {
      setIsSubmittingDispatch(false);
    }
  };

  // Submit Result Receipt
  const handleConfirmResultReceived = async () => {
    if (!selectedSample) return;
    if (!refReportNo.trim()) {
      setOperationError('Reference laboratory report number is required.');
      return;
    }
    setIsSubmittingResult(true);
    try {
      let governedResults: any[] = [];
      if (selectedSample.order_item_id) {
        const { data: resultRows, error: resultErr } = await (supabase.from as any)('test_results').select('display_value,numeric_value,text_value,parameter:parameters(code,value_type)').eq('order_item_id', selectedSample.order_item_id);
        if (resultErr) throw resultErr;
        governedResults = (resultRows || []).filter((row:any)=>String(row.display_value || '').trim()).map((row:any)=>({parameter_code:row.parameter?.code,display_value:row.display_value,numeric_value:row.numeric_value,text_value:row.text_value}));
        if (!governedResults.length) { setOperationError('Enter the external report values in Result Entry before recording receipt.'); setIsSubmittingResult(false); return; }
      }
      const { error: rpcErr } = selectedSample.order_item_id ? await (supabase.rpc as any)('transition_outsource_order_item', {
        p_order_item_id: selectedSample.order_item_id,
        p_to_state: 'ResultReceived',
        p_destination_id: selectedSample.reference_laboratory_id || null,
        p_external_reference: refReportNo.trim(),
        p_payload: { result_type: governedResults.some((row:any)=>row.numeric_value != null) ? 'STRUCTURED' : 'NARRATIVE', results: governedResults, source_report_reference: refReportNo.trim(), interpretation: resultNotes.trim(), external_report_date: externalReportDate },
        p_reason: resultNotes.trim() || 'External report received',
      }) : await supabase.rpc('update_outsource_sample_status', {
        p_sample_id: selectedSample.id,
        p_to_status: 'ResultReceived',
        p_notes: resultNotes.trim() || `External report received from reference lab: ${refReportNo.trim()}`,
        p_meta: {
          reference_lab_report_no: refReportNo.trim(),
          external_report_date: externalReportDate,
          result_notes: resultNotes.trim(),
        },
      });

      if (rpcErr) throw rpcErr;
      setResultModalOpen(false);
      await loadSamples();

      if (selectedSample.order_item_id) {
        const { data: item } = await supabase.from('clinical_order_items').select('order_id').eq('id', selectedSample.order_item_id).maybeSingle();
        if (item?.order_id) {
          const nextAction = await getNextOrderAction(supabase, item.order_id);
          setToastMsg(nextAction.message);
          scheduleOrderNavigation(navigate, nextAction, 800);
        }
      }
    } catch {
      setOperationError('Failed to record external result receipt. Please verify the details and try again.');
    } finally {
      setIsSubmittingResult(false);
    }
  };

  const handleInternalReviewAndVerify = async (sample: OutsourceSample) => {
    if (!sample.order_item_id) return;
    try {
      let { error } = await (supabase.rpc as any)('transition_outsource_order_item', { p_order_item_id: sample.order_item_id, p_to_state: 'InternalReview', p_destination_id: null, p_external_reference: null, p_payload: {}, p_reason: 'External source report reviewed internally' });
      if (error) throw error;
      ({ error } = await (supabase.rpc as any)('transition_outsource_order_item', { p_order_item_id: sample.order_item_id, p_to_state: 'Verified', p_destination_id: null, p_external_reference: null, p_payload: {}, p_reason: 'External result verified by Bimal' }));
      if (error) throw error;
      await loadSamples();

      const { data: item } = await supabase.from('clinical_order_items').select('order_id').eq('id', sample.order_item_id).maybeSingle();
      if (item?.order_id) {
        const nextAction = await getNextOrderAction(supabase, item.order_id);
        setToastMsg(nextAction.message);
        scheduleOrderNavigation(navigate, nextAction, 800);
      }
    } catch (err) { setOperationError(safeErrorMessage(err, 'Internal review could not be completed. Check required result fields.')); }
  };

  const handleRejectForRecollection = async (sample: OutsourceSample) => {
    if (!sample.order_item_id) return;
    try {
      const { error } = await (supabase.rpc as any)('transition_outsource_order_item', {
        p_order_item_id: sample.order_item_id,
        p_to_state: 'RecollectionRequired',
        p_destination_id: sample.reference_laboratory_id || null,
        p_external_reference: null,
        p_payload: {},
        p_reason: 'Reference laboratory rejected the dispatched specimen; recollection required',
      });
      if (error) throw error;
      await loadSamples();

      const { data: item } = await supabase.from('clinical_order_items').select('order_id').eq('id', sample.order_item_id).maybeSingle();
      if (item?.order_id) {
        const nextAction = await getNextOrderAction(supabase, item.order_id);
        setToastMsg(nextAction.message);
        scheduleOrderNavigation(navigate, nextAction, 800);
      }
    } catch (err) {
      setOperationError(safeErrorMessage(err, 'Recollection could not be initiated. Verify the dispatch state and try again.'));
    }
  };

  // Submit Material Return
  const handleConfirmMaterialReturn = async () => {
    if (!selectedSample) return;
    setIsSubmittingReturn(true);
    try {
      const { error: rpcErr } = await supabase.rpc('update_outsource_sample_status', {
        p_sample_id: selectedSample.id,
        p_to_status: 'MaterialReturned',
        p_notes: returnNotes || `Histopathology specimen returned: ${blocksReturned} blocks, ${slidesReturned} slides`,
        p_meta: {
          blocks_returned_count: typeof blocksReturned === 'number' ? blocksReturned : 0,
          slides_returned_count: typeof slidesReturned === 'number' ? slidesReturned : 0,
          return_notes: returnNotes,
        },
      });

      if (rpcErr) throw rpcErr;
      setReturnModalOpen(false);
      await loadSamples();
    } catch {
      setOperationError('Failed to record material return. Please verify the details and try again.');
    } finally {
      setIsSubmittingReturn(false);
    }
  };

  // Submit Generic Status Transition
  const handleConfirmGenericStatus = async () => {
    if (!selectedSample) return;
    setIsSubmittingStatus(true);
    try {
      const { error: rpcErr } = await supabase.rpc('update_outsource_sample_status', {
        p_sample_id: selectedSample.id,
        p_to_status: targetStatus,
        p_notes: statusNotes || `Status updated to ${targetStatus}`,
        p_meta: {},
      });

      if (rpcErr) throw rpcErr;
      setStatusModalOpen(false);
      await loadSamples();
    } catch {
      setOperationError('Failed to update the outsource status. Please verify the transition and try again.');
    } finally {
      setIsSubmittingStatus(false);
    }
  };

  // Status Chip Formatter
  const renderStatusChip = (status: OutsourceSampleStatus) => {
    switch (status) {
      case 'ReceivedAtBimal':
        return <Chip label="Received at Bimal" color="default" size="small" sx={{ fontWeight: 700 }} />;
      case 'PreparedForDispatch':
        return <Chip label="Prepared for Dispatch" color="warning" size="small" sx={{ fontWeight: 700 }} />;
      case 'DispatchedToReferenceLab':
        return <Chip label="Dispatched" color="primary" size="small" sx={{ fontWeight: 700 }} />;
      case 'ReceivedByReferenceLab':
      case 'ProcessingAtReferenceLab':
        return <Chip label="Processing at Ref Lab" color="info" size="small" sx={{ fontWeight: 700 }} />;
      case 'ResultReceived':
        return <Chip label="Result Received" color="success" variant="outlined" size="small" sx={{ fontWeight: 700 }} />;
      case 'MaterialReturned':
        return <Chip label="Material Returned" color="success" size="small" sx={{ fontWeight: 700 }} />;
      case 'Completed':
        return <Chip label="Completed" color="success" size="small" sx={{ fontWeight: 800 }} />;
      case 'Rejected':
      case 'Cancelled':
      case 'LostInTransit':
        return <Chip label={status} color="error" size="small" sx={{ fontWeight: 800 }} />;
      default:
        return <Chip label={status} size="small" />;
    }
  };

  // Calculate Days Out
  const calculateDaysOut = (receivedAt: string, completedAt?: string | null) => {
    const start = new Date(receivedAt).getTime();
    const end = completedAt ? new Date(completedAt).getTime() : Date.now();
    const diffDays = Math.floor((end - start) / (1000 * 60 * 60 * 24));
    return diffDays === 0 ? 'Today' : `${diffDays}d`;
  };

  // Operational Counts
  const counts = useMemo(() => {
    let receivedToday = 0;
    let awaitingDispatch = 0;
    let atRefLab = 0;
    let resultsPending = 0;
    let returnPending = 0;

    const today = getNepalDayBounds();

    samples.forEach((s) => {
      if (s.received_at && s.received_at >= today.startIso && s.received_at < today.endExclusiveIso) receivedToday++;
      if (s.status === 'ReceivedAtBimal' || s.status === 'PreparedForDispatch') awaitingDispatch++;
      if (s.status === 'DispatchedToReferenceLab' || s.status === 'ReceivedByReferenceLab' || s.status === 'ProcessingAtReferenceLab') {
        atRefLab++;
        resultsPending++;
      }
      if (s.status === 'ResultReceived' && !s.material_returned) returnPending++;
    });

    return { receivedToday, awaitingDispatch, atRefLab, resultsPending, returnPending };
  }, [samples]);

  // Filtered Dataset
  const filteredSamples = useMemo(() => {
    return samples.filter((s) => {
      // Tab filter
      if (tabValue === 1 && s.status !== 'ReceivedAtBimal' && s.status !== 'PreparedForDispatch') return false;
      if (tabValue === 2 && s.status !== 'DispatchedToReferenceLab' && s.status !== 'ReceivedByReferenceLab' && s.status !== 'ProcessingAtReferenceLab') return false;
      if (tabValue === 3 && s.status !== 'DispatchedToReferenceLab' && s.status !== 'ProcessingAtReferenceLab') return false;
      if (tabValue === 4 && (s.status !== 'ResultReceived' || s.material_returned)) return false;
      if (tabValue === 5 && s.status !== 'Completed' && s.status !== 'MaterialReturned') return false;

      // Search filter
      if (searchTerm.trim()) {
        const term = searchTerm.toLowerCase();
        const tracking = s.tracking_number?.toLowerCase() || '';
        const name = s.patient?.full_name?.toLowerCase() || '';
        const uhid = s.patient?.uhid?.toLowerCase() || '';
        const desc = s.service_description?.toLowerCase() || '';
        const bill = s.bill?.bill_number?.toLowerCase() || '';
        const courier = s.courier_tracking_no?.toLowerCase() || '';

        return (
          tracking.includes(term) ||
          name.includes(term) ||
          uhid.includes(term) ||
          desc.includes(term) ||
          bill.includes(term) ||
          courier.includes(term)
        );
      }

      return true;
    });
  }, [samples, tabValue, searchTerm]);

  return (
    <Box sx={{ width: '100%' }}>
      <PageHeader
        title="Outsource Sample Tracking"
        subtitle="End-to-end chain-of-custody for physical biopsy blocks, slides, and outsourced referral tests"
        action={
          <Button variant="outlined" size="small" startIcon={<RefreshIcon />} onClick={loadSamples} disabled={loading}>
            Refresh
          </Button>
        }
      />

      {error && (
        <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>
          {error}
        </Alert>
      )}

      {/* Operational Summary Cards */}
      <Grid container spacing={2} sx={{ mb: 3 }}>
        <Grid item xs={6} sm={2.4}>
          <Card sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
            <CardContent sx={{ p: 1.75, '&:last-child': { pb: 1.75 } }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                Received Today
              </Typography>
              <Typography variant="h5" fontWeight={800} color="primary.main">
                {counts.receivedToday}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={6} sm={2.4}>
          <Card sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
            <CardContent sx={{ p: 1.75, '&:last-child': { pb: 1.75 } }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                Awaiting Dispatch
              </Typography>
              <Typography variant="h5" fontWeight={800} color="warning.main">
                {counts.awaitingDispatch}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={6} sm={2.4}>
          <Card sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
            <CardContent sx={{ p: 1.75, '&:last-child': { pb: 1.75 } }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                At Reference Lab
              </Typography>
              <Typography variant="h5" fontWeight={800} color="info.main">
                {counts.atRefLab}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={6} sm={2.4}>
          <Card sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
            <CardContent sx={{ p: 1.75, '&:last-child': { pb: 1.75 } }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                Results Pending
              </Typography>
              <Typography variant="h5" fontWeight={800} color="secondary.main">
                {counts.resultsPending}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
        <Grid item xs={6} sm={2.4}>
          <Card sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
            <CardContent sx={{ p: 1.75, '&:last-child': { pb: 1.75 } }}>
              <Typography variant="caption" color="text.secondary" fontWeight={600}>
                Material Return Due
              </Typography>
              <Typography variant="h5" fontWeight={800} color="error.main">
                {counts.returnPending}
              </Typography>
            </CardContent>
          </Card>
        </Grid>
      </Grid>

      {/* Main Workspace Table */}
      <Card elevation={0} sx={{ border: '1px solid #e2e8f0', bgcolor: '#ffffff' }}>
        <Box sx={{ borderBottom: 1, borderColor: 'divider', px: 2, pt: 0.5 }}>
          <Tabs
            value={tabValue}
            onChange={(_, val) => setTabValue(val)}
            textColor="primary"
            indicatorColor="primary"
            variant="scrollable"
            scrollButtons="auto"
          >
            <Tab label={`All Specimens (${samples.length})`} sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label={`Awaiting Dispatch (${counts.awaitingDispatch})`} sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label={`At Ref Lab (${counts.atRefLab})`} sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="Results Pending" sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label={`Return Due (${counts.returnPending})`} sx={{ textTransform: 'none', fontWeight: 600 }} />
            <Tab label="Completed" sx={{ textTransform: 'none', fontWeight: 600 }} />
          </Tabs>
        </Box>

        <CardContent sx={{ p: 2 }}>
          {/* Search Bar */}
          <Box sx={{ mb: 2 }}>
            <TextField
              size="small"
              placeholder="Search by Tracking No, Patient, UHID, Service, Courier Tracking..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              sx={{ minWidth: 360 }}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" sx={{ color: 'text.secondary' }} />
                  </InputAdornment>
                ),
              }}
            />
          </Box>

          {loading ? (
            <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
              <CircularProgress size={32} />
            </Box>
          ) : (
            <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
              <Table size="small">
                <TableHead>
                  <TableRow sx={{ bgcolor: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a' }}>Tracking No / Received</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a' }}>Patient Details</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a' }}>Service & Specimen</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a' }}>Reference Lab & Dispatch</TableCell>
                    <TableCell sx={{ fontWeight: 700, color: '#0f172a' }}>Status</TableCell>
                    <TableCell align="center" sx={{ fontWeight: 700, color: '#0f172a' }}>TAT</TableCell>
                    <TableCell align="center" sx={{ fontWeight: 700, color: '#0f172a', width: 220 }}>Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredSamples.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={7} align="center" sx={{ py: 4, color: 'text.secondary' }}>
                        No outsource samples match your criteria.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredSamples.map((s) => (
                      <TableRow key={s.id} hover sx={{ borderBottom: '1px solid #f1f5f9' }}>
                        {/* 1. Tracking No / Received */}
                        <TableCell sx={{ py: 1 }}>
                          <Typography variant="body2" fontWeight={700} color="primary.main" sx={{ fontFamily: 'monospace' }}>
                            {s.tracking_number}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {formatAdDateTime(s.received_at)}
                          </Typography>
                          {s.bill?.bill_number && (
                            <Typography variant="caption" sx={{ display: 'block', color: 'text.secondary' }}>
                              Bill: {s.bill.bill_number}
                            </Typography>
                          )}
                        </TableCell>

                        {/* 2. Patient Details */}
                        <TableCell sx={{ py: 1 }}>
                          <Typography variant="body2" fontWeight={600}>
                            {s.patient?.full_name || 'Patient'}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {s.patient?.uhid} &bull; {s.patient?.age_years ? `${s.patient.age_years}Y` : ''} / {s.patient?.gender}
                          </Typography>
                        </TableCell>

                        {/* 3. Service & Specimen */}
                        <TableCell sx={{ py: 1 }}>
                          <Typography variant="body2" fontWeight={700}>
                            {s.service_description}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {s.specimen_type} &bull; <strong>{s.quantity_received}</strong>
                          </Typography>
                        </TableCell>

                        {/* 4. Reference Lab & Dispatch */}
                        <TableCell sx={{ py: 1 }}>
                          <Typography variant="body2" fontWeight={600}>
                            {s.reference_lab_name || 'External Reference Lab'}
                          </Typography>
                          {s.courier_name && (
                            <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                              via {s.courier_name} {s.courier_tracking_no ? `(#${s.courier_tracking_no})` : ''}
                            </Typography>
                          )}
                          {s.dispatched_at && (
                            <Typography variant="caption" color="text.secondary">
                              Sent: {formatAdDateTime(s.dispatched_at)}
                            </Typography>
                          )}
                        </TableCell>

                        {/* 5. Status */}
                        <TableCell sx={{ py: 1 }}>
                          {renderStatusChip(s.status)}
                        </TableCell>

                        {/* 6. Days Out */}
                        <TableCell align="center" sx={{ py: 1 }}>
                          <Typography variant="body2" fontWeight={600} color="text.secondary">
                            {calculateDaysOut(s.received_at, s.completed_at)}
                          </Typography>
                        </TableCell>

                        {/* 7. Actions */}
                        <TableCell align="center" sx={{ py: 1 }}>
                          <Box sx={{ display: 'flex', gap: 0.5, justifyContent: 'center', flexWrap: 'wrap' }}>
                            {/* View Timeline */}
                            <Button
                              size="small"
                              variant="outlined"
                              onClick={() => handleOpenTimeline(s)}
                              sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none' }}
                            >
                              Timeline
                            </Button>

                            {/* State Specific Actions */}
                            {(s.status === 'ReceivedAtBimal' || s.status === 'PreparedForDispatch') && (
                              <Button
                                size="small"
                                variant="contained"
                                color="primary"
                                startIcon={<LocalShippingIcon fontSize="small" />}
                                onClick={() => {
                                  setSelectedSample(s);
                                  setReferenceLabId(s.reference_laboratory_id || '');
                                  setDispatchModalOpen(true);
                                }}
                                sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none', fontWeight: 700 }}
                              >
                                Dispatch
                              </Button>
                            )}

                            {(s.status === 'DispatchedToReferenceLab' || s.status === 'ProcessingAtReferenceLab' || s.status === 'ReceivedByReferenceLab') && (
                              <Button
                                size="small"
                                variant="contained"
                                color="success"
                                startIcon={<ReceiptLongIcon fontSize="small" />}
                                onClick={() => {
                                  setSelectedSample(s);
                                  setResultModalOpen(true);
                                }}
                                sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none', fontWeight: 700 }}
                              >
                                Result Received
                              </Button>
                            )}

                            {s.order_item_id && (s.status === 'DispatchedToReferenceLab' || s.status === 'ProcessingAtReferenceLab' || s.status === 'ReceivedByReferenceLab') && (
                              <Button size="small" variant="outlined" color="error" onClick={() => handleRejectForRecollection(s)} sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none', fontWeight: 700 }}>
                                Reject & Require Recollection
                              </Button>
                            )}

                            {s.status === 'ResultReceived' && s.order_item?.outsource_state === 'ResultReceived' && !s.material_returned && (
                              <Button size="small" variant="contained" color="success" onClick={() => handleInternalReviewAndVerify(s)} sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none', fontWeight: 700 }}>
                                Internal Review & Verify
                              </Button>
                            )}

                            {s.status === 'ResultReceived' && !s.material_returned && (
                              <Button
                                size="small"
                                variant="contained"
                                color="warning"
                                startIcon={<InventoryIcon fontSize="small" />}
                                onClick={() => {
                                  setSelectedSample(s);
                                  setReturnModalOpen(true);
                                }}
                                sx={{ fontSize: '0.72rem', px: 1, py: 0.2, textTransform: 'none', fontWeight: 700 }}
                              >
                                Return Material
                              </Button>
                            )}

                            {/* Flexible Status Update */}
                            <Button
                              size="small"
                              variant="text"
                              onClick={() => {
                                setSelectedSample(s);
                                setStatusModalOpen(true);
                              }}
                              sx={{ fontSize: '0.72rem', px: 0.5, py: 0.2, textTransform: 'none' }}
                            >
                              Status...
                            </Button>
                          </Box>
                        </TableCell>
                      </TableRow>
                    ))
                  )}
                </TableBody>
              </Table>
            </TableContainer>
          )}
        </CardContent>
      </Card>

      {/* 1. Timeline & Audit History Drawer */}
      <Drawer
        anchor="right"
        open={timelineDrawerOpen}
        onClose={() => setTimelineDrawerOpen(false)}
        PaperProps={{ sx: { width: { xs: '100%', sm: 440 }, p: 3 } }}
      >
        {selectedSample && (
          <Box>
            <Typography variant="h6" fontWeight={800} color="primary.main" gutterBottom>
              Chain of Custody Timeline
            </Typography>
            <Typography variant="body2" fontWeight={700}>
              Tracking No: {selectedSample.tracking_number}
            </Typography>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
              Patient: {selectedSample.patient?.full_name} ({selectedSample.patient?.uhid}) &bull; Service: {selectedSample.service_description}
            </Typography>

            <Divider sx={{ my: 1.5 }} />

            <Typography variant="subtitle2" fontWeight={700} sx={{ mb: 1 }}>
              Audit History Events:
            </Typography>

            {loadingEvents ? (
              <Box sx={{ display: 'flex', justifyContent: 'center', p: 3 }}>
                <CircularProgress size={24} />
              </Box>
            ) : sampleEvents.length === 0 ? (
              <Typography variant="body2" color="text.secondary">
                No events recorded.
              </Typography>
            ) : (
              <List sx={{ p: 0 }}>
                {sampleEvents.map((ev, idx) => (
                  <ListItem key={ev.id || idx} sx={{ px: 0, py: 1, alignItems: 'flex-start', borderBottom: '1px solid #f1f5f9' }}>
                    <ListItemText
                      primary={
                        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                          <Typography variant="body2" fontWeight={700}>
                            {ev.to_status}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {formatAdDateTime(ev.created_at)}
                          </Typography>
                        </Box>
                      }
                      secondary={
                        <Box sx={{ mt: 0.5 }}>
                          <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
                            By: <strong>{ev.performed_by_name || 'Staff'}</strong>
                          </Typography>
                          {ev.notes && (
                            <Typography variant="caption" color="text.primary" sx={{ fontStyle: 'italic', display: 'block', mt: 0.25 }}>
                              &ldquo;{ev.notes}&rdquo;
                            </Typography>
                          )}
                        </Box>
                      }
                    />
                  </ListItem>
                ))}
              </List>
            )}

            <Button fullWidth variant="outlined" onClick={() => setTimelineDrawerOpen(false)} sx={{ mt: 3 }}>
              Close Timeline
            </Button>
          </Box>
        )}
      </Drawer>

      {/* 2. Dispatch Dialog */}
      <Dialog open={dispatchModalOpen} onClose={() => setDispatchModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>Dispatch Sample to Reference Lab</DialogTitle>
        <DialogContent dividers>
          {selectedSample && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <Typography variant="body2">
                Specimen: <strong>{selectedSample.service_description}</strong> ({selectedSample.quantity_received})
              </Typography>

              <TextField
                fullWidth
                size="small"
                label="Reference Laboratory *"
                select={Boolean(selectedSample.order_item_id)}
                value={selectedSample.order_item_id ? referenceLabId : refLabName}
                onChange={(e) => selectedSample.order_item_id ? setReferenceLabId(e.target.value) : setRefLabName(e.target.value)}
              >
                {selectedSample.order_item_id && referenceLabs.map((lab)=><MenuItem key={lab.id} value={lab.id}>{lab.name}</MenuItem>)}
              </TextField>

              <TextField
                fullWidth
                size="small"
                label="Courier / Hand-Carry Person *"
                value={courierName}
                onChange={(e) => setCourierName(e.target.value)}
              />

              <TextField
                fullWidth
                size="small"
                label="Courier Tracking / Receipt No."
                placeholder="e.g. AWB-9823412"
                value={courierTrackingNo}
                onChange={(e) => setCourierTrackingNo(e.target.value)}
              />

              <TextField
                fullWidth
                size="small"
                label="Items / Blocks Sent Count"
                value={itemsSentCount}
                onChange={(e) => setItemsSentCount(e.target.value)}
              />

              <TextField
                fullWidth
                multiline
                rows={2}
                size="small"
                label="Dispatch Notes / Instructions"
                value={dispatchNotes}
                onChange={(e) => setDispatchNotes(e.target.value)}
              />
            </Box>
          )}
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setDispatchModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="primary"
            disabled={isSubmittingDispatch}
            onClick={handleConfirmDispatch}
          >
            {isSubmittingDispatch ? 'Dispatching...' : 'Confirm Dispatch'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* 3. Result Receipt Dialog */}
      <Dialog open={resultModalOpen} onClose={() => setResultModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>Record External Result Receipt</DialogTitle>
        <DialogContent dividers>
          {selectedSample && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <Typography variant="body2">
                Sample: <strong>{selectedSample.tracking_number}</strong> &bull; {selectedSample.service_description}
              </Typography>

              <TextField
                fullWidth
                size="small"
                label="Reference Lab Report Number *"
                placeholder="e.g. REF-2026-8942"
                value={refReportNo}
                onChange={(e) => setRefReportNo(e.target.value)}
              />

              <TextField
                fullWidth
                type="date"
                size="small"
                label="External Report Date"
                value={externalReportDate}
                onChange={(e) => setExternalReportDate(e.target.value)}
                InputLabelProps={{ shrink: true }}
              />

              <TextField
                fullWidth
                multiline
                rows={2}
                size="small"
                label="Result Notes / Diagnostic Findings Summary"
                value={resultNotes}
                onChange={(e) => setResultNotes(e.target.value)}
              />
            </Box>
          )}
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setResultModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="success"
            disabled={isSubmittingResult}
            onClick={handleConfirmResultReceived}
          >
            {isSubmittingResult ? 'Saving...' : 'Record Result Received'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* 4. Material Return Dialog */}
      <Dialog open={returnModalOpen} onClose={() => setReturnModalOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>Record Histopathology Material Return</DialogTitle>
        <DialogContent dividers>
          {selectedSample && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <Typography variant="body2">
                Tracking: <strong>{selectedSample.tracking_number}</strong> &bull; Original Sent: {selectedSample.quantity_received}
              </Typography>

              <Grid container spacing={2}>
                <Grid item xs={6}>
                  <TextField
                    fullWidth
                    type="number"
                    size="small"
                    label="Blocks Returned Count"
                    inputProps={{ min: 0 }}
                    value={blocksReturned}
                    onChange={(e) => setBlocksReturned(e.target.value ? Number(e.target.value) : '')}
                  />
                </Grid>
                <Grid item xs={6}>
                  <TextField
                    fullWidth
                    type="number"
                    size="small"
                    label="Slides Returned Count"
                    inputProps={{ min: 0 }}
                    value={slidesReturned}
                    onChange={(e) => setSlidesReturned(e.target.value ? Number(e.target.value) : '')}
                  />
                </Grid>
              </Grid>

              <TextField
                fullWidth
                multiline
                rows={2}
                size="small"
                label="Return Custody Notes / Storage Location"
                placeholder="e.g. Returned to archive block file Cabinet A-12"
                value={returnNotes}
                onChange={(e) => setReturnNotes(e.target.value)}
              />
            </Box>
          )}
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setReturnModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="warning"
            disabled={isSubmittingReturn}
            onClick={handleConfirmMaterialReturn}
          >
            {isSubmittingReturn ? 'Saving...' : 'Confirm Material Returned'}
          </Button>
        </DialogActions>
      </Dialog>

      {/* 5. Generic Status Update Dialog */}
      <Dialog open={statusModalOpen} onClose={() => setStatusModalOpen(false)} maxWidth="xs" fullWidth>
        <DialogTitle sx={{ fontWeight: 800 }}>Update Outsource Sample Status</DialogTitle>
        <DialogContent dividers>
          {selectedSample && (
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
              <TextField
                select
                fullWidth
                size="small"
                label="New Status *"
                value={targetStatus}
                onChange={(e) => setTargetStatus(e.target.value as OutsourceSampleStatus)}
              >
                <MenuItem value="ReceivedAtBimal">Received at Bimal</MenuItem>
                <MenuItem value="PreparedForDispatch">Prepared for Dispatch</MenuItem>
                <MenuItem value="DispatchedToReferenceLab">Dispatched to Reference Lab</MenuItem>
                <MenuItem value="ReceivedByReferenceLab">Received by Reference Lab</MenuItem>
                <MenuItem value="ProcessingAtReferenceLab">Processing at Reference Lab</MenuItem>
                <MenuItem value="ResultReceived">Result Received</MenuItem>
                <MenuItem value="MaterialReturned">Material Returned</MenuItem>
                <MenuItem value="Completed">Completed</MenuItem>
                <MenuItem value="Rejected">Rejected</MenuItem>
                <MenuItem value="Cancelled">Cancelled</MenuItem>
                <MenuItem value="LostInTransit">Lost in Transit</MenuItem>
              </TextField>

              <TextField
                fullWidth
                multiline
                rows={2}
                size="small"
                label="Transition Notes *"
                value={statusNotes}
                onChange={(e) => setStatusNotes(e.target.value)}
              />
            </Box>
          )}
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setStatusModalOpen(false)}>Cancel</Button>
          <Button
            variant="contained"
            color="primary"
            disabled={isSubmittingStatus}
            onClick={handleConfirmGenericStatus}
          >
            {isSubmittingStatus ? 'Updating...' : 'Update Status'}
          </Button>
        </DialogActions>
      </Dialog>

      <Snackbar
        open={Boolean(operationError)}
        autoHideDuration={7000}
        onClose={() => setOperationError(null)}
        anchorOrigin={{ vertical: 'bottom', horizontal: 'center' }}
      >
        <Alert severity="error" variant="filled" onClose={() => setOperationError(null)}>
          {operationError}
        </Alert>
      </Snackbar>

      <Snackbar
        open={Boolean(toastMsg)}
        autoHideDuration={4000}
        onClose={() => setToastMsg(null)}
        message={toastMsg}
      />
    </Box>
  );
};
