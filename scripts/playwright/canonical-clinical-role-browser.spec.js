import { expect, test } from '@playwright/test';
import { loadStagingAcceptanceEnvironment } from './stagingAcceptanceGuard.js';

const target=loadStagingAcceptanceEnvironment();
if(!target.verifierEmail||!target.verifierPassword||!target.signatoryEmail||!target.signatoryPassword) throw new Error('Verifier and Signatory browser fixtures are required.');
async function login(page,email,password){await page.goto('/login');await page.locator('#login-email').fill(email);await page.locator('#login-password').fill(password);await page.locator('#login-submit').click();await expect(page).toHaveURL(/\/$/);}
async function denied(page,path){await page.goto(path);await expect(page.getByRole('heading',{name:'Access Denied',exact:true})).toBeVisible();}

test('Verifier has verification workspace but no sign-off or administration',async({page})=>{
  await login(page,target.verifierEmail,target.verifierPassword);
  await expect(page.getByRole('link',{name:'Lab Worklist & Results',exact:true})).toBeVisible();
  await expect(page.getByRole('link',{name:'Diagnostic Reports',exact:true})).toBeVisible();
  for(const label of ['New Bill / Booking','Test Catalogue','User Management','Roles & Permissions']) await expect(page.getByRole('link',{name:label,exact:true})).toHaveCount(0);
  await page.goto(`/worklist/entry/${target.resultItemId}`);
  await expect(page.getByRole('button',{name:'Back to Laboratory Worklist',exact:true})).toBeVisible();
  await expect(page.getByPlaceholder('Enter result...').first()).toBeDisabled();
  await expect(page.getByRole('button',{name:/Sign-Off/})).toHaveCount(0);
  await denied(page,'/billing/new'); await denied(page,'/admin/users'); await denied(page,'/catalogue');
});

test('Signatory has report/sign-off workspace but no result entry or administration',async({page})=>{
  await login(page,target.signatoryEmail,target.signatoryPassword);
  await expect(page.getByRole('link',{name:'Lab Worklist & Results',exact:true})).toBeVisible();
  await expect(page.getByRole('link',{name:'Diagnostic Reports',exact:true})).toBeVisible();
  for(const label of ['New Bill / Booking','Test Catalogue','User Management','Roles & Permissions']) await expect(page.getByRole('link',{name:label,exact:true})).toHaveCount(0);
  await page.goto(`/worklist/entry/${target.resultItemId}`);
  await expect(page.getByRole('button',{name:'Back to Laboratory Worklist',exact:true})).toBeVisible();
  await expect(page.getByPlaceholder('Enter result...').first()).toBeDisabled();
  await expect(page.getByRole('button',{name:'Save Draft',exact:true})).toHaveCount(0);
  await denied(page,'/billing'); await denied(page,'/admin/roles'); await denied(page,'/catalogue');
});
