/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Reagent-Specific PT/INR Configuration Master Section
 * Admin-governed MNPT and ISI reagent parameters, lot tracking, and audit history.
 */

import React, { useState, useEffect, useCallback } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  Button,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField,
  Grid,
  Alert,
  Chip,
  Stack,
  CircularProgress,
} from '@mui/material';
import ScienceIcon from '@mui/icons-material/Science';
import AddIcon from '@mui/icons-material/Add';
import HistoryIcon from '@mui/icons-material/History';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import WarningAmberIcon from '@mui/icons-material/WarningAmber';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { formatAdDate, formatAdDateTime } from '@/lib/dateTime';

export interface PtInrReagentConfig {
  id: string;
  reagent_name: string;
  manufacturer?: string | null;
  lot_number?: string | null;
  expiry_date?: string | null;
  isi: number;
  mnpt: number;
  effective_from: string;
  effective_to?: string | null;
  is_active: boolean;
  notes?: string | null;
  created_at: string;
  updated_at: string;
}

interface PtInrReagentConfigSectionProps {
  isAdmin: boolean;
}

export const PtInrReagentConfigSection: React.FC<PtInrReagentConfigSectionProps> = ({ isAdmin }) => {
  const [activeConfig, setActiveConfig] = useState<PtInrReagentConfig | null>(null);
  const [history, setHistory] = useState<PtInrReagentConfig[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');

  // Dialog state
  const [dialogOpen, setDialogOpen] = useState(false);
  const [reagentName, setReagentName] = useState('');
  const [manufacturer, setManufacturer] = useState('');
  const [lotNumber, setLotNumber] = useState('');
  const [expiryDate, setExpiryDate] = useState('');
  const [isi, setIsi] = useState('');
  const [mnpt, setMnpt] = useState('');
  const [notes, setNotes] = useState('');
  const [saving, setSaving] = useState(false);

  const loadConfigs = useCallback(async () => {
    setLoading(true);
    setError('');
    try {
      // 1. Fetch active config via RPC
      const { data: activeData, error: activeErr } = await (supabase.rpc as any)('get_active_pt_inr_config');
      if (activeErr) throw activeErr;
      setActiveConfig(activeData || null);

      // 2. Fetch full history
      const { data: allData, error: allErr } = await supabase
        .from('pt_inr_reagent_configs' as any)
        .select('*')
        .order('effective_from', { ascending: false });

      if (allErr) throw allErr;
      setHistory((allData || []) as PtInrReagentConfig[]);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load PT/INR reagent configurations.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadConfigs();
  }, [loadConfigs]);

  const handleOpenNewConfig = () => {
    if (activeConfig) {
      setReagentName(activeConfig.reagent_name || '');
      setManufacturer(activeConfig.manufacturer || '');
      setLotNumber('');
      setExpiryDate('');
      setIsi(String(activeConfig.isi || ''));
      setMnpt(String(activeConfig.mnpt || ''));
      setNotes('');
    } else {
      setReagentName('Commercial PT Reagent');
      setManufacturer('');
      setLotNumber('');
      setExpiryDate('');
      setIsi('');
      setMnpt('');
      setNotes('');
    }
    setError('');
    setSuccess('');
    setDialogOpen(true);
  };

  const handleSaveConfig = async () => {
    if (!reagentName.trim()) {
      setError('Reagent name is required.');
      return;
    }
    const numIsi = parseFloat(isi);
    if (isNaN(numIsi) || numIsi <= 0) {
      setError('International Sensitivity Index (ISI) must be a positive number greater than 0.');
      return;
    }
    const numMnpt = parseFloat(mnpt);
    if (isNaN(numMnpt) || numMnpt <= 0) {
      setError('Mean Normal Prothrombin Time (MNPT) must be a positive number in seconds greater than 0.');
      return;
    }

    setSaving(true);
    setError('');
    try {
      const { error: saveErr } = await (supabase.rpc as any)('save_pt_inr_reagent_config', {
        p_reagent_name: reagentName.trim(),
        p_isi: numIsi,
        p_mnpt: numMnpt,
        p_manufacturer: manufacturer.trim() || null,
        p_lot_number: lotNumber.trim() || null,
        p_expiry_date: expiryDate.trim() || null,
        p_notes: notes.trim() || null,
      });

      if (saveErr) throw saveErr;

      setSuccess(`Active PT/INR reagent configuration updated (MNPT: ${numMnpt}s, ISI: ${numIsi}). Previous records preserved.`);
      setDialogOpen(false);
      await loadConfigs();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save PT/INR reagent configuration.'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Card elevation={0} sx={{ border: '1px solid', borderColor: 'divider', borderRadius: 2 }}>
      <CardContent sx={{ p: 3 }}>
        <Stack direction="row" alignItems="center" justifyContent="space-between" sx={{ mb: 2 }}>
          <Box>
            <Stack direction="row" alignItems="center" spacing={1.5}>
              <ScienceIcon color="primary" />
              <Typography variant="h6" fontWeight={800}>
                PT / INR Reagent Configuration
              </Typography>
              {isAdmin ? (
                <Chip label="Admin Governed" size="small" color="primary" variant="outlined" />
              ) : (
                <Chip label="Operational View (Read-Only)" size="small" variant="outlined" />
              )}
            </Stack>
            <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
              Controls the Mean Normal Prothrombin Time (MNPT) and International Sensitivity Index (ISI) used by the automated INR calculation engine: <code>INR = (Patient PT / MNPT) ^ ISI</code>.
            </Typography>
          </Box>
          {isAdmin && (
            <Button
              variant="contained"
              startIcon={<AddIcon />}
              onClick={handleOpenNewConfig}
              sx={{ fontWeight: 700 }}
            >
              Update Reagent Parameters
            </Button>
          )}
        </Stack>

        {error && (
          <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>
            {error}
          </Alert>
        )}
        {success && (
          <Alert severity="success" sx={{ mb: 2 }} onClose={() => setSuccess('')}>
            {success}
          </Alert>
        )}

        {loading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', p: 4 }}>
            <CircularProgress />
          </Box>
        ) : (
          <Stack spacing={3}>
            {/* Active Configuration Card */}
            <Paper
              variant="outlined"
              sx={{
                p: 2.5,
                borderRadius: 2,
                bgcolor: activeConfig ? 'success.50' : 'warning.50',
                borderColor: activeConfig ? 'success.300' : 'warning.300',
              }}
            >
              {activeConfig ? (
                <Grid container spacing={2} alignItems="center">
                  <Grid item xs={12} md={4}>
                    <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 0.5 }}>
                      <CheckCircleIcon color="success" fontSize="small" />
                      <Typography variant="subtitle2" fontWeight={800} color="success.dark">
                        CURRENT ACTIVE REAGENT
                      </Typography>
                    </Stack>
                    <Typography variant="h6" fontWeight={800}>
                      {activeConfig.reagent_name}
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      {activeConfig.manufacturer ? `Manufacturer: ${activeConfig.manufacturer}` : 'Manufacturer: Unspecified'}
                      {activeConfig.lot_number ? ` · Lot: ${activeConfig.lot_number}` : ''}
                    </Typography>
                    {activeConfig.expiry_date && (
                      <Typography variant="caption" color="text.secondary" display="block">
                        Expiry: {formatAdDate(activeConfig.expiry_date)}
                      </Typography>
                    )}
                  </Grid>

                  <Grid item xs={6} md={2}>
                    <Typography variant="caption" color="text.secondary" fontWeight={700}>
                      MNPT (Mean Normal PT)
                    </Typography>
                    <Typography variant="h5" fontWeight={800} color="primary.main">
                      {activeConfig.mnpt} <Typography component="span" variant="body2">sec</Typography>
                    </Typography>
                  </Grid>

                  <Grid item xs={6} md={2}>
                    <Typography variant="caption" color="text.secondary" fontWeight={700}>
                      ISI (Sensitivity Index)
                    </Typography>
                    <Typography variant="h5" fontWeight={800} color="primary.main">
                      {activeConfig.isi}
                    </Typography>
                  </Grid>

                  <Grid item xs={12} md={4}>
                    <Typography variant="caption" color="text.secondary" fontWeight={700}>
                      Effective From
                    </Typography>
                    <Typography variant="body2" fontWeight={600}>
                      {formatAdDateTime(activeConfig.effective_from)}
                    </Typography>
                    {activeConfig.notes && (
                      <Typography variant="caption" color="text.secondary" sx={{ fontStyle: 'italic', display: 'block', mt: 0.5 }}>
                        Note: {activeConfig.notes}
                      </Typography>
                    )}
                  </Grid>
                </Grid>
              ) : (
                <Stack direction="row" spacing={1.5} alignItems="center">
                  <WarningAmberIcon color="warning" />
                  <Box>
                    <Typography variant="subtitle1" fontWeight={700} color="warning.dark">
                      No Active PT/INR Reagent Configured
                    </Typography>
                    <Typography variant="body2" color="text.secondary">
                      Automated INR calculation is currently disabled in result entry. Administrator must configure MNPT and ISI before automated ratio calculation can occur.
                    </Typography>
                  </Box>
                </Stack>
              )}
            </Paper>

            {/* Reagent History Table */}
            <Box>
              <Stack direction="row" alignItems="center" spacing={1} sx={{ mb: 1.5 }}>
                <HistoryIcon fontSize="small" color="action" />
                <Typography variant="subtitle1" fontWeight={700}>
                  Reagent Configuration History & QC Traceability
                </Typography>
              </Stack>
              <TableContainer component={Paper} variant="outlined" sx={{ borderRadius: 1.5 }}>
                <Table size="small">
                  <TableHead sx={{ bgcolor: 'grey.50' }}>
                    <TableRow>
                      <TableCell sx={{ fontWeight: 700 }}>Status</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Reagent / Lot</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>MNPT (sec)</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>ISI</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Effective Period</TableCell>
                      <TableCell sx={{ fontWeight: 700 }}>Notes</TableCell>
                    </TableRow>
                  </TableHead>
                  <TableBody>
                    {history.length === 0 ? (
                      <TableRow>
                        <TableCell colSpan={6} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                          No historical reagent records found.
                        </TableCell>
                      </TableRow>
                    ) : (
                      history.map((cfg) => (
                        <TableRow key={cfg.id} hover>
                          <TableCell>
                            {cfg.is_active ? (
                              <Chip label="Active" color="success" size="small" />
                            ) : (
                              <Chip label="Archived" size="small" variant="outlined" />
                            )}
                          </TableCell>
                          <TableCell>
                            <Typography variant="body2" fontWeight={600}>
                              {cfg.reagent_name}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              {cfg.manufacturer || 'Unspecified'} {cfg.lot_number ? `· Lot ${cfg.lot_number}` : ''}
                            </Typography>
                          </TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>{cfg.mnpt} s</TableCell>
                          <TableCell sx={{ fontWeight: 700 }}>{cfg.isi}</TableCell>
                          <TableCell>
                            <Typography variant="caption" display="block">
                              From: {formatAdDate(cfg.effective_from)}
                            </Typography>
                            <Typography variant="caption" color="text.secondary">
                              To: {cfg.effective_to ? formatAdDate(cfg.effective_to) : 'Present'}
                            </Typography>
                          </TableCell>
                          <TableCell>
                            <Typography variant="caption" color="text.secondary">
                              {cfg.notes || '—'}
                            </Typography>
                          </TableCell>
                        </TableRow>
                      ))
                    )}
                  </TableBody>
                </Table>
              </TableContainer>
            </Box>
          </Stack>
        )}
      </CardContent>

      {/* Admin Update Configuration Modal */}
      <Dialog
        open={dialogOpen}
        onClose={() => !saving && setDialogOpen(false)}
        maxWidth="sm"
        fullWidth
      >
        <DialogTitle sx={{ fontWeight: 800 }}>
          Update PT / INR Reagent Configuration
        </DialogTitle>
        <DialogContent dividers>
          <Alert severity="info" sx={{ mb: 2.5 }}>
            Updating MNPT or ISI creates a new active version and archives previous records. Historical patient reports and validated results remain immutable.
          </Alert>

          {error && (
            <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError('')}>
              {error}
            </Alert>
          )}

          <Grid container spacing={2}>
            <Grid item xs={12}>
              <TextField
                fullWidth
                required
                size="small"
                label="Commercial Reagent Name"
                value={reagentName}
                onChange={(e) => setReagentName(e.target.value)}
                placeholder="e.g. Coral Thromboplastin-LI"
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Manufacturer (Optional)"
                value={manufacturer}
                onChange={(e) => setManufacturer(e.target.value)}
                placeholder="e.g. Tulip Diagnostics"
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Lot Number (Optional)"
                value={lotNumber}
                onChange={(e) => setLotNumber(e.target.value)}
                placeholder="e.g. LOT-2026-09"
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                type="date"
                label="Expiry Date (Optional)"
                value={expiryDate}
                onChange={(e) => setExpiryDate(e.target.value)}
                InputLabelProps={{ shrink: true }}
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                required
                size="small"
                type="number"
                label="Mean Normal PT (MNPT in sec)"
                value={mnpt}
                onChange={(e) => setMnpt(e.target.value)}
                placeholder="e.g. 12.0"
                helperText="Lab-validated normal baseline (e.g. 12.0)"
              />
            </Grid>

            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                required
                size="small"
                type="number"
                label="Reagent ISI"
                value={isi}
                onChange={(e) => setIsi(e.target.value)}
                placeholder="e.g. 1.10"
                helperText="Package insert sensitivity index (e.g. 1.10)"
              />
            </Grid>

            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Configuration Notes / QC Summary"
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                multiline
                minRows={2}
                placeholder="e.g. Lot validated with 20 normal donor plasmas on 37°C water bath tilt tube method."
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions sx={{ p: 2 }}>
          <Button onClick={() => setDialogOpen(false)} disabled={saving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            onClick={handleSaveConfig}
            disabled={saving}
            sx={{ fontWeight: 700 }}
          >
            {saving ? 'Saving...' : 'Commit Reagent Parameters'}
          </Button>
        </DialogActions>
      </Dialog>
    </Card>
  );
};
