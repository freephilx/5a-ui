import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { validateInput } from '../src/server/validation';
import { installScript, statusScript } from '../src/server/remote';
import { spawnSync } from 'node:child_process';
const cases = JSON.parse(readFileSync('contracts/connection-cases.json', 'utf8'));
describe('shared Dart/TypeScript input contract', () => {
  for (const entry of cases) it(entry.name, () => {
    if (entry.error) expect(() => validateInput(entry.input)).toThrow(expect.objectContaining({ code: entry.error }));
    else expect(validateInput(entry.input)).toEqual(entry.expected);
  });
  it('generates byte-identical remote commands in Dart and TypeScript', () => {
    const valid = cases.filter((entry: { error?: string }) => !entry.error).map((entry: { input: unknown }) => entry.input);
    const direct = process.env.DART_COMMAND;
    const result = spawnSync(direct || 'fvm', [...(direct ? [] : ['dart']), 'run', 'tool/contract_export.dart'], { input: JSON.stringify(valid), encoding: 'utf8', timeout: 30000 });
    expect(result.status, result.stderr).toBe(0);
    expect(JSON.parse(result.stdout)).toEqual(valid.map((value: unknown) => ({ install: installScript(validateInput(value)), status: statusScript() })));
  });
});
