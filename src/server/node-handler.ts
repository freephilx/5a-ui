import type { IncomingMessage, ServerResponse } from 'node:http';
import { handleAPI } from './app';
import { MAX_BODY_BYTES } from './validation';

export async function nodeHandler(req: IncomingMessage, res: ServerResponse, route?: string): Promise<void> {
  const isLocal = !process.env.VERCEL;
  const origin = `${isLocal ? 'http' : 'https'}://${req.headers.host || 'localhost:5000'}`;
  const headers = new Headers();
  for (const [key, value] of Object.entries(req.headers)) if (value) headers.set(key, Array.isArray(value) ? value.join(',') : value);
  const chunks: Buffer[] = [];
  let length = 0;
  try {
    for await (const chunk of req) {
      length += chunk.length;
      if (length > MAX_BODY_BYTES) {
        res.writeHead(413, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
        res.end(JSON.stringify({ error: { code: 'BODY_TOO_LARGE', message: '连接信息过大，私钥文件最大支持 64 KB。' } }));
        return;
      }
      chunks.push(Buffer.from(chunk));
    }
    // Vercel may already have parsed the body before invoking a Node handler.
    const parsedBody = (req as IncomingMessage & { body?: unknown }).body;
    const body = length ? Buffer.concat(chunks) : parsedBody === undefined ? undefined : Buffer.from(typeof parsedBody === 'string' ? parsedBody : JSON.stringify(parsedBody));
    if (body && body.byteLength > MAX_BODY_BYTES) {
      res.writeHead(413, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
      res.end(JSON.stringify({ error: { code: 'BODY_TOO_LARGE', message: '连接信息过大，私钥文件最大支持 64 KB。' } }));
      return;
    }
    const request = new Request(new URL(route || req.url || '/', origin), { method: req.method, headers, ...(body ? { body } : {}) });
    const ip = process.env.VERCEL ? headers.get('x-vercel-forwarded-for')?.split(',')[0].trim() || 'unknown' : req.socket.remoteAddress || 'local';
    const response = await handleAPI(request, { TURNSTILE_SITE_KEY: process.env.TURNSTILE_SITE_KEY, TURNSTILE_SECRET_KEY: process.env.TURNSTILE_SECRET_KEY }, ip);
    res.writeHead(response.status, Object.fromEntries(response.headers));
    res.end(Buffer.from(await response.arrayBuffer()));
  } catch {
    res.writeHead(500, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify({ error: { code: 'INTERNAL_ERROR', message: '服务器暂时无法处理此请求，请重试。' } }));
  }
}
