/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Isolated Report-Only Print Engine
 * Opens an isolated iframe / print document containing strictly the report document HTML and A4 CSS.
 * Suppresses browser-generated headers/footers (title, URL, date, page) and ensures full Nepali Unicode font fidelity.
 */

import { BIMAL_PRINT_CSS } from './printDesign';

export function clonePrintElement(source: HTMLElement): HTMLElement {
  const clone = source.cloneNode(true) as HTMLElement;
  const sourceNodes = [source, ...Array.from(source.querySelectorAll<HTMLElement>('*'))];
  const cloneNodes = [clone, ...Array.from(clone.querySelectorAll<HTMLElement>('*'))];

  sourceNodes.forEach((node, index) => {
    const cloneNode = cloneNodes[index];
    if (!cloneNode) return;
    if (node instanceof HTMLImageElement && cloneNode instanceof HTMLImageElement) {
      cloneNode.src = node.currentSrc || node.src;
    }
  });
  return clone;
}

function stylesheetRuleText(node: HTMLStyleElement): string | null {
  try {
    const rules = node.sheet?.cssRules;
    if (!rules) return null;
    return Array.from(rules, (rule) => rule.cssText).join('\n');
  } catch {
    // A browser may deny CSSOM access to a cross-origin sheet. Style elements
    // normally remain same-origin, but retain their authored text if not.
    return null;
  }
}

export function printableStylesheetMarkup(doc: Document): string {
  return Array.from(doc.head.querySelectorAll<HTMLStyleElement | HTMLLinkElement>('style, link[rel="stylesheet"]'))
    .map((node) => {
      if (node instanceof HTMLLinkElement) return node.outerHTML;

      // Emotion's production/speedy mode inserts rules through CSSOM. In that
      // mode outerHTML can be an empty <style> even though node.sheet contains
      // every MUI `sx` rule. Materialize the live rules for the isolated print
      // document instead of silently dropping the canonical presentation.
      const cssText = stylesheetRuleText(node) ?? node.textContent ?? '';
      const media = node.media ? ` media="${node.media.replace(/"/g, '&quot;')}"` : '';
      const nonce = node.nonce ? ` nonce="${node.nonce.replace(/"/g, '&quot;')}"` : '';
      return `<style${media}${nonce}>${cssText}</style>`;
    })
    .join('\n');
}

async function waitForPrintAssets(doc: Document): Promise<void> {
  const images = Array.from(doc.images);
  await Promise.all(images.map((image) => {
    if (image.complete) return Promise.resolve();
    return new Promise<void>((resolve) => {
      image.addEventListener('load', () => resolve(), { once: true });
      image.addEventListener('error', () => resolve(), { once: true });
    });
  }));
  if (doc.fonts?.ready) await doc.fonts.ready;
}

export async function printReportDocument(reportElementOrId?: HTMLElement | string | null): Promise<void> {
  if (typeof window === 'undefined') return;

  let targetEl: HTMLElement | null = null;
  if (typeof reportElementOrId === 'string') {
    targetEl = document.getElementById(reportElementOrId);
  } else if (reportElementOrId) {
    targetEl = reportElementOrId;
  } else {
    targetEl = document.getElementById('printable-report');
  }

  if (!targetEl) {
    console.warn('[Report Print] Printable report element not found.');
    return;
  }

  // Preserve the structural document without materializing every computed CSS
  // property on every node. The latter leaks preview state and becomes
  // prohibitively large for 50-100 page reports. The isolated frame receives
  // the same authored stylesheets plus the authoritative print overrides.
  const reportHtml = clonePrintElement(targetEl).outerHTML;
  const stylesheetMarkup = printableStylesheetMarkup(document);

  // Remove existing print frame if any
  let iframe = document.getElementById('bimal-print-frame') as HTMLIFrameElement;
  if (iframe) {
    iframe.remove();
  }

  // Create isolated invisible iframe for printing
  iframe = document.createElement('iframe');
  iframe.id = 'bimal-print-frame';
  iframe.style.position = 'fixed';
  iframe.style.right = '0';
  iframe.style.bottom = '0';
  iframe.style.width = '0';
  iframe.style.height = '0';
  iframe.style.border = '0';
  iframe.style.visibility = 'hidden';
  document.body.appendChild(iframe);

  const doc = iframe.contentWindow?.document;
  if (!doc) {
    console.warn('[Report Print] Isolated print document could not be created.');
    iframe.remove();
    return;
  }

  doc.open();
  doc.write(`
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <title>Diagnostic Report - Bimal Pathology</title>
        ${stylesheetMarkup}
        <style>
          ${BIMAL_PRINT_CSS}
        </style>
      </head>
      <body>
        ${reportHtml}
      </body>
    </html>
  `);
  doc.close();

  const printTrigger = () => {
    try {
      iframe.contentWindow?.focus();
      iframe.contentWindow?.print();
    } catch (err) {
      console.warn('[Report Print] Isolated iframe print failed:', err);
    } finally {
      setTimeout(() => {
        iframe.remove();
      }, 3000);
    }
  };

  await waitForPrintAssets(doc);
  await new Promise<void>((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
  printTrigger();
}
