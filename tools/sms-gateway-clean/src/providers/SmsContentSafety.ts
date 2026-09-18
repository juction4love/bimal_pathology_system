// Fail closed during the Nepal Telecom URL restriction. Do not log message text.
// Includes bare domains, IP links, URI schemes and tokenized report paths.
export const SMS_LINK_PATTERN = /[a-z][a-z0-9+.-]*:\/\/|https?:|www\.|bimalpathology|(?:[\p{L}\p{N}](?:[\p{L}\p{N}-]*[\p{L}\p{N}])?\.)+[\p{L}]{2,63}\b|(?:\d{1,3}\.){3}\d{1,3}|\/(?:r|o)\/[a-z0-9_-]+|mailto:|tel:/iu;

export function containsSmsLink(body: string): boolean {
  return SMS_LINK_PATTERN.test(body.normalize('NFKC').replace(/[\u200B-\u200D\uFEFF]/g, ''));
}
