import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { fileURLToPath, URL } from 'node:url'
import fs from 'node:fs'

const packageJson = JSON.parse(
  fs.readFileSync(fileURLToPath(new URL('./package.json', import.meta.url)), 'utf8'),
) as { version?: string }
const frontendVersion = packageJson.version?.trim()
if (!frontendVersion || frontendVersion === '0.0.0') {
  throw new Error('A non-placeholder package version is required for a production build.')
}
const assetNamespace = `r${frontendVersion.replace(/[^0-9A-Za-z]+/g, '_').replace(/^_+|_+$/g, '')}`

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      output: {
        // Package version is the human-readable namespace; Rollup's content
        // hash remains the byte-level cache identity.
        entryFileNames: `assets/[name]-[hash]-${assetNamespace}.js`,
        chunkFileNames: `assets/[name]-[hash]-${assetNamespace}.js`,
        manualChunks(id) {
          if (id.includes('node_modules')) {
            if (
              id.includes('/react/') ||
              id.includes('/react-dom/') ||
              id.includes('/react-router/') ||
              id.includes('/react-router-dom/') ||
              id.includes('/scheduler/')
            ) {
              return 'vendor-react';
            }
            if (id.includes('/@mui/') || id.includes('/@emotion/')) {
              return 'vendor-mui';
            }
            if (id.includes('/@supabase/')) {
              return 'vendor-supabase';
            }
            if (id.includes('/@tanstack/')) {
              return 'vendor-query';
            }
          }
        },
      },
    },
  },
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
})
