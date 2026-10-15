import { describe, expect, it } from 'vitest';
import { createServer, type Socket } from 'node:net';
import { spawn } from 'node:child_process';
import ssh2 from 'ssh2';
import { runSSH } from '../src/server/ssh';
import { generateEd25519Key } from './ssh-keys.mjs';
import candidates from '../contracts/ssh-usernames.json';
import type { ConnectionInput } from '../src/shared/types';

const privateKey = generateEd25519Key();
const publicKey = ssh2.utils.parseKey(privateKey) as ssh2.ParsedKey;

async function fixture(options: { username?: string; rotate?: boolean; delay?: number; exitCode?: number } = {}) {
  const attempts: string[] = [];
  const scripts: string[] = [];
  const sockets = new Set<Socket>();
  const servers = [generateEd25519Key(), generateEd25519Key()].map(hostKey => new ssh2.Server({ hostKeys: [hostKey] }, client => {
    let seen = false;
    let closed = false;
    client.on('error', () => {});
    client.on('close', () => { closed = true; });
    client.on('authentication', ctx => {
      if (!seen) { seen = true; attempts.push(ctx.username); }
      const authenticate = () => {
        if (closed) return;
        if (ctx.username === (options.username ?? 'ubuntu')) {
          if (ctx.method === 'password' && ctx.password === 'fixture-password') return ctx.accept();
          if (ctx.method === 'publickey' && ctx.key.data.equals(publicKey.getPublicSSH()) &&
              (!ctx.signature || publicKey.verify(ctx.blob!, ctx.signature, ctx.hashAlgo) === true)) return ctx.accept();
        }
        ctx.reject(['password', 'publickey']);
      };
      if (options.delay) setTimeout(authenticate, options.delay); else authenticate();
    });
    client.on('ready', () => client.on('session', accept => accept().on('exec', acceptCommand => {
      const stream = acceptCommand();
      let script = '';
      stream.on('data', (chunk: Buffer) => { script += chunk; });
      stream.on('end', () => {
        scripts.push(script);
        stream.write('fixture-success');
        stream.exit(options.exitCode ?? 0);
        stream.end();
      });
    })));
  }));
  let connections = 0;
  const gate = createServer(socket => {
    sockets.add(socket);
    socket.on('close', () => sockets.delete(socket));
    servers[options.rotate && connections++ > 0 ? 1 : 0].injectSocket(socket);
  });
  await new Promise<void>(resolve => gate.listen(0, '127.0.0.1', resolve));
  return {
    port: (gate.address() as { port: number }).port, attempts, scripts,
    async close() {
      for (const socket of sockets) socket.destroy();
      await new Promise<void>(resolve => gate.close(() => resolve()));
    },
  };
}

type Result = { stdout?: string; username?: string; fingerprint?: string; error?: string };
async function invoke(runtime: string, input: ConnectionInput, timeout = 3000, cancelAfter?: number): Promise<Result> {
  if (runtime === 'Node') {
    try { return await runSSH(input, 'fixture-script', timeout); }
    catch (error) { return { error: (error as { code: string }).code }; }
  }
  return new Promise((resolve, reject) => {
    const direct = process.env.DART_COMMAND;
    const child = spawn(direct || 'fvm', [...(direct ? [] : ['dart']), 'run', 'tool/ssh_auto_smoke.dart'], { shell: process.platform === 'win32' });
    const timer = setTimeout(() => child.kill(), 12000);
    let stdout = '', stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', reject);
    child.on('exit', code => {
      clearTimeout(timer);
      if (code !== 0) reject(new Error(stderr));
      else { try { resolve(JSON.parse(stdout)); } catch (error) { reject(error); } }
    });
    child.stdin.end(JSON.stringify({ ...input, timeout, cancelAfter }));
  });
}

describe.each(['Node', 'Dart'])('%s automatic SSH login with a local SSH server', runtime => {
  for (const authMethod of ['password', 'key'] as const) it(`falls back to ubuntu with ${authMethod} and executes once`, async () => {
    const server = await fixture();
    try {
      const result = await invoke(runtime, { host: '127.0.0.1', port: server.port, username: '', authMethod, password: 'fixture-password', privateKey });
      expect(result).toMatchObject({ stdout: 'fixture-success', username: 'ubuntu' });
      expect(result.fingerprint).toMatch(/^SHA256:/);
      expect(server.attempts).toEqual(['root', 'ubuntu']);
      expect(server.scripts).toEqual(['fixture-script']);
    } finally { await server.close(); }
  }, 15000);

  for (const scenario of [
    { name: 'root success', options: { username: 'root' }, user: '', expected: undefined, attempts: ['root'], scripts: 1 },
    { name: 'explicit username', options: {}, user: 'root', expected: 'SSH_AUTH', attempts: ['root'], scripts: 0 },
    { name: 'exhausted candidates', options: { username: 'custom' }, user: '', expected: 'SSH_AUTH', attempts: candidates, scripts: 0 },
    { name: 'changed key between attempts', options: { rotate: true }, user: '', expected: 'HOST_KEY_CHANGED', attempts: ['root'], scripts: 0 },
    { name: 'sudo failure after authentication', options: { exitCode: 77 }, user: '', expected: 'SUDO_REQUIRED', attempts: ['root', 'ubuntu'], scripts: 1 },
    { name: 'remote command failure', options: { exitCode: 1 }, user: '', expected: 'REMOTE_COMMAND', attempts: ['root', 'ubuntu'], scripts: 1 },
    { name: 'shared timeout', options: { delay: 500 }, user: '', expected: 'SSH_TIMEOUT', attempts: ['root'], scripts: 0, timeout: 350 },
  ]) it(scenario.name, async () => {
    const server = await fixture(scenario.options);
    try {
      const result = await invoke(runtime, { host: '127.0.0.1', port: server.port, username: scenario.user, authMethod: 'password', password: 'fixture-password' }, scenario.timeout ?? 6000);
      expect(result.error).toBe(scenario.expected);
      expect(server.attempts).toEqual(scenario.attempts);
      expect(server.scripts).toHaveLength(scenario.scripts);
    } finally { await server.close(); }
  }, 15000);

  it('network failure never starts another attempt', async () => {
    const gate = createServer(socket => { connections++; socket.destroy(); });
    let connections = 0;
    await new Promise<void>(resolve => gate.listen(0, '127.0.0.1', resolve));
    try {
      const result = await invoke(runtime, { host: '127.0.0.1', port: (gate.address() as { port: number }).port, username: '', authMethod: 'password', password: 'fixture-password' });
      expect(result.error).not.toBe('SSH_AUTH');
      expect(result.error).toBeTruthy();
      expect(connections).toBe(1);
    } finally { await new Promise<void>(resolve => gate.close(() => resolve())); }
  }, 15000);
});

it('Dart cancellation stops username fallback', async () => {
  const server = await fixture({ delay: 500 });
  try {
    const result = await invoke('Dart', { host: '127.0.0.1', port: server.port, username: '', authMethod: 'password', password: 'fixture-password' }, 3000, 350);
    expect(result.error).toBe('CANCELLED');
    expect(server.attempts).toEqual(['root']);
    expect(server.scripts).toHaveLength(0);
  } finally { await server.close(); }
}, 15000);
