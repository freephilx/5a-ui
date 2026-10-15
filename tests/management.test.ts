import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { describe, it, expect, vi } from 'vitest';
import { validateManagement, managementScript } from '../src/server/management';
import { createApp } from '../src/server/app';

const cases = JSON.parse(readFileSync('contracts/management-cases.json', 'utf8'));
describe('panel management contract', () => {
  for (const entry of cases) it(entry.name, () => {
    if (entry.error) expect(() => validateManagement(entry.input)).toThrow(expect.objectContaining({ code: entry.error }));
    else expect(validateManagement(entry.input)).toEqual(entry.expected);
  });
  it('Dart and TypeScript send byte-identical management scripts without shell interpolation', () => {
    const inputs = cases.filter((v: any) => !v.error).map((v: any) => v.input);
    const result = spawnSync('fvm', ['dart', 'run', 'tool/management_contract_export.dart'], {
      input: JSON.stringify(inputs), encoding: 'utf8', timeout: 30000, maxBuffer: 16 * 1024 * 1024,
    });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual(inputs.map((input: any) => managementScript(input)));
    for (const input of inputs) {
      const script = managementScript(input);
      expect(script).not.toContain('synthetic-token');
      expect(spawnSync('/bin/bash', ['-n'], { input: script }).status).toBe(0);
    }
  });
  it('protects management with same-origin checks and preserves deliberate authenticated data', async () => {
    const management = { result: { streamSettings: { security: 'reality' } }, revision: 'fixture' };
    const ssh = vi.fn().mockResolvedValue({ stdout: '5A_UI_RESULT=' + JSON.stringify({ phase: 'ready', message: 'ok', management }), fingerprint: 'SHA256:fixture' });
    const app = createApp(ssh, vi.fn());
    const req = (origin: string, op: unknown = cases[0].input) => new Request('https://fixture.test/api/manage', {
      method: 'POST', headers: { origin, 'Content-Type': 'application/json' },
      body: JSON.stringify({ host: '8.8.8.8', authMethod: 'password', password: 'synthetic-ssh', management: op }),
    });
    expect((await app(req('https://other.test'))).status).toBe(403);
    expect(ssh).not.toHaveBeenCalled();
    expect((await app(req('https://fixture.test', { operation: 'arbitrary' }))).status).toBe(400);
    expect(ssh).not.toHaveBeenCalled();
    const response = await app(req('https://fixture.test'));
    expect(response.status).toBe(200);
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect((await response.json()).management).toEqual(management);
  });
});
