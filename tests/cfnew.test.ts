import { describe, it, expect, afterEach } from 'vitest';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { cfnewRelease, cfnewMetadata, cfnewOwner, cfnewSteps, parseCfnewInput, createCfnewDeployer } from '../src/server/cfnew';
import { createApp } from '../src/server/app';
const input={accountId:'a'.repeat(32),apiToken:'synthetic-token-0000000000',workerName:'cfnew-fixture',uuid:'12345678-1234-4123-8123-123456789abc',step:'prepare'};
const id='b'.repeat(32), code='export default {fetch(){return new Response("fixture")}};';
const originalHash=cfnewRelease.sha256;
afterEach(()=>{cfnewRelease.sha256=originalHash;});
function cloud() {
  const state={settings:null as any,exists:false,enabled:false,creates:0,uploads:0,deny:false,failActivate:false,runtimeOk:true,requests:[] as Request[]};
  const fetcher:typeof fetch=async(url,init)=>{
    const request=new Request(url,init); state.requests.push(request);
    const u=new URL(request.url), path=u.pathname;
    if(u.hostname==='raw.githubusercontent.com') {expect(request.headers.has('authorization')).toBe(false);return new Response(code);}
    if(u.hostname.endsWith('.workers.dev')) {expect(request.headers.has('authorization')).toBe(false);return Response.json({kvEnabled:state.runtimeOk});}
    expect(u.hostname).toBe('api.cloudflare.com');
    expect(request.headers.get('authorization')).toBe(`Bearer ${input.apiToken}`);
    if(state.deny)return Response.json({success:false,errors:[{code:9109,message:input.apiToken}]},{status:403});
    let result:any;
    const title=`5a-ui-${input.workerName}-${(await cfnewOwner(parseCfnewInput(input))).slice(0,16)}`;
    if(path.endsWith('/settings')) {if(!state.settings)return Response.json({success:false,errors:[{code:10007}]},{status:404});result=state.settings;}
    else if(path.endsWith('/workers/subdomain'))result={subdomain:'fixture'};
    else if(path.endsWith('/storage/kv/namespaces')) {if(request.method==='POST'){state.creates++;state.exists=true;result={id};}else result=state.exists?[{id,title}]:[];}
    else if(path.endsWith(`/namespaces/${id}`))result={id,title};
    else if(path.endsWith('/scripts/cfnew-fixture')&&request.method==='PUT'){
      const form=await request.formData();const metadata=form.get('metadata') as Blob;
      state.settings=JSON.parse(await metadata.text());
      expect(await (form.get('worker.js') as Blob).text()).toBe(code);
      expect(JSON.stringify(state.settings)).not.toContain(input.apiToken);
      state.uploads++;result={};
    }else if(path.endsWith('/subdomain')){if(request.method==='POST'){if(state.failActivate)return Response.json({success:false},{status:500});state.enabled=true;}result={enabled:state.enabled};}
    else throw new Error(`Unexpected route ${path}`);
    return Response.json({success:true,result});
  };
  return {state,run:createCfnewDeployer(fetcher)};
}
describe('cfnew deployment',()=>{
  it('shares input, owner and upload metadata with Dart',async()=>{
    const cases=JSON.parse(readFileSync('contracts/cfnew-cases.json','utf8'));
    const values=cases.map((c:any)=>({...input,...c.patch}));
    const direct=process.env.DART_COMMAND;
    const result=spawnSync(direct||'fvm',[...(direct?[]:['dart']),'run','tool/cfnew_contract_export.dart'],{input:JSON.stringify(values),encoding:'utf8',timeout:30000});
    expect(result.status,result.stderr).toBe(0);
    const dart=JSON.parse(result.stdout);
    for(let j=0;j<values.length;j++){
      if(cases[j].valid){const parsed=parseCfnewInput(values[j]);expect(dart[j]).toEqual({input:parsed,owner:await cfnewOwner(parsed),metadata:await cfnewMetadata(parsed,id)});}
      else{expect(()=>parseCfnewInput(values[j])).toThrow();expect(dart[j]).toEqual({error:'CF_INPUT'});}
    }
  },35000);
  it('creates and verifies once; retry preserves Worker and KV',async()=>{
    cfnewRelease.sha256=createHash('sha256').update(code).digest('hex');
    const {state,run}=cloud();
    for(let round=0;round<2;round++)for(const step of cfnewSteps){const result=await run(parseCfnewInput({...input,step,...(step==='prepare'?{}:{namespaceId:id})}));expect(result.namespaceId).toBe(id);if(step==='verify')expect(result.runtimeVerified).toBe(true);}
    expect(state.creates).toBe(1);expect(state.uploads).toBe(1);
  });
  it('blocks unknown Worker ownership and corrupted source before mutation',async()=>{
    const {state,run}=cloud();state.settings={bindings:[]};
    await expect(run(parseCfnewInput(input))).rejects.toMatchObject({code:'CF_CONFLICT'});
    state.settings=null;
    await expect(run(parseCfnewInput(input))).rejects.toMatchObject({code:'CF_SOURCE'});
    expect(state.creates).toBe(0);expect(state.uploads).toBe(0);
  });
  it('retains resources after activation failure and reports runtime propagation accurately',async()=>{
    cfnewRelease.sha256=createHash('sha256').update(code).digest('hex');
    const {state,run}=cloud();const stage=(step:string)=>run(parseCfnewInput({...input,step,...(step==='prepare'?{}:{namespaceId:id})}));
    await stage('prepare');await stage('upload');state.failActivate=true;
    await expect(stage('activate')).rejects.toMatchObject({code:'CF_API'});
    state.failActivate=false;await stage('upload');await stage('activate');state.runtimeOk=false;
    expect((await stage('verify')).runtimeVerified).toBe(false);
    expect(state.uploads).toBe(1);expect(state.requests.some(r=>r.method==='DELETE')).toBe(false);
  });
  it('sanitizes provider permission errors',async()=>{
    const {state,run}=cloud();state.deny=true;
    await expect(run(parseCfnewInput(input))).rejects.toMatchObject({code:'CF_AUTH',status:403});
    expect(state.creates).toBe(0);
  });
  it('uses protected same-origin API without SSH, rejects malformed input and requires CAPTCHA',async()=>{
    let calls=0;
    const app=createApp(async()=>{throw new Error('SSH must not run');},async()=>false,async()=>{calls++;return {step:'prepare',namespaceId:id};});
    const req=(data:object=input,origin='https://fixture.example')=>new Request('https://fixture.example/api/cfnew',{method:'POST',headers:{origin,'Content-Type':'application/json'},body:JSON.stringify(data)});
    const env={REQUEST_LIMITER:{limit:async()=>({success:true})},INSTALL_LIMITER:{limit:async()=>({success:true})}};
    expect((await app(req({},'https://other.example'),env)).status).toBe(403);
    expect((await app(req({}),env)).status).toBe(400);
    expect((await app(req(),{...env,TURNSTILE_SITE_KEY:'site',TURNSTILE_SECRET_KEY:'secret'})).status).toBe(403);
    const response=await app(req(),env);expect(response.status).toBe(200);expect(response.headers.get('cache-control')).toBe('no-store');expect(calls).toBe(1);
  });
});
