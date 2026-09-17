/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Canonical Bill / Invoice Viewer & Print Dialog
 * Provides unified A4 preview, direct isolated iframe print, and workflow navigation.
 */

import React from 'react';
import {
  Box,
  Button,
  Dialog,
  DialogContent,
  DialogTitle,
  Typography,
} from '@mui/material';
import PrintIcon from '@mui/icons-material/Print';
import ArrowForwardIcon from '@mui/icons-material/ArrowForward';
import { printReportDocument } from '@/lib/reportPrint';
import { BillDocument, BillSnapshot } from './BillDocument';

interface BillViewerDialogProps {
  open: boolean;
  bill: BillSnapshot | null;
  onClose: () => void;
  onNavigateNext?: () => void;
  nextActionLabel?: string;
}

export const BillViewerDialog: React.FC<BillViewerDialogProps> = ({
  open,
  bill,
  onClose,
  onNavigateNext,
  nextActionLabel,
}) => {
  const handlePrint = () => {
    printReportDocument('printable-invoice');
  };

  return (
    <Dialog
      open={open}
      onClose={onClose}
      maxWidth="lg"
      fullWidth
      PaperProps={{
        sx: {
          bgcolor: '#525659',
          p: 1,
        },
      }}
    >
      <DialogTitle
        sx={{
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'center',
          color: '#ffffff',
          py: 1,
        }}
      >
        <Typography variant="h6" fontWeight={700}>
          Official Bill Receipt — {bill?.bill_number || '-'}
        </Typography>
        <Box className="screen-only" sx={{ display: 'flex', gap: 1, alignItems: 'center' }}>
          <Button
            variant="contained"
            color="primary"
            size="small"
            startIcon={<PrintIcon />}
            onClick={handlePrint}
            sx={{ fontWeight: 700 }}
          >
            Print Bill (A4)
          </Button>

          {onNavigateNext && (
            <Button
              variant="contained"
              color="success"
              size="small"
              endIcon={<ArrowForwardIcon />}
              onClick={onNavigateNext}
              sx={{ fontWeight: 700 }}
            >
              {nextActionLabel || 'Continue to Samples'}
            </Button>
          )}

          <Button
            variant="outlined"
            color="inherit"
            size="small"
            onClick={onClose}
          >
            Close
          </Button>
        </Box>
      </DialogTitle>

      <DialogContent
        sx={{
          display: 'flex',
          justifyContent: 'center',
          p: 2,
          overflowY: 'auto',
          maxHeight: 'calc(90vh - 80px)',
        }}
      >
        <Box sx={{ width: '100%', maxWidth: '210mm' }}>
          {bill && <BillDocument bill={bill} />}
        </Box>
      </DialogContent>
    </Dialog>
  );
};
