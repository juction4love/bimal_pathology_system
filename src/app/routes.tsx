/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Application Routes Configuration with Granular UI Permission Gates
 */

import React, { Suspense } from 'react';
import { createBrowserRouter, Navigate } from 'react-router-dom';
import { Box, CircularProgress } from '@mui/material';
import { RouteErrorBoundary } from '@/components/common/RouteErrorBoundary';

import { AppLayout } from './AppLayout';
import { PermissionGuard, UnauthorizedPage } from '@/components/common/PermissionGuard';
import { PERMISSION_KEYS } from '@/types/permissions';
import {
  AuditLogPage,
  BillListPage,
  CataloguePage,
  ChangePasswordPage,
  DashboardPage,
  ForgotPasswordPage,
  HmisMonthlyReportPage,
  LoginPage,
  NewBillPage,
  OutsourceTrackingPage,
  PatientsPage,
  PublicReportPage,
  ReferringDoctorsPage,
  ReportingPersonnelPage,
  ReportsPage,
  ResetPasswordPage,
  ResultEntryPage,
  RolePermissionsPage,
  SampleAccessioningPage,
  SettingsPage,
  SmsDeliveryPage,
  UserManagementPage,
  WorklistPage,
} from './lazyPages';

const lazyScreen = (element: React.ReactNode) => (
  <RouteErrorBoundary>
    <Suspense fallback={<Box sx={{ minHeight: '50vh', display: 'grid', placeItems: 'center' }}><CircularProgress aria-label="Loading page" /></Box>}>
      {element}
    </Suspense>
  </RouteErrorBoundary>
);

export const router = createBrowserRouter([
  {
    path: '/login',
    element: lazyScreen(<LoginPage />),
  },
  {
    path: '/forgot-password',
    element: lazyScreen(<ForgotPasswordPage />),
  },
  {
    path: '/reset-password',
    element: lazyScreen(<ResetPasswordPage />),
  },
  {
    path: '/r/:token',
    element: lazyScreen(<PublicReportPage />),
  },
  {
    path: '/',
    element: <AppLayout />,
    children: [
      {
        index: true,
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_VIEW_DASHBOARD} fallback={<UnauthorizedPage />}>
            <DashboardPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'billing/new',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_CREATE_BILL} fallback={<UnauthorizedPage />}>
            <NewBillPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'billing',
        element: (
          <PermissionGuard anyPermissions={[PERMISSION_KEYS.CAN_CREATE_BILL, PERMISSION_KEYS.CAN_VIEW_FINANCIALS]} fallback={<UnauthorizedPage />}>
            <BillListPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'patients',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_EDIT_PATIENT} fallback={<UnauthorizedPage />}>
            <PatientsPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'samples',
        element: (
          <PermissionGuard anyPermissions={[PERMISSION_KEYS.CAN_COLLECT_SAMPLE, PERMISSION_KEYS.CAN_RECEIVE_SAMPLE, PERMISSION_KEYS.CAN_REJECT_SAMPLE]} fallback={<UnauthorizedPage />}>
            <SampleAccessioningPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'outsource',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_OUTSOURCE_TRACKING} fallback={<UnauthorizedPage />}>
            <OutsourceTrackingPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'worklist',
        element: (
          <PermissionGuard anyPermissions={[PERMISSION_KEYS.CAN_ENTER_RESULTS, PERMISSION_KEYS.CAN_VERIFY_RESULTS, PERMISSION_KEYS.CAN_SIGN_REPORTS]} fallback={<UnauthorizedPage />}>
            <WorklistPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'worklist/entry/:id',
        element: (
          <PermissionGuard anyPermissions={[PERMISSION_KEYS.CAN_ENTER_RESULTS, PERMISSION_KEYS.CAN_VERIFY_RESULTS, PERMISSION_KEYS.CAN_SIGN_REPORTS]} fallback={<UnauthorizedPage />}>
            <ResultEntryPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'worklist/order/:orderId',
        element: (
          <PermissionGuard anyPermissions={[PERMISSION_KEYS.CAN_ENTER_RESULTS, PERMISSION_KEYS.CAN_VERIFY_RESULTS, PERMISSION_KEYS.CAN_SIGN_REPORTS]} fallback={<UnauthorizedPage />}>
            <ResultEntryPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'reports',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_PRINT_REPORTS} fallback={<UnauthorizedPage />}>
            <ReportsPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'catalogue',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_CATALOGUE} fallback={<UnauthorizedPage />}>
            <CataloguePage />
          </PermissionGuard>
        ),
      },
      {
        path: 'personnel/doctors',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_REFERRING_DOCTORS} fallback={<UnauthorizedPage />}>
            <ReferringDoctorsPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'personnel/reporting',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_PERSONNEL} fallback={<UnauthorizedPage />}>
            <ReportingPersonnelPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'admin/hmis',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_VIEW_HMIS_REPORTS} fallback={<UnauthorizedPage />}>
            <HmisMonthlyReportPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'admin/users',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_USERS} fallback={<UnauthorizedPage />}>
            <UserManagementPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'admin/roles',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_ROLES} fallback={<UnauthorizedPage />}>
            <RolePermissionsPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'admin/sms',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_USERS} fallback={<UnauthorizedPage />}>
            <SmsDeliveryPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'admin/audit',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_VIEW_AUDIT_LOGS} fallback={<UnauthorizedPage />}>
            <AuditLogPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'settings',
        element: (
          <PermissionGuard permission={PERMISSION_KEYS.CAN_MANAGE_USERS} fallback={<UnauthorizedPage />}>
            <SettingsPage />
          </PermissionGuard>
        ),
      },
      {
        path: 'account/change-password',
        element: <ChangePasswordPage />,
      },
      {
        path: '*',
        element: <Navigate to="/" replace />,
      },
    ],
  },
]);
