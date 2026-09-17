export async function acceptanceControlAuthorized(header:string|null,configured:string|undefined){
  if(!configured)return false;
  const match=header?.match(/^Bearer ([A-Za-z0-9_-]{32,256})$/i);
  if(!match)return false;
  const encoder=new TextEncoder();
  const[candidateHash,configuredHash]=await Promise.all([
    crypto.subtle.digest('SHA-256',encoder.encode(match[1])),
    crypto.subtle.digest('SHA-256',encoder.encode(configured)),
  ]);
  const candidate=new Uint8Array(candidateHash),expected=new Uint8Array(configuredHash);
  let difference=match[1].length^configured.length;
  for(let index=0;index<expected.length;index++)difference|=candidate[index]^expected[index];
  return difference===0;
}
