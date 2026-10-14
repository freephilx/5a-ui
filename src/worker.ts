import { handleAPI, type AppEnv } from './server/app';
import { securityHeaders } from './server/security';

interface Env extends AppEnv { ASSETS: { fetch(request: Request): Promise<Response> } }
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (new URL(request.url).pathname.startsWith('/api/')) return handleAPI(request, env, request.headers.get('cf-connecting-ip') || 'unknown');
    return securityHeaders(await env.ASSETS.fetch(request));
  },
};
