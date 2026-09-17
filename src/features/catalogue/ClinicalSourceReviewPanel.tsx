import React, { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Alert, Box, Button, Card, CardContent, Checkbox, Chip, Dialog, DialogActions,
  DialogContent, DialogTitle, FormControlLabel, MenuItem, Table, TableBody,
  TableCell, TableContainer, TableHead, TableRow, TextField, Typography,
} from '@mui/material';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';

type ReviewRow = {
  source_version: string;
  source_item_id: string;
  canonical_parameter: string;
  supplied_value: string;
  supplied_unit: string | null;
  supplied_context: string;
  source_note: string | null;
  source_classification: string;
  conflict_key: string | null;
  normalized_representation: Record<string, unknown> | null;
  review_state: string;
  row_version: number;
  decision_id: string | null;
  decision_version: number | null;
  selected_action: string | null;
  selected_policy: Record<string, unknown> | null;
  reason: string | null;
  decision_status: string | null;
  decision_row_version: number | null;
  reviewer_id: string | null;
  materialized_range_id: string | null;
  current_lis_policies: Array<Record<string, unknown>>;
};

const actions = ['AcceptSource', 'RetainOlderPolicy', 'CorrectLaboratoryPolicy', 'RestrictApplicability', 'RejectSource'];

export const ClinicalSourceReviewPanel: React.FC = () => {
  const [rows, setRows] = useState<ReviewRow[]>([]);
  const [selected, setSelected] = useState<ReviewRow | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [form, setForm] = useState({
    action: 'AcceptSource', reason: '', gender: 'All', age_min_days: '', age_max_days: '',
    normal_min: '', normal_max: '', unit: '', applicability_basis: '',
    method_or_analyzer_context: '', critical_limits_reviewed: false,
  });

  const load = useCallback(async () => {
    const { data, error: queryError } = await supabase
      .from('clinical_source_review_matrix')
      .select('*')
      .like('source_version', 'CBC-V%')
      .order('conflict_key')
      .order('source_version');
    if (queryError) throw queryError;
    setRows((data || []) as ReviewRow[]);
  }, []);

  useEffect(() => { load().catch((e) => setError(safeErrorMessage(e, 'clinical source review'))); }, [load]);

  const openDecision = (row: ReviewRow) => {
    const normalized = row.normalized_representation || {};
    setSelected(row);
    setForm({
      action: 'AcceptSource', reason: '', gender: String(normalized.gender || 'All'),
      age_min_days: '', age_max_days: '', normal_min: normalized.normal_min == null ? '' : String(normalized.normal_min),
      normal_max: normalized.normal_max == null ? '' : String(normalized.normal_max),
      unit: String(normalized.unit || row.supplied_unit || ''), applicability_basis: '',
      method_or_analyzer_context: String(normalized.method || ''), critical_limits_reviewed: false,
    });
  };

  const recordDecision = async () => {
    if (!selected) return;
    setBusy(true); setError(null);
    try {
      const selectedPolicy = form.action === 'RejectSource' ? {} : {
        gender: form.gender,
        age_min_days: form.age_min_days === '' ? null : Number(form.age_min_days),
        age_max_days: form.age_max_days === '' ? null : Number(form.age_max_days),
        normal_min: form.normal_min === '' ? null : Number(form.normal_min),
        normal_max: form.normal_max === '' ? null : Number(form.normal_max),
        unit: form.unit,
        applicability_basis: form.applicability_basis,
        method_or_analyzer_context: form.method_or_analyzer_context,
        method: form.method_or_analyzer_context,
        critical_limits_reviewed: form.critical_limits_reviewed,
      };
      const { error: rpcError } = await supabase.rpc('catalogue_record_clinical_source_decision', {
        p_source_item_id: selected.source_item_id,
        p_action: form.action,
        p_selected_policy: selectedPolicy,
        p_reason: form.reason,
        p_expected_item_version: selected.row_version,
      });
      if (rpcError) throw rpcError;
      setSelected(null); setSuccess('Technical decision recorded as a new immutable version.'); await load();
    } catch (e) { setError(safeErrorMessage(e, 'technical decision')); } finally { setBusy(false); }
  };

  const approve = async (row: ReviewRow) => {
    if (!row.decision_id || row.decision_status !== 'Draft') return;
    setBusy(true); setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('catalogue_approve_clinical_source_decision', {
        p_decision_id: row.decision_id, p_expected_version: row.decision_row_version,
      });
      if (rpcError) throw rpcError;
      setSuccess('Decision clinically approved. It remains unmaterialized and inactive.'); await load();
    } catch (e) { setError(safeErrorMessage(e, 'clinical decision approval')); } finally { setBusy(false); }
  };

  const materialize = async (row: ReviewRow) => {
    if (!row.decision_id || row.decision_status !== 'Approved' || row.materialized_range_id) return;
    setBusy(true); setError(null);
    try {
      const { error: rpcError } = await supabase.rpc('catalogue_materialize_clinical_source_decision', {
        p_decision_id: row.decision_id, p_expected_version: row.decision_row_version,
      });
      if (rpcError) throw rpcError;
      setSuccess('Approved policy materialized as an inactive Draft range. Activate it only through the catalogue lifecycle.'); await load();
    } catch (e) { setError(safeErrorMessage(e, 'clinical policy materialization')); } finally { setBusy(false); }
  };

  const groups = useMemo(() => {
    const map = new Map<string, ReviewRow[]>();
    rows.forEach((row) => {
      const key = row.conflict_key || row.canonical_parameter;
      map.set(key, [...(map.get(key) || []), row]);
    });
    return [...map.entries()];
  }, [rows]);

  return <Card sx={{ mb: 2 }}>
    <CardContent>
      <Typography variant="h6">CBC Clinical Source Review — V1 / V2 / V3 / V4</Typography>
      <Typography variant="body2" color="text.secondary" sx={{ mb: 2 }}>
        Operator authorization admits evidence to governance. Only an explicit technical decision with complete applicability can become ClinicallyValidated; materialization creates an inactive Draft.
      </Typography>
      {error && <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 1 }}>{error}</Alert>}
      {success && <Alert severity="success" onClose={() => setSuccess(null)} sx={{ mb: 1 }}>{success}</Alert>}
      <TableContainer sx={{ maxHeight: 520 }}>
        <Table size="small" stickyHeader>
          <TableHead><TableRow>
            <TableCell>Parameter / conflict</TableCell><TableCell>Source</TableCell><TableCell>Supplied</TableCell>
            <TableCell>Context</TableCell><TableCell>Current LIS</TableCell><TableCell>Decision / reviewer</TableCell><TableCell>Action</TableCell>
          </TableRow></TableHead>
          <TableBody>{groups.flatMap(([key, values]) => values.map((row, index) => <TableRow key={row.source_item_id}>
            <TableCell>{index === 0 && <><strong>{key}</strong><br /></>}{row.canonical_parameter}<br /><Chip size="small" label={row.source_classification} color={row.source_classification.includes('Approximate') || row.source_classification.includes('Changed') ? 'warning' : 'default'} /></TableCell>
            <TableCell>{row.source_version}</TableCell>
            <TableCell>{row.supplied_value} {row.supplied_unit || ''}</TableCell>
            <TableCell>{row.supplied_context}{row.source_note ? ` — ${row.source_note}` : ''}</TableCell>
            <TableCell><code>{JSON.stringify(row.current_lis_policies || [])}</code></TableCell>
            <TableCell>{row.selected_action || 'Pending'} {row.decision_version ? `v${row.decision_version}` : ''}<br />{row.reason || ''}<br />{row.reviewer_id ? `Reviewer ${row.reviewer_id.slice(0, 8)}…` : ''}</TableCell>
            <TableCell><Box sx={{ display: 'flex', flexDirection: 'column', gap: .5 }}>
              <Button size="small" onClick={() => openDecision(row)}>Review / Correct</Button>
              {row.decision_status === 'Draft' && <Button size="small" disabled={busy} onClick={() => approve(row)}>Approve decision</Button>}
              {row.decision_status === 'Approved' && !row.materialized_range_id && <Button size="small" disabled={busy} onClick={() => materialize(row)}>Version as Draft range</Button>}
              {row.materialized_range_id && <Chip size="small" color="success" label="Materialized Draft" />}
            </Box></TableCell>
          </TableRow>))}</TableBody>
        </Table>
      </TableContainer>
    </CardContent>

    <Dialog open={Boolean(selected)} onClose={() => !busy && setSelected(null)} maxWidth="md" fullWidth>
      <DialogTitle>Technical decision — {selected?.canonical_parameter}</DialogTitle>
      <DialogContent><Box sx={{ display: 'grid', gridTemplateColumns: { xs: '1fr', md: '1fr 1fr' }, gap: 1.5, mt: 1 }}>
        <TextField select label="Decision" value={form.action} onChange={(e) => setForm({ ...form, action: e.target.value })}>{actions.map((a) => <MenuItem key={a} value={a}>{a}</MenuItem>)}</TextField>
        <TextField label="Sex" select value={form.gender} onChange={(e) => setForm({ ...form, gender: e.target.value })}><MenuItem value="All">All</MenuItem><MenuItem value="Male">Male</MenuItem><MenuItem value="Female">Female</MenuItem></TextField>
        <TextField label="Age from (days)" type="number" value={form.age_min_days} onChange={(e) => setForm({ ...form, age_min_days: e.target.value })} />
        <TextField label="Age to (days)" type="number" value={form.age_max_days} onChange={(e) => setForm({ ...form, age_max_days: e.target.value })} />
        <TextField label="Lower bound" type="number" value={form.normal_min} onChange={(e) => setForm({ ...form, normal_min: e.target.value })} />
        <TextField label="Upper bound" type="number" value={form.normal_max} onChange={(e) => setForm({ ...form, normal_max: e.target.value })} />
        <TextField label="Unit" value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })} />
        <TextField label="Method / analyzer applicability" value={form.method_or_analyzer_context} onChange={(e) => setForm({ ...form, method_or_analyzer_context: e.target.value })} />
        <TextField sx={{ gridColumn: '1 / -1' }} label="Applicability basis" value={form.applicability_basis} onChange={(e) => setForm({ ...form, applicability_basis: e.target.value })} />
        <TextField sx={{ gridColumn: '1 / -1' }} required multiline minRows={2} label="Decision/correction reason" value={form.reason} onChange={(e) => setForm({ ...form, reason: e.target.value })} />
        <FormControlLabel control={<Checkbox checked={form.critical_limits_reviewed} onChange={(e) => setForm({ ...form, critical_limits_reviewed: e.target.checked })} />} label="Critical-limit policy reviewed (review does not require inventing limits)" />
      </Box></DialogContent>
      <DialogActions><Button onClick={() => setSelected(null)} disabled={busy}>Cancel</Button><Button variant="contained" onClick={recordDecision} disabled={busy}>Record new decision version</Button></DialogActions>
    </Dialog>
  </Card>;
};
