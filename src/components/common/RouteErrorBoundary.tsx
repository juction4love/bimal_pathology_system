import React from 'react';
import { Alert, Box, Button, Typography } from '@mui/material';
import { clearChunkReloadMarkers, isChunkLoadError } from '@/app/lazyWithChunkRecovery';

interface State { error: Error | null }

export class RouteErrorBoundary extends React.Component<React.PropsWithChildren, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State { return { error }; }

  componentDidCatch(error: Error, errorInfo: React.ErrorInfo) {
    console.error('RouteErrorBoundary caught error:', error, errorInfo);
  }

  private refresh = () => {
    clearChunkReloadMarkers();
    window.location.reload();
  };

  render() {
    if (!this.state.error) return this.props.children;
    const versionMismatch = isChunkLoadError(this.state.error.cause) || /newer application version/i.test(this.state.error.message);
    return (
      <Box sx={{ p: 3, maxWidth: 640, mx: 'auto', mt: 4 }}>
        <Alert severity={versionMismatch ? 'info' : 'error'} sx={{ mb: 2 }}>
          <Typography variant="subtitle1" fontWeight={700}>
            {versionMismatch ? 'New version available — Refresh' : 'This page could not be loaded'}
          </Typography>
          <Typography variant="body2" sx={{ mt: 0.5 }}>
            {versionMismatch
              ? 'The application was updated while this page was open. Refresh once to load the current version.'
              : 'Refresh the page and try again. If the problem continues, contact the administrator.'}
          </Typography>
        </Alert>
        <Button variant="contained" onClick={this.refresh}>Refresh</Button>
      </Box>
    );
  }
}
