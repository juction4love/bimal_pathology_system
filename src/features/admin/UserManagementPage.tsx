/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * User Management Page (Supabase Auth & Roles mapping)
 * Connects directly with PostgreSQL tables: user_profiles, roles, user_roles (Phase 1)
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
import PersonAddIcon from '@mui/icons-material/PersonAdd';
import EditIcon from '@mui/icons-material/Edit';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { formatDualDate } from '@/lib/dateTime';

interface UserWithRoles {
  id: string;
  email: string;
  full_name: string;
  phone?: string | null;
  is_active: boolean;
  is_super_admin: boolean;
  created_at: string;
  roles: Array<{ id: string; code: string; name: string }>;
}

export const UserManagementPage: React.FC = () => {
  const { can } = usePermissions();
  const [searchTerm, setSearchTerm] = useState('');
  const [users, setUsers] = useState<UserWithRoles[]>([]);
  const [allRoles, setAllRoles] = useState<Array<{ id: string; code: string; name: string }>>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);

  // Edit / Role Assignment Dialog
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingUser, setEditingUser] = useState<UserWithRoles | null>(null);
  const [selectedRoleIds, setSelectedRoleIds] = useState<string[]>([]);
  const [userActive, setUserActive] = useState(true);
  const [userSuperAdmin, setUserSuperAdmin] = useState(false);

  const loadUsers = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      // 1. Fetch all roles
      const { data: dbRoles } = await supabase.from('roles').select('id, code, name');
      setAllRoles((dbRoles || []).filter((role) => role.code === 'lab_technician'));

      // 2. Fetch user profiles
      const { data: profiles, error: pErr } = await supabase
        .from('user_profiles')
        .select('*')
        .order('full_name', { ascending: true });

      if (pErr) throw pErr;

      // 3. Fetch user_roles
      const { data: userRoles, error: urErr } = await supabase
        .from('user_roles')
        .select('user_id, role_id, role:roles(id, code, name)');

      if (urErr) throw urErr;

      const roleMap: Record<string, Array<{ id: string; code: string; name: string }>> = {};
      (userRoles || []).forEach((ur: any) => {
        if (!roleMap[ur.user_id]) roleMap[ur.user_id] = [];
        if (ur.role) roleMap[ur.user_id].push(ur.role);
      });

      const assembled: UserWithRoles[] = (profiles || []).map((p) => ({
        ...p,
        roles: roleMap[p.id] || [],
      }));

      setUsers(assembled);
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load user accounts.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadUsers();
  }, [loadUsers]);

  const handleOpenEdit = (u: UserWithRoles) => {
    setEditingUser(u);
    setSelectedRoleIds(u.roles.filter((r) => r.code === 'lab_technician').map((r) => r.id));
    setUserActive(u.is_active);
    setUserSuperAdmin(u.is_super_admin);
    setDialogOpen(true);
  };

  const handleSaveUser = async () => {
    if (!editingUser) return;

    try {
      const { error: updateError } = await supabase.rpc('update_user_access', {
        p_user_id: editingUser.id,
        p_is_active: userActive,
        p_is_super_admin: userSuperAdmin,
        p_role_ids: selectedRoleIds,
      });
      if (updateError) throw updateError;

      setSuccess(`User '${editingUser.full_name}' updated successfully.`);
      setDialogOpen(false);
      loadUsers();
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to update user roles or status.'));
    }
  };

  const filteredUsers = users.filter(
    (u) =>
      u.full_name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      u.email.toLowerCase().includes(searchTerm.toLowerCase()) ||
      u.roles.some((r) => r.name.toLowerCase().includes(searchTerm.toLowerCase()))
  );

  return (
    <Box>
      <PageHeader
        title="User Accounts & Access Control"
        subtitle="Manage staff access, Lab Technician assignment, and login security"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <Button variant="outlined" startIcon={<RefreshIcon />} onClick={loadUsers} disabled={loading}>
              Refresh
            </Button>
            {can(PERMISSION_KEYS.CAN_MANAGE_USERS) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<PersonAddIcon />}
                onClick={() => setSuccess('Create the Auth account through the approved Super Admin process. It remains inactive until Lab Technician access is assigned here.')}
              >
                Onboard User
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
              placeholder="Search users by name, email, or role..."
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
                    <TableCell>Full Name</TableCell>
                    <TableCell>Email / Username</TableCell>
                    <TableCell>Assigned Roles</TableCell>
                    <TableCell>Registered Date</TableCell>
                    <TableCell align="center">Status</TableCell>
                    <TableCell align="center">Actions</TableCell>
                  </TableRow>
                </TableHead>
                <TableBody>
                  {filteredUsers.length === 0 ? (
                    <TableRow>
                      <TableCell colSpan={6} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                        No user profiles registered in database yet.
                      </TableCell>
                    </TableRow>
                  ) : (
                    filteredUsers.map((user) => (
                      <TableRow key={user.id} hover>
                        <TableCell>
                          <Typography variant="body2" fontWeight={700} color="primary.main">
                            {user.full_name}
                          </Typography>
                          {user.is_super_admin && (
                            <Chip label="Super Admin" size="small" color="primary" sx={{ height: 18, fontSize: '0.65rem' }} />
                          )}
                        </TableCell>
                        <TableCell>{user.email}</TableCell>
                        <TableCell>
                          {user.roles.length === 0 ? (
                            <Typography variant="caption" color="text.secondary">No role assigned</Typography>
                          ) : (
                            user.roles.map((r) => (
                              <Chip key={r.id} label={r.name} size="small" variant="outlined" sx={{ mr: 0.5, mb: 0.5 }} />
                            ))
                          )}
                        </TableCell>
                        <TableCell>{formatDualDate(user.created_at)}</TableCell>
                        <TableCell align="center">
                          <Chip
                            label={user.is_active ? 'Active' : 'Disabled'}
                            color={user.is_active ? 'success' : 'default'}
                            size="small"
                          />
                        </TableCell>
                        <TableCell align="center">
                          {can(PERMISSION_KEYS.CAN_MANAGE_USERS) && (
                            <IconButton size="small" color="primary" onClick={() => handleOpenEdit(user)}>
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

      {/* Edit User & Assign Roles Dialog */}
      <Dialog open={dialogOpen} onClose={() => setDialogOpen(false)} maxWidth="sm" fullWidth>
        <DialogTitle>Configure Access: {editingUser?.full_name}</DialogTitle>
        <DialogContent dividers>
          <Grid container spacing={2}>
            <Grid item xs={12}>
              <Typography variant="body2" color="text.secondary">
                Email: <strong>{editingUser?.email}</strong>
              </Typography>
            </Grid>
            <Grid item xs={12}>
              <TextField
                fullWidth
                size="small"
                select
                SelectProps={{
                  multiple: true,
                  value: selectedRoleIds,
                  onChange: (e: any) => setSelectedRoleIds(typeof e.target.value === 'string' ? e.target.value.split(',') : e.target.value),
                  renderValue: (selected: any) => (
                    <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                      {(selected as string[]).map((val) => {
                        const r = allRoles.find((role) => role.id === val);
                        return <Chip key={val} label={r?.name || val} size="small" />;
                      })}
                    </Box>
                  ),
                }}
                label="Operational Role"
              >
                {allRoles.map((role) => (
                  <MenuItem key={role.id} value={role.id}>
                    {role.name}
                  </MenuItem>
                ))}
              </TextField>
            </Grid>
            <Grid item xs={12}>
              <FormControlLabel
                control={
                  <Switch
                    checked={userActive}
                    onChange={(e) => setUserActive(e.target.checked)}
                    color="success"
                  />
                }
                label="Account Active (Can log in)"
              />
            </Grid>
            <Grid item xs={12}>
              <FormControlLabel
                control={
                  <Switch
                    checked={userSuperAdmin}
                    onChange={(e) => setUserSuperAdmin(e.target.checked)}
                    color="primary"
                  />
                }
                label="System Owner / Super Admin (server-authoritative bypass)"
              />
            </Grid>
          </Grid>
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setDialogOpen(false)}>Cancel</Button>
          <Button variant="contained" color="primary" onClick={handleSaveUser}>
            Save User Configuration
          </Button>
        </DialogActions>
      </Dialog>
    </Box>
  );
};
