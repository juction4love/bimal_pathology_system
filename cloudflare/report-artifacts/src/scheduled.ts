export type GenerationResult={enabled:boolean;claimed?:boolean;ready?:boolean;failureCode?:string};

const safeScheduleFailure=(error:unknown)=>{
  const value=String(error);
  if(value.includes('WORKER_AUTH_'))return'WORKER_AUTH_FAILED';
  if(value.includes('RPC_claim_report_pdf_artifact_v2_'))return'CLAIM_RPC_FAILED';
  if(value.includes('RPC_complete_report_pdf_artifact_v2_'))return'COMPLETE_RPC_FAILED';
  return'SCHEDULE_FAILED';
};

export async function runScheduled<Env>(env:Env,generate:(env:Env)=>Promise<GenerationResult>,verify:(env:Env)=>Promise<Record<string,unknown>>,log:(value:string)=>void=console.log){
  log(JSON.stringify({event:'artifact.schedule.started'}));
  try{
    const result=await generate(env);
    if(!result.enabled){log(JSON.stringify({event:'artifact.generation.disabled'}));return result}
    if(!result.claimed)log(JSON.stringify({event:'artifact.claim.none'}));
    else if(result.ready)log(JSON.stringify({event:'artifact.complete.succeeded'}));
    else log(JSON.stringify({event:'artifact.generation.failed',code:result.failureCode??'PDF_GENERATION_FAILED'}));
    const acceptance=await verify(env);
    log(JSON.stringify({event:'report_pdf_delivery_acceptance',...acceptance}));
    return result;
  }catch(error){
    log(JSON.stringify({event:'artifact.schedule.failed',code:safeScheduleFailure(error)}));
    throw error;
  }
}
