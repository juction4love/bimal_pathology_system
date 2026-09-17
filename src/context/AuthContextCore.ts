/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Core Auth Context & Hook
 */

import { createContext, useContext } from 'react';
import { User, Session } from '@supabase/supabase-js';
import { PermissionKey } from '@/types/permissions';
import { UserProfile } from '@/types/database';

export interface AuthContextType {
  user: User | null;
  session: Session | null;
  profile: UserProfile | null;
  roles: string[];
  permissions: Set<PermissionKey>;
  isLoading: boolean;
  isConfigured: boolean;
  isPasswordRecovery: boolean;
  hasPermission: (permission: PermissionKey) => boolean;
  hasAnyPermission: (permissions: PermissionKey[]) => boolean;
  hasAllPermissions: (permissions: PermissionKey[]) => boolean;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string, fullName: string, phone?: string) => Promise<{ error: Error | null; user: User | null }>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
  clearPasswordRecovery: () => void;
}

export const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};
