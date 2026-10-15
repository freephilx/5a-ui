import { AppError } from './errors';
import { CFNEW_RELEASE_JSON } from './remote.generated';
import type { ConnectionInput } from '../shared/types';
export const cfnewRelease = JSON.parse(CFNEW_RELEASE_JSON) as { version: string; commit: string; sourceUrl: string; sha256: string; compatibilityDate: string; defaults: Record<string,string> };
export const cfnewSteps = ['prepare', 'upload', 'activate', 'verify'] as const;
export interface CfnewInput { accountId: string; apiToken: string; workerName: string; uuid: string; step: typeof cfnewSteps[number]; namespaceId?: string; turnstileToken?: string; proofToken?: string }
export function parseCfnewInput(raw: unknown): CfnewInput {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) throw new AppError('CF_INPUT', 'Cloudflare 部署参数格式不正确。');
  const r = raw as Record<string, unknown>;
  function field(key: string, pattern: RegExp, message: string): string {
    const value = r[key];
    if (typeof value !== 'string' || pattern.exec(value)?.[0] !== value) throw new AppError('CF_INPUT', message);
    return value;
  }
  const accountId = field('accountId', /^[a-f0-9]{32}$/, '账号 ID 应为 32 位小写十六进制字符。');
  const apiToken = field('apiToken', /^[A-Za-z0-9_-]{20,256}$/, '请输入有效的 Cloudflare API Token。');
  const workerName = field('workerName', /^[a-z][a-z0-9-]{1,61}[a-z0-9]$/, 'Worker 名称须为 3–63 位小写字母、数字或连字符，以字母开头，不能以连字符结尾。');
  const uuid = field('uuid', /^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/, '请输入有效的 UUID v4，或使用自动生成的值。');
  if (!cfnewSteps.includes(r.step as CfnewInput['step'])) throw new AppError('CF_INPUT', '未知的部署阶段。');
  if (r.namespaceId != null && (typeof r.namespaceId !== 'string' || r.namespaceId.length !== 32 || !/^[a-f0-9]{32}$/.test(r.namespaceId))) throw new AppError('CF_INPUT', '配置存储标识不正确。');
  if (r.step !== 'prepare' && r.namespaceId == null) throw new AppError('CF_INPUT', '请先准备配置存储。');
  for (const key of ['turnstileToken','proofToken']) if (r[key] != null && (typeof r[key] !== 'string' || (r[key] as string).length > 4096)) throw new AppError('CF_INPUT', '验证参数不正确。');
  return { accountId, apiToken, workerName, uuid, step: r.step as CfnewInput['step'], ...(r.namespaceId != null ? { namespaceId: r.namespaceId as string } : {}), ...(r.turnstileToken != null ? { turnstileToken: r.turnstileToken as string } : {}), ...(r.proofToken != null ? { proofToken: r.proofToken as string } : {}) };
}
export function cfnewCaptchaIdentity(i: CfnewInput): ConnectionInput { return { host: `cfnew:${i.accountId}`, port: 0, username: `${i.workerName}:${i.uuid}`, authMethod: 'password', turnstileToken: i.turnstileToken, proofToken: i.proofToken }; }
async function digest(value: string | ArrayBuffer): Promise<string> { return Buffer.from(await crypto.subtle.digest('SHA-256', typeof value === 'string' ? new TextEncoder().encode(value) : value)).toString('hex'); }
export async function cfnewOwner(i: CfnewInput): Promise<string> { return digest(`5a-ui-cfnew:${i.uuid}`); }
export async function cfnewMetadata(i: CfnewInput, id: string) {
  return { main_module: 'worker.js', compatibility_date: cfnewRelease.compatibilityDate, logpush: false, observability: { enabled: false }, bindings: [
    { type:'kv_namespace', name:'C', namespace_id:id }, { type:'secret_text', name:'u', text:i.uuid },
    { type:'plain_text', name:'FIVE_A_CFNEW_OWNER', text:await cfnewOwner(i) }, { type:'plain_text', name:'FIVE_A_CFNEW_REVISION', text:cfnewRelease.commit },
    ...Object.entries(cfnewRelease.defaults).map(([name,text])=>({type:'plain_text',name,text})),
  ] };
}
export function createCfnewDeployer(fetcher: typeof fetch = fetch) {
  return async (i: CfnewInput): Promise<Record<string, unknown>> => {
    const owner = await cfnewOwner(i), title = `5a-ui-${i.workerName}-${owner.slice(0,16)}`, path = `workers/scripts/${i.workerName}`;
    async function send(url: string, init: RequestInit = {}, limit = 2*1024*1024) {
      try {
        const response = await fetcher(url, { ...init, redirect:'error', signal:AbortSignal.timeout(15_000) });
        const reader = response.body?.getReader();
        const parts: Uint8Array[] = []; let size = 0;
        if (reader) try { while (true) { const chunk=await reader.read(); if (chunk.done) break; size+=chunk.value.length; if (size>limit) throw new AppError('CF_RESPONSE','远端响应过大，已停止处理。',502); parts.push(chunk.value); } } finally { await reader.cancel(); }
        const bytes = Buffer.concat(parts);
        return { status:response.status, bytes, text:bytes.toString('utf8') };
      } catch(error) { if (error instanceof AppError) throw error; throw new AppError('CF_NETWORK','Cloudflare 请求未能确认。保持原账号、名称和 UUID 重试，可继续未完成的部署。',502); }
    }
    async function api(route: string, init: RequestInit = {}, missing = false): Promise<Record<string, any> | null> {
      const response=await send(`https://api.cloudflare.com/client/v4/accounts/${i.accountId}/${route}`,{...init,headers:{Authorization:`Bearer ${i.apiToken}`,...init.headers}});
      let value: any; try { value=JSON.parse(response.text); } catch { /* Safe provider error below. */ }
      const codes=Array.isArray(value?.errors)?value.errors.map((e:any)=>e?.code):[];
      if (missing && response.status===404 && codes.includes(10007)) return null;
      if ([401,403].includes(response.status)||codes.includes(10000)||codes.includes(9109)) throw new AppError('CF_AUTH','Cloudflare 拒绝访问。请检查 Token、账号范围，以及 Workers Scripts 和 Workers KV Storage 编辑权限。',403);
      if (response.status===429) throw new AppError('CF_LIMIT','Cloudflare 限流或额度不足，请稍后重试并检查账号额度。',429);
      if (response.status<200||response.status>=300||value?.success!==true) throw new AppError('CF_API',`Cloudflare 操作未成功（HTTP ${response.status}）。请检查账号状态后使用相同参数重试；已创建的资源会保留。`,502);
      return value;
    }
    const json=(body:object):RequestInit=>({method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});
    async function source() { const r=await send(cfnewRelease.sourceUrl,{},1024*1024); if(r.status!==200||await digest(Uint8Array.from(r.bytes).buffer)!==cfnewRelease.sha256) throw new AppError('CF_SOURCE','cfnew 上游源码下载或完整性校验失败，未上传代码。',502); return r.text; }
    async function settings() {
      const e=await api(`${path}/settings`,{},true); if(!e) return null;
      const s=e.result;
      if(!s||!Array.isArray(s.bindings)) throw new AppError('CF_RESPONSE','无法核对 Worker 配置。',502);
      const has=(name:string,type:string,key:string,value:string)=>s.bindings.some((b:any)=>b?.name===name&&b.type===type&&b[key]===value);
      if(!has('FIVE_A_CFNEW_OWNER','plain_text','text',owner)||!has('FIVE_A_CFNEW_REVISION','plain_text','text',cfnewRelease.commit)||!s.bindings.some((b:any)=>b?.name==='u'&&b.type==='secret_text')||s.compatibility_date!==cfnewRelease.compatibilityDate) throw new AppError('CF_CONFLICT','已有同名 Worker，或其配置已改变。本次不会覆盖，请更换名称；恢复本次部署需使用原 UUID。',409);
      return s;
    }
    function bound(s:any):string { const id=s.bindings.find((b:any)=>b?.name==='C'&&b.type==='kv_namespace')?.namespace_id; if(typeof id!=='string'||!/^[a-f0-9]{32}$/.test(id)) throw new AppError('CF_CONFLICT','Worker 的配置存储绑定不匹配，请在 Cloudflare 控制台检查。',409); return id; }
    async function namespace(id:string) { const r=(await api(`storage/kv/namespaces/${id}`))?.result; if(r?.id!==id||r?.title!==title) throw new AppError('CF_CONFLICT','配置存储不属于本次部署，已停止操作。',409); }
    async function subdomain():Promise<string> { const name=(await api('workers/subdomain'))?.result?.subdomain; if(typeof name!=='string'||!/^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/.test(name)) throw new AppError('CF_SUBDOMAIN','请先在 Cloudflare 控制台启用账号的 workers.dev 子域名。'); return name; }
    const s=await settings(); let id=i.namespaceId;
    if(i.step==='prepare') {
      await subdomain();
      if(s) { id=bound(s); await namespace(id); }
      else {
        await source();
        for(let page=1;page<=10;page++) {
          const value=await api(`storage/kv/namespaces?per_page=100&page=${page}`), list=value?.result;
          if(!Array.isArray(list)) throw new AppError('CF_RESPONSE','无法核对配置存储列表。',502);
          const matches=list.filter((n:any)=>n?.title===title);
          if(matches.length>1) throw new AppError('CF_CONFLICT','存在重复的部署存储，请在 Cloudflare 控制台检查。',409);
          if(matches.length) { id=matches[0].id; break; }
          if(list.length<100) break;
          if(page===10) throw new AppError('CF_NAMESPACES','配置存储数量过多，请在 Cloudflare 控制台整理后重试。');
        }
        if(!id) id=(await api('storage/kv/namespaces',json({title})))?.result?.id;
        if(typeof id!=='string'||!/^[a-f0-9]{32}$/.test(id)) throw new AppError('CF_RESPONSE','未能确认配置存储，请使用相同参数重试。',502);
        await namespace(id);
      }
      return {step:i.step,namespaceId:id};
    }
    await namespace(id!);
    if(s&&bound(s)!==id) throw new AppError('CF_CONFLICT','Worker 绑定的配置存储与本次部署不同。',409);
    if(i.step==='upload') {
      if(!s) { const code=await source(); if(!await settings()) {
        const form=new FormData(); form.set('metadata',new Blob([JSON.stringify(await cfnewMetadata(i,id!))],{type:'application/json'})); form.set('worker.js',new Blob([code],{type:'application/javascript+module'}),'worker.js');
        await api(path,{method:'PUT',body:form});
      } }
      const saved=await settings(); if(!saved||bound(saved)!==id) throw new AppError('CF_VERIFY','Worker 上传后未能确认，请重试。',502);
      return {step:i.step,namespaceId:id};
    }
    if(!s) throw new AppError('CF_MISSING','Worker 尚未上传，请重新部署。',409);
    if(i.step==='activate') await api(`${path}/subdomain`,json({enabled:true,previews_enabled:false}));
    const access=(await api(`${path}/subdomain`))?.result;
    if(access?.enabled!==true) throw new AppError('CF_VERIFY','workers.dev 访问尚未启用，请重试。',502);
    const domain=await subdomain(), base=`https://${i.workerName}.${domain}.workers.dev`;
    let verified=false;
    if(i.step==='verify') try { const r=await send(`${base}/${i.uuid}/api/config`,{},128*1024); verified=r.status===200&&JSON.parse(r.text)?.kvEnabled===true; } catch { /* Retain the deployment while edge propagation completes. */ }
    return {step:i.step,namespaceId:id,phase:'deployed',runtimeVerified:verified,workerUrl:base,managementUrl:`${base}/${i.uuid}`,subscriptionUrl:`${base}/${i.uuid}/sub`,clashUrl:`${base}/${i.uuid}/sub?target=clash`,dashboardUrl:`https://dash.cloudflare.com/${i.accountId}/workers/services/view/${i.workerName}/production`};
  };
}
