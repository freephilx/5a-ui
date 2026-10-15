import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { strict as assert } from 'node:assert';
import { cfnewRelease } from '../src/server/cfnew';

// Upstream is downloaded only for this explicit smoke check, never vendored.
const bytes = process.env.CFNEW_SOURCE_FILE
  ? await readFile(process.env.CFNEW_SOURCE_FILE)
  : Buffer.from(await (await fetch(cfnewRelease.sourceUrl, { redirect: 'error', signal: AbortSignal.timeout(30_000) })).arrayBuffer());
assert.equal(createHash('sha256').update(bytes).digest('hex'), cfnewRelease.sha256);
const uuid='12345678-1234-4123-8123-123456789abc';
let outbound=0;
const mf=new Miniflare(convertV4MiniflareOptions({
  modules:true,script:bytes.toString('utf8'),compatibilityDate:cfnewRelease.compatibilityDate,
  bindings:{...cfnewRelease.defaults,u:uuid},kvNamespaces:['C'],
  outboundService:async()=>{outbound++; return new Response('External requests disabled in this test',{status:503});},
}));
try {
  const base=`https://cfnew.fixture.workers.dev/${uuid}`;
  const config=await mf.dispatchFetch(`${base}/api/config`);
  assert.equal(config.status,200);
  const initial=await config.json() as Record<string,unknown>;
  assert.equal(initial.kvEnabled,true);assert.equal(initial.ena,'yes');assert.equal(initial.dkby,'yes');assert.equal(initial.epi,'no');
  const subscription=await mf.dispatchFetch(`${base}/sub`);
  assert.equal(subscription.status,200);
  const links=Buffer.from(await subscription.text(),'base64').toString('utf8');
  assert(links.includes(`vless://${uuid}@cfnew.fixture.workers.dev:`));assert(links.includes('security=tls'));
  const clash=await mf.dispatchFetch(`${base}/sub?target=clash`);
  assert.equal(clash.status,200);assert((await clash.text()).includes('proxies:'));
  assert.equal((await mf.dispatchFetch('https://cfnew.fixture.workers.dev/wrong/api/config')).status,403);
  const save=await mf.dispatchFetch(`${base}/api/config`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({et:'yes',alpn:'h2'})});
  assert.equal(save.status,200);assert.equal((await save.json() as any).success,true);
  const updated=await (await mf.dispatchFetch(`${base}/api/config`)).json() as any;
  assert.equal(updated.et,'yes');assert.equal(updated.alpn,'h2');
  const kv=await mf.getKVNamespace('C');
  assert.equal(JSON.parse(await kv.get('c', 'text') as unknown as string).et,'yes');
  assert.equal(outbound,0);
  console.log('cfnew v3.1 workerd: config/KV, TLS VLESS, Clash subscription, invalid path, save/readback passed; no external requests.');
} finally { await mf.dispose(); }
