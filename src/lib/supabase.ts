/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Supabase Client Initialization
 */

import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import type { Database } from '@/types/supabase.generated';

export type SupabaseDatabase = Database;

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || 'https://placeholder.supabase.co';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || 'placeholder-key';

export const isSupabaseConfigured = Boolean(
  import.meta.env.VITE_SUPABASE_URL && 
  import.meta.env.VITE_SUPABASE_ANON_KEY &&
  !import.meta.env.VITE_SUPABASE_URL.includes('your-project-id')
);

// Construct against the generated schema while retaining the existing domain-facing
// client boundary. Feature modules intentionally map JSON-returning RPCs into richer
// clinical/domain types after runtime validation.
export const supabase: SupabaseClient = createClient<Database>(supabaseUrl, supabaseAnonKey, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});
