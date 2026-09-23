/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Authentication & Granular Permissions Provider Component
 * Integrates directly with Supabase Auth & PostgreSQL Row Level Security (Phase 1)
 */

import React, { useEffect, useState, useMemo, useCallback, useRef } from 'react';
import { User, Session } from '@supabase/supabase-js';
import { supabase, isSupabaseConfigured } from '@/lib/supabase';
import { PermissionKey, PERMISSION_KEYS } from '@/types/permissions';
import { UserProfile } from '@/types/database';
import { AuthContext } from './AuthContextCore';

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [user, setUser] = useState<User | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [profile, setProfile] = useState<UserProfile | null>(null);
  const [roles, setRoles] = useState<string[]>([]);
  const [permissions, setPermissions] = useState<Set<PermissionKey>>(new Set());
  const [isLoading, setIsLoading] = useState<boolean>(true);
  const [isPasswordRecovery, setIsPasswordRecovery] = useState(() => {
    const hash = new URLSearchParams(window.location.hash.slice(1));
    const query = new URLSearchParams(window.location.search);
    return window.location.pathname === '/reset-password' &&
      (hash.get('type') === 'recovery' || hash.has('access_token') || query.has('code'));
  });
  const recoveryUrlAtLoad = useRef(isPasswordRecovery).current;

  // Load user profile, roles, and granular permissions directly from PostgreSQL
  const loadUserPermissions = useCallback(async (userId: string): Promise<boolean> => {
    try {
      if (!isSupabaseConfigured) {
        setProfile(null);
        setRoles([]);
        setPermissions(new Set());
        return false;
      }

      // 1. Query user_profiles
      let { data: dbProfile, error: profileErr } = await supabase
        .from('user_profiles')
        .select('*')
        .eq('id', userId)
        .maybeSingle();

      if (profileErr) {
        console.warn('[Auth] Error fetching user profile:', profileErr.message);
        throw profileErr;
      }

      let activeProfile: UserProfile | null = null;

      if (dbProfile) {
        activeProfile = {
          id: dbProfile.id,
          email: dbProfile.email,
          fullName: dbProfile.full_name,
          phone: dbProfile.phone,
          isActive: dbProfile.is_active,
          isSuperAdmin: dbProfile.is_super_admin,
          createdAt: dbProfile.created_at,
          updatedAt: dbProfile.updated_at,
        };
        setProfile(activeProfile);
      }

      // If user account is disabled
      if (activeProfile && !activeProfile.isActive) {
        console.warn('[Auth] User account is deactivated.');
        setRoles([]);
        setPermissions(new Set());
        return false;
      }

      if (!activeProfile) {
        setRoles([]);
        setPermissions(new Set());
        return false;
      }

      // 2. Query assigned roles
      const { data: userRoles, error: rolesErr } = await supabase
        .from('user_roles')
        .select('role_id, role:roles(id, code, name)')
        .eq('user_id', userId);

      if (rolesErr) {
        console.warn('[Auth] Error fetching user roles:', rolesErr.message);
        throw rolesErr;
      }

      const assignedRoleCodes: string[] = [];
      const assignedRoleIds: string[] = [];

      (userRoles || []).forEach((r: any) => {
        if (r.role?.code) assignedRoleCodes.push(r.role.code);
        if (r.role_id) assignedRoleIds.push(r.role_id);
      });

      setRoles(assignedRoleCodes);

      // 3. Query role-based permissions
      const perms = new Set<PermissionKey>();

      if (assignedRoleIds.length > 0) {
        const { data: rolePerms, error: permErr } = await supabase
          .from('role_permissions')
          .select('permission_key')
          .in('role_id', assignedRoleIds);

        if (permErr) throw permErr;
        if (rolePerms) {
          rolePerms.forEach((rp: any) => {
            if (rp.permission_key) {
              perms.add(rp.permission_key as PermissionKey);
            }
          });
        }
      }

      // 4. Query direct permission overrides
      const { data: directPerms, error: directPermsError } = await supabase
        .from('user_direct_permissions')
        .select('permission_key, is_granted')
        .eq('user_id', userId);

      if (directPermsError) throw directPermsError;

      (directPerms || []).forEach((dp: any) => {
        if (dp.is_granted) {
          perms.add(dp.permission_key as PermissionKey);
        } else {
          perms.delete(dp.permission_key as PermissionKey);
        }
      });

      // 5. Admin and Super Admin receive all system permissions
      if (activeProfile?.isSuperAdmin || assignedRoleCodes.includes('admin')) {
        Object.values(PERMISSION_KEYS).forEach((p) => perms.add(p));
      }

      setPermissions(perms);
      return true;
    } catch (err) {
      console.error('[Auth] Unexpected error loading user authorization:', err);
      setProfile(null);
      setRoles([]);
      setPermissions(new Set());
      return false;
    }
  }, []);

  // Initialize session & register auth listener
  useEffect(() => {
    let isMounted = true;

    if (!isSupabaseConfigured) {
      // Production must fail closed when its public Supabase configuration is absent.
      setUser(null);
      setSession(null);
      setProfile(null);
      setRoles([]);
      setPermissions(new Set());
      setIsLoading(false);
      return;
    }

    // Session Restore
    supabase.auth.getSession().then(({ data: { session: initialSession }, error }) => {
      if (!isMounted) return;

      if (error) {
        console.warn('[Auth] Session restore error:', error.message);
        setUser(null);
        setSession(null);
        setProfile(null);
        setRoles([]);
        setPermissions(new Set());
        setIsLoading(false);
        return;
      }

      setSession(initialSession);
      setUser(initialSession?.user ?? null);

      if (initialSession?.user && recoveryUrlAtLoad) {
        // Recovery sessions may belong to inactive staff. Password recovery must
        // remain available without loading or changing LIS authorization state.
        setIsLoading(false);
      } else if (initialSession?.user) {
        loadUserPermissions(initialSession.user.id).then(async (isActive) => {
          if (!isActive) await supabase.auth.signOut();
        }).finally(() => {
          if (isMounted) setIsLoading(false);
        });
      } else {
        setIsLoading(false);
      }
    });

    // Real-time Auth State Subscription
    const { data: { subscription } } = supabase.auth.onAuthStateChange(async (event, currentSession) => {
      if (!isMounted) return;

      setSession(currentSession);
      setUser(currentSession?.user ?? null);

      if (event === 'PASSWORD_RECOVERY') {
        setIsPasswordRecovery(Boolean(currentSession?.user));
        setIsLoading(false);
        return;
      }

      if (event === 'SIGNED_OUT' || !currentSession?.user) {
        setIsPasswordRecovery(false);
        setProfile(null);
        setRoles([]);
        setPermissions(new Set());
        setIsLoading(false);
      } else if (event === 'SIGNED_IN' || event === 'TOKEN_REFRESHED' || event === 'USER_UPDATED') {
        if (currentSession?.user) {
          const isActive = await loadUserPermissions(currentSession.user.id);
          if (!isActive) await supabase.auth.signOut();
        }
        setIsLoading(false);
      }
    });

    return () => {
      isMounted = false;
      subscription.unsubscribe();
    };
  }, [loadUserPermissions, recoveryUrlAtLoad]);

  const refreshProfile = useCallback(async () => {
    if (user?.id) {
      await loadUserPermissions(user.id);
    }
  }, [user, loadUserPermissions]);

  const hasPermission = useCallback((permission: PermissionKey): boolean => {
    if (profile?.isSuperAdmin || roles.includes('admin')) return true;
    return permissions.has(permission);
  }, [permissions, profile?.isSuperAdmin, roles]);

  const hasAnyPermission = useCallback((perms: PermissionKey[]): boolean => {
    if (profile?.isSuperAdmin || roles.includes('admin')) return true;
    return perms.some((p) => permissions.has(p));
  }, [permissions, profile?.isSuperAdmin, roles]);

  const hasAllPermissions = useCallback((perms: PermissionKey[]): boolean => {
    if (profile?.isSuperAdmin || roles.includes('admin')) return true;
    return perms.every((p) => permissions.has(p));
  }, [permissions, profile?.isSuperAdmin, roles]);

  const signIn = useCallback(async (email: string, password: string) => {
    if (!isSupabaseConfigured) {
      return { error: new Error('LIS cloud configuration is unavailable. Contact the system administrator.') };
    }

    const { data, error } = await supabase.auth.signInWithPassword({ email, password });
    if (!error && data.user) {
      const isActive = await loadUserPermissions(data.user.id);
      if (!isActive) {
        await supabase.auth.signOut();
        setUser(null);
        setSession(null);
        setProfile(null);
        return { error: new Error('This staff account is inactive. Contact an administrator.') };
      }
    }
    return { error };
  }, [loadUserPermissions]);

  const signUp = useCallback(async (email: string, password: string, fullName: string, phone?: string) => {
    if (!isSupabaseConfigured) {
      return { error: new Error('Supabase is not configured.'), user: null };
    }

    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          full_name: fullName,
          phone: phone || null,
        },
      },
    });

    // The auth-user trigger installed by migration 00048 is authoritative:
    // the first identity may bootstrap as Admin; all later identities are
    // provisioned inactive and without a clinical role.

    return { error, user: data.user };
  }, []);

  const signOut = useCallback(async () => {
    if (isSupabaseConfigured) {
      await supabase.auth.signOut();
    }
    setUser(null);
    setSession(null);
    setProfile(null);
    setRoles([]);
    setPermissions(new Set());
    setIsPasswordRecovery(false);
  }, []);

  const clearPasswordRecovery = useCallback(() => setIsPasswordRecovery(false), []);

  const value = useMemo(
    () => ({
      user,
      session,
      profile,
      roles,
      permissions,
      isLoading,
      isConfigured: isSupabaseConfigured,
      isPasswordRecovery,
      hasPermission,
      hasAnyPermission,
      hasAllPermissions,
      signIn,
      signUp,
      signOut,
      refreshProfile,
      clearPasswordRecovery,
    }),
    [
      user,
      session,
      profile,
      roles,
      permissions,
      isLoading,
      isPasswordRecovery,
      hasPermission,
      hasAnyPermission,
      hasAllPermissions,
      signIn,
      signUp,
      signOut,
      refreshProfile,
      clearPasswordRecovery,
    ]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};
