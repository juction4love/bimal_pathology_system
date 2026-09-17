/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Live Real-Time Laboratory Dashboard (Phase 5)
 * Aggregates live PostgreSQL data for clinical pipeline, critical alerts, and finances
 */

import React, { useState, useEffect, useCallback } from 'react';
import {
  Grid,
  Card,
  CardContent,
  Typography,
  Box,
  Button,
  Table,
  TableBody,
  TableCell,
  TableContainer,
  TableHead,
  TableRow,
  Paper,
  Alert,
  LinearProgress,
  CircularProgress,
  IconButton,
} from '@mui/material';
import PeopleAltIcon from '@mui/icons-material/PeopleAlt';
import ReceiptIcon from '@mui/icons-material/Receipt';
import AttachMoneyIcon from '@mui/icons-material/AttachMoney';
import WarningAmberIcon from '@mui/icons-material/WarningAmber';
import ScienceIcon from '@mui/icons-material/Science';
import PendingActionsIcon from '@mui/icons-material/PendingActions';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import VerifiedIcon from '@mui/icons-material/Verified';
import AddShoppingCartIcon from '@mui/icons-material/AddShoppingCart';
import WarningIcon from '@mui/icons-material/Warning';
import BlockIcon from '@mui/icons-material/Block';
import RefreshIcon from '@mui/icons-material/Refresh';

import { PageHeader } from '@/components/common/PageHeader';
import { MoneyDisplay } from '@/components/common/MoneyDisplay';
import { StatusChip } from '@/components/common/StatusChip';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { getNepalTodayAd } from '@/lib/dateTime';
import { TechnicianDashboard } from './TechnicianDashboard';
import { PatientOrderWorklist } from './PatientOrderWorklist';
import { subscribeWorkflowInvalidation } from '@/lib/workflowInvalidation';

interface MetricCardProps {
  title: string;
  value: React.ReactNode;
  icon: React.ReactNode;
  color?: string;
  subtext?: string;
  onClick?: () => void;
}

const MetricCard: React.FC<MetricCardProps> = ({ title, value, icon, color = 'primary.main', subtext, onClick }) => (
  <Card
    role={onClick ? 'button' : undefined}
    tabIndex={onClick ? 0 : undefined}
    aria-label={onClick ? `Open ${title}` : undefined}
    sx={{
      height: '100%',
      cursor: onClick ? 'pointer' : 'default',
      transition: 'transform 0.15s ease, box-shadow 0.15s ease',
      '&:hover': onClick ? { transform: 'translateY(-2px)', boxShadow: 3 } : {},
      '&:focus-visible': onClick ? { outline: '3px solid var(--color-focus)', outlineOffset: 2 } : {},
    }}
    onClick={onClick}
    onKeyDown={(event) => {
      if (onClick && (event.key === 'Enter' || event.key === ' ')) {
        event.preventDefault();
        onClick();
      }
    }}
  >
    <CardContent sx={{ p: 2.5 }}>
      <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <Box>
          <Typography variant="caption" fontWeight={600} color="text.secondary" sx={{ textTransform: 'uppercase' }}>
            {title}
          </Typography>
          <Typography variant="h4" fontWeight={700} sx={{ my: 0.5, color: 'text.primary' }}>
            {value}
          </Typography>
          {subtext && (
            <Typography variant="caption" color="text.secondary">
              {subtext}
            </Typography>
          )}
        </Box>
        <Box
          sx={{
            p: 1.25,
            borderRadius: 2,
            bgcolor: `color-mix(in srgb, ${color} 11%, white)`,
            color: color,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {icon}
        </Box>
      </Box>
    </CardContent>
  </Card>
);

export const DashboardPage: React.FC = () => {
  const { can } = usePermissions();
  const navigate = useNavigate();
  const canFinancials = can(PERMISSION_KEYS.CAN_VIEW_FINANCIALS);
  const isAdmin = can(PERMISSION_KEYS.CAN_MANAGE_USERS);

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  // Live Metrics State
  const [metrics, setMetrics] = useState({
    todayPatients: 0,
    todayBills: 0,
    todayRevenuePaisa: 0,
    outstandingDuePaisa: 0,
    pendingSamples: 0,
    receivedSamples: 0,
    pendingResults: 0,
    awaitingVerification: 0,
    signedReports: 0,
    signedReportsToday: 0,
    totalSignedReports: 0,
    rejectedSamples: 0,
    criticalUnackCount: 0,
  });

  const [criticalItems, setCriticalItems] = useState<any[]>([]);
  const [recentOrders, setRecentOrders] = useState<any[]>([]);
  const [departmentWorkload, setDepartmentWorkload] = useState<Array<{ dept: string; count: number; max: number; color: string }>>([]);

  const loadDashboardData = useCallback(async () => {
    // Technicians render the separate operational-only dashboard below. Do not
    // issue the Admin financial-summary RPC in the background for that role.
    if (!isAdmin) return;

    setLoading(true);
    setError(null);

    try {
      const { data: summary, error: summaryError } = await supabase.rpc('get_dashboard_operational_summary');
      if (summaryError) throw summaryError;

      // 7. Fetch Unacknowledged Critical Results
      const { data: critData } = await supabase
        .from('test_results')
        .select(`
          id,
          parameter_name,
          display_value,
          flag,
          order_item:clinical_order_items(
            id,
            test_name,
            order:clinical_orders(
              order_number,
              patient:patients(uhid, full_name)
            )
          )
        `)
        .eq('is_critical', true)
        .eq('critical_acknowledged', false)
        .limit(5);

      setCriticalItems(critData || []);

      // 8. Fetch Recent Clinical Orders
      const { data: ordersData } = await supabase
        .from('clinical_orders')
        .select(`
          id,
          order_number,
          status,
          created_at,
          patient:patients(uhid, full_name, age_years, gender),
          bill:bills(net_amount_paisa),
          items:clinical_order_items(
            id,
            test_name,
            department,
            status,
            test:tests(code, validation_status, clinical_reporting_enabled)
          )
        `)
        .order('created_at', { ascending: false })
        .limit(5);

      setRecentOrders(ordersData || []);

      const colors = ['var(--color-info)', 'var(--color-primary)', 'var(--color-verification)', 'var(--color-success)', 'var(--color-warning)'];
      const workload = Array.isArray(summary?.department_workload) ? summary.department_workload : [];
      const maxCount = Math.max(10, ...workload.map((item: any) => Number(item.count) || 0));
      const formattedDept = workload.map((item: any, idx: number) => ({
        dept: String(item.dept),
        count: Number(item.count) || 0,
        max: maxCount,
        color: colors[idx % colors.length],
      }));
      setDepartmentWorkload(formattedDept);

      const signedToday = Number(summary?.signed_reports_today ?? summary?.signed_reports) || 0;
      const totalSigned = Number(summary?.total_signed_reports ?? summary?.signed_reports) || 0;

      setMetrics({
        todayPatients: Number(summary?.today_patients) || 0,
        todayBills: Number(summary?.today_invoices) || 0,
        todayRevenuePaisa: Number(summary?.today_collection_paisa) || 0,
        outstandingDuePaisa: Number(summary?.outstanding_due_paisa) || 0,
        pendingSamples: Number(summary?.pending_samples) || 0,
        receivedSamples: Number(summary?.received_samples) || 0,
        pendingResults: Number(summary?.pending_results) || 0,
        awaitingVerification: Number(summary?.awaiting_verification) || 0,
        signedReports: signedToday,
        signedReportsToday: signedToday,
        totalSignedReports: totalSigned,
        rejectedSamples: Number(summary?.rejected_samples) || 0,
        criticalUnackCount: Number(summary?.critical_unacknowledged) || 0,
      });
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load live dashboard statistics.'));
    } finally {
      setLoading(false);
    }
  }, [isAdmin]);

  useEffect(() => {
    if (isAdmin) void loadDashboardData();
  }, [isAdmin, loadDashboardData]);
  useEffect(()=>subscribeWorkflowInvalidation('dashboard',()=>{if(isAdmin)void loadDashboardData()}),[isAdmin,loadDashboardData]);

  // Lab Technicians see their own operational-only dashboard (no revenue figures)
  if (!isAdmin) {
    return <TechnicianDashboard />;
  }

  return (
    <Box>
      <PageHeader
        title="Laboratory Operations Dashboard"
        subtitle="Real-time clinical pipeline, critical alerts, and revenue performance"
        action={
          <Box sx={{ display: 'flex', gap: 1 }}>
            <IconButton aria-label="Refresh dashboard" onClick={loadDashboardData} disabled={loading} color="primary">
              <RefreshIcon />
            </IconButton>
            {can(PERMISSION_KEYS.CAN_CREATE_BILL) && (
              <Button
                variant="contained"
                color="primary"
                startIcon={<AddShoppingCartIcon />}
                onClick={() => navigate('/billing/new')}
              >
                New Bill / Booking
              </Button>
            )}
          </Box>
        }
      />

      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      {/* Critical Alert Banner if any critical values awaiting acknowledgement */}
      {metrics.criticalUnackCount > 0 && (
        <Alert
          severity="error"
          icon={<WarningIcon fontSize="inherit" />}
          action={
            <Button color="inherit" size="small" onClick={() => navigate('/worklist')}>
              View Worklist
            </Button>
          }
          sx={{ mb: 3, fontWeight: 500 }}
        >
          <strong>{metrics.criticalUnackCount} Critical Panic Results Pending Acknowledgment:</strong> Immediate clinician notification required.
          {criticalItems.length > 0 && (
            <span> ({criticalItems[0].order_item?.order?.patient?.full_name} - {criticalItems[0].parameter_name}: {criticalItems[0].display_value})</span>
          )}
        </Alert>
      )}

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', p: 6 }}>
          <CircularProgress />
        </Box>
      ) : (
        <>
          {/* Primary Operational Metrics */}
          <Grid container spacing={2.5} sx={{ mb: 3 }}>
            <Grid item xs={12} sm={6} md={3}>
              <MetricCard
                title="Today's Patients"
                value={metrics.todayPatients}
                icon={<PeopleAltIcon />}
                color="var(--color-info)"
                subtext="Registered today"
                onClick={() => navigate(`/patients?date=${getNepalTodayAd()}`)}
              />
            </Grid>
            <Grid item xs={12} sm={6} md={3}>
              <MetricCard
                title="Today's Invoices"
                value={metrics.todayBills}
                icon={<ReceiptIcon />}
                color="var(--color-primary)"
                subtext="Lab bookings"
                onClick={() => navigate(`/billing?date=${getNepalTodayAd()}`)}
              />
            </Grid>
            {canFinancials && (
              <>
                <Grid item xs={12} sm={6} md={3}>
                  <MetricCard
                    title="Today's Collections"
                    value={<MoneyDisplay paisa={metrics.todayRevenuePaisa} />}
                    icon={<AttachMoneyIcon />}
                    color="var(--color-success)"
                    subtext="Payments received today (by receipt time)"
                  />
                </Grid>
                <Grid item xs={12} sm={6} md={3}>
                  <MetricCard
                    title="Outstanding Due"
                    value={<MoneyDisplay paisa={metrics.outstandingDuePaisa} highlightDue />}
                    icon={<WarningAmberIcon />}
                    color="var(--color-danger)"
                    subtext="Unsettled balance"
                  />
                </Grid>
              </>
            )}
          </Grid>

          {/* Laboratory Pipeline Metrics */}
          <Grid container spacing={2.5} sx={{ mb: 3 }}>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Pending Samples"
                value={metrics.pendingSamples}
                icon={<ScienceIcon />}
                color="var(--color-secondary)"
                onClick={() => navigate('/samples?status=Pending')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Pending Results"
                value={metrics.pendingResults}
                icon={<PendingActionsIcon />}
                color="var(--color-warning)"
                onClick={() => navigate('/worklist?view=Pending')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Awaiting Verification"
                value={metrics.awaitingVerification}
                icon={<FactCheckIcon />}
                color="var(--color-verification)"
                onClick={() => navigate('/worklist?view=ToVerify')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Signed Reports Today"
                value={metrics.signedReportsToday}
                icon={<VerifiedIcon />}
                color="var(--color-success)"
                subtext={`All-Time Total: ${metrics.totalSignedReports}`}
                onClick={() => navigate(`/reports?status=SignedOff&date=${getNepalTodayAd()}`)}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Rejected Samples"
                value={metrics.rejectedSamples}
                icon={<BlockIcon />}
                color="var(--color-danger)"
                onClick={() => navigate('/samples?status=Rejected')}
              />
            </Grid>
          </Grid>

          {/* Detailed Workload and Recent Orders */}
          <Grid container spacing={3}>
            {/* Department Workload Breakdown */}
            <Grid item xs={12} md={5}>
              <Card sx={{ height: '100%' }}>
                <CardContent>
                  <Typography variant="h6" fontWeight={700} gutterBottom>
                    Department Active Workload
                  </Typography>
                  <Typography variant="caption" color="text.secondary" sx={{ display: 'block', mb: 2 }}>
                    Active tests currently in laboratory workflow
                  </Typography>

                  {departmentWorkload.map((item) => (
                    <Box key={item.dept} sx={{ mb: 2 }}>
                      <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
                        <Typography variant="body2" fontWeight={600}>
                          {item.dept}
                        </Typography>
                        <Typography variant="body2" color="text.secondary">
                          {item.count} tests
                        </Typography>
                      </Box>
                      <LinearProgress
                        variant="determinate"
                        value={(item.count / item.max) * 100}
                        sx={{
                          height: 8,
                          borderRadius: 4,
                          bgcolor: 'var(--color-surface-alt)',
                          '& .MuiLinearProgress-bar': { bgcolor: item.color, borderRadius: 4 },
                        }}
                      />
                    </Box>
                  ))}
                </CardContent>
              </Card>
            </Grid>

            {/* Recent Orders List */}
            <Grid item xs={12} md={7}>
              <Card sx={{ height: '100%' }}>
                <CardContent>
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', mb: 2 }}>
                    <Typography variant="h6" fontWeight={700}>
                      Recent Patient Orders
                    </Typography>
                  </Box>

                  <TableContainer component={Paper} elevation={0} sx={{ border: '1px solid #e2e8f0' }}>
                    <Table size="small">
                      <TableHead>
                        <TableRow>
                          <TableCell>Lab No / UHID</TableCell>
                          <TableCell>Patient Name</TableCell>
                          <TableCell>Investigations</TableCell>
                          <TableCell>Status</TableCell>
                          <TableCell align="right">Amount</TableCell>
                        </TableRow>
                      </TableHead>
                      <TableBody>
                        {recentOrders.length === 0 ? (
                          <TableRow>
                            <TableCell colSpan={5} align="center" sx={{ py: 3, color: 'text.secondary' }}>
                              No orders registered yet today.
                            </TableCell>
                          </TableRow>
                        ) : (
                          recentOrders.map((row) => {
                            const pName = row.patient?.full_name || 'Patient';
                            const pUhid = row.patient?.uhid || '-';
                            const pAgeGen = `${row.patient?.age_years != null ? `${row.patient.age_years}Y` : '-'} / ${row.patient?.gender || '-'}`;
                            const testsList = (row.items || []).map((i: any) => i.test_name).join(', ') || '-';
                            const amountPaisa = row.bill?.net_amount_paisa || 0;

                            return (
                              <TableRow key={row.id} hover>
                                <TableCell>
                                  <Typography variant="body2" fontWeight={600} color="primary.main">
                                    {row.order_number}
                                  </Typography>
                                  <Typography variant="caption" color="text.secondary">
                                    {pUhid}
                                  </Typography>
                                </TableCell>
                                <TableCell>
                                  <Typography variant="body2" fontWeight={600}>
                                    {pName}
                                  </Typography>
                                  <Typography variant="caption" color="text.secondary">
                                    {pAgeGen}
                                  </Typography>
                                </TableCell>
                                <TableCell>
                                  <Typography variant="body2" color="text.secondary" sx={{ maxWidth: 180 }} noWrap>
                                    {testsList}
                                  </Typography>
                                </TableCell>
                                <TableCell>
                                  <StatusChip status={row.status} />
                                </TableCell>
                                <TableCell align="right">
                                  <MoneyDisplay paisa={amountPaisa} />
                                </TableCell>
                              </TableRow>
                            );
                          })
                        )}
                      </TableBody>
                    </Table>
                  </TableContainer>
                </CardContent>
              </Card>
            </Grid>
          </Grid>

          <PatientOrderWorklist />
        </>
      )}
    </Box>
  );
};
