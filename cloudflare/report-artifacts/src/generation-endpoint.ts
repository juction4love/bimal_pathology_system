import{acceptanceControlAuthorized}from'./acceptance-auth.ts';
import type{GenerationResult}from'./scheduled.ts';

type SafeBody={attempted:boolean;claimed:boolean;generated:boolean;completed:boolean;status:string;safeErrorCode?:string};

const safeResult=(result:GenerationResult):SafeBody=>{
  if(!result.enabled)return{attempted:false,claimed:false,generated:false,completed:false,status:'Disabled'};
  if(!result.claimed)return{attempted:true,claimed:false,generated:false,completed:false,status:'NoClaim'};
  if(result.ready)return{attempted:true,claimed:true,generated:true,completed:true,status:'Ready'};
  return{attempted:true,claimed:true,generated:false,completed:true,status:'Failed',safeErrorCode:result.failureCode??'PDF_GENERATION_FAILED'};
};

export async function handleGenerationRequest(request:Request,secret:string|undefined,cycle:()=>Promise<GenerationResult>):Promise<{status:number;body:SafeBody|{error:string}}>{
  if(request.method!=='POST')return{status:405,body:{error:'Method not allowed'}};
  if(!await acceptanceControlAuthorized(request.headers.get('authorization'),secret))return{status:401,body:{error:'Unauthorized'}};
  try{return{status:200,body:safeResult(await cycle())}}
  catch(error){const value=String(error);const code=value.includes('WORKER_AUTH_')?'WORKER_AUTH_FAILED':value.includes('RPC_claim_report_pdf_artifact_v2_')?'CLAIM_RPC_FAILED':value.includes('RPC_complete_report_pdf_artifact_v2_')?'COMPLETE_RPC_FAILED':'GENERATION_CYCLE_FAILED';return{status:500,body:{attempted:true,claimed:false,generated:false,completed:false,status:'Failed',safeErrorCode:code}}}
}
