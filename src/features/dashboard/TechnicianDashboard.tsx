/**
 * BIMAL PATHOLOGY & DIAGNOSTIC CENTER
 * Lab Technician Operational Dashboard
 * Operational-only view: patients, samples, results, and workload.
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
  Chip,
  Divider,
} from '@mui/material';
import PeopleAltIcon from '@mui/icons-material/PeopleAlt';
import ScienceIcon from '@mui/icons-material/Science';
import PendingActionsIcon from '@mui/icons-material/PendingActions';
import FactCheckIcon from '@mui/icons-material/FactCheck';
import VerifiedIcon from '@mui/icons-material/Verified';
import WarningIcon from '@mui/icons-material/Warning';
import BlockIcon from '@mui/icons-material/Block';
import RefreshIcon from '@mui/icons-material/Refresh';
import CheckCircleOutlineIcon from '@mui/icons-material/CheckCircleOutline';
import AssignmentIcon from '@mui/icons-material/Assignment';
import AddShoppingCartIcon from '@mui/icons-material/AddShoppingCart';
import SearchIcon from '@mui/icons-material/Search';
import DescriptionIcon from '@mui/icons-material/Description';

import { PageHeader } from '@/components/common/PageHeader';
import { StatusChip } from '@/components/common/StatusChip';
import { usePermissions } from '@/hooks/usePermissions';
import { PERMISSION_KEYS } from '@/types/permissions';
import { PatientOrderWorklist } from './PatientOrderWorklist';
import { useNavigate } from 'react-router-dom';
import { supabase } from '@/lib/supabase';
import { safeErrorMessage } from '@/lib/safeError';
import { SmartMessageDialog } from '@/components/common/SmartMessageDialog';
import { formatAdDate, formatAdDateTime, getNepalTodayAd } from '@/lib/dateTime';

// ─── Metric Card ───────────────────────────────────────────────────────────────

interface MetricCardProps {
  title: string;
  value: React.ReactNode;
  icon: React.ReactNode;
  color?: string;
  subtext?: string;
  urgent?: boolean;
  onClick?: () => void;
}

const MetricCard: React.FC<MetricCardProps> = ({
  title, value, icon, color = 'primary.main', subtext, urgent, onClick,
}) => (
  <Card
    role={onClick ? 'button' : undefined}
    tabIndex={onClick ? 0 : undefined}
    aria-label={onClick ? `Open ${title}` : undefined}
    sx={{
      height: '100%',
      cursor: onClick ? 'pointer' : 'default',
      transition: 'transform 0.15s ease, box-shadow 0.15s ease',
      border: urgent ? '1.5px solid #fca5a5' : '1px solid transparent',
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
          <Typography variant="caption" fontWeight={600} color="text.secondary" sx={{ textTransform: 'uppercase', letterSpacing: '0.04em' }}>
            {title}
          </Typography>
          <Typography variant="h4" fontWeight={700} sx={{ my: 0.5, color: urgent ? 'error.main' : 'text.primary' }}>
            {value}
          </Typography>
          {subtext && (
            <Typography variant="caption" color="text.secondary">{subtext}</Typography>
          )}
        </Box>
        <Box
          sx={{
            p: 1.25,
            borderRadius: 2,
            bgcolor: `color-mix(in srgb, ${color} 11%, white)`,
            color,
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

// ─── Department Bar ─────────────────────────────────────────────────────────────

interface DeptBarProps {
  dept: string;
  count: number;
  max: number;
  color: string;
}

const DeptBar: React.FC<DeptBarProps> = ({ dept, count, max, color }) => (
  <Box sx={{ mb: 1.5 }}>
    <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 0.5 }}>
      <Typography variant="body2" fontWeight={500}>{dept}</Typography>
      <Typography variant="body2" fontWeight={700} color={color}>{count}</Typography>
    </Box>
    <LinearProgress
      variant="determinate"
      value={max > 0 ? Math.min((count / max) * 100, 100) : 0}
      sx={{
        height: 7,
        borderRadius: 4,
        bgcolor: `color-mix(in srgb, ${color} 15%, white)`,
        '& .MuiLinearProgress-bar': { bgcolor: color, borderRadius: 4 },
      }}
    />
  </Box>
);

// ─── Main Component ─────────────────────────────────────────────────────────────

export const TechnicianDashboard: React.FC = () => {
  const { can } = usePermissions();
  const navigate = useNavigate();

  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [metrics, setMetrics] = useState({
    todayPatients: 0,
    todayOrders: 0,
    pendingSamples: 0,
    receivedSamples: 0,
    pendingResults: 0,
    resultEntryPending: 0,
    specialistPending: 0,
    awaitingVerification: 0,
    signedReports: 0,
    rejectedSamples: 0,
    criticalUnackCount: 0,
  });

  const [recentOrders, setRecentOrders] = useState<any[]>([]);
  const [departmentWorkload, setDepartmentWorkload] = useState<DeptBarProps[]>([]);
  const [criticalItems, setCriticalItems] = useState<any[]>([]);

  const loadData = useCallback(async () => {
    setLoading(true);
    setError(null);

    try {
      const {data:summary,error:summaryError}=await supabase.rpc('get_technician_operational_summary');
      if(summaryError)throw summaryError;
      const critData=summary?.critical_items||[]; const ordersData=(summary?.recent_orders||[]).map((item:any)=>({...item,patient:{uhid:item.uhid,full_name:item.full_name,age_years:item.age_years,gender:item.gender},items:[]}));
      setCriticalItems(critData); setRecentOrders(ordersData);

      const colors = ['var(--color-info)', 'var(--color-primary)', 'var(--color-verification)', 'var(--color-success)', 'var(--color-warning)'];
      const deptCounts=Object.fromEntries((summary?.department_workload||[]).map((item:any)=>[item.department,Number(item.count)]));
      const maxCount = Math.max(1, ...Object.values(deptCounts) as number[]);
      setDepartmentWorkload(
        Object.entries(deptCounts).map(([dept, count], idx) => ({
          dept, count, max: maxCount, color: colors[idx % colors.length],
        }))
      );

      setMetrics({
        todayPatients: Number(summary?.today_patients)||0,
        todayOrders: Number(summary?.today_orders)||0,
        pendingSamples: Number(summary?.samples_pending)||0,
        receivedSamples: Number(summary?.samples_received)||0,
        rejectedSamples: Number(summary?.samples_rejected)||0,
        pendingResults: Number(summary?.worklist_pending)||0,
        resultEntryPending: Number(summary?.result_entry_pending)||0,
        specialistPending: Number(summary?.specialist_microbiology_pending)||0,
        awaitingVerification: Number(summary?.awaiting_verification)||0,
        signedReports: Number(summary?.signed_reports_today)||0,
        criticalUnackCount: Number(summary?.critical_unacknowledged)||0,
      });
    } catch (err: any) {
      setError(safeErrorMessage(err, 'Failed to load operational data.'));
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    loadData();
  }, [loadData]);

  return (
    <Box>
      <PageHeader
        title="Lab Operations Dashboard"
        subtitle={`Today's Operational Overview — ${formatAdDate(new Date())}`}
        action={
          <Box sx={{ display: 'flex', gap: 1, flexWrap: 'wrap', alignItems: 'center' }}>
            <Button
              variant="contained"
              color="primary"
              size="small"
              startIcon={<AddShoppingCartIcon />}
              onClick={() => navigate('/billing/new')}
              sx={{ fontWeight: 700 }}
            >
              + New Bill
            </Button>
            <Button
              variant="outlined"
              size="small"
              startIcon={<SearchIcon />}
              onClick={() => navigate('/patients')}
            >
              Search Patient
            </Button>
            <Button
              variant="outlined"
              size="small"
              startIcon={<AssignmentIcon />}
              onClick={() => navigate('/worklist')}
            >
              Open Worklist
            </Button>
            <Button
              variant="outlined"
              size="small"
              startIcon={<DescriptionIcon />}
              onClick={() => navigate('/reports')}
            >
              Open Reports
            </Button>
            <IconButton aria-label="Refresh dashboard" onClick={loadData} disabled={loading} color="primary" title="Refresh">
              <RefreshIcon />
            </IconButton>
          </Box>
        }
      />

      {/* Error */}
      <SmartMessageDialog open={Boolean(error)} message={error || ''} onPrimary={() => setError(null)} />

      {/* Critical Panic Banner */}
      {metrics.criticalUnackCount > 0 && (
        <Alert
          severity="error"
          icon={<WarningIcon fontSize="inherit" />}
          action={
            <Button color="inherit" size="small" onClick={() => navigate('/worklist')}>
              Go to Worklist
            </Button>
          }
          sx={{ mb: 3, fontWeight: 500 }}
        >
          <strong>{metrics.criticalUnackCount} Critical Panic Value{metrics.criticalUnackCount > 1 ? 's' : ''} Pending Acknowledgment</strong>
          {criticalItems.length > 0 && (
            <span> — {criticalItems[0].order_item?.order?.patient?.full_name}: {criticalItems[0].parameter_name} = {criticalItems[0].display_value}</span>
          )}
        </Alert>
      )}

      {loading ? (
        <Box sx={{ display: 'flex', justifyContent: 'center', p: 6 }}>
          <CircularProgress />
        </Box>
      ) : (
        <>
          {/* ================================================================ */}
          {/* ROW 1 — TODAY'S ACTIVITY (2 cards)                               */}
          {/* ================================================================ */}
          <Typography variant="overline" color="text.secondary" fontWeight={700} sx={{ mb: 1.5, display: 'block', letterSpacing: '0.08em' }}>
            Today's Activity
          </Typography>
          <Grid container spacing={2.5} sx={{ mb: 3 }}>
            <Grid item xs={12} sm={6}>
              <MetricCard
                title="Today's Patients"
                value={metrics.todayPatients}
                icon={<PeopleAltIcon />}
                color="var(--color-info)"
                subtext="New registrations today"
                onClick={() => navigate(`/patients?date=${getNepalTodayAd()}`)}
              />
            </Grid>
            <Grid item xs={12} sm={6}>
              <MetricCard
                title="Today's Lab Registrations"
                value={metrics.todayOrders}
                icon={<AssignmentIcon />}
                color="var(--color-verification)"
                subtext="Clinical orders registered today"
                onClick={() => navigate('/worklist')}
              />
            </Grid>
          </Grid>

          {/* ================================================================ */}
          {/* ROW 2 — PIPELINE STATUS (5 cards)                                */}
          {/* ================================================================ */}
          <Typography variant="overline" color="text.secondary" fontWeight={700} sx={{ mb: 1.5, display: 'block', letterSpacing: '0.08em' }}>
            Laboratory Pipeline
          </Typography>
          <Grid container spacing={2.5} sx={{ mb: 3 }}>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Pending Samples"
                value={metrics.pendingSamples}
                icon={<ScienceIcon />}
                color="var(--color-secondary)"
                subtext={`${metrics.receivedSamples} received`}
                urgent={metrics.pendingSamples > 5}
                onClick={() => navigate('/samples?status=Pending')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Pending Results"
                value={metrics.pendingResults}
                icon={<PendingActionsIcon />}
                color="var(--color-warning)"
                subtext={`${metrics.resultEntryPending} ready for entry · ${metrics.specialistPending} microbiology`}
                onClick={() => navigate('/worklist?view=Pending')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Awaiting Verification"
                value={metrics.awaitingVerification}
                icon={<FactCheckIcon />}
                color="var(--color-verification)"
                subtext="Submitted for review"
                urgent={metrics.awaitingVerification > 0}
                onClick={() => navigate('/worklist?view=ToVerify')}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Signed Reports Today"
                value={metrics.signedReports}
                icon={<VerifiedIcon />}
                color="var(--color-success)"
                subtext="Completed today"
                onClick={() => navigate(`/reports?status=SignedOff&date=${getNepalTodayAd()}`)}
              />
            </Grid>
            <Grid item xs={6} sm={4} md={2.4}>
              <MetricCard
                title="Rejected Samples"
                value={metrics.rejectedSamples}
                icon={<BlockIcon />}
                color={metrics.rejectedSamples > 0 ? 'var(--color-danger)' : 'var(--color-text-muted)'}
                subtext="Needs recollection"
                urgent={metrics.rejectedSamples > 0}
                onClick={() => navigate('/samples?status=Rejected')}
              />
            </Grid>
          </Grid>

          {/* ================================================================ */}
          {/* ROW 3 — DEPARTMENT WORKLOAD + RECENT ORDERS                      */}
          {/* ================================================================ */}
          <Grid container spacing={2.5}>
            {/* Department Workload */}
            <Grid item xs={12} md={4}>
              <Card sx={{ height: '100%' }}>
                <CardContent sx={{ p: 2.5 }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', gap: 1, mb: 2 }}>
                    <AssignmentIcon sx={{ color: 'primary.main', fontSize: 20 }} />
                    <Typography variant="subtitle1" fontWeight={700}>Department Active Workload</Typography>
                  </Box>
                  <Divider sx={{ mb: 2 }} />
                  {departmentWorkload.every(d => d.count === 0) ? (
                    <Box sx={{ textAlign: 'center', py: 3 }}>
                      <CheckCircleOutlineIcon sx={{ fontSize: 40, color: 'success.main', mb: 1 }} />
                      <Typography variant="body2" color="text.secondary">All departments clear</Typography>
                    </Box>
                  ) : (
                    departmentWorkload.map((d) => (
                      <DeptBar key={d.dept} {...d} />
                    ))
                  )}
                  <Divider sx={{ mt: 2, mb: 1.5 }} />
                  <Box sx={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                    <Typography variant="caption" color="text.secondary">
                      Total active items: {departmentWorkload.reduce((s, d) => s + d.count, 0)}
                    </Typography>
                    <Button size="small" onClick={() => navigate('/worklist')}>Open Worklist →</Button>
                  </Box>
                </CardContent>
              </Card>
            </Grid>

            {/* Recent Patient Orders */}
            <Grid item xs={12} md={8}>
              <Card sx={{ height: '100%' }}>
                <CardContent sx={{ p: 2.5 }}>
                  <Box sx={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', mb: 2 }}>
                    <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
                      <AssignmentIcon sx={{ color: 'primary.main', fontSize: 20 }} />
                      <Typography variant="subtitle1" fontWeight={700}>Recent Patient Orders</Typography>
                    </Box>
                  </Box>
                  <Divider sx={{ mb: 0 }} />
                  {recentOrders.length === 0 ? (
                    <Box sx={{ textAlign: 'center', py: 4 }}>
                      <Typography variant="body2" color="text.secondary">No orders recorded today.</Typography>
                    </Box>
                  ) : (
                    <TableContainer component={Paper} elevation={0} sx={{ maxHeight: 360 }}>
                      <Table size="small" stickyHeader>
                        <TableHead>
                          <TableRow>
                            <TableCell sx={{ fontWeight: 700, bgcolor: '#f8fafc' }}>Order No.</TableCell>
                            <TableCell sx={{ fontWeight: 700, bgcolor: '#f8fafc' }}>Patient</TableCell>
                            <TableCell sx={{ fontWeight: 700, bgcolor: '#f8fafc' }}>Tests</TableCell>
                            <TableCell sx={{ fontWeight: 700, bgcolor: '#f8fafc' }}>Time</TableCell>
                            <TableCell sx={{ fontWeight: 700, bgcolor: '#f8fafc' }}>Status</TableCell>
                          </TableRow>
                        </TableHead>
                        <TableBody>
                          {recentOrders.map((order) => (
                            <TableRow key={order.id} hover sx={{ cursor: 'pointer' }} onClick={() => navigate('/worklist')}>
                              <TableCell>
                                <Typography variant="body2" fontWeight={700} color="primary.main" sx={{ fontFamily: 'monospace' }}>
                                  {order.order_number}
                                </Typography>
                              </TableCell>
                              <TableCell>
                                <Typography variant="body2" fontWeight={600} sx={{ lineHeight: 1.2 }}>
                                  {order.patient?.full_name}
                                </Typography>
                                <Typography variant="caption" color="text.secondary">
                                  {order.patient?.uhid} · {order.patient?.age_years}y {order.patient?.gender?.[0]}
                                </Typography>
                              </TableCell>
                              <TableCell>
                                <Box sx={{ display: 'flex', flexWrap: 'wrap', gap: 0.5 }}>
                                  {(order.items || []).slice(0, 3).map((item: any, i: number) => (
                                    <Chip
                                      key={i}
                                      label={item.test_name}
                                      size="small"
                                      variant="outlined"
                                      sx={{ fontSize: '0.65rem', height: 20 }}
                                    />
                                  ))}
                                  {(order.items || []).length > 3 && (
                                    <Chip
                                      label={`+${order.items.length - 3}`}
                                      size="small"
                                      sx={{ fontSize: '0.65rem', height: 20, bgcolor: '#f1f5f9' }}
                                    />
                                  )}
                                </Box>
                              </TableCell>
                              <TableCell>
                                <Typography variant="caption" color="text.secondary" sx={{ whiteSpace: 'nowrap' }}>
                                  {formatAdDateTime(order.created_at)}
                                </Typography>
                              </TableCell>
                              <TableCell>
                                <StatusChip status={order.status} />
                              </TableCell>
                            </TableRow>
                          ))}
                        </TableBody>
                      </Table>
                    </TableContainer>
                  )}
                </CardContent>
              </Card>
            </Grid>
          </Grid>

          <PatientOrderWorklist />

          {/* Quick Action Strip */}
          <Box
            sx={{
              mt: 3,
              p: 2,
              borderRadius: 2,
              bgcolor: '#f0f9ff',
              border: '1px solid #bae6fd',
              display: 'flex',
              flexWrap: 'wrap',
              gap: 1.5,
              alignItems: 'center',
            }}
          >
            <Typography variant="body2" fontWeight={700} color="primary.dark" sx={{ mr: 1 }}>
              Quick Actions:
            </Typography>
            {can(PERMISSION_KEYS.CAN_CREATE_BILL) && (
              <Button size="small" variant="contained" startIcon={<AddShoppingCartIcon />} onClick={() => navigate('/billing/new')}>
                New Bill / Booking
              </Button>
            )}
            {can(PERMISSION_KEYS.CAN_RECEIVE_SAMPLE) && (
              <Button size="small" variant="outlined" startIcon={<ScienceIcon />} onClick={() => navigate('/samples')}>
                Sample Accessioning
              </Button>
            )}
            {can(PERMISSION_KEYS.CAN_ENTER_RESULTS) && (
              <Button size="small" variant="outlined" startIcon={<PendingActionsIcon />} onClick={() => navigate('/worklist')}>
                Lab Worklist
              </Button>
            )}
            {can(PERMISSION_KEYS.CAN_PRINT_REPORTS) && (
              <Button size="small" variant="outlined" startIcon={<VerifiedIcon />} onClick={() => navigate('/reports')}>
                Diagnostic Reports
              </Button>
            )}
          </Box>
        </>
      )}
    </Box>
  );
};
