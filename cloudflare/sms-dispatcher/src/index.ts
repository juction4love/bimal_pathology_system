// Deliberately non-sending tombstone retained to make accidental legacy Worker
// deployment fail closed. Sparrow credentials and queue mutation are forbidden.
const response = () => new Response(JSON.stringify({
  success: false,
  error: 'Windows SMS Gateway is the only authoritative SMS sender',
}), { status: 410, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

export default {
  fetch: response,
  scheduled: () => undefined,
  queue: () => undefined,
};
