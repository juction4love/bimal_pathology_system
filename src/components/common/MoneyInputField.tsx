/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Money Input Field (Keeps editable string state while focused, validates on blur/commit)
 * Prevents blocking modal popups during intermediate typing.
 */

import React, { useState, useEffect } from 'react';
import { TextField, TextFieldProps } from '@mui/material';
import { isValidMoneyIntermediate, validateMoneyCommitted } from '@/lib/currency';

export interface MoneyInputFieldProps extends Omit<TextFieldProps, 'value' | 'onChange' | 'onBlur'> {
  valuePaisa?: number | null;
  onCommitPaisa?: (paisa: number | null, rawText: string) => void;
  required?: boolean;
  allowZero?: boolean;
  maxPaisa?: number;
  fieldName?: string;
  externalError?: string | null;
  onKeyDown?: (e: React.KeyboardEvent<HTMLInputElement>) => void;
  onBlur?: (e: React.FocusEvent<HTMLInputElement>) => void;
  onFocus?: (e: React.FocusEvent<HTMLInputElement>) => void;
}

export const MoneyInputField: React.FC<MoneyInputFieldProps> = ({
  valuePaisa,
  onCommitPaisa,
  required = false,
  allowZero = true,
  maxPaisa,
  fieldName = 'Rate',
  externalError,
  helperText,
  error,
  inputRef,
  onKeyDown,
  onBlur,
  onFocus,
  inputProps,
  ...rest
}) => {
  const [isFocused, setIsFocused] = useState(false);
  const [textValue, setTextValue] = useState<string>(() => {
    if (valuePaisa !== null && valuePaisa !== undefined) {
      return (valuePaisa / 100).toFixed(2);
    }
    return '';
  });
  const [localError, setLocalError] = useState<string | null>(null);

  // Sync external changes when not focused
  useEffect(() => {
    if (!isFocused) {
      if (valuePaisa !== null && valuePaisa !== undefined) {
        setTextValue((valuePaisa / 100).toFixed(2));
      } else {
        setTextValue('');
      }
      setLocalError(null);
    }
  }, [valuePaisa, isFocused]);

  const handleChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const raw = e.target.value;
    if (isValidMoneyIntermediate(raw)) {
      setTextValue(raw);
      if (localError) setLocalError(null);
    }
  };

  const handleBlur = (e: React.FocusEvent<HTMLInputElement>) => {
    setIsFocused(false);
    const outcome = validateMoneyCommitted(textValue, {
      required,
      allowZero,
      maxPaisa,
      fieldName,
    });

    if (!outcome.isValid) {
      setLocalError(outcome.error);
      onCommitPaisa?.(null, textValue);
    } else {
      setLocalError(null);
      setTextValue(outcome.normalizedText);
      onCommitPaisa?.(outcome.paisa, outcome.normalizedText);
    }

    onBlur?.(e);
  };

  const handleFocus = (e: React.FocusEvent<HTMLInputElement>) => {
    setIsFocused(true);
    onFocus?.(e);
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Enter') {
      const outcome = validateMoneyCommitted(textValue, {
        required,
        allowZero,
        maxPaisa,
        fieldName,
      });
      if (outcome.isValid) {
        setLocalError(null);
        setTextValue(outcome.normalizedText);
        onCommitPaisa?.(outcome.paisa, outcome.normalizedText);
      } else {
        setLocalError(outcome.error);
        onCommitPaisa?.(null, textValue);
      }
    }
    onKeyDown?.(e);
  };

  const displayError = Boolean(externalError || localError || error);
  const displayHelperText = localError || externalError || helperText;

  return (
    <TextField
      inputRef={inputRef}
      value={textValue}
      onChange={handleChange}
      onFocus={handleFocus}
      onBlur={handleBlur}
      onKeyDown={handleKeyDown}
      error={displayError}
      helperText={displayHelperText}
      inputProps={{
        inputMode: 'decimal',
        ...inputProps,
      }}
      {...rest}
    />
  );
};
