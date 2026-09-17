/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Permission Guard Component for UI Elements and Routes
 */

import React from 'react';
import { usePermissions } from '@/hooks/usePermissions';
import { PermissionKey } from '@/types/permissions';
import { Box, Typography, Button } from '@mui/material';
import LockOutlinedIcon from '@mui/icons-material/LockOutlined';

interface PermissionGuardProps {
  permission?: PermissionKey;
  anyPermissions?: PermissionKey[];
  allPermissions?: PermissionKey[];
  fallback?: React.ReactNode;
  children: React.ReactNode;
}

export const PermissionGuard: React.FC<PermissionGuardProps> = ({
  permission,
  anyPermissions,
  allPermissions,
  fallback = null,
  children,
}) => {
  const { can, canAny, canAll } = usePermissions();

  let hasAccess = true;

  if (permission && !can(permission)) {
    hasAccess = false;
  }

  if (anyPermissions && !canAny(anyPermissions)) {
    hasAccess = false;
  }

  if (allPermissions && !canAll(allPermissions)) {
    hasAccess = false;
  }

  if (!hasAccess) {
    return <>{fallback}</>;
  }

  return <>{children}</>;
};

export const UnauthorizedPage: React.FC = () => {
  return (
    <Box
      sx={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        minHeight: '60vh',
        textAlign: 'center',
        p: 3,
      }}
    >
      <LockOutlinedIcon sx={{ fontSize: 64, color: 'text.secondary', mb: 2 }} />
      <Typography variant="h4" fontWeight={700} gutterBottom>
        Access Denied
      </Typography>
      <Typography variant="body1" color="text.secondary" sx={{ maxWidth: 460, mb: 3 }}>
        You do not possess the required permissions to access this laboratory resource.
        Please contact the Lab Technician or Super Admin if you require access.
      </Typography>
      <Button variant="contained" color="primary" href="/">
        Return to Dashboard
      </Button>
    </Box>
  );
};
