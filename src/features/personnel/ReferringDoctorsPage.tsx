/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Referring Doctors Master (External Clinicians & Institutions)
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
  FormControlLabel,
  Switch,
  Alert,
  CircularProgress,
} from '@mui/material';
import SearchIcon from '@mui/icons-material/Search';
import AddIcon from '@mui/icons-material/Add';
import EditIcon from '@mui/icons-material/Edit';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { toTitleCase } from '@/lib/stringUtils';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';

interface DbDoctor {
  id: string;
  full_name: string;
  code?: string | null;
  degree?: string | null;
  institution?: string | null;
  phone?: string | null;
  email?: string | null;
  address?: string | null;
  is_active: boolean;
  created_at?: string;
  updated_at?: string;
}

export const ReferringDoctorsPage: React.FC = () => {
  const { can } = usePermissions();
  const [searchTerm, setSearchTerm] = useState('');
  const [doctors, setDoctors] = useState<DbDoctor[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingDoctor, setEditingDoctor] = useState<DbDoctor | null>(null);
  const [form, setForm] = useState({
    full_name: '',
    code: '',
    degree: '',
    institution: '',
    phone: '',
    email: '',
    address: '',
    is_active: true,
  });

  const loadDoctors = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const { data, error: fetchErr } = await supabase
        .from('referring_doctors')
        .select('*')
        .order('full_name', { ascending: true });

      if (fetchErr) throw fetchErr;
      setDoctors(data || []);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load referring clinicians.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadDoctors();
  }, [loadDoctors]);

  const handleOpenModal = (doc?: DbDoctor) => {
    if (doc) {
      setEditingDoctor(doc);
      setForm({
        full_name: doc.full_name,
        code: doc.code || '',
        degree: doc.degree || '',
        institution: doc.institution || '',
        phone: doc.phone || '',
        email: doc.email || '',
        address: doc.address || '',
        is_active: doc.is_active,
      });
    } else {
      setEditingDoctor(null);
      setForm({
        full_name: '',
        code: '',
        degree: '',
        institution: '',
        phone: '',
        email: '',
        address: '',
        is_active: true,
      });
    }
    setDialogOpen(true);
  };

  const handleSaveDoctor = async () => {
    if (!form.full_name.trim()) {
      setError('Doctor name is required.');
      return;
    }

    const payload = {
      full_name: form.full_name.trim(),
      code: form.code.trim() ? form.code.trim().toUpperCase() : null,
      degree: form.degree.trim() || null,
      institution: form.institution.trim() || null,
      phone: form.phone.trim() || null,
      email: form.email.trim() || null,
      address: form.address.trim() || null,
      is_active: form.is_active,
    };

    try {
      const { error: saveErr } = await supabase.rpc('save_referring_doctor', {
        p_doctor: { ...payload, id: editingDoctor?.id },
      });
      if (saveErr) throw saveErr;
      setSuccess(editingDoctor ? `Clinician '${payload.full_name}' updated.` : `Clinician '${payload.full_name}' added.`);

      setDialogOpen(false);
      loadDoctors();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'The clinician record could not be saved.'));
    }
  };

  const filteredDoctors = doctors.filter(
    (d) =>
      d.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (d.code && d.code.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (d.institution && d.institution.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (d.phone && d.phone.includes(searchTerm))
  );

  return (
    <Box>
      <PageHeader
        title="Referring Clinicians Master"
        subtitle="Manage referring physicians, clinical specialists, and hospital affiliations"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadDoctors} disabled={loading}>
              Refresh
            </Button>
            {can(PERMISSION_KEYS.CAN_MANAGE_REFERRING_DOCTORS) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<AddIcon />}
                onClick={() => handleOpenModal()}
              >
                Add Referring Doctor
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
              placeholder="Search by Doctor Name, Degree, or Hospital..."
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
                    <TableCell>Doctor Name & Code</TableCell>
                    <TableCell>Degree & Qualification</TableCell>
                    <TableCell>Hospital / Clinic Affiliation</TableCell>
                    <TableCell>Contact Details</TableCell>
                    <TableCell align="center">Status</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredDoctors.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                        No referring doctors found. Click 'Add Referring Doctor' to register clinicians.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredDoctors.map((doc) => (
                      <TableRow key={doc.id} hover>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700} color="primary.main">
                            {doc.full_name}
                          </Typography>
                          {doc.code && (
                            <Typography variant="caption" color="text.secondary">
                              Code: {doc.code}
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell>{doc.degree || '-'}</TableCell>
                        <TableCell>{doc.institution || '-'}</TableCell>
                        <TableCell>
                          <Typography variant="body2">{doc.phone || '-'}</Typography>
                          {doc.email && (
                            <Typography variant="caption" color="text.secondary">
                              {doc.email}
                            </Typography>
                          )}
                        </TableCell>
                        <TableCell align="center">
                          <Chip
                            label={doc.is_active ? 'Active' : 'Inactive'}
                            color={doc.is_active ? 'success' : 'default'}
                            size="small"
                          />
                        </TableCell>
                        <TableCell align="center">
                          {can(PERMISSION_KEYS.CAN_MANAGE_REFERRING_DOCTORS) && (
                            <IconButton
                              size="small"
                              color="primary"
                              onClick={() => handleOpenModal(doc)}
                            >
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

      {/* Add / Edit Doctor Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>{editingDoctor ? `Edit Clinician: ${editingDoctor.full_name}` : 'Add Referring Clinician'}</DialogTitle>
        <DialogContent dividers>
          <Grid container spacing={2}>
            <Grid item xs={12} sm={8}>
              <TextField
                fullWidth
                size="small"
                label="Full Clinician Name"
                value={form.full_name}
                onChange={(e) => setForm({ ...form, full_name: e.target.value })}
                onBlur={() => setForm({ ...form, full_name: toTitleCase(form.full_name) })}
                onKeyDown={handleEnterKeyNavigation}
                required
                placeholder="e.g. Dr. Sunil Shrestha"
              />
            </Grid>
            <Grid item xs={12} sm={4}>
              <TextField
                fullWidth
                size="small"
                label="Doctor Code"
                value={form.code}
                onChange={(e) => setForm({ ...form, code: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. DOC-01"
              />
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Medical Degree / Qualifications"
                value={form.degree}
                onChange={(e) => setForm({ ...form, degree: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. MBBS, MD (Internal Medicine)"
              />
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Hospital / Clinic Institution"
                value={form.institution}
                onChange={(e) => setForm({ ...form, institution: e.target.value })}
                onBlur={() => setForm({ ...form, institution: toTitleCase(form.institution) })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. Bharatpur Hospital / Private Clinic"
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <TextField
                fullWidth
                size="small"
                label="Phone Number"
                value={form.phone}
                onChange={(e) => setForm({ ...form, phone: e.target.value })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. 9855011111"
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
                onKeyDown={handleEnterKeyNavigation}
              />
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                label="Clinic Address"
                value={form.address}
                onChange={(e) => setForm({ ...form, address: e.target.value })}
                onBlur={() => setForm({ ...form, address: toTitleCase(form.address) })}
                onKeyDown={handleEnterKeyNavigation}
                placeholder="e.g. Chaubiskothi, Bharatpur-10"
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
                label="Active for Selection in Billing"
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" color="primary" onClick={handleSaveDoctor}>
            Save Doctor
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};
