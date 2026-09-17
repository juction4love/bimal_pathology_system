/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Bulk Reference Range Editor Component
 * Configure, validate, and approve all biological reference intervals for a test profile.
 */

import React, { useState, useEffect } from 'react';
import {
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Button,
  Box,
  Typography,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  TextField,
  MenuItem,
  IconButton,
  Chip,
  Alert,
  CircularProgress,
  Switch,
} from '@mui/material';
import AddCircleOutlineIcon from '@mui/icons-material/AddCircleOutline';
import DeleteOutlineIcon from '@mui/icons-material/DeleteOutline';

import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { useAuth } from '@/hooks/useAuth';
import {
  DbReferenceRange,
  validateReferenceRange,
} from '@/lib/clinicalReferenceRange';
import { getNepalTodayAd } from '@/lib/dateTime';

interface BulkReferenceRangeEditorProps {
  open: boolean;
  onClose: () => void;
  test: {
    id: string;
    code: string;
    name: string;
    department: string;
  } | null;
  onSaved?: () => void;
}

interface EditableRange extends DbReferenceRange {
  tempId?: string;
  isNew?: boolean;
  isDirty?: boolean;
  validationError?: string | null;
  validation_state?: 'Unclassified' | 'LegacyDefaultRequiresValidation' | 'ClinicallyValidated';
  validation_source?: string | null;
}

export const BulkReferenceRangeEditor: React.FC<BulkReferenceRangeEditorProps> = ({
  open,
  onClose,
  test,
  onSaved,
}) => {
  const { profile } = useAuth();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [parameters, setParameters] = useState<any[]>([]);
  const [rangesByParam, setRangesByParam] = useState<Record<string, EditableRange[]>>({});

  // Load parameters and existing reference ranges for the test
  useEffect(() => {
    if (!open || !test) return;

    const loadData = async () => {
      setLoading(true);
      setError(null);
      setSuccess(null);

      try {
        // 1. Fetch active parameters for the test
        const { data: params, error: pErr } = await supabase
          .from('parameters')
          .select('id, code, name, value_type, unit, display_order')
          .eq('test_id', test.id)
          .eq('is_active', true)
          .order('display_order', { ascending: true });

        if (pErr) throw pErr;
        setParameters(params || []);

        const paramIds = (params || []).map((p) => p.id);
        const map: Record<string, EditableRange[]> = {};
        paramIds.forEach((pid) => {
          map[pid] = [];
        });

        if (paramIds.length > 0) {
          // 2. Fetch existing reference ranges
          const { data: ranges, error: rErr } = await supabase
            .from('reference_ranges')
            .select('*')
            .in('parameter_id', paramIds)
            .neq('lifecycle_status', 'Archived')
            .order('gender', { ascending: true })
            .order('age_min_days', { ascending: true });

          if (rErr) throw rErr;

          (ranges || []).forEach((r: any) => {
            if (map[r.parameter_id]) {
              map[r.parameter_id].push({
                ...r,
                // Legacy/default rows may still carry historical is_approved=true.
                // They are not clinically validated until an operator explicitly
                // changes the approval switch in this editor.
                is_approved: r.is_approved === true && r.validation_state === 'ClinicallyValidated',
                isDirty: false,
                isNew: false,
              });
            }
          });
        }

        setRangesByParam(map);
      } catch (err: any) {
        setError(safeErrorMessage(err, 'Failed to load reference ranges.'));
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, [open, test]);

  // Add a new empty range row for a parameter
  const handleAddRange = (parameterId: string) => {
    const newRange: EditableRange = {
      tempId: `new_${Date.now()}_${Math.random()}`,
      parameter_id: parameterId,
      gender: 'All',
      age_min_days: 0,
      age_max_days: 43800,
      normal_min: null,
      normal_max: null,
      critical_low: null,
      critical_high: null,
      normal_text: null,
      reference_text: null,
      method: null,
      effective_from: getNepalTodayAd(),
      effective_to: null,
      is_active: true,
      is_approved: false,
      validation_state: 'Unclassified',
      validation_source: null,
      isNew: true,
      isDirty: true,
    };

    setRangesByParam((prev) => ({
      ...prev,
      [parameterId]: [...(prev[parameterId] || []), newRange],
    }));
  };

  // Update a field in a range row
  const handleUpdateField = (
    parameterId: string,
    index: number,
    field: keyof DbReferenceRange,
    value: any
  ) => {
    setRangesByParam((prev) => {
      const list = [...(prev[parameterId] || [])];
      const target: EditableRange = { ...list[index], [field]: value, isDirty: true };

      // A clinical value change invalidates the previous approval. The operator
      // must deliberately toggle clinical validation again after reviewing it.
      if (field !== 'is_approved') {
        target.is_approved = false;
        if (target.validation_state === 'ClinicallyValidated') {
          target.validation_state = 'Unclassified';
          target.validation_source = null;
        }
      }

      // Live validation
      const validation = validateReferenceRange(target);
      target.validationError = validation.isValid ? null : validation.error;

      list[index] = target;
      return { ...prev, [parameterId]: list };
    });
  };

  // Remove a range row
  const handleRemoveRange = (parameterId: string, index: number) => {
    setRangesByParam((prev) => {
      const list = [...(prev[parameterId] || [])];
      list.splice(index, 1);
      return { ...prev, [parameterId]: list };
    });
  };

  // Save all ranges to Supabase
  const handleSaveAll = async () => {
    if (!test) return;
    setSaving(true);
    setError(null);
    setSuccess(null);

    try {
      const unresolvedLegacy = Object.values(rangesByParam)
        .flat()
        .some((range) =>
          range.validation_state === 'LegacyDefaultRequiresValidation' &&
          range.is_approved !== true
        );
      if (unresolvedLegacy) {
        setError('Legacy/default ranges cannot be bulk-saved as validated implicitly. Explicitly validate each legacy row, or use the individual range editor for an unvalidated change.');
        return;
      }

      // Validate all ranges before saving
      let hasValidationError = false;
      const allRangesToSave: any[] = [];
      const currentParamIds = parameters.map((p) => p.id);

      Object.entries(rangesByParam).forEach(([, ranges]) => {
        ranges.forEach((r) => {
          const val = validateReferenceRange(r);
          if (!val.isValid) {
            hasValidationError = true;
            setError(`Validation error: ${val.error}`);
          }

          allRangesToSave.push({
            id: r.id && !r.isNew ? r.id : undefined,
            parameter_id: r.parameter_id,
            gender: r.gender || 'All',
            age_min_days: Number(r.age_min_days) || 0,
            age_max_days: Number(r.age_max_days) || 43800,
            normal_min: r.normal_min !== null && r.normal_min !== undefined && String(r.normal_min) !== '' ? Number(r.normal_min) : null,
            normal_max: r.normal_max !== null && r.normal_max !== undefined && String(r.normal_max) !== '' ? Number(r.normal_max) : null,
            critical_low: r.critical_low !== null && r.critical_low !== undefined && String(r.critical_low) !== '' ? Number(r.critical_low) : null,
            critical_high: r.critical_high !== null && r.critical_high !== undefined && String(r.critical_high) !== '' ? Number(r.critical_high) : null,
            normal_text: r.normal_text?.trim() || null,
            reference_text: r.reference_text?.trim() || null,
            method: r.method?.trim() || null,
            effective_from: r.effective_from || getNepalTodayAd(),
            effective_to: r.effective_to || null,
            is_active: r.is_active !== false,
            is_approved: r.is_approved === true,
            validation_state: r.is_approved === true
              ? 'ClinicallyValidated'
              : r.validation_state === 'LegacyDefaultRequiresValidation'
                ? 'LegacyDefaultRequiresValidation'
                : 'Unclassified',
            validation_source: r.is_approved === true
              ? 'Explicit Lab Technician validation in bulk reference-range editor'
              : r.validation_state === 'LegacyDefaultRequiresValidation'
                ? r.validation_source || 'Legacy/default interval; clinical validation required'
                : null,
            approved_by: r.is_approved === true ? profile?.id || null : null,
            approved_at: r.is_approved === true ? new Date().toISOString() : null,
            updated_at: new Date().toISOString(),
          });
        });
      });

      if (hasValidationError) {
        setSaving(false);
        return;
      }

      const insertPayload = allRangesToSave.map(({ id: _id, ...rest }) => rest);
      const { error: replaceErr } = await supabase.rpc('catalogue_replace_ranges', { p_parameter_ids: currentParamIds, p_ranges: insertPayload });
      if (replaceErr) throw replaceErr;

      const approvedCount = allRangesToSave.filter((range) => range.is_approved === true).length;
      setSuccess(`Saved ${allRangesToSave.length} reference ranges for ${test.name}; ${approvedCount} explicitly clinically validated.`);
      if (onSaved) onSaved();
      setTimeout(() => {
        onClose();
      }, 1200);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to save reference ranges.'));
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onClose={onClose} maxWidth="xl" fullWidth>
      <DialogTitle sx={{ pb: 1 }}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <Box>
            <Typography variant="h6" fontWeight={800} color="primary.main">
              Biological Reference Range Editor: {test?.name} ({test?.code})
            </Typography>
            <Typography variant="caption" color="text.secondary">
              Department: {test?.department} | Configure age, sex, panic alerts, and clinical reference intervals.
            </Typography>
          </Box>
        </Box>
      </DialogTitle>

      <DialogContent dividers sx={{ p: 2 }}>
        {error && (
          <Alert severity="error" sx={{ mb: 2 }} onClose={() => setError(null)}>
            {error}
          </Alert>
        )}
        {success && (
          <Alert severity="success" sx={{ mb: 2 }} onClose={() => setSuccess(null)}>
            {success}
          </Alert>
        )}
        <Alert severity="warning" sx={{ mb: 2 }}>
          Clinical validation is fail-closed. Legacy/default intervals and newly added rows remain unvalidated unless each row is explicitly marked clinically validated.
        </Alert>

        {loading ? (
          <Box sx={{ display: 'flex', justifyContent: 'center', p: 5 }}>
            <CircularProgress />
          </Box>
        ) : parameters.length === 0 ? (
          <Alert severity="warning">
            No active parameters found for this investigation. Please add parameters first under Test Catalogue.
          </Alert>
        ) : (
          <Box sx={{ display: 'flex', flexDirection: 'column', gap: 3 }}>
            {parameters.map((param) => {
              const isHeading = param.value_type === 'Heading';
              if (isHeading) {
                return (
                  <Box key={param.id} sx={{ p: 1.5, bgcolor: '#f1f5f9', borderRadius: 1 }}>
                    <Typography variant="subtitle2" fontWeight={800} color="primary.main">
                      {param.name} (Section Header)
                    </Typography>
                  </Box>
                );
              }

              const ranges = rangesByParam[param.id] || [];
              const isConfigured = ranges.some((r) =>
                r.is_active && r.is_approved === true && r.validation_state === 'ClinicallyValidated'
              );

              return (
                <Paper
                  key={param.id}
                  variant="outlined"
                  sx={{
                    p: 2,
                    borderColor: isConfigured ? '#cbd5e1' : '#f59e0b',
                    bgcolor: isConfigured ? '#ffffff' : '#fffbeb',
                  }}
                >
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 1.5 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
                      <Typography variant="subtitle1" fontWeight={700}>
                        {param.name}
                      </Typography>
                      <Chip label={param.code} size="small" variant="outlined" />
                      <Chip label={`Type: ${param.value_type}`} size="small" />
                      {param.unit && <Chip label={`Unit: ${param.unit}`} size="small" color="info" variant="outlined" />}
                      <Chip
                        label={isConfigured ? 'Configured' : ranges.length > 0 ? 'Needs Review' : 'Not Configured'}
                        size="small"
                        color={isConfigured ? 'success' : ranges.length > 0 ? 'warning' : 'default'}
                      />
                    </Box>

                    <Button
                      size="small"
                      variant="outlined"
                      startIcon={<AddCircleOutlineIcon />}
                      onClick={() => handleAddRange(param.id)}
                    >
                      Add Interval
                    </Button>
                  </Box>

                  {ranges.length === 0 ? (
                    <Typography variant="body2" color="text.secondary" sx={{ fontStyle: 'italic', py: 1 }}>
                      No reference intervals configured. Will display "Not configured" in Result Entry and PDF reports.
                    </Typography>
                  ) : (
                    <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
                      <Table size="small">
                        <TableHead sx={{ bgcolor: '#f8fafc' }}>
                          <TableRow>
                            <TableCell width={100} sx={{ fontWeight: 700 }}>Sex</TableCell>
                            <TableCell width={140} sx={{ fontWeight: 700 }}>Age Range (Days)</TableCell>
                            <TableCell width={100} sx={{ fontWeight: 700 }}>Normal Min</TableCell>
                            <TableCell width={100} sx={{ fontWeight: 700 }}>Normal Max</TableCell>
                            <TableCell width={110} sx={{ fontWeight: 700 }}>Critical Low</TableCell>
                            <TableCell width={110} sx={{ fontWeight: 700 }}>Critical High</TableCell>
                            <TableCell width={160} sx={{ fontWeight: 700 }}>Reference Text / Note</TableCell>
                            <TableCell width={130} sx={{ fontWeight: 700 }}>Qualitative Val</TableCell>
                            <TableCell width={110} align="center" sx={{ fontWeight: 700 }}>Clinically Validated</TableCell>
                            <TableCell width={50} align="center" sx={{ fontWeight: 700 }}>Del</TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {ranges.map((r, rIdx) => (
                            <TableRow
                              key={r.id || r.tempId || rIdx}
                              sx={{ bgcolor: r.validationError ? '#fef2f2' : 'inherit' }}
                            >
                                <TableCell>
                                  <TextField
                                    select
                                    size="small"
                                    fullWidth
                                    value={r.gender || 'All'}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'gender', e.target.value)}
                                  >
                                    <MenuItem value="All">All</MenuItem>
                                    <MenuItem value="Male">Male</MenuItem>
                                    <MenuItem value="Female">Female</MenuItem>
                                  </TextField>
                                </TableCell>
                                <TableCell>
                                  <Box sx={{ display: 'flex', gap: 0.5, alignItems: 'center' }}>
                                    <TextField
                                      size="small"
                                      type="number"
                                      value={r.age_min_days}
                                      onChange={(e) => handleUpdateField(param.id, rIdx, 'age_min_days', Number(e.target.value))}
                                      placeholder="0"
                                      sx={{ width: 65 }}
                                    />
                                    <Typography variant="caption">-</Typography>
                                    <TextField
                                      size="small"
                                      type="number"
                                      value={r.age_max_days}
                                      onChange={(e) => handleUpdateField(param.id, rIdx, 'age_max_days', Number(e.target.value))}
                                      placeholder="43800"
                                      sx={{ width: 65 }}
                                    />
                                  </Box>
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={r.normal_min ?? ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'normal_min', e.target.value === '' ? null : e.target.value)}
                                    placeholder="Min"
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={r.normal_max ?? ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'normal_max', e.target.value === '' ? null : e.target.value)}
                                    placeholder="Max"
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={r.critical_low ?? ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'critical_low', e.target.value === '' ? null : e.target.value)}
                                    placeholder="≤ Panic"
                                    sx={{ input: { color: '#dc2626', fontWeight: 700 } }}
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    type="number"
                                    value={r.critical_high ?? ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'critical_high', e.target.value === '' ? null : e.target.value)}
                                    placeholder="≥ Panic"
                                    sx={{ input: { color: '#dc2626', fontWeight: 700 } }}
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    value={r.reference_text || ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'reference_text', e.target.value)}
                                    placeholder="e.g. Desirable: < 200"
                                  />
                                </TableCell>
                                <TableCell>
                                  <TextField
                                    size="small"
                                    value={r.normal_text || ''}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'normal_text', e.target.value)}
                                    placeholder="e.g. Negative"
                                  />
                                </TableCell>
                                <TableCell align="center">
                                  <Switch
                                    size="small"
                                    checked={r.is_approved === true}
                                    onChange={(e) => handleUpdateField(param.id, rIdx, 'is_approved', e.target.checked)}
                                    color="success"
                                  />
                                </TableCell>
                                <TableCell align="center">
                                  <IconButton
                                    size="small"
                                    color="error"
                                    onClick={() => handleRemoveRange(param.id, rIdx)}
                                  >
                                    <DeleteOutlineIcon fontSize="small" />
                                  </IconButton>
                                </TableCell>
                              </TableRow>
                            ))}
                        </TableBody>
                      </Table>
                    </TableContainer>
                  )}
                </Paper>
              );
            })}
          </Box>
        )}
      </DialogContent>

      <DialogActions sx={{ p: 2, display: 'flex', justifyContent: 'space-between' }}>
        <Typography variant="caption" color="text.secondary">
          Note: Unapproved or invalid reference ranges are excluded from production Result Entry and reports.
        </Typography>
        <Box sx={{ display: 'flex', gap: 1 }}>
          <Button onClick={onClose} disabled={saving}>
            Cancel
          </Button>
          <Button
            variant="contained"
            color="primary"
            disabled={saving || loading}
            onClick={handleSaveAll}
          >
            {saving ? 'Saving...' : 'Save All Ranges'}
          </Button>
        </Box>
      </DialogActions>
    </Dialog>
  );
};
