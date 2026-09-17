export type WorkflowDomain = 'patients'|'bills'|'samples'|'worklist'|'reports'|'dashboard';
export type WorkflowEvent =
  | 'patient-changed'|'order-created'|'payment-completed'
  | 'sample-changed'|'result-changed'|'report-changed';

interface Message { source: string; event: WorkflowEvent; domains: WorkflowDomain[]; opaqueId?: string; at: number }
const CHANNEL='bimal-lis-workflow-v1', source=crypto.randomUUID();
const listeners=new Set<(message:Message)=>void>();
let channel:BroadcastChannel|null=null;

function receive(message:Message){
  if(!message||message.source===source||!Array.isArray(message.domains))return;
  listeners.forEach(listener=>listener(message));
}

if(typeof window!=='undefined'){
  if('BroadcastChannel'in window){channel=new BroadcastChannel(CHANNEL);channel.onmessage=(event)=>receive(event.data as Message)}
  window.addEventListener('storage',(event)=>{if(event.key!==CHANNEL||!event.newValue)return;try{receive(JSON.parse(event.newValue) as Message)}catch{/* ignore malformed same-origin storage */}});
}

export function publishWorkflowInvalidation(event:WorkflowEvent,domains:WorkflowDomain[],opaqueId?:string){
  const message:Message={source,event,domains:[...new Set(domains)],opaqueId,at:Date.now()};
  channel?.postMessage(message);
  try{localStorage.setItem(CHANNEL,JSON.stringify(message));localStorage.removeItem(CHANNEL)}catch{/* storage may be disabled */}
}

export function subscribeWorkflowInvalidation(domain:WorkflowDomain,listener:()=>void){
  let timer:number|undefined;
  const wrapped=(message:Message)=>{if(!message.domains.includes(domain))return;window.clearTimeout(timer);timer=window.setTimeout(listener,120)};
  listeners.add(wrapped);
  return()=>{listeners.delete(wrapped);window.clearTimeout(timer)};
}
