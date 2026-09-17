// Deliberately non-sending tombstone. Production SMS ownership belongs only to
// BimalPathologySMSGateway on Windows. No provider credential is read here.
const providerEnabled = false;

Deno.serve(() => new Response(JSON.stringify({
  success: false,
  providerEnabled,
  error: 'Windows SMS Gateway is the only authoritative SMS sender',
}), {
  status: 410,
  headers: { 'content-type': 'application/json', 'cache-control': 'no-store' },
}));
