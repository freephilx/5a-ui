import { generateKeyPairSync, createHash } from 'node:crypto';
import { workerBundle } from './worker-bundle';
import { Miniflare, convertV4MiniflareOptions } from 'miniflare';
import ssh2 from 'ssh2';
import { strict as assert } from 'node:assert';

const hostKey = ssh2.utils.generateKeyPairSync('ed25519').private;
const parsedHostKey = ssh2.utils.parseKey(hostKey);
assert(!(parsedHostKey instanceof Error) && !Array.isArray(parsedHostKey));
const fingerprint = `SHA256:${createHash('sha256').update(parsedHostKey.getPublicSSH()).digest('base64').replace(/=+$/, '')}`;
const rsa = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs1', format: 'pem', cipher: 'aes-256-cbc', passphrase: 'test-key-passphrase' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
const edKey = ssh2.utils.generateKeyPairSync('ed25519').private;
const encryptedEdKey = ssh2.utils.generateKeyPairSync('ed25519', { cipher: 'aes256-ctr', passphrase: 'test-key-passphrase', rounds: 16 }).private;
const rsaPKCS8 = generateKeyPairSync('rsa', { modulusLength: 2048, privateKeyEncoding: { type: 'pkcs8', format: 'pem', cipher: 'aes-256-cbc', passphrase: 'test-key-passphrase' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
const ecPKCS8 = generateKeyPairSync('ec', { namedCurve: 'prime256v1', privateKeyEncoding: { type: 'pkcs8', format: 'pem' }, publicKeyEncoding: { type: 'spki', format: 'pem' } });
const rsaParsed = ssh2.utils.parseKey(rsa.privateKey, 'test-key-passphrase');
const edParsed = ssh2.utils.parseKey(edKey);
assert(!(rsaParsed instanceof Error) && !Array.isArray(rsaParsed));
assert(!(edParsed instanceof Error) && !Array.isArray(edParsed));
const encryptedEdParsed = ssh2.utils.parseKey(encryptedEdKey, 'test-key-passphrase');
assert(!(encryptedEdParsed instanceof Error) && !Array.isArray(encryptedEdParsed));
// Server verification keys use native Node normalization; the Worker exercises its own crypto implementation.
const { createPrivateKey } = await import('node:crypto');
const rsaPKCS8Parsed = ssh2.utils.parseKey(createPrivateKey({ key: rsaPKCS8.privateKey, passphrase: 'test-key-passphrase' }).export({ type: 'pkcs1', format: 'pem' }));
const ecPKCS8Parsed = ssh2.utils.parseKey(createPrivateKey(ecPKCS8.privateKey).export({ type: 'sec1', format: 'pem' }));
assert(!(rsaPKCS8Parsed instanceof Error) && !Array.isArray(rsaPKCS8Parsed));
assert(!(ecPKCS8Parsed instanceof Error) && !Array.isArray(ecPKCS8Parsed));
const publicKeys = [rsaParsed, edParsed, encryptedEdParsed, rsaPKCS8Parsed, ecPKCS8Parsed];
const server = new ssh2.Server({ hostKeys: [hostKey] }, (client) => {
  client.on('error', () => {});
  client.on('authentication', (ctx) => {
    if (ctx.username !== 'root') return ctx.reject();
    if (ctx.method === 'password' && ctx.password === 'test-password') return ctx.accept();
    if (ctx.method === 'publickey') {
      const key = publicKeys.find((key) => key.getPublicSSH().equals(ctx.key.data));
      if (key && (!ctx.signature || key.verify(ctx.blob!, ctx.signature, ctx.hashAlgo) === true)) return ctx.accept();
    }
    ctx.reject();
  });
  client.on('ready', () => client.on('session', (accept) => {
    const session = accept();
    session.on('exec', (acceptCommand) => {
      const stream = acceptCommand();
      let script = '';
      stream.on('data', (chunk: Buffer) => { script += chunk.toString(); });
      stream.on('end', () => {
        stream.write(script.includes('worker-ssh-ok') ? 'worker-ssh-ok' : 'unexpected-script');
        stream.exit(0);
        stream.end();
      });
    });
  }));
});
await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
const port = (server.address() as { port: number }).port;
let mf: Miniflare | undefined;
try {
  const bundle = await workerBundle('tests/worker-ssh.worker.ts', { write: false });
  mf = new Miniflare(convertV4MiniflareOptions({ modules: true, script: bundle.outputFiles![0].text, compatibilityDate: '2026-10-14', compatibilityFlags: ['nodejs_compat'] }));
  for (const auth of [
    { label: 'password', authMethod: 'password', password: 'test-password' },
    { label: 'Ed25519 OpenSSH', authMethod: 'key', privateKey: edKey },
    { label: 'encrypted RSA PEM', authMethod: 'key', privateKey: rsa.privateKey, passphrase: 'test-key-passphrase' },
    { label: 'encrypted Ed25519 OpenSSH', authMethod: 'key', privateKey: encryptedEdKey, passphrase: 'test-key-passphrase' },
    { label: 'encrypted RSA PKCS#8', authMethod: 'key', privateKey: rsaPKCS8.privateKey, passphrase: 'test-key-passphrase' },
    { label: 'EC PKCS#8', authMethod: 'key', privateKey: ecPKCS8.privateKey },
  ]) {
    const response = await mf.dispatchFetch('http://worker.test/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ host: '127.0.0.1', port, username: 'root', hostFingerprint: fingerprint, ...auth }) });
    const body = await response.json() as { stdout?: string; fingerprint?: string; error?: string };
    assert.equal(response.status, 200, JSON.stringify(body));
    assert.equal(body.stdout, 'worker-ssh-ok');
    assert.equal(body.fingerprint, fingerprint);
    console.log(`Workers SSH ${auth.label}: passed`);
  }
  const changed = await mf.dispatchFetch('http://worker.test/', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ host: '127.0.0.1', port, username: 'root', authMethod: 'password', password: 'test-password', hostFingerprint: 'SHA256:wrong' }) });
  assert.equal(changed.status, 500);
  assert.match(JSON.stringify(await changed.json()), /指纹/);
  console.log('Workers SSH host fingerprint mismatch: rejected');
  const guards = [
    { name: 'same-origin', headers: { Origin: 'http://other.test' }, data: { host: '8.8.8.8', authMethod: 'password', password: 'test-password' }, status: 403 },
    { name: 'private IP', headers: { Origin: 'http://worker.test' }, data: { host: '169.254.169.254', authMethod: 'password', password: 'test-password' }, status: 400 },
  ];
  for (const guard of guards) {
    const response = await mf.dispatchFetch('http://worker.test/api/status', { method: 'POST', headers: { 'Content-Type': 'application/json', ...guard.headers }, body: JSON.stringify(guard.data) });
    assert.equal(response.status, guard.status, await response.text());
    assert.equal(response.headers.get('Cache-Control'), 'no-store');
    console.log(`Workers API ${guard.name}: rejected`);
  }
} finally {
  await mf?.dispose();
  await new Promise<void>((resolve) => server.close(() => resolve()));
}
