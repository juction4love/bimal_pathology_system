/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Pure TypeScript Zero-Dependency QR Code Generator (ISO/IEC 18004)
 * Generates clean, crisp SVG QR codes for offline, print, and PDF verification.
 */

// QR Code Constants & Polynomial Tables
const QR_POLYNOMIAL_TABLE: number[][] = [
  [], // ver 0
  [1, 127, 122, 154, 164, 11, 68, 117], // 7 ECC words (Ver 1-M)
  [1, 216, 194, 159, 111, 199, 94, 95, 113, 157, 193], // 10 ECC words (Ver 2-M)
  [1, 17, 60, 79, 50, 61, 163, 26, 187, 202, 180, 221, 225, 83, 239, 156], // 15 ECC words (Ver 3-M)
  [1, 42, 60, 79, 50, 61, 163, 26, 187, 202, 180, 221, 225, 83, 239, 156, 165, 109, 107, 138, 55], // 20 ECC (Ver 4-M)
];

const EXP_TABLE = new Uint8Array(256);
const LOG_TABLE = new Uint8Array(256);

(function initGaloisField() {
  let val = 1;
  for (let i = 0; i < 255; i++) {
    EXP_TABLE[i] = val;
    LOG_TABLE[val] = i;
    val = val << 1;
    if (val & 256) {
      val = val ^ 285;
    }
  }
  EXP_TABLE[255] = EXP_TABLE[0];
})();

function gMult(a: number, b: number): number {
  if (a === 0 || b === 0) return 0;
  return EXP_TABLE[(LOG_TABLE[a] + LOG_TABLE[b]) % 255];
}

export function generateQrMatrix(text: string): boolean[][] {
  const bytes = new TextEncoder().encode(text);
  const len = bytes.length;

  // Determine minimum version (1 to 4 for URLs up to ~70 chars)
  let version = 1;
  let totalDataBytes = 14;
  let eccBytes = 10;

  if (len <= 14) {
    version = 1;
    totalDataBytes = 14;
    eccBytes = 7;
  } else if (len <= 26) {
    version = 2;
    totalDataBytes = 26;
    eccBytes = 10;
  } else if (len <= 42) {
    version = 3;
    totalDataBytes = 42;
    eccBytes = 15;
  } else {
    version = 4;
    totalDataBytes = 62;
    eccBytes = 20;
  }

  const moduleCount = 17 + version * 4;
  const matrix: boolean[][] = Array.from({ length: moduleCount }, () => Array(moduleCount).fill(false));
  const isReserved: boolean[][] = Array.from({ length: moduleCount }, () => Array(moduleCount).fill(false));

  // Helper to place finder pattern
  function placeFinder(row: number, col: number) {
    for (let r = -1; r <= 7; r++) {
      for (let c = -1; c <= 7; c++) {
        const nr = row + r;
        const nc = col + c;
        if (nr >= 0 && nr < moduleCount && nc >= 0 && nc < moduleCount) {
          isReserved[nr][nc] = true;
          if (r >= 0 && r <= 6 && c >= 0 && c <= 6) {
            matrix[nr][nc] =
              r === 0 || r === 6 || c === 0 || c === 6 || (r >= 2 && r <= 4 && c >= 2 && c <= 4);
          } else {
            matrix[nr][nc] = false;
          }
        }
      }
    }
  }

  // 1. Place 3 Finder Patterns
  placeFinder(0, 0);
  placeFinder(0, moduleCount - 7);
  placeFinder(moduleCount - 7, 0);

  // 2. Timing Patterns
  for (let i = 8; i < moduleCount - 8; i++) {
    isReserved[6][i] = true;
    matrix[6][i] = i % 2 === 0;
    isReserved[i][6] = true;
    matrix[i][6] = i % 2 === 0;
  }

  // 3. Dark module & format reservations
  isReserved[4 * version + 9][8] = true;
  matrix[4 * version + 9][8] = true;

  for (let i = 0; i < 9; i++) {
    if (i < moduleCount) {
      isReserved[8][i] = true;
      isReserved[i][8] = true;
    }
  }
  for (let i = 0; i < 8; i++) {
    isReserved[8][moduleCount - 1 - i] = true;
    isReserved[moduleCount - 1 - i][8] = true;
  }

  // 4. Encode Data Bits (Byte mode = 0100)
  const bitBuffer: number[] = [];
  function pushBits(val: number, count: number) {
    for (let i = count - 1; i >= 0; i--) {
      bitBuffer.push((val >>> i) & 1);
    }
  }

  pushBits(0b0100, 4); // Byte mode
  pushBits(len, 8); // Character count indicator
  for (let i = 0; i < len; i++) {
    pushBits(bytes[i], 8);
  }

  // Terminator & Padding
  const maxBits = totalDataBytes * 8;
  const termLen = Math.min(4, maxBits - bitBuffer.length);
  pushBits(0, termLen);

  while (bitBuffer.length % 8 !== 0) {
    bitBuffer.push(0);
  }

  const padBytes = [0xec, 0x11];
  let padIdx = 0;
  while (bitBuffer.length < maxBits) {
    pushBits(padBytes[padIdx % 2], 8);
    padIdx++;
  }

  // Convert to data bytes
  const dataBytes: number[] = [];
  for (let i = 0; i < bitBuffer.length; i += 8) {
    let byteVal = 0;
    for (let b = 0; b < 8; b++) {
      byteVal = (byteVal << 1) | bitBuffer[i + b];
    }
    dataBytes.push(byteVal);
  }

  // Compute Reed-Solomon ECC
  const eccPoly = QR_POLYNOMIAL_TABLE[version] || QR_POLYNOMIAL_TABLE[1];
  const eccCount = eccBytes;
  const ecc: number[] = Array(eccCount).fill(0);

  for (let i = 0; i < dataBytes.length; i++) {
    const factor = dataBytes[i] ^ ecc[0];
    ecc.shift();
    ecc.push(0);
    for (let j = 0; j < eccCount; j++) {
      ecc[j] ^= gMult(eccPoly[j + 1] || 0, factor);
    }
  }

  // Final codeword stream
  const allWords = [...dataBytes, ...ecc];
  const allBits: number[] = [];
  for (const w of allWords) {
    for (let b = 7; b >= 0; b--) {
      allBits.push((w >>> b) & 1);
    }
  }

  // 5. Place Data Bits in Matrix (Zig-zag from bottom-right)
  let bitIdx = 0;
  let upwards = true;

  for (let right = moduleCount - 1; right > 0; right -= 2) {
    if (right === 6) right--; // Skip vertical timing line
    const colList = [right, right - 1];

    for (let step = 0; step < moduleCount; step++) {
      const row = upwards ? moduleCount - 1 - step : step;
      for (const col of colList) {
        if (!isReserved[row][col]) {
          const bitVal = bitIdx < allBits.length ? allBits[bitIdx] === 1 : false;
          bitIdx++;

          // Apply Mask 0: (row + col) % 2 === 0
          const mask = (row + col) % 2 === 0;
          matrix[row][col] = bitVal !== mask;
        }
      }
    }
    upwards = !upwards;
  }

  // 6. Format bits (Mask 0, Level M = 00)
  // Mask 0 + Level M => format string 101010000010010
  const formatBits = [1, 0, 1, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 1, 0];
  for (let i = 0; i < 6; i++) matrix[8][i] = formatBits[i] === 1;
  matrix[8][7] = formatBits[6] === 1;
  matrix[8][8] = formatBits[7] === 1;
  matrix[7][8] = formatBits[8] === 1;
  for (let i = 9; i < 15; i++) matrix[14 - i][8] = formatBits[i] === 1;

  for (let i = 0; i < 8; i++) matrix[moduleCount - 1 - i][8] = formatBits[i] === 1;
  for (let i = 8; i < 15; i++) matrix[8][moduleCount - 15 + i] = formatBits[i] === 1;

  return matrix;
}

export function generateQrSvgPath(text: string, size = 68): { path: string; viewBox: string; size: number } {
  try {
    const matrix = generateQrMatrix(text);
    const n = matrix.length;
    const quiet = 2;
    const totalModules = n + quiet * 2;
    const scale = size / totalModules;

    let d = '';
    for (let r = 0; r < n; r++) {
      for (let c = 0; c < n; c++) {
        if (matrix[r][c]) {
          const x = (c + quiet) * scale;
          const y = (r + quiet) * scale;
          d += `M${x.toFixed(2)},${y.toFixed(2)}h${scale.toFixed(2)}v${scale.toFixed(2)}h-${scale.toFixed(2)}z `;
        }
      }
    }

    return { path: d, viewBox: `0 0 ${size} ${size}`, size };
  } catch (err) {
    console.warn('[QR Code Generator Error]', err);
    return { path: '', viewBox: `0 0 ${size} ${size}`, size };
  }
}
