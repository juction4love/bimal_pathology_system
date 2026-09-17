import React, { useEffect, useState } from 'react';
import { Alert, Button, CircularProgress, Stack } from '@mui/material';
import { Link as RouterLink, useNavigate } from 'react-router-dom';
import { useAuth } from '@/hooks/useAuth';
import { supabase } from '@/lib/supabase';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';
import { AuthCard } from './AuthCard';
import { PasswordField } from './PasswordField';
import { safeAuthError, validateNewPassword } from './passwordSecurity';

const INVALID_LINK_MESSAGE = 'This password recovery link is invalid, expired, or has already been used.';

export const ResetPasswordPage: React.FC = () => {
  const navigate = useNavigate();
  const { session, isLoading: authLoading, isPasswordRecovery, clearPasswordRecovery } = useAuth();
  const [newPassword, setNewPassword] = useState('');
  const [confirmation, setConfirmation] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const recoveryErrorInUrl = new URLSearchParams(window.location.search).has('error') ||
    new URLSearchParams(window.location.hash.slice(1)).has('error');
  const recoveryValid = !authLoading && !recoveryErrorInUrl && isPasswordRecovery && Boolean(session?.user);

  useEffect(() => {
    return () => {
      setNewPassword('');
      setConfirmation('');
    };
  }, []);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (loading || !recoveryValid) return;
    const validationError = validateNewPassword(newPassword, confirmation);
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);
    setError(null);
    const { error: updateError } = await supabase.auth.updateUser({ password: newPassword });
    setNewPassword('');
    setConfirmation('');

    if (updateError) {
      setError(safeAuthError(updateError, 'Password reset failed. Request a new recovery link and try again.'));
      setLoading(false);
      return;
    }

    clearPasswordRecovery();
    await supabase.auth.signOut({ scope: 'global' });
    navigate('/login', {
      replace: true,
      state: { passwordMessage: 'Password reset successfully. Please sign in with your new password.' },
    });
  };

  return (
    <AuthCard title="Reset Password" subtitle="Choose a new password for your staff account.">
      {authLoading && <Alert severity="info" sx={{ mb: 2 }}>Validating recovery link…</Alert>}
      {!authLoading && !recoveryValid && <Alert severity="error" sx={{ mb: 2 }}>{INVALID_LINK_MESSAGE}</Alert>}
      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />
      <Stack component="form" data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation} onSubmit={handleSubmit} spacing={2}>
        <PasswordField id="reset-new-password" label="New Password" value={newPassword} onChange={setNewPassword} autoComplete="new-password" autoFocus />
        <PasswordField id="reset-confirm-password" label="Confirm New Password" value={confirmation} onChange={setConfirmation} autoComplete="new-password" />
        <Button id="reset-submit" data-keyboard-action="true" type="submit" variant="contained" size="large" disabled={loading || !recoveryValid}>
          {loading ? <CircularProgress size={24} color="inherit" /> : 'Reset Password'}
        </Button>
        {!recoveryValid && !authLoading && <Button component={RouterLink} to="/forgot-password">Request a New Link</Button>}
        <Button component={RouterLink} to="/login" variant="text">Back to Sign In</Button>
      </Stack>
    </AuthCard>
  );
};
