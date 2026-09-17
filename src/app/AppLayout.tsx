/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Main Application Layout (Sidebar, Top Bar, Role Switcher, Permitted Nav)
 */

import React, { Suspense, useEffect, useState } from 'react';
import { Navigate, Outlet, useNavigate, useLocation, Link as RouterLink } from 'react-router-dom';
import { RouteErrorBoundary } from '@/components/common/RouteErrorBoundary';
import {
  Box,
  Drawer,
  AppBar,
  Toolbar,
  List,
  Typography,
  Divider,
  IconButton,
  ListItem,
  ListItemButton,
  ListItemIcon,
  ListItemText,
  Avatar,
  Menu,
  MenuItem,
  Chip,
  Button,
  useTheme,
  useMediaQuery,
  CircularProgress,
} from '@mui/material';
import MenuIcon from '@mui/icons-material/Menu';
import DashboardIcon from '@mui/icons-material/Dashboard';
import ReceiptLongIcon from '@mui/icons-material/ReceiptLong';
import AddShoppingCartIcon from '@mui/icons-material/AddShoppingCart';
import PeopleIcon from '@mui/icons-material/People';
import ScienceIcon from '@mui/icons-material/Science';
import AssignmentIcon from '@mui/icons-material/Assignment';
import DescriptionIcon from '@mui/icons-material/Description';
import BiotechIcon from '@mui/icons-material/Biotech';
import LocalHospitalIcon from '@mui/icons-material/LocalHospital';
import BadgeIcon from '@mui/icons-material/Badge';
import ManageAccountsIcon from '@mui/icons-material/ManageAccounts';
import SecurityIcon from '@mui/icons-material/Security';
import HistoryIcon from '@mui/icons-material/History';
import LogoutIcon from '@mui/icons-material/Logout';
import SendIcon from '@mui/icons-material/Send';
import PasswordIcon from '@mui/icons-material/Password';
import InstallDesktopIcon from '@mui/icons-material/InstallDesktop';
import AssessmentIcon from '@mui/icons-material/Assessment';

import { useAuth } from '@/hooks/useAuth';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { ORG_CONFIG } from '@/config/constants';

const DRAWER_WIDTH = 270;

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed'; platform: string }>;
}

interface NavItem {
  label: string;
  path: string;
  icon: React.ReactNode;
  permission?: string;
  anyPermissions?: string[];
  badge?: string;
}

export const AppLayout: React.FC = () => {
  const muiTheme = useTheme();
  const isMobile = useMediaQuery(muiTheme.breakpoints.down('md'));
  const [mobileOpen, setMobileOpen] = useState(false);
  const [userMenuAnchor, setUserMenuAnchor] = useState<null | HTMLElement>(null);
  const [installPrompt, setInstallPrompt] = useState<BeforeInstallPromptEvent | null>(null);

  const { user, profile, signOut, isConfigured, isLoading } = useAuth();
  const { can } = usePermissions();
  const location = useLocation();
  const navigate = useNavigate();
  const operationalRoleLabel = profile?.isSuperAdmin ? 'Super Admin' : 'Lab Technician';

  useEffect(() => {
    const captureInstallPrompt = (event: Event) => {
      event.preventDefault();
      setInstallPrompt(event as BeforeInstallPromptEvent);
    };
    const clearInstallPrompt = () => setInstallPrompt(null);

    window.addEventListener('beforeinstallprompt', captureInstallPrompt);
    window.addEventListener('appinstalled', clearInstallPrompt);
    return () => {
      window.removeEventListener('beforeinstallprompt', captureInstallPrompt);
      window.removeEventListener('appinstalled', clearInstallPrompt);
    };
  }, []);

  const handleInstall = async () => {
    if (!installPrompt) return;
    await installPrompt.prompt();
    await installPrompt.userChoice;
    setInstallPrompt(null);
  };

  if (isLoading) {
    return (
      <Box sx={{ minHeight: '100vh', display: 'grid', placeItems: 'center' }}>
        <CircularProgress aria-label="Restoring staff session" />
      </Box>
    );
  }

  if (!user || !profile?.isActive) {
    return <Navigate to="/login" replace state={{ from: location.pathname }} />;
  }

  const handleDrawerToggle = () => {
    setMobileOpen(!mobileOpen);
  };

  const navSections: Array<{ title: string; items: NavItem[] }> = [
    {
      title: 'Clinical Operations',
      items: [
        {
          label: 'Dashboard',
          path: '/',
          icon: <DashboardIcon />,
          permission: PERMISSION_KEYS.CAN_VIEW_DASHBOARD,
        },
        {
          label: 'New Bill / Booking',
          path: '/billing/new',
          icon: <AddShoppingCartIcon />,
          permission: PERMISSION_KEYS.CAN_CREATE_BILL,
        },
        {
          label: 'Sample Accessioning',
          path: '/samples',
          icon: <ScienceIcon />,
          anyPermissions: [PERMISSION_KEYS.CAN_COLLECT_SAMPLE, PERMISSION_KEYS.CAN_RECEIVE_SAMPLE, PERMISSION_KEYS.CAN_REJECT_SAMPLE],
        },
        {
          label: 'Lab Worklist & Results',
          path: '/worklist',
          icon: <AssignmentIcon />,
          anyPermissions: [PERMISSION_KEYS.CAN_ENTER_RESULTS, PERMISSION_KEYS.CAN_VERIFY_RESULTS, PERMISSION_KEYS.CAN_SIGN_REPORTS],
        },
        {
          label: 'Diagnostic Reports',
          path: '/reports',
          icon: <DescriptionIcon />,
          permission: PERMISSION_KEYS.CAN_PRINT_REPORTS,
        },
        {
          label: 'Bills & Invoices',
          path: '/billing',
          icon: <ReceiptLongIcon />,
          anyPermissions: [PERMISSION_KEYS.CAN_CREATE_BILL, PERMISSION_KEYS.CAN_VIEW_FINANCIALS],
        },
        {
          label: 'Patient Registry',
          path: '/patients',
          icon: <PeopleIcon />,
          permission: PERMISSION_KEYS.CAN_EDIT_PATIENT,
        },
        {
          label: 'Outsource Tracking',
          path: '/outsource',
          icon: <SendIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_OUTSOURCE_TRACKING,
        },
      ],
    },
    {
      title: 'Catalogue & Personnel',
      items: [
        {
          label: 'Test Catalogue',
          path: '/catalogue',
          icon: <BiotechIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_CATALOGUE,
        },
        {
          label: 'Referring Doctors',
          path: '/personnel/doctors',
          icon: <LocalHospitalIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_REFERRING_DOCTORS,
        },
        {
          label: 'Reporting Personnel',
          path: '/personnel/reporting',
          icon: <BadgeIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_PERSONNEL,
        },
      ],
    },
    {
      title: 'Administration',
      items: [
        {
          label: 'HMIS Monthly Report',
          path: '/admin/hmis',
          icon: <AssessmentIcon />,
          permission: PERMISSION_KEYS.CAN_VIEW_HMIS_REPORTS,
        },
        {
          label: 'User Management',
          path: '/admin/users',
          icon: <ManageAccountsIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_USERS,
        },
        {
          label: 'Roles & Permissions',
          path: '/admin/roles',
          icon: <SecurityIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_ROLES,
        },
        {
          label: 'SMS Delivery',
          path: '/admin/sms',
          icon: <HistoryIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_USERS,
        },
        {
          label: 'Audit Logs',
          path: '/admin/audit',
          icon: <HistoryIcon />,
          permission: PERMISSION_KEYS.CAN_VIEW_AUDIT_LOGS,
        },
        {
          label: 'Settings',
          path: '/settings',
          icon: <SecurityIcon />,
          permission: PERMISSION_KEYS.CAN_MANAGE_USERS,
        },
      ],
    },
  ];

  const drawerContent = (
    <Box sx={{ display: 'flex', flexDirection: 'column', height: '100%', bgcolor: 'var(--color-sidebar)', color: '#fff' }}>
      {/* Brand Header */}
      <Box sx={{ p: 2.5, display: 'flex', alignItems: 'center', gap: 1.5 }}>
        <Box
          component="img"
          src="/pathology-logo.png"
          alt="Bimal Pathology Logo"
          sx={{
            width: 48,
            height: 48,
            objectFit: 'contain',
            flexShrink: 0,
            borderRadius: 1,
            background: 'transparent',
          }}
        />
        <Box>
          <Typography variant="subtitle2" fontWeight={800} sx={{ color: '#fff', lineHeight: 1.15, fontSize: '0.85rem' }}>
            {ORG_CONFIG.nameEn}
          </Typography>
          <Typography variant="caption" sx={{ color: 'var(--color-sidebar-muted)', fontSize: '0.725rem' }}>
            {ORG_CONFIG.nameNp}
          </Typography>
        </Box>
      </Box>

      <Divider sx={{ borderColor: 'rgba(255, 255, 255, 0.12)' }} />

      {/* Navigation List */}
      <Box sx={{ flexGrow: 1, overflowY: 'auto', px: 1.5, py: 1.5 }}>
        {navSections.map((section) => {
          const visibleItems = section.items.filter(
            (item) => (!item.permission || can(item.permission as any))
              && (!item.anyPermissions || item.anyPermissions.some((permission) => can(permission as any)))
          );

          if (visibleItems.length === 0) return null;

          return (
            <Box key={section.title} sx={{ mb: 2 }}>
              <Typography
                variant="caption"
                sx={{
                  px: 1.5,
                  py: 0.5,
                  display: 'block',
                  color: 'var(--color-sidebar-section)',
                  fontWeight: 700,
                  textTransform: 'uppercase',
                  letterSpacing: '0.05em',
                  fontSize: '0.675rem',
                }}
              >
                {section.title}
              </Typography>
              <List dense disablePadding>
                {visibleItems.map((item) => {
                  const isSelected = item.path === '/'
                    ? location.pathname === '/'
                    : item.path === '/billing'
                      ? location.pathname === '/billing'
                      : location.pathname.startsWith(item.path);

                  return (
                    <ListItem key={item.path} disablePadding sx={{ mb: 0.5 }}>
                      <ListItemButton
                        component={RouterLink}
                        to={item.path}
                        onClick={() => isMobile && setMobileOpen(false)}
                        selected={isSelected}
                        sx={{
                          borderRadius: 2,
                          color: 'var(--color-sidebar-text)',
                          bgcolor: isSelected ? 'var(--color-sidebar-active) !important' : 'transparent',
                          borderLeft: isSelected ? '4px solid #70f0a8' : '4px solid transparent',
                          opacity: 1,
                          '&:hover': {
                            bgcolor: 'var(--color-sidebar-hover)',
                            color: '#ffffff',
                          },
                          py: 0.8,
                        }}
                      >
                        <ListItemIcon
                          sx={{
                            color: isSelected ? '#d7ffe8' : '#a9e8c5',
                            opacity: 1,
                            '& .MuiSvgIcon-root': { fontSize: 20 },
                            minWidth: 36,
                          }}
                        >
                          {item.icon}
                        </ListItemIcon>
                        <ListItemText
                          primary={item.label}
                          primaryTypographyProps={{
                            fontSize: '0.825rem',
                            fontWeight: isSelected ? 600 : 500,
                          }}
                        />
                      </ListItemButton>
                    </ListItem>
                  );
                })}
              </List>
            </Box>
          );
        })}
      </Box>

      <Divider sx={{ borderColor: 'rgba(255, 255, 255, 0.12)' }} />

      {/* Footer Info */}
      <Box sx={{ p: 2, bgcolor: 'rgba(0, 0, 0, 0.2)' }}>
        <Typography variant="caption" sx={{ display: 'block', color: '#d6f2e2', fontSize: '0.7rem' }}>
          Reg: {ORG_CONFIG.regNo} | PAN: {ORG_CONFIG.panNo}
        </Typography>
        <Typography variant="caption" sx={{ display: 'block', color: 'var(--color-sidebar-muted)', fontSize: '0.675rem' }}>
          Phone: {ORG_CONFIG.phone}
        </Typography>
      </Box>
    </Box>
  );

  return (
    <Box sx={{ display: 'flex', minHeight: '100vh', bgcolor: 'background.default' }}>
      {/* Top Navigation Bar */}
      <AppBar
        position="fixed"
        elevation={0}
        sx={{
          width: { md: `calc(100% - ${DRAWER_WIDTH}px)` },
          ml: { md: `${DRAWER_WIDTH}px` },
          bgcolor: 'rgba(255,255,255,0.97)',
          color: 'text.primary',
          borderBottom: '1px solid var(--color-border)',
          boxShadow: '0 1px 5px rgba(20, 33, 61, 0.05)',
        }}
      >
        <Toolbar sx={{ minHeight: '64px !important', px: { xs: 2, sm: 3 } }}>
          <IconButton
            aria-label="Open navigation"
            color="inherit"
            edge="start"
            onClick={handleDrawerToggle}
            sx={{ mr: 2, display: { md: 'none' } }}
          >
            <MenuIcon />
          </IconButton>

          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5, flexGrow: 1 }}>
            <Typography variant="h6" fontWeight={700} color="primary.main" sx={{ display: { xs: 'none', sm: 'block' } }}>
              Cloud LIS
            </Typography>
            <Chip
              size="small"
              label={isConfigured ? 'Live Cloud' : 'Configuration Required'}
              color={isConfigured ? 'success' : 'error'}
              variant="outlined"
              sx={{ height: 22, fontSize: '0.7rem', fontWeight: 600 }}
            />
          </Box>

          {installPrompt && (
            <Button
              variant="outlined"
              color="primary"
              size="small"
              startIcon={<InstallDesktopIcon />}
              onClick={() => void handleInstall()}
              sx={{ mr: 1.5, display: { xs: 'none', sm: 'inline-flex' } }}
            >
              Install App
            </Button>
          )}

          {/* Real User Profile / Session */}
          {profile ? (
            <Box sx={{ display: 'flex', alignItems: 'center', gap: 1.5 }}>
              <Chip
                icon={<SecurityIcon />}
                label={operationalRoleLabel}
                color={profile.isSuperAdmin ? 'primary' : 'secondary'}
                size="small"
                sx={{ fontWeight: 600 }}
              />
              <IconButton aria-label="Open user menu" onClick={(e) => setUserMenuAnchor(e.currentTarget)} size="small">
                <Avatar sx={{ width: 34, height: 34, bgcolor: 'primary.main', border: '2px solid #b7e4c7', fontSize: '0.85rem' }}>
                  {profile.fullName?.charAt(0) || 'U'}
                </Avatar>
              </IconButton>
              <Menu
                anchorEl={userMenuAnchor}
                open={Boolean(userMenuAnchor)}
                onClose={() => setUserMenuAnchor(null)}
              >
                <Box sx={{ px: 2, py: 1 }}>
                  <Typography variant="subtitle2" fontWeight={700}>
                    {profile.fullName}
                  </Typography>
                  <Typography variant="caption" color="text.secondary">
                    {operationalRoleLabel}
                  </Typography>
                </Box>
                <Divider />
                <MenuItem onClick={() => { setUserMenuAnchor(null); navigate('/account/change-password'); }}>
                  <ListItemIcon><PasswordIcon fontSize="small" /></ListItemIcon>
                  <Typography>Change Password</Typography>
                </MenuItem>
                <MenuItem onClick={() => { setUserMenuAnchor(null); signOut(); navigate('/login'); }}>
                  <ListItemIcon><LogoutIcon fontSize="small" color="error" /></ListItemIcon>
                  <Typography color="error">Sign Out</Typography>
                </MenuItem>
              </Menu>
            </Box>
          ) : (
            <Button
              variant="contained"
              color="primary"
              size="small"
              onClick={() => navigate('/login')}
              sx={{ textTransform: 'none', fontWeight: 600 }}
            >
              Sign In
            </Button>
          )}
        </Toolbar>
      </AppBar>

      {/* Left Navigation Drawer */}
      <Box
        component="nav"
        sx={{ width: { md: DRAWER_WIDTH }, flexShrink: { md: 0 } }}
      >
        {/* Mobile Drawer */}
        <Drawer
          variant="temporary"
          open={mobileOpen}
          onClose={handleDrawerToggle}
          ModalProps={{ keepMounted: true }}
          sx={{
            display: { xs: 'block', md: 'none' },
            '& .MuiDrawer-paper': { boxSizing: 'border-box', width: DRAWER_WIDTH },
          }}
        >
          {drawerContent}
        </Drawer>

        {/* Desktop Permanent Drawer */}
        <Drawer
          variant="permanent"
          sx={{
            display: { xs: 'none', md: 'block' },
            '& .MuiDrawer-paper': { boxSizing: 'border-box', width: DRAWER_WIDTH, borderRight: 'none' },
          }}
          open
        >
          {drawerContent}
        </Drawer>
      </Box>

      {/* Main Content Area */}
      <Box
        component="main"
        sx={{
          flexGrow: 1,
          p: { xs: 2, sm: 2.5, md: 3 },
          width: { md: `calc(100% - ${DRAWER_WIDTH}px)` },
          mt: '64px',
          minHeight: 'calc(100vh - 64px)',
        }}
      >
        <RouteErrorBoundary>
          <Suspense fallback={<Box sx={{ minHeight: '50vh', display: 'grid', placeItems: 'center' }}><CircularProgress aria-label="Loading page" /></Box>}>
            <Outlet />
          </Suspense>
        </RouteErrorBoundary>
      </Box>
    </Box>
  );
};
