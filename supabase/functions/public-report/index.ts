// BIMAL PATHOLOGY & DIAGNOSTIC CENTER
// Supabase Edge Function: Public Diagnostic Report Gateway
// Validates token hash, enforces SignedOff state, and returns patient-facing report

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.112.3';

// Production gateway accepts browser calls only from the canonical LIS origin.
const ALLOWED_ORIGINS = [
  'https://lis.bimalpathology.com.np',
];

function corsHeaders(origin: string | null): Record<string, string> {
  const allowed = origin && ALLOWED_ORIGINS.includes(origin) ? origin : ALLOWED_ORIGINS[0];
  return {
    'Access-Control-Allow-Origin': allowed,
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Vary': 'Origin',
  };
}

serve(async (req: Request) => {
  const origin = req.headers.get('origin');
  const hdrs = corsHeaders(origin);

  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: hdrs });
  }

  try {
    const url = new URL(req.url);
    const token = url.searchParams.get('token') || '';

    if (!/^[A-Za-z0-9_-]{32,256}$/.test(token.trim())) {
      return new Response(
        JSON.stringify({ error: 'Valid report token is required.' }),
        { status: 400, headers: { ...hdrs, 'Content-Type': 'application/json' } }
      );
    }

    // 1. Calculate SHA-256 hash of token
    const encoder = new TextEncoder();
    const data = encoder.encode(token.trim().toLowerCase());
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    const tokenHash = Array.from(new Uint8Array(hashBuffer))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');

    // 2. Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY') || '';
    const supabase = createClient(supabaseUrl, supabaseAnonKey);

    // 3. Resolve report via Security Definer RPC
    const { data: reportData, error: rpcErr } = await supabase.rpc('resolve_public_report_by_token', {
      p_token_hash: tokenHash,
    });

    if (rpcErr) {
      return new Response(
        JSON.stringify({ error: 'The report could not be verified.' }),
        { status: 500, headers: { ...hdrs, 'Content-Type': 'application/json' } }
      );
    }

    if (!reportData || !reportData.valid) {
      const errorStatus = reportData?.error?.includes('expired') ? 410 : 404;
      return new Response(
        JSON.stringify({ error: reportData?.error || 'Invalid or revoked report token.' }),
        { status: errorStatus, headers: { ...hdrs, 'Content-Type': 'application/json' } }
      );
    }

    return new Response(
      JSON.stringify(reportData),
      { status: 200, headers: { ...hdrs, 'Content-Type': 'application/json' } }
    );
  } catch {
    return new Response(
      JSON.stringify({ error: 'The report could not be verified.' }),
      { status: 500, headers: { ...hdrs, 'Content-Type': 'application/json' } }
    );
  }
});
