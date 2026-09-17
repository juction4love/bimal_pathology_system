import React, { useEffect, useState } from 'react';
import { Box, Button, CircularProgress, Paper, Stack, Typography } from '@mui/material';
import { useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';
import { PasswordField } from './PasswordField';
import { safeAuthError, validateNewPassword } from './passwordSecurity';

export const ChangePasswordPage: React.FC = () => {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => () => {
    setCurrentPassword('');
    setNewPassword('');
    setConfirmation('');
  }, []);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (loading) return;
    if (!currentPassword) {
      setError('Current password is required.');
      return;
    }
    const validationError = validateNewPassword(newPassword, confirmation);
    if (validationError) {
      setError(validationError);
      return;
    }
    if (newPassword === currentPassword) {
      setError('New password must be different from the current password.');
      return;
    }
    if (!user?.email) {
      setError('Your authenticated email is unavailable. Please sign in again.');
      return;
    }

    setLoading(true);
    setError(null);
    const { data: reauthenticated, error: reauthError } = await supabase.auth.signInWithPassword({
      email: user.email,
      password: currentPassword,
    });
    setCurrentPassword('');

    if (reauthError || reauthenticated.user?.id !== user.id) {
      setError('Current password is incorrect.');
      setLoading(false);
      return;
    }

    const { error: updateError } = await supabase.auth.updateUser({
      password: newPassword,
      current_password: currentPassword,
    });
    setNewPassword('');
    setConfirmation('');
    if (updateError) {
      setError(safeAuthError(updateError, 'Password change failed. Please try again.'));
      setLoading(false);
      return;
    }

    await supabase.auth.signOut({ scope: 'global' });
    navigate('/login', {
      replace: true,
      state: { passwordMessage: 'Password changed successfully. Please sign in with your new password.' },
    });
  };

  return (
    <Box sx={{ maxWidth: 560, mx: 'auto' }}>
      <Typography variant="h4" fontWeight={800} color="primary.main" gutterBottom>Change Password</Typography>
      <Typography color="text.secondary" sx={{ mb: 3 }}>Re-enter your current password before choosing a new one.</Typography>
      <Paper sx={{ p: { xs: 2.5, sm: 4 }, borderRadius: 3 }}>
        <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />
        <Stack component="form" data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation} onSubmit={handleSubmit} spacing={2}>
          <PasswordField id="change-current-password" label="Current Password" value={currentPassword} onChange={setCurrentPassword} autoComplete="current-password" autoFocus />
          <PasswordField id="change-new-password" label="New Password" value={newPassword} onChange={setNewPassword} autoComplete="new-password" />
          <PasswordField id="change-confirm-password" label="Confirm New Password" value={confirmation} onChange={setConfirmation} autoComplete="new-password" />
          <Button id="change-password-submit" data-keyboard-action="true" type="submit" variant="contained" size="large" disabled={loading}>
            {loading ? <CircularProgress size={24} color="inherit" /> : 'Change Password'}
          </Button>
        </Stack>
      </Paper>
    </Box>
  );
};
