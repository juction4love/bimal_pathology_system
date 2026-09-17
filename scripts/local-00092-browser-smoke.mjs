import { chromium } from 'playwright';
const widths=[320,375,390,430,768,1366];
const browser=await chromium.launch({headless:true});
let passed=0;
for(const width of widths){
 const page=await browser.newPage({viewport:{width,height:Math.max(720,Math.round(width*0.75))}});
 const errors=[]; page.on('pageerror',e=>errors.push(String(e))); page.on('console',m=>{if(m.type()==='error')errors.push(m.text())});
 const response=await page.goto('http://127.0.0.1:41792/login',{waitUntil:'networkidle'});
 if(response?.status()!==200)throw new Error(`${width}: HTTP ${response?.status()}`);
 await page.getByRole('button',{name:/sign in/i}).waitFor();
 const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>document.documentElement.clientWidth+1);
 if(overflow)throw new Error(`${width}: horizontal overflow`);
 const actionable=errors.filter((message)=>!message.includes('ERR_NETWORK_ACCESS_DENIED'));
 if(actionable.length)throw new Error(`${width}: ${actionable.join('; ')}`);
 await page.close(); passed++;
}
const routePage=await browser.newPage({viewport:{width:1366,height:768}});
await routePage.goto('http://127.0.0.1:41792/worklist/order/00000000-0000-0000-0000-000000000001?item=00000000-0000-0000-0000-000000000002',{waitUntil:'networkidle'});
if(!routePage.url().includes('/login'))throw new Error('protected order workspace did not fail closed to login');
passed++;
await browser.close();
console.log(`local 00092 browser smoke: ${passed}/7 passed`);
