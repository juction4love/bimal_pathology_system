import React, { useState } from 'react';
import { Alert, IconButton, InputAdornment, TextField } from '@mui/material';
import VisibilityIcon from '@mui/icons-material/Visibility';
import VisibilityOffIcon from '@mui/icons-material/VisibilityOff';

interface PasswordFieldProps {
  id: string;
  label: string;
  value: string;
  autoComplete: string;
  onChange: (value: string) => void;
  autoFocus?: boolean;
  sx?: object;
}

export const PasswordField: React.FC<PasswordFieldProps> = ({
  id,
  label,
  value,
  autoComplete,
  onChange,
  autoFocus,
  sx,
}) => {
  const [visible, setVisible] = useState(false);
  const [capsLock, setCapsLock] = useState(false);

  return (
    <>
      <TextField
        fullWidth
        required
        id={id}
        label={label}
        type={visible ? 'text' : 'password'}
        value={value}
        autoComplete={autoComplete}
        autoFocus={autoFocus}
        onChange={(event) => onChange(event.target.value)}
        onKeyDown={(event) => setCapsLock(event.getModifierState('CapsLock'))}
        onKeyUp={(event) => setCapsLock(event.getModifierState('CapsLock'))}
        onBlur={() => setCapsLock(false)}
        sx={sx}
        slotProps={{
          input: {
            endAdornment: (
              <InputAdornment position="end">
                <IconButton
                  type="button"
                  onClick={() => setVisible((current) => !current)}
                  edge="end"
                  aria-label={visible ? `Hide ${label.toLowerCase()}` : `Show ${label.toLowerCase()}`}
                  tabIndex={-1}
                >
                  {visible ? <VisibilityOffIcon /> : <VisibilityIcon />}
                </IconButton>
              </InputAdornment>
            ),
          },
        }}
      />
      {capsLock && (
        <Alert severity="warning" icon={false} sx={{ mt: -1, mb: 2, py: 0 }}>
          Caps Lock is on.
        </Alert>
      )}
    </>
  );
};
