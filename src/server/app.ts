import { createConnection } from 'node:net';
import { AppError } from './errors';
import { readInput } from './validation';
import { runSSH } from './ssh';
import { installScript, parseRemoteResult, statusScript } from './remote';
import { authorize, type CaptchaEnv } from './captcha';
import { limitRequest, type RateEnv } from './rate-limit';
import { securityHeaders } from './security';

export type AppEnv = CaptchaEnv & RateEnv;
export type SSHRunner = typeof runSSH;

export async function probePort(host: string, port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const socket = createConnection({ host, port });
    const timer = setTimeout(() => finish(false), 4_000);
    let done = false;
    function finish(reachable: boolean) {
      if (done) return;
      done = true;
      clearTimeout(timer);
      socket.destroy();
      resolve(reachable);
    }
    socket.once('connect', () => finish(true));
    socket.once('error', () => finish(false));
  });
}

export function createApp(ssh: SSHRunner = runSSH, probe = probePort) {
  return async function handle(request: Request, env: AppEnv = {}, ip = 'unknown'): Promise<Response> {
    let response: Response;
    try {
      const url = new URL(request.url);
      if (url.pathname === '/api/health' && request.method === 'GET') return securityHeaders(Response.json({ ok: true }));
      if (url.pathname === '/api/config' && request.method === 'GET') return securityHeaders(Response.json({ turnstileSiteKey: env.TURNSTILE_SITE_KEY || null }));
      const action = url.pathname === '/api/install' ? 'install' : url.pathname === '/api/status' ? 'status' : null;
      if (!action) throw new AppError('NOT_FOUND', '此接口不存在。', 404);
      if (request.method !== 'POST') throw new AppError('METHOD_NOT_ALLOWED', '此操作需要 POST 请求。', 405);
      if (request.headers.get('origin') !== url.origin || request.headers.get('sec-fetch-site') === 'cross-site') throw new AppError('CROSS_ORIGIN', '请在本网站页面中操作。', 403);
      await limitRequest(ip, action, env);
      const input = await readInput(request);
      const proofToken = await authorize(input, ip, env, url.hostname);
      const result = await ssh(input, action === 'install' ? installScript(input) : statusScript(input.host));
      const status = parseRemoteResult(result.stdout);
      status.hostFingerprint = result.fingerprint;
      if (proofToken) status.proofToken = proofToken;
      if (status.node) {
        // A server's public IP may have changed since installation.
        const nodeURL = new URL(status.node.link);
        nodeURL.hostname = input.host.includes(':') ? `[${input.host}]` : input.host;
        status.node.link = nodeURL.toString();
        status.node.host = input.host;
        status.portReachable = await probe(input.host, status.node.port);
      }
      response = Response.json(status);
    } catch (error) {
      const safe = error instanceof AppError ? error : new AppError('INTERNAL_ERROR', '网站暂时无法完成操作，请稍后重试。', 500);
      response = Response.json({ error: { code: safe.code, message: safe.message } }, { status: safe.status });
      if (safe.status === 429) response.headers.set('Retry-After', '60');
    }
    return securityHeaders(response);
  };
}

export const handleAPI = createApp();
