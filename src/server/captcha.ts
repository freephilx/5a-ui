import type { ConnectionInput } from '../shared/types';
import { AppError } from './errors';

export interface CaptchaEnv { TURNSTILE_SITE_KEY?: string; TURNSTILE_SECRET_KEY?: string }

async function signingKey(secret: string) {
  return crypto.subtle.importKey('raw', new TextEncoder().encode(`5a-ui-proof-v1:${secret}`), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function authorize(input: ConnectionInput, ip: string, env: CaptchaEnv, hostname: string): Promise<string | undefined> {
  if (!env.TURNSTILE_SECRET_KEY && !env.TURNSTILE_SITE_KEY) return undefined;
  if (!env.TURNSTILE_SECRET_KEY || !env.TURNSTILE_SITE_KEY) throw new AppError('CAPTCHA_SETUP', '网站的人机验证尚未配置完成，请联系网站维护者。', 503);
  const identity = `${ip}|${input.host}|${input.port}|${input.username}`;
  const key = await signingKey(env.TURNSTILE_SECRET_KEY);
  if (input.proofToken) {
    try {
      const [data, signature, extra] = input.proofToken.split('.');
      if (extra || !data || !signature) throw new Error();
      const valid = await crypto.subtle.verify('HMAC', key, Buffer.from(signature, 'base64url'), new TextEncoder().encode(data));
      const payload = JSON.parse(Buffer.from(data, 'base64url').toString());
      if (valid && payload.identity === identity && payload.expires > Date.now() && payload.expires < Date.now() + 31 * 60_000) return input.proofToken;
    } catch { /* An expired proof needs a fresh challenge, without exposing details. */ }
  }
  if (!input.turnstileToken) throw new AppError('CAPTCHA_REQUIRED', '请完成人机验证后再试。', 403);
  let result: { success?: boolean; hostname?: string };
  try {
    const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', { method: 'POST', body: new URLSearchParams({ secret: env.TURNSTILE_SECRET_KEY, response: input.turnstileToken, remoteip: ip }), signal: AbortSignal.timeout(10_000) });
    result = await response.json();
  } catch { throw new AppError('CAPTCHA_UNAVAILABLE', '人机验证服务暂时不可用，请稍后重试。', 503); }
  if (!result.success || result.hostname !== hostname) throw new AppError('CAPTCHA_FAILED', '人机验证已过期或失败，请重新验证。', 403);
  return issueProof(input, ip, env.TURNSTILE_SECRET_KEY, Date.now() + 30 * 60_000);
}

// Only call with the proof returned by authorize in this request, after SSH
// resolves an automatic username. Preserve its expiry and never reuse CAPTCHA.
export async function rebindAuthorizedProof(proof: string, input: ConnectionInput, ip: string, env: CaptchaEnv): Promise<string> {
  const payload = JSON.parse(Buffer.from(proof.split('.')[0], 'base64url').toString());
  return issueProof(input, ip, env.TURNSTILE_SECRET_KEY!, payload.expires);
}

async function issueProof(input: ConnectionInput, ip: string, secret: string, expires: number): Promise<string> {
  const identity = `${ip}|${input.host}|${input.port}|${input.username}`;
  const key = await signingKey(secret);
  // A short proof allows polling without reusing the one-time Turnstile token.
  const data = Buffer.from(JSON.stringify({ identity, expires })).toString('base64url');
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data));
  return `${data}.${Buffer.from(signature).toString('base64url')}`;
}
