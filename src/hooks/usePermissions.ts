/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Permissions Hook for Components
 */

import { useAuth } from '@/hooks/useAuth';
import { PermissionKey } from '@/types/permissions';

export function usePermissions() {
  const { permissions, hasPermission, hasAnyPermission, hasAllPermissions, roles, profile } = useAuth();

  return {
    permissions,
    roles,
    profile,
    can: (permission: PermissionKey) => hasPermission(permission),
    canAny: (perms: PermissionKey[]) => hasAnyPermission(perms),
    canAll: (perms: PermissionKey[]) => hasAllPermissions(perms),
  };
}
