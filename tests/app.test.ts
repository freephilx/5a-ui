import { describe, expect, it, vi } from 'vitest';
import { createApp } from '../src/server/app';

const input = { host: '8.8.8.8', authMethod: 'password', password: 'secret' };
function request(path: string, data: object = input, origin = 'https://selfhost.test') {
  return new Request(`https://selfhost.test/api/${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: origin }, body: JSON.stringify(data) });
}
const okLimit = { limit: async () => ({ success: true }) };
const env = { REQUEST_LIMITER: okLimit, INSTALL_LIMITER: okLimit };

describe('API access and output', () => {
  it('rejects cross-origin operations before SSH', async () => {
    const ssh = vi.fn();
    const response = await createApp(ssh)(request('install', input, 'https://other.test'), env);
    expect(response.status).toBe(403);
    expect(ssh).not.toHaveBeenCalled();
  });
  it('enforces a public destination before SSH', async () => {
    const ssh = vi.fn();
    expect((await createApp(ssh)(request('status', { ...input, host: '169.254.169.254' }), env)).status).toBe(400);
    expect(ssh).not.toHaveBeenCalled();
  });
  it('enforces rate limits before credential processing', async () => {
    const ssh = vi.fn();
    const response = await createApp(ssh)(request('install'), { REQUEST_LIMITER: { limit: async () => ({ success: false }) } });
    expect(response.status).toBe(429);
    expect(response.headers.get('retry-after')).toBe('60');
    expect(ssh).not.toHaveBeenCalled();
  });
  it('pins the observed fingerprint and prevents response caching', async () => {
    const ssh = vi.fn().mockResolvedValue({ stdout: '5A_UI_RESULT={"phase":"queued","message":"started"}', fingerprint: 'SHA256:recorded' });
    const response = await createApp(ssh)(request('install'), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ phase: 'queued', message: 'started', hostFingerprint: 'SHA256:recorded' });
    expect(response.headers.get('cache-control')).toBe('no-store');
    expect(response.headers.get('referrer-policy')).toBe('no-referrer');
  });
  it('does not expose a raw exception containing credentials', async () => {
    const ssh = vi.fn().mockRejectedValue(new Error('unexpected password=secret'));
    const response = await createApp(ssh)(request('status'), env);
    expect(response.status).toBe(500);
    expect(await response.text()).not.toContain('secret');
  });
  it('probes the current validated IP and updates an IPv6 node link', async () => {
    const ssh = vi.fn().mockResolvedValue({ stdout: '5A_UI_RESULT={"phase":"ready","message":"ok","running":true,"node":{"host":"8.8.8.8","port":443,"serverName":"www.microsoft.com","link":"vless://abc@8.8.8.8:443?security=reality#node"}}', fingerprint: 'SHA256:recorded' });
    const probe = vi.fn().mockResolvedValue(false);
    const response = await createApp(ssh, probe)(request('status', { ...input, host: '2606:4700:4700::1111' }), env);
    const result = await response.json();
    expect(result.node.link).toContain('@[2606:4700:4700::1111]:443');
    expect(result.portReachable).toBe(false);
    expect(probe).toHaveBeenCalledWith('2606:4700:4700::1111', 443);
  });
});
