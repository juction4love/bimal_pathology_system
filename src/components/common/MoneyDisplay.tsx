/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Money Display Component (Formats Integer Paisa cleanly)
 */

import React from 'react';
import { Typography, TypographyProps } from '@mui/material';
import { formatPaisa } from '@/lib/currency';

interface MoneyDisplayProps extends Omit<TypographyProps, 'children'> {
  paisa: number | null | undefined;
  includeSymbol?: boolean;
  highlightDue?: boolean;
}

export const MoneyDisplay: React.FC<MoneyDisplayProps> = ({
  paisa,
  includeSymbol = true,
  highlightDue = false,
  sx,
  ...rest
}) => {
  const isDue = highlightDue && (paisa ?? 0) > 0;

  return (
    <Typography
      component="span"
      sx={{
        fontFamily: 'monospace, Roboto, sans-serif',
        fontWeight: 600,
        color: isDue ? 'error.main' : 'inherit',
        ...sx,
      }}
      {...rest}
    >
      {formatPaisa(paisa, includeSymbol)}
    </Typography>
  );
};
