/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Staff Sign-In Page
 * Production: sign-in only. Registration is disabled from public UI.
 */

import React, { useState } from 'react';
import {
  Box,
  Card,
  CardContent,
  Typography,
  TextField,
  Button,
  Alert,
  CircularProgress,
  InputAdornment,
  IconButton,
} from '@mui/material';
import VisibilityIcon from '@mui/icons-material/Visibility';
import VisibilityOffIcon from '@mui/icons-material/VisibilityOff';
import { Link as RouterLink, useLocation, useNavigate } from 'react-router-dom';

import { useAuth } from '@/hooks/useAuth';
import { ORG_CONFIG } from '@/config/constants';
import { handleEnterKeyNavigation } from '@/lib/keyboardNav';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';

export const LoginPage: React.FC = () => {
  const navigate = useNavigate();
  const location = useLocation();
  const { signIn } = useAuth();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSignIn = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);

    const { error: signInError } = await signIn(email.trim(), password);
    setLoading(false);

    if (signInError) {
      setError(safeErrorMessage(signInError, 'Invalid email or password. Please try again.'));
    } else {
      navigate('/');
    }
  };

  return (
    <Box
      sx={{
        minHeight: '100vh',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        bgcolor: '#081e38',
        p: 2,
      }}
    >
      <Card sx={{ maxWidth: 440, width: '100%', borderRadius: 3, boxShadow: 6 }}>
        <CardContent sx={{ p: 4, textAlign: 'center' }}>

          {/* Logo */}
          <Box
            component="img"
            src="/pathology-logo.png"
            alt="Bimal Pathology Logo"
            sx={{
              width: 80,
              height: 80,
              objectFit: 'contain',
              mx: 'auto',
              mb: 1.5,
              display: 'block',
            }}
          />

          {/* Org Name */}
          <Typography variant="h5" fontWeight={800} color="primary.main" gutterBottom>
            {ORG_CONFIG.nameEn}
          </Typography>
          <Typography variant="subtitle2" color="secondary.main" sx={{ mb: 1 }}>
            {ORG_CONFIG.nameNp}
          </Typography>
          <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 3 }}>
            Laboratory Information System (LIS) Cloud Portal
          </Typography>

          {/* Error */}
          {location.state?.passwordMessage && (
            <Alert severity="success" sx={{ mb: 2, textAlign: 'left' }}>
              {location.state.passwordMessage}
            </Alert>
          )}
          <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

          {/* Sign-In Form */}
          <form data-keyboard-form="true" onKeyDown={handleEnterKeyNavigation} onSubmit={handleSignIn}>
            <TextField
              fullWidth
              id="login-email"
              label="Email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="username"
              sx={{ mb: 2 }}
            />

            <TextField
              fullWidth
              id="login-password"
              label="Password"
              type={showPassword ? 'text' : 'password'}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              sx={{ mb: 1 }}
              InputProps={{
                endAdornment: (
                  <InputAdornment position="end">
                    <IconButton
                      onClick={() => setShowPassword(!showPassword)}
                      edge="end"
                      aria-label={showPassword ? 'Hide password' : 'Show password'}
                    >
                      {showPassword ? <VisibilityOffIcon /> : <VisibilityIcon />}
                    </IconButton>
                  </InputAdornment>
                ),
              }}
            />

            <Box sx={{ display: 'flex', justifyContent: 'flex-end', mb: 2 }}>
              <Button component={RouterLink} to="/forgot-password" size="small" sx={{ textTransform: 'none' }}>
                Forgot Password?
              </Button>
            </Box>

            <Button
              id="login-submit"
              data-keyboard-action="true"
              type="submit"
              fullWidth
              variant="contained"
              color="primary"
              size="large"
              disabled={loading}
              sx={{ py: 1.25, fontWeight: 700 }}
            >
              {loading ? <CircularProgress size={24} color="inherit" /> : 'Sign In'}
            </Button>
          </form>

          {/* Footer */}
          <Box sx={{ mt: 3, pt: 2, borderTop: '1px solid #e2e8f0' }}>
            <Typography variant="caption" color="text.secondary">
              Reg. No: {ORG_CONFIG.regNo}&nbsp;|&nbsp;PAN: {ORG_CONFIG.panNo}
            </Typography>
            <Typography variant="caption" color="text.secondary" sx={{ display: 'block' }}>
              {ORG_CONFIG.addressEn}
            </Typography>
          </Box>

        </CardContent>
      </Card>
    </Box>
  );
};
