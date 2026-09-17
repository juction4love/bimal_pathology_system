/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Common UI Layout Helpers: PageHeader, LoadingScreen, ErrorBoundary
 */

import React from 'react';
import { Box, Typography, CircularProgress } from '@mui/material';
import { SmartMessageDialog } from './SmartMessageDialog';

export interface PageHeaderProps {
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}

export const PageHeader: React.FC<PageHeaderProps> = ({ title, subtitle, action }) => {
  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: { xs: 'column', sm: 'row' },
        justifyContent: 'space-between',
        alignItems: { xs: 'flex-start', sm: 'center' },
        mb: 3,
        gap: 1.5,
      }}
    >
      <Box>
        <Typography variant="h4" component="h1" fontWeight={700} color="text.primary">
          {title}
        </Typography>
        {subtitle && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 0.5 }}>
            {subtitle}
          </Typography>
        )}
      </Box>
      {action && <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap' }}>{action}</Box>}
    </Box>
  );
};

export const LoadingScreen: React.FC<{ message?: string }> = ({ message = 'Loading laboratory data...' }) => {
  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '40vh',
        gap: 2,
      }}
    >
      <CircularProgress color="primary" size={40} />
      <Typography variant="body2" color="text.secondary">
        {message}
      </Typography>
    </Box>
  );
};

interface ErrorBoundaryProps {
  children: React.ReactNode;
}

interface ErrorBoundaryState {
  hasError: boolean;
  error: Error | null;
  reference: string | null;
}

export class ErrorBoundary extends React.Component<ErrorBoundaryProps, ErrorBoundaryState> {
  constructor(props: ErrorBoundaryProps) {
    super(props);
    this.state = { hasError: false, error: null, reference: null };
  }

  static getDerivedStateFromError(error: Error): ErrorBoundaryState {
    const reference = `ERR-${Math.random().toString(16).slice(2, 6).toUpperCase()}`;
    return { hasError: true, error, reference };
  }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('ErrorBoundary caught error:', error, errorInfo);
  }

  handleReset = () => {
    this.setState({ hasError: false, error: null, reference: null });
    window.location.reload();
  };

  render() {
    if (this.state.hasError) {
      return (
        <Box sx={{ minHeight: '60vh' }}>
          <SmartMessageDialog
            open
            variant="error"
            message="This screen could not be displayed."
            guidance={`Reload the application. If the problem continues, contact the Super Admin and provide reference ${this.state.reference}.`}
            primaryLabel="Reload Application"
            onPrimary={this.handleReset}
            allowEscape={false}
          />
        </Box>
      );
    }
    return this.props.children;
  }
}
