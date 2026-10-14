import { describe, expect, it } from 'vitest';
import { publicIP, validateInput } from '../src/server/validation';
import { installScript, parseRemoteResult, statusScript } from '../src/server/remote';
import { spawnSync } from 'node:child_process';

describe('public SSH destinations', () => {
  it.each(['127.0.0.1', '10.0.0.1', '172.16.0.1', '192.168.1.1', '169.254.169.254', '100.64.0.1', '0.0.0.0', '224.0.0.1', '192.0.2.1', '::1', 'fc00::1', 'fe80::1', '::ffff:127.0.0.1', '2001:db8::1', 'example.com', '1.1.1.1;echo secret', 'fe80::1%en0'])('blocks %s', (value) => expect(() => publicIP(value)).toThrow());
  it('normalizes public IPv4 and IPv6 addresses', () => {
    expect(publicIP(' 8.8.8.8 ')).toBe('8.8.8.8');
    expect(publicIP('2606:4700:4700:0:0:0:0:1111')).toBe('2606:4700:4700::1111');
    expect(publicIP('::ffff:8.8.8.8')).toBe('8.8.8.8');
  });
  it('does not coerce ports or accept command syntax', () => {
    const base = { host: '8.8.8.8', authMethod: 'password', password: 'secret' };
    expect(() => validateInput({ ...base, port: '22' })).toThrow();
    expect(() => validateInput({ ...base, port: 65536 })).toThrow();
    expect(() => validateInput({ ...base, username: 'root;reboot' })).toThrow();
    expect(() => validateInput({ ...base, realityServerName: 'localhost' })).toThrow();
    expect(() => validateInput({ ...base, nodePort: 22 })).toThrow();
  });
});

describe('remote execution boundary', () => {
  it('keeps SSH secrets out of the dispatched script and persists only node settings', () => {
    const input = validateInput({ host: '8.8.8.8', authMethod: 'password', password: 'secret-do-not-save-123' });
    const script = installScript(input);
    expect(script).not.toContain(input.password);
    const payload = script.match(/printf '%s' '([^']+)' \| base64 -d >'\/var\/lib\/5a-ui\/request.json'/)![1];
    expect(JSON.parse(Buffer.from(payload, 'base64').toString())).toEqual({ host: '8.8.8.8', nodePort: 443, realityServerName: '' });
    for (const value of [script, statusScript('8.8.8.8')]) expect(spawnSync('/bin/bash', ['-n'], { input: value }).status).toBe(0);
  });
  it('never forwards installer output or unknown credential fields', () => {
    const status = parseRemoteResult('Password: unsafe-secret\n5A_UI_RESULT={"phase":"ready","message":"ok","apiToken":"unsafe-token","privateKey":"unsafe-key"}\n');
    expect(status).toEqual({ phase: 'ready', message: 'ok' });
  });
  it('rejects corrupt responses and surfaces a controlled remote failure', () => {
    expect(() => parseRemoteResult('random output')).toThrow();
    expect(() => parseRemoteResult('5A_UI_RESULT={"phase":"invented","message":"ok"}')).toThrow();
    expect(() => parseRemoteResult('5A_UI_RESULT={"error":{"code":"NODE_PORT_BUSY","message":"端口已被占用"}}')).toThrow('端口已被占用');
  });
});
