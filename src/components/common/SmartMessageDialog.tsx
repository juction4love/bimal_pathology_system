import { useEffect, useId } from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogActions,
  DialogContent,
  DialogTitle,
  Typography,
} from '@mui/material';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import InfoOutlinedIcon from '@mui/icons-material/InfoOutlined';
import WarningAmberOutlinedIcon from '@mui/icons-material/WarningAmberOutlined';
import ErrorOutlineIcon from '@mui/icons-material/ErrorOutline';
import HelpOutlineIcon from '@mui/icons-material/HelpOutline';
import type { SafeMessageVariant } from '@/lib/safeError';

export type SmartMessageDialogProps = {
  open: boolean;
  variant?: SafeMessageVariant;
  message: string;
  guidance?: string;
  primaryLabel?: string;
  secondaryLabel?: string;
  onPrimary: () => void;
  onSecondary?: () => void;
  allowEscape?: boolean;
  busy?: boolean;
};

const presentation = {
  success: { color: '#15803d', bg: '#f0fdf4', Icon: CheckCircleOutlineIcon },
  info: { color: '#0369a1', bg: '#f0f9ff', Icon: InfoOutlinedIcon },
  warning: { color: '#a16207', bg: '#fffbeb', Icon: WarningAmberOutlinedIcon },
  error: { color: '#b91c1c', bg: '#fef2f2', Icon: ErrorOutlineIcon },
  confirm: { color: '#4338ca', bg: '#eef2ff', Icon: HelpOutlineIcon },
} as const;

const defaultGuidance: Record<string, string> = {
  'This mobile number is already registered.': 'Please verify the patient or use the existing patient record.',
  'You do not have permission to perform this action.': 'Contact the Super Admin if you believe access is required.',
  'This payment has already been processed.': 'Refresh the bill to view the latest balance.',
  'Payment amount is greater than the outstanding balance.': 'Refresh the bill and enter an amount no greater than the balance due.',
  'This report can no longer be modified.': 'The report has already been signed.',
  'Patient details changed. Refresh and try again.': 'Re-select the existing patient before continuing.',
  'Unable to connect. Check your internet connection and try again.': 'If the problem continues, contact the Super Admin.',
};

export function SmartMessageDialog({
  open,
  variant,
  message,
  guidance,
  primaryLabel,
  secondaryLabel = 'Cancel',
  onPrimary,
  onSecondary,
  allowEscape = variant !== 'confirm',
  busy = false,
}: SmartMessageDialogProps) {
  const titleId = useId();
  const descriptionId = useId();
  const inferredVariant: SafeMessageVariant = message.includes('already registered') || message.includes('greater than') || message.includes('can no longer') || message.includes('changed. Refresh') ? 'warning'
    : message.includes('already been processed') ? 'info' : 'error';
  const resolvedVariant = variant || inferredVariant;
  const { color, bg, Icon } = presentation[resolvedVariant];
  const resolvedPrimaryLabel = primaryLabel || (resolvedVariant === 'confirm' ? 'Confirm' : 'Close');
  const resolvedGuidance = guidance || defaultGuidance[message];

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Enter' && !busy) {
        event.preventDefault();
        onPrimary();
      }
    };
    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [busy, onPrimary, open]);

  const handleClose = (_event: object, reason: 'backdropClick' | 'escapeKeyDown') => {
    if (busy || (reason === 'escapeKeyDown' && !allowEscape) || resolvedVariant === 'confirm') return;
    onPrimary();
  };

  return (
    <Dialog
      open={open}
      onClose={handleClose}
      aria-labelledby={titleId}
      aria-describedby={descriptionId}
      maxWidth="xs"
      fullWidth
      disableEscapeKeyDown={!allowEscape || resolvedVariant === 'confirm'}
      PaperProps={{ sx: { m: { xs: 2, sm: 3 }, width: '100%', maxWidth: 460, borderRadius: 2.5 } }}
    >
      <DialogTitle id={titleId} sx={{ pb: 1, textAlign: 'center', fontWeight: 800 }}>
        Bimal Pathology
      </DialogTitle>
      <DialogContent sx={{ textAlign: 'center', px: { xs: 2.5, sm: 4 }, pt: '8px !important' }}>
        <Box sx={{ width: 56, height: 56, mx: 'auto', mb: 2, borderRadius: '50%', bgcolor: bg, color, display: 'grid', placeItems: 'center' }}>
          <Icon sx={{ fontSize: 34 }} aria-hidden="true" />
        </Box>
        <Typography id={descriptionId} variant="body1" sx={{ fontWeight: 700, overflowWrap: 'anywhere' }}>
          {message}
        </Typography>
        {resolvedGuidance && (
          <Typography variant="body2" color="text.secondary" sx={{ mt: 1.25, overflowWrap: 'anywhere' }}>
            {resolvedGuidance}
          </Typography>
        )}
      </DialogContent>
      <DialogActions sx={{ px: { xs: 2.5, sm: 4 }, pb: 3, pt: 2, gap: 1, justifyContent: 'center', flexDirection: { xs: 'column-reverse', sm: 'row' } }}>
        {onSecondary && (
          <Button fullWidth={false} disabled={busy} onClick={onSecondary} sx={{ minHeight: 44, minWidth: 120 }}>
            {secondaryLabel}
          </Button>
        )}
        <Button autoFocus variant="contained" disabled={busy} onClick={onPrimary} sx={{ minHeight: 44, minWidth: 120 }}>
          {resolvedPrimaryLabel}
        </Button>
      </DialogActions>
    </Dialog>
  );
}
