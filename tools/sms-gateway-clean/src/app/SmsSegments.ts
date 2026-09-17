const gsmBasic = /^[\x0A\x0D\x20-\x7E£¥èéùìòÇØøÅåΔ_ΦΓΛΩΠΨΣΘΞÆæßÉÄÖÑÜ§¿äöñüà^{}\\\[~\]|€]*$/;
export function countSmsSegments(text: string): { encoding: 'GSM-7' | 'UCS-2'; segments: number } {
  if (gsmBasic.test(text)) { const units = [...text].reduce((n, c) => n + ('^{}\\[~]|€'.includes(c) ? 2 : 1), 0); return { encoding: 'GSM-7', segments: units <= 160 ? 1 : Math.ceil(units / 153) }; }
  const units = [...text].reduce((n, c) => n + (c.codePointAt(0)! > 0xffff ? 2 : 1), 0);
  return { encoding: 'UCS-2', segments: units <= 70 ? 1 : Math.ceil(units / 67) };
}
