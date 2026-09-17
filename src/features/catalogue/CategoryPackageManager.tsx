import { useCallback, useEffect, useState } from 'react';
import { Alert, Box, Button, Card, CardContent, Chip, Dialog, DialogActions, DialogContent, DialogTitle, FormControlLabel, Grid, MenuItem, Switch, TextField, Typography } from '@mui/material';
import { supabase } from '@/lib/supabase';
import { paisaToRupees, rupeesToPaisa } from '@/lib/currency';
import { safeErrorMessage } from '@/lib/safeError';

type Lifecycle = 'Draft' | 'Active' | 'Archived';
type PricingPolicy = 'Fixed' | 'Negotiable' | 'PricePending' | 'Manual';
type Category = { id: string; code: string; name: string; description?: string | null; lifecycle_status: Lifecycle; display_order: number; row_version: number };
type TestOption = { id: string; code: string; name: string };
type Package = { id: string; code: string; name: string; description?: string | null; price_paisa: number; pricing_policy: PricingPolicy; search_aliases: string[]; lifecycle_status: Lifecycle; row_version: number; health_package_components?: { test_id: string; display_order: number }[] };

export function CategoryPackageManager({ onCatalogueChanged }: { onCatalogueChanged: () => void }) {
  const [categories, setCategories] = useState<Category[]>([]);
  const [packages, setPackages] = useState<Package[]>([]);
  const [tests, setTests] = useState<TestOption[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [categoryDialog, setCategoryDialog] = useState(false);
  const [packageDialog, setPackageDialog] = useState(false);
  const [categoryForm, setCategoryForm] = useState({ id: '', code: '', name: '', description: '', display_order: 0, row_version: 0 });
  const [packageForm, setPackageForm] = useState({ id: '', code: '', name: '', description: '', price_npr: '0', pricing_policy: 'Fixed' as PricingPolicy, search_aliases: '', row_version: 0, component_ids: [] as string[] });

  const load = useCallback(async () => {
    const [categoryResult, packageResult, testResult] = await Promise.all([
      supabase.from('test_categories').select('*').order('display_order'),
      supabase.from('health_packages').select('*, health_package_components(test_id, display_order)').order('name'),
      supabase.from('tests').select('id, code, name').eq('lifecycle_status', 'Active').order('name'),
    ]);
    const firstError = categoryResult.error || packageResult.error || testResult.error;
    if (firstError) setError(safeErrorMessage(firstError, 'Could not load categories and packages.'));
    else { setCategories(categoryResult.data || []); setPackages(packageResult.data || []); setTests(testResult.data || []); }
  }, []);
  useEffect(() => { load(); }, [load]);

  const saveCategory = async () => {
    const { error: rpcError } = await supabase.rpc('catalogue_save_category', { p_category: { ...categoryForm, id: categoryForm.id || undefined }, p_expected_version: categoryForm.id ? categoryForm.row_version : null });
    if (rpcError) return setError(safeErrorMessage(rpcError, 'Category could not be saved.'));
    setCategoryDialog(false); await load(); onCatalogueChanged();
  };
  const setCategoryLifecycle = async (category: Category, status: Lifecycle) => {
    const { error: rpcError } = await supabase.rpc('catalogue_set_category_lifecycle', { p_category_id: category.id, p_status: status, p_expected_version: category.row_version });
    if (rpcError) setError(safeErrorMessage(rpcError, 'Category lifecycle could not be changed.')); else { await load(); onCatalogueChanged(); }
  };
  const deleteCategory = async (category: Category) => {
    const { error: rpcError } = await supabase.rpc('catalogue_delete_category', { p_category_id: category.id, p_expected_version: category.row_version });
    if (rpcError) setError(safeErrorMessage(rpcError, 'Used categories must be archived.')); else { await load(); onCatalogueChanged(); }
  };
  const savePackage = async () => {
    const { error: rpcError } = await supabase.rpc('catalogue_save_package', { p_package: { id: packageForm.id || undefined, code: packageForm.code, name: packageForm.name, description: packageForm.description, price_paisa: rupeesToPaisa(packageForm.price_npr), pricing_policy: packageForm.pricing_policy, search_aliases: packageForm.search_aliases.split(',').map((alias) => alias.trim().toLowerCase()).filter(Boolean) }, p_components: packageForm.component_ids, p_expected_version: packageForm.id ? packageForm.row_version : null });
    if (rpcError) return setError(safeErrorMessage(rpcError, 'Package could not be saved.'));
    setPackageDialog(false); await load();
  };
  const setPackageLifecycle = async (pkg: Package, status: Lifecycle) => {
    const { error: rpcError } = await supabase.rpc('catalogue_set_package_lifecycle', { p_package_id: pkg.id, p_status: status, p_expected_version: pkg.row_version });
    if (rpcError) setError(safeErrorMessage(rpcError, 'Package lifecycle could not be changed.')); else await load();
  };
  const deletePackage = async (pkg: Package) => {
    const { error: rpcError } = await supabase.rpc('catalogue_delete_package', { p_package_id: pkg.id, p_expected_version: pkg.row_version });
    if (rpcError) setError(safeErrorMessage(rpcError, 'Used packages must be archived.')); else await load();
  };

  return <Card sx={{ mt: 2 }}><CardContent>
    {error && <Alert severity="error" onClose={() => setError(null)} sx={{ mb: 2 }}>{error}</Alert>}
    <Grid container spacing={3}>
      <Grid item xs={12} lg={6}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}><Typography variant="h6">Categories</Typography><Button onClick={() => { setCategoryForm({ id: '', code: '', name: '', description: '', display_order: categories.length + 1, row_version: 0 }); setCategoryDialog(true); }}>Add Category</Button></Box>
        {categories.map((category) => <Box key={category.id} sx={{ display: 'flex', alignItems: 'center', gap: 1, py: .75, borderBottom: '1px solid #e2e8f0' }}><Typography sx={{ flex: 1 }}><strong>{category.code}</strong> — {category.name}</Typography><Chip size="small" label={category.lifecycle_status} /><Button size="small" onClick={() => { setCategoryForm({ id: category.id, code: category.code, name: category.name, description: category.description || '', display_order: category.display_order, row_version: category.row_version }); setCategoryDialog(true); }}>Edit</Button>{category.lifecycle_status === 'Draft' && <Button size="small" onClick={() => setCategoryLifecycle(category, 'Active')}>Activate</Button>}{category.lifecycle_status === 'Archived' ? <Button size="small" onClick={() => setCategoryLifecycle(category, 'Draft')}>Restore</Button> : <Button size="small" onClick={() => setCategoryLifecycle(category, 'Archived')}>Archive</Button>}{category.lifecycle_status !== 'Active' && <Button color="error" size="small" onClick={() => deleteCategory(category)}>Delete</Button>}</Box>)}
      </Grid>
      <Grid item xs={12} lg={6}>
        <Box sx={{ display: 'flex', justifyContent: 'space-between', mb: 1 }}><Typography variant="h6">Health Packages</Typography><Button onClick={() => { setPackageForm({ id: '', code: '', name: '', description: '', price_npr: '0', pricing_policy: 'Fixed', search_aliases: '', row_version: 0, component_ids: [] }); setPackageDialog(true); }}>Add Package</Button></Box>
        {packages.length === 0 && <Typography color="text.secondary">No packages configured.</Typography>}
        {packages.map((pkg) => <Box key={pkg.id} sx={{ display: 'flex', alignItems: 'center', gap: 1, py: .75, borderBottom: '1px solid #e2e8f0' }}><Typography sx={{ flex: 1 }}><strong>{pkg.code}</strong> — {pkg.name}<br/><small>NPR {paisaToRupees(pkg.price_paisa)} · {pkg.pricing_policy} · {pkg.health_package_components?.length || 0} unique components</small></Typography><Chip size="small" label={pkg.lifecycle_status} /><Button size="small" onClick={() => { setPackageForm({ id: pkg.id, code: pkg.code, name: pkg.name, description: pkg.description || '', price_npr: String(paisaToRupees(pkg.price_paisa)), pricing_policy: pkg.pricing_policy || 'Fixed', search_aliases: (pkg.search_aliases || []).join(', '), row_version: pkg.row_version, component_ids: (pkg.health_package_components || []).sort((a,b) => a.display_order-b.display_order).map((x) => x.test_id) }); setPackageDialog(true); }}>Edit</Button>{pkg.lifecycle_status === 'Draft' && <Button size="small" onClick={() => setPackageLifecycle(pkg, 'Active')}>Activate</Button>}{pkg.lifecycle_status === 'Archived' ? <Button size="small" onClick={() => setPackageLifecycle(pkg, 'Draft')}>Restore</Button> : <Button size="small" onClick={() => setPackageLifecycle(pkg, 'Archived')}>Archive</Button>}{pkg.lifecycle_status !== 'Active' && <Button color="error" size="small" onClick={() => deletePackage(pkg)}>Delete</Button>}</Box>)}
      </Grid>
    </Grid>
    <Dialog open={categoryDialog} onClose={() => setCategoryDialog(false)} maxWidth="sm" fullWidth><DialogTitle>{categoryForm.id ? 'Edit' : 'Add'} Category</DialogTitle><DialogContent><Grid container spacing={2} sx={{ pt: 1 }}><Grid item xs={4}><TextField fullWidth label="Code" value={categoryForm.code} onChange={(e) => setCategoryForm({ ...categoryForm, code: e.target.value })}/></Grid><Grid item xs={8}><TextField fullWidth label="Name" value={categoryForm.name} onChange={(e) => setCategoryForm({ ...categoryForm, name: e.target.value })}/></Grid><Grid item xs={12}><TextField fullWidth multiline label="Description" value={categoryForm.description} onChange={(e) => setCategoryForm({ ...categoryForm, description: e.target.value })}/></Grid></Grid></DialogContent><DialogActions><Button onClick={() => setCategoryDialog(false)}>Cancel</Button><Button variant="contained" onClick={saveCategory}>Save Draft</Button></DialogActions></Dialog>
    <Dialog open={packageDialog} onClose={() => setPackageDialog(false)} maxWidth="md" fullWidth><DialogTitle>{packageForm.id ? 'Edit' : 'Add'} Health Package</DialogTitle><DialogContent><Grid container spacing={2} sx={{ pt: 1 }}><Grid item xs={4}><TextField fullWidth label="Package Code" value={packageForm.code} onChange={(e) => setPackageForm({ ...packageForm, code: e.target.value })}/></Grid><Grid item xs={8}><TextField fullWidth label="Package Name" value={packageForm.name} onChange={(e) => setPackageForm({ ...packageForm, name: e.target.value })}/></Grid><Grid item xs={6}><TextField fullWidth type="number" label="Package Price (NPR)" value={packageForm.price_npr} onChange={(e) => setPackageForm({ ...packageForm, price_npr: e.target.value })}/></Grid><Grid item xs={6}><TextField fullWidth select label="Pricing Policy" value={packageForm.pricing_policy} onChange={(e) => setPackageForm({ ...packageForm, pricing_policy: e.target.value as PricingPolicy })}>{(['Fixed', 'Negotiable', 'PricePending', 'Manual'] as PricingPolicy[]).map((policy) => <MenuItem key={policy} value={policy}>{policy}</MenuItem>)}</TextField></Grid><Grid item xs={12}><TextField fullWidth label="Search Aliases" value={packageForm.search_aliases} onChange={(e) => setPackageForm({ ...packageForm, search_aliases: e.target.value })} helperText="Comma-separated short names used by unified billing search" /></Grid><Grid item xs={12}><TextField fullWidth multiline label="Description" value={packageForm.description} onChange={(e) => setPackageForm({ ...packageForm, description: e.target.value })}/></Grid><Grid item xs={12}><Typography variant="subtitle2">Ordered canonical components</Typography>{tests.map((test) => { const selected = packageForm.component_ids.includes(test.id); return <FormControlLabel key={test.id} sx={{ width: '47%' }} control={<Switch checked={selected} onChange={() => setPackageForm((current) => ({ ...current, component_ids: selected ? current.component_ids.filter((id) => id !== test.id) : [...current.component_ids, test.id] }))}/>} label={`${test.code} — ${test.name}`}/>; })}</Grid></Grid></DialogContent><DialogActions><Button onClick={() => setPackageDialog(false)}>Cancel</Button><Button variant="contained" onClick={savePackage}>Save Draft</Button></DialogActions></Dialog>
  </CardContent></Card>;
}
