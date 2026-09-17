/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Standardized Keyboard Navigation & Focus Helpers
 */

import React, { useEffect } from 'react';

/**
 * Returns all focusable interactive inputs inside a container in DOM order.
 */
export function getFocusableInputs(container: HTMLElement | Document = document): HTMLElement[] {
  const selector = [
    'input:not([disabled]):not([type="hidden"])',
    'select:not([disabled])',
    'textarea:not([disabled])',
    '[contenteditable="true"]',
    '.MuiSelect-select',
    '.MuiAutocomplete-input',
    '[data-keyboard-action="true"]',
  ].join(', ');

  const elements = Array.from(container.querySelectorAll<HTMLElement>(selector));
  return elements.filter((el) => {
    // Check if element is visible and not inside a hidden container
    const input = el as HTMLInputElement;
    return el.offsetParent !== null && !el.getAttribute('aria-hidden') && !input.readOnly && el.tabIndex !== -1;
  });
}

/**
 * Advances focus to the next focusable input element in DOM order.
 */
export function focusNextInputElement(currentElement: HTMLElement, container?: HTMLElement): boolean {
  const inputs = getFocusableInputs(container || document);
  const currentIndex = inputs.indexOf(currentElement);

  if (currentIndex !== -1 && currentIndex < inputs.length - 1) {
    const nextEl = inputs[currentIndex + 1];
    nextEl.focus();
    if (nextEl instanceof HTMLInputElement && (nextEl.type === 'text' || nextEl.type === 'number')) {
      nextEl.select();
    }
    return true;
  }
  return false;
}

/**
 * Shifts focus to the previous focusable input element in DOM order.
 */
export function focusPreviousInputElement(currentElement: HTMLElement, container?: HTMLElement): boolean {
  const inputs = getFocusableInputs(container || document);
  const currentIndex = inputs.indexOf(currentElement);

  if (currentIndex > 0) {
    const prevEl = inputs[currentIndex - 1];
    prevEl.focus();
    if (prevEl instanceof HTMLInputElement && (prevEl.type === 'text' || prevEl.type === 'number')) {
      prevEl.select();
    }
    return true;
  }
  return false;
}

/**
 * Standard onKeyDown handler to advance on Enter key without triggering accidental form submit.
 */
export function handleEnterKeyNavigation(
  e: React.KeyboardEvent<HTMLElement>,
  onEnterCustomAction?: () => void
): void {
  // If Enter is pressed without modifier keys
  if (e.key === 'Enter' && !e.shiftKey && !e.ctrlKey && !e.altKey && !e.metaKey) {
    const target = e.target as HTMLElement;

    // Do not intercept Enter in multiline textareas or buttons
    if (target.tagName === 'TEXTAREA' || target.tagName === 'BUTTON') {
      return;
    }

    e.preventDefault();

    if (onEnterCustomAction) {
      onEnterCustomAction();
      return;
    }

    const formScope = target.closest<HTMLElement>('[data-keyboard-form="true"]') || undefined;
    focusNextInputElement(target, formScope);
  }
}

/**
 * React hook to bind keyboard shortcuts like Ctrl+S for saving drafts.
 */
export function useKeyboardShortcut(
  key: string,
  callback: (e: KeyboardEvent) => void,
  options?: { ctrlOrCmd?: boolean; shift?: boolean; preventDefault?: boolean }
): void {
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      const isCtrlOrCmd = options?.ctrlOrCmd ? (e.ctrlKey || e.metaKey) : true;
      const isShift = options?.shift ? e.shiftKey : !e.shiftKey;

      if (e.key.toLowerCase() === key.toLowerCase() && isCtrlOrCmd && isShift) {
        if (options?.preventDefault !== false) {
          e.preventDefault();
        }
        callback(e);
      }
    };

    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [key, callback, options]);
}
