import { createCipheriv, createDecipheriv, randomBytes } from 'node:crypto';
import { createWriteStream, existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve, relative } from 'node:path';
import { spawnSync } from 'node:child_process';
import { pipeline } from 'node:stream/promises';

const root=resolve(import.meta.dirname,'..');
const within=p=>{const x=resolve(root,p);if(relative(root,x).startsWith('..'))throw new Error('RECOVERY_PATH_OUTSIDE_WORKSPACE');return x};
const keyPath=within(process.env.BPDR_KEY_PATH||'recovery/keys/production-recovery-key.dpapi');
const bridge=within('tools/sms-gateway-v2/src/security/DpapiBridge.ps1');
const dpapi=(mode,input)=>{const r=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-File',bridge,mode],{input,maxBuffer:1024*1024,windowsHide:true});if(r.status!==0)throw new Error(`DPAPI_${mode.toUpperCase()}_FAILED`);return r.stdout};
const key=()=>{if(!existsSync(keyPath)){mkdirSync(dirname(keyPath),{recursive:true});const k=randomBytes(32);writeFileSync(keyPath,dpapi('protect',k),{flag:'wx'});k.fill(0)}return dpapi('unprotect',readFileSync(keyPath))};
const mode=process.argv[2], target=process.argv[3]&&within(process.argv[3]);
if(mode==='encrypt'){
  if(!target)throw new Error('OUTPUT_REQUIRED');mkdirSync(dirname(target),{recursive:true});const k=key(),nonce=randomBytes(12),cipher=createCipheriv('aes-256-gcm',k,nonce);k.fill(0);const out=createWriteStream(target,{flags:'wx'});out.write(Buffer.concat([Buffer.from('BPDR2'),nonce]));await pipeline(process.stdin,cipher,out,{end:false});out.write(cipher.getAuthTag());out.end();await new Promise((ok,bad)=>out.on('close',ok).on('error',bad));process.stdout.write('RECOVERY_STREAM_ENCRYPT_PASS\n');
}else if(mode==='decrypt'){
  if(!target)throw new Error('INPUT_REQUIRED');const all=readFileSync(target);if(all.length<33||all.subarray(0,5).toString()!=='BPDR2')throw new Error('BAD_HEADER');const k=key(),decipher=createDecipheriv('aes-256-gcm',k,all.subarray(5,17));k.fill(0);decipher.setAuthTag(all.subarray(all.length-16));process.stdout.write(Buffer.concat([decipher.update(all.subarray(17,all.length-16)),decipher.final()]));
}else throw new Error('MODE_MUST_BE_encrypt_OR_decrypt');
