/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Modern Medical LIS Theme Configuration (MUI)
 */

import { createTheme } from '@mui/material/styles';

export const theme = createTheme({
  palette: {
    mode: 'light',
    primary: {
      main: '#0b6b3a', // Bimal clinical green
      light: '#0f8f5b',
      dark: '#064d2c',
      contrastText: '#ffffff',
    },
    secondary: {
      main: '#0f8f5b', // Emerald accent
      light: '#34b77c',
      dark: '#075f34',
      contrastText: '#ffffff',
    },
    success: {
      main: '#15803d', // Success green
      light: '#34d399',
      dark: '#065f46',
    },
    warning: {
      main: '#c4660a', // Amber
      light: '#fbbf24',
      dark: '#92400e',
    },
    error: {
      main: '#c62828', // Clinical crimson
      light: '#f87171',
      dark: '#991b1b',
    },
    info: {
      main: '#0f766e',
      light: '#5bb5ab',
      dark: '#115e59',
    },
    background: {
      default: '#f2f7f4',
      paper: '#ffffff',
    },
    text: {
      primary: '#14213d',
      secondary: '#526477',
    },
    divider: '#e2e8f0',
  },
  typography: {
    fontFamily: [
      'Inter',
      '-apple-system',
      'BlinkMacSystemFont',
      '"Segoe UI"',
      'Roboto',
      '"Helvetica Neue"',
      'Arial',
      'sans-serif',
    ].join(','),
    h1: { fontSize: '2rem', fontWeight: 700, letterSpacing: '-0.02em' },
    h2: { fontSize: '1.6rem', fontWeight: 700, letterSpacing: '-0.01em' },
    h3: { fontSize: '1.35rem', fontWeight: 600 },
    h4: { fontSize: '1.15rem', fontWeight: 600 },
    h5: { fontSize: '1rem', fontWeight: 600 },
    h6: { fontSize: '0.875rem', fontWeight: 600 },
    subtitle1: { fontSize: '0.95rem', fontWeight: 500 },
    subtitle2: { fontSize: '0.825rem', fontWeight: 500 },
    body1: { fontSize: '0.9rem', lineHeight: 1.5 },
    body2: { fontSize: '0.825rem', lineHeight: 1.4 },
    button: { textTransform: 'none', fontWeight: 600 },
  },
  shape: {
    borderRadius: 8,
  },
  components: {
    MuiButton: {
      defaultProps: {
        disableElevation: true,
      },
      styleOverrides: {
        root: {
          minHeight: 38,
          borderRadius: 8,
          padding: '7px 18px',
          fontWeight: 600,
          '&:focus-visible': {
            outline: '3px solid rgba(24, 166, 106, 0.42)',
            outlineOffset: '2px',
          },
        },
        containedPrimary: {
          '&:hover': { backgroundColor: '#075f34' },
        },
      },
    },
    MuiOutlinedInput: {
      styleOverrides: {
        root: {
          minHeight: 40,
          backgroundColor: '#ffffff',
          '&.Mui-focused .MuiOutlinedInput-notchedOutline': {
            borderColor: '#0b6b3a',
            borderWidth: '2px',
          },
        },
      },
    },
    MuiCard: {
      styleOverrides: {
        root: {
          borderRadius: 12,
          border: '1px solid #e2e8f0',
          boxShadow: '0 2px 8px rgba(20, 33, 61, 0.07)',
        },
      },
    },
    MuiPaper: {
      styleOverrides: {
        root: {
          backgroundImage: 'none',
        },
      },
    },
    MuiTableCell: {
      styleOverrides: {
        head: {
          fontWeight: 600,
          backgroundColor: '#e9f7ef',
          color: '#195b38',
          fontSize: '0.825rem',
        },
        root: {
          fontSize: '0.85rem',
          padding: '10px 14px',
        },
      },
    },
    MuiTableRow: {
      styleOverrides: {
        root: {
          '&.MuiTableRow-hover:hover': { backgroundColor: '#f0faf4' },
          '&.Mui-selected, &.Mui-selected:hover': { backgroundColor: '#ddf4e7' },
        },
      },
    },
    MuiChip: {
      styleOverrides: {
        root: {
          fontWeight: 600,
          fontSize: '0.75rem',
          borderRadius: 6,
        },
      },
    },
    MuiTextField: {
      defaultProps: {
        size: 'small',
      },
    },
  },
});
