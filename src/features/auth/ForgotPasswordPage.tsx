import React, { useState } from 'react';
import { Alert, Button, CircularProgress, Stack, TextField } from '@mui/material';
import { Link as RouterLink } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';
import { AuthCard } from './AuthCard';
import { GENERIC_RECOVERY_MESSAGE, PRODUCTION_RESET_URL, safeAuthError } from './passwordSecurity';

export const ForgotPasswordPage: React.FC = () => {
  const [email, setEmail] = useState('');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (loading) return;
    setLoading(true);
    setMessage(null);
    setError(null);

    const { error: recoveryError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: PRODUCTION_RESET_URL,
    });

    if (recoveryError && /fetch|network/i.test(recoveryError.message)) {
      setError(safeAuthError(recoveryError, 'Unable to send the reset request. Please try again.'));
    } else {
      // Deliberately identical for existing, missing, and rate-limited accounts.
      setMessage(GENERIC_RECOVERY_MESSAGE);
    }
    setLoading(false);
  };

  return (
    <AuthCard title="Forgot Password" subtitle="Enter your staff account email to request a secure recovery link.">
      {message && <Alert severity="success" sx={{ mb: 2 }}>{message}</Alert>}
      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />
      <Stack component="form" data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation} onSubmit={handleSubmit} spacing={2}>
        <TextField
          id="forgot-email"
          label="Email"
          type="email"
          value={email}
          onChange={(event) => setEmail(event.target.value)}
          required
          autoFocus
          autoComplete="email"
          fullWidth
        />
        <Button id="forgot-submit" data-keyboard-action="true" type="submit" variant="contained" size="large" disabled={loading}>
          {loading ? <CircularProgress size={24} color="inherit" /> : 'Send Reset Link'}
        </Button>
        <Button component={RouterLink} to="/login" variant="text">Back to Sign In</Button>
      </Stack>
    </AuthCard>
  );
};
