// Network-only service worker: required for installability, intentionally offline-disabled.
// Do not add Cache API usage or fetch interception; this LIS handles sensitive clinical data.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});
