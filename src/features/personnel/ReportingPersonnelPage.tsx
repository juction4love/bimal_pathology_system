/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Clinical & Reporting Personnel Master (Internal Signatories)
 * Full Supabase PostgreSQL CRUD with Row Level Security Enforcement (Phase 1)
 */

import React, { useState, useEffect, useCallback } from 'react';
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
  Chip,
  IconButton,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Grid,
  MenuItem,
  FormControlLabel,
  Switch,
  Alert,
  CircularProgress,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddIcon from '@mui/icons-material/Add';
import EditIcon from '@mui/icons-material/Edit';
import CheckCircleIcon from '@mui/icons-material/CheckCircle';
import CancelIcon from '@mui/icons-material/Cancel';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { toTitleCase } from '@/lib/stringUtils';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';

interface DbPersonnel {
  id: string;
  user_id?: string | null;
  full_name: string;
  professional_type: string;
  qualification: string;
  registration_council: string;
  registration_number: string;
  specialization?: string | null;
  phone?: string | null;
  email?: string | null;
  signature_url?: string | null;
  can_enter_results: boolean;
  can_verify_results: boolean;
  can_acknowledge_critical: boolean;
  can_sign_reports: boolean;
  is_active: boolean;
  display_order: number;
}

export const ReportingPersonnelPage: React.FC = () => {
  const { can } = usePermissions();
  const [searchTerm, setSearchTerm] = useState('');
  const [personnel, setPersonnel] = useState<DbPersonnel[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingPersonnel, setEditingPersonnel] = useState<DbPersonnel | null>(null);
  const [form, setForm] = useState({
    full_name: '',
    professional_type: 'Lab Technologist',
    qualification: '',
    registration_council: 'Nepal Health Professional Council (NHPC)',
    registration_number: '',
    specialization: '',
    phone: '',
    email: '',
    can_enter_results: true,
    can_verify_results: false,
    can_acknowledge_critical: false,
    can_sign_reports: false,
    is_active: true,
    display_order: 1,
  });

  const loadPersonnel = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase
        .from('reporting_personnel')
        .select('*')
        .order('display_order', { ascending: true })
        .order('full_name', { ascending: true });

      if (fetchErr) throw fetchErr;
      setPersonnel(data || []);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load reporting signatories.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadPersonnel();
  }, [loadPersonnel]);

  const handleOpenModal = (p?: DbPersonnel) => {
    if (p) {
      setEditingPersonnel(p);
      setForm({
        full_name: p.full_name,
        professional_type: p.professional_type,
        qualification: p.qualification,
        registration_council: p.registration_council,
        registration_number: p.registration_number,
        specialization: p.specialization || '',
        phone: p.phone || '',
        email: p.email || '',
        can_enter_results: p.can_enter_results,
        can_verify_results: p.can_verify_results,
        can_acknowledge_critical: p.can_acknowledge_critical,
        can_sign_reports: p.can_sign_reports,
        is_active: p.is_active,
        display_order: p.display_order || 1,
      });
    } else {
      setEditingPersonnel(null);
      setForm({
        full_name: '',
        professional_type: 'Lab Technologist',
        qualification: '',
        registration_council: 'Nepal Health Professional Council (NHPC)',
        registration_number: '',
        specialization: '',
        phone: '',
        email: '',
        can_enter_results: true,
        can_verify_results: false,
        can_acknowledge_critical: false,
        can_sign_reports: false,
        is_active: true,
        display_order: personnel.length + 1,
      });
    }
    setDialogOpen(true);
  };

  const handleSavePersonnel = async () => {
    if (!form.full_name.trim() || !form.qualification.trim() || !form.registration_number.trim()) {
      setError('Full Name, Qualification, and Council Registration Number are mandatory.');
      return;
    }

    const payload = {
      full_name: form.full_name.trim(),
      professional_type: form.professional_type,
      qualification: form.qualification.trim(),
      registration_council: form.registration_council.trim(),
      registration_number: form.registration_number.trim(),
      specialization: form.specialization.trim() || null,
      phone: form.phone.trim() || null,
      email: form.email.trim() || null,
      can_enter_results: form.can_enter_results,
      can_verify_results: form.can_verify_results,
      can_acknowledge_critical: form.can_acknowledge_critical,
      can_sign_reports: form.can_sign_reports,
      is_active: form.is_active,
      display_order: parseInt(String(form.display_order), 10) || 1,
    };

    try {
      const { error: saveErr } = await supabase.rpc('save_reporting_personnel', {
        p_personnel: { ...payload, id: editingPersonnel?.id },
      });
      if (saveErr) throw saveErr;
      setSuccess(editingPersonnel ? `Signatory '${payload.full_name}' updated.` : `Signatory '${payload.full_name}' registered.`);

      setDialogOpen(false);
      loadPersonnel();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'The reporting-personnel record could not be saved.'));
    }
  };

  const filteredPersonnel = personnel.filter(
    (p) =>
      p.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.professional_type.toLowerCase().includes(searchTerm.toLowerCase()) ||
      p.registration_number.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (p.specialization && p.specialization.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  return (
    <Box>
      <PageHeader
        title="Clinical & Reporting Personnel"
        subtitle="Manage internal laboratory signatories, professional council registrations, and clinical sign-off authorizations"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadPersonnel} disabled={loading}>
              Refresh
            </Button>
            {can(PERMISSION_KEYS.CAN_MANAGE_PERSONNEL) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<AddIcon />}
                onClick={() => handleOpenModal()}
              >
                Add Reporting Personnel
              </Button>
            )}
          </Box>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      {success && (
        <Alert severity="success" onClose={() => setSuccess(null)} sx={{ mb: 2 }}>
          {success}
        </Alert>
      )}

      <Card>
        <CardContent>
          <Box sx={{ mb: 2, maxWidth: 400 }}>
            <TextField
              fullWidth
              size="small"
              placeholder="Search by Name, Council No, or Role..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              InputProps={{
                startAdornment: (
                  <InputAdornment position="start">
                    <SearchIcon fontSize="small" />
                  </InputAdornment>
                ),
              }}
            />
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
                    <TableCell>Full Name & Role</TableCell>
                    <TableCell>Qualification & Specialization</TableCell>
                    <TableCell>Council & Reg. No.</TableCell>
                    <TableCell align="center">Enter</TableCell>
                    <TableCell align="center">Verify</TableCell>
                    <TableCell align="center">Ack. Critical</TableCell>
                    <TableCell align="center">Sign Reports</TableCell>
                    <TableCell align="center">Status</TableCell>
                    <TableCell align="center">Action</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredPersonnel.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={9} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                        No reporting personnel found. Click 'Add Reporting Personnel' to configure signatories.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredPersonnel.map((p) => (
                      <TableRow key={p.id} hover>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700} color="primary.main">
                            {p.full_name}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {p.professional_type}
                          </Typography>
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2">{p.qualification}</Typography>
                          {p.specialization && (
                            <Typography variant="caption" color="text.secondary">
                              {p.specialization}
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell>
                          <Typography variant="body2" fontWeight={600}>
                            {p.registration_number}
                          </Typography>
                          <Typography variant="caption" color="text.secondary">
                            {p.registration_council}
                          </Typography>
                        </TableCell>
                        <TableCell align="center">
                          {p.can_enter_results ? (
                            <CheckCircleIcon color="success" fontSize="small" />
                          ) : (
                            <CancelIcon color="disabled" fontSize="small" />
                          )}
                        </TableCell>
                        <TableCell align="center">
                          {p.can_verify_results ? (
                            <CheckCircleIcon color="success" fontSize="small" />
                          ) : (
                            <CancelIcon color="disabled" fontSize="small" />
                          )}
                        </TableCell>
                        <TableCell align="center">
                          {p.can_acknowledge_critical ? (
                            <CheckCircleIcon color="success" fontSize="small" />
                          ) : (
                            <CancelIcon color="disabled" fontSize="small" />
                          )}
                        </TableCell>
                        <TableCell align="center">
                          {p.can_sign_reports ? (
                            <CheckCircleIcon color="success" fontSize="small" />
                          ) : (
                            <CancelIcon color="disabled" fontSize="small" />
                          )}
                        </TableCell>
                        <TableCell align="center">
                          <Chip
                            label={p.is_active ? 'Active' : 'Inactive'}
                            color={p.is_active ? 'success' : 'default'}
                            size="small"
                          />
                        </TableCell>
                        <TableCell align="center">
                          {can(PERMISSION_KEYS.CAN_MANAGE_PERSONNEL) && (
                            <IconButton size="small" color="primary" onClick={() => handleOpenModal(p)}>
                              <EditIcon fontSize="small" />
                            </IconButton>
                          )}
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

      {/* Add / Edit Reporting Personnel Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="md" fullWidth>
        <DialogTitle>
          {editingPersonnel ? `Edit Signatory: ${editingPersonnel.full_name}` : 'Add Clinical Reporting Signatory'}
        </DialogTitle>
        <DialogContent dividers>
          <Grid container spacing={2}>
            <Grid item xs={12} sm={8}>
              <TextField
                fullWidth
                size="small"
                label="Full Legal Name & Title"
                value={form.full_name}
                onChange={(e) => setForm({ ...form, full_name: e.target.value })}
                onBlur={() => setForm({ ...form, full_name: toTitleCase(form.full_name) })}
                onKeyDown={handleEnterKeyNavigation}
                required
                placeholder="e.g. Dr. Bimal Pathak, MD"
              />
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                fullWidth
                size="small"
                select
                label="Professional Designation"
                value={form.professional_type}
                onChange={(e) => setForm({ ...form, professional_type: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
              >
                <MenuItem value="Pathologist">Pathologist</MenuItem>
                <MenuItem value="Lab Technologist">Lab Technologist</MenuItem>
                <MenuItem value="Lab Technician">Lab Technician</MenuItem>
                <MenuItem value="Lab Assistant">Lab Assistant</MenuItem>
                <MenuItem value="Receptionist">Receptionist</MenuItem>
                <MenuItem value="Admin">Admin</MenuItem>
              </TextField>
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Degree / Academic Qualifications"
                value={form.qualification}
                onChange={(e) => setForm({ ...form, qualification: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                required
                placeholder="e.g. MBBS, MD (Pathology) or B.Sc. MLT"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Specialization / Department"
                value={form.specialization}
                onChange={(e) => setForm({ ...form, specialization: e.target.value })}
                onBlur={() => setForm({ ...form, specialization: toTitleCase(form.specialization) })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. Histopathology & Hematology"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Registration Council Name"
                value={form.registration_council}
                onChange={(e) => setForm({ ...form, registration_council: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                required
                placeholder="e.g. Nepal Medical Council (NMC), NHPC"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Council Registration Number"
                value={form.registration_number}
                onChange={(e) => setForm({ ...form, registration_number: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                required
                placeholder="e.g. 1423 or A-874"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Phone Number"
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Email Address"
                type="email"
                value={form.email}
                onChange={(e) => setForm({ ...form, email: e.target.value })}
              />
            </Grid>

            <Grid item xs={12}>
              <Typography variant="subtitle2" fontWeight={700} sx={{ mt: 1, mb: 0.5 }}>
                Clinical Authority & Sign-off Permissions
              </Typography>
            </Grid>
            <Grid item xs={6} sm={3}>
              <FormControlLabel
                control={
                  <Switch
                    checked={form.can_enter_results}
                    onChange={(e) => setForm({ ...form, can_enter_results: e.target.checked })}
                  />
                }
                label="Enter Results"
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <FormControlLabel
                control={
                  <Switch
                    checked={form.can_verify_results}
                    onChange={(e) => setForm({ ...form, can_verify_results: e.target.checked })}
                  />
                }
                label="Verify Results"
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <FormControlLabel
                control={
                  <Switch
                    checked={form.can_acknowledge_critical}
                    onChange={(e) => setForm({ ...form, can_acknowledge_critical: e.target.checked })}
                  />
                }
                label="Ack. Critical"
              />
            </Grid>
            <Grid item xs={6} sm={3}>
              <FormControlLabel
                control={
                  <Switch
                    checked={form.can_sign_reports}
                    onChange={(e) => setForm({ ...form, can_sign_reports: e.target.checked })}
                    color="secondary"
                  />
                }
                label="Sign Reports"
              />
            </Grid>

            <Grid item xs={12}>
              <FormControlLabel
                control={
                  <Switch
                    checked={form.is_active}
                    onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
                    color="primary"
                  />
                }
                label="Active Signatory"
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" color="primary" onClick={handleSavePersonnel}>
            Save Signatory
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};
