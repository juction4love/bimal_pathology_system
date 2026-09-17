import type { HmisSnapshot } from './hmisModel';

export function printHmis(element: HTMLElement, snapshot: HmisSnapshot) {
  const frame=document.createElement('iframe'); frame.setAttribute('title','HMIS print preview'); frame.style.position='fixed'; frame.style.width='0'; frame.style.height='0'; frame.style.border='0';
  document.body.appendChild(frame); const doc=frame.contentDocument; if(!doc) return;
  doc.open(); doc.write(`<!doctype html><html><head><title>HMIS ${snapshot.header.reportMonth}</title><style>@page{size:A4 landscape;margin:8mm}*{box-sizing:border-box}body{font:8pt Arial,sans-serif;color:#000;margin:0}table{border-collapse:collapse;width:100%;page-break-inside:auto}thead{display:table-header-group}tr{page-break-inside:avoid}th,td{border:1px solid #000;padding:2px 3px}h1,h2,p{margin:2px;text-align:center}.no-print{display:none}.hmis-sheet{width:100%}.hmis-grid{display:grid;grid-template-columns:1.15fr .85fr;gap:5px}.source-tag{font-size:6.5pt}.page-footer{position:fixed;bottom:0;right:0}.page-footer:after{content:'Page ' counter(page)}</style></head><body>${element.outerHTML}<div class="page-footer"></div></body></html>`); doc.close();
  frame.onload=()=>{frame.contentWindow?.focus(); frame.contentWindow?.print(); setTimeout(()=>frame.remove(),1000);};
}

export function downloadBlob(content:string,type:string,name:string){const url=URL.createObjectURL(new Blob([content],{type}));const a=document.createElement('a');a.href=url;a.download=name;a.click();setTimeout(()=>URL.revokeObjectURL(url),0)}
