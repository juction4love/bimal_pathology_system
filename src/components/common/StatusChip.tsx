/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Clinical & Financial Status Chip Component
 */

import React from 'react';
import { Chip, ChipProps } from '@mui/material';
import {
  SampleStatus,
  ResultStatus,
  ResultFlag,
  ReportingType,
  SAMPLE_STATUSES,
  RESULT_STATUSES,
  RESULT_FLAGS,
  REPORTING_TYPES,
} from '@/config/constants';

interface StatusChipProps extends Omit<ChipProps, 'color'> {
  status: SampleStatus | ResultStatus | ResultFlag | ReportingType | 'Paid' | 'Partial' | 'Due' | string;
  type?: 'sample' | 'result' | 'flag' | 'payment' | 'reporting' | 'auto';
}

export const StatusChip: React.FC<StatusChipProps> = ({ status, sx, ...rest }) => {
  let chipColor: ChipProps['color'] = 'default';
  let label = status;
  let customSx = {};

  // Sample statuses
  if (status === SAMPLE_STATUSES.PENDING) {
    customSx = { bgcolor: 'var(--color-surface-alt)', color: 'var(--color-text-muted)', border: '1px solid var(--color-border)' };
  } else if (status === SAMPLE_STATUSES.COLLECTED) {
    chipColor = 'info';
  } else if (status === SAMPLE_STATUSES.RECEIVED) {
    chipColor = 'primary';
  } else if (status === SAMPLE_STATUSES.PROCESSING) {
    chipColor = 'secondary';
  } else if (status === SAMPLE_STATUSES.COMPLETED) {
    chipColor = 'success';
  } else if (status === SAMPLE_STATUSES.REJECTED) {
    chipColor = 'error';
  } else if (status === SAMPLE_STATUSES.RECOLLECTED) {
    customSx = { bgcolor: 'var(--color-warning-soft)', color: 'var(--color-warning)', border: '1px solid #f3c58c' };
  }

  // Result flags
  else if (status === RESULT_FLAGS.NORMAL) {
    chipColor = 'success';
    customSx = { bgcolor: 'var(--color-success-soft)', color: 'var(--color-success)', border: '1px solid #a9dfc8' };
  } else if (status === RESULT_FLAGS.LOW || status === RESULT_FLAGS.HIGH) {
    chipColor = 'warning';
    customSx = { bgcolor: 'var(--color-warning-soft)', color: 'var(--color-warning)', border: '1px solid #f3c58c', fontWeight: 700 };
  } else if (status === RESULT_FLAGS.CRITICAL_LOW || status === RESULT_FLAGS.CRITICAL_HIGH) {
    chipColor = 'error';
    customSx = {
      bgcolor: 'var(--color-danger-soft)',
      color: 'var(--color-danger)',
      border: '1px solid #f0b7b7',
      fontWeight: 800,
    };
  } else if (status === RESULT_FLAGS.ABNORMAL) {
    chipColor = 'error';
  } else if (status === RESULT_FLAGS.NO_RANGE) {
    chipColor = 'default';
  }

  // Result lifecycle
  else if (status === RESULT_STATUSES.DRAFT) {
    customSx = { bgcolor: 'var(--color-warning-soft)', color: 'var(--color-warning)', border: '1px solid #f3c58c' };
  } else if (status === RESULT_STATUSES.SUBMITTED_FOR_VERIFICATION) {
    customSx = { bgcolor: 'var(--color-verification-soft)', color: 'var(--color-verification)', border: '1px solid #cfbfed' };
    label = 'Awaiting Verification';
  } else if (status === RESULT_STATUSES.VERIFIED) {
    chipColor = 'info';
  } else if (status === RESULT_STATUSES.SIGNED_OFF) {
    chipColor = 'success';
    label = 'Signed Off';
  } else if (status === RESULT_STATUSES.RETURNED_FOR_CORRECTION) {
    chipColor = 'error';
    label = 'Returned';
  }

  // Financial payment statuses
  else if (status === 'Paid') {
    chipColor = 'success';
  } else if (status === 'Partial') {
    chipColor = 'warning';
  } else if (status === 'Due') {
    chipColor = 'error';
  }

  // Reporting types
  else if (status === REPORTING_TYPES.IN_HOUSE) {
    customSx = { bgcolor: 'var(--color-primary-soft)', color: 'var(--color-primary)', border: '1px solid #a8d8ba' };
    label = 'In-House';
  } else if (status === REPORTING_TYPES.OUTSOURCE_WITH_BIMAL_REPORT) {
    customSx = { bgcolor: 'var(--color-warning-soft)', color: 'var(--color-warning)', border: '1px solid #f3c58c' };
    label = 'Outsource + Report';
  } else if (status === REPORTING_TYPES.NO_REPORTING) {
    chipColor = 'default';
    label = 'No Reporting (Bill Only)';
  }

  return (
    <Chip
      size="small"
      label={label}
      color={chipColor}
      sx={{
        fontWeight: 600,
        fontSize: '0.75rem',
        ...customSx,
        ...sx,
      }}
      {...rest}
    />
  );
};
