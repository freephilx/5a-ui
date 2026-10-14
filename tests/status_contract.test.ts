import { readFileSync } from 'node:fs';
import { describe, it, expect } from 'vitest';
import { parseRemoteResult } from '../src/server/remote';

const cases = JSON.parse(readFileSync('contracts/status-cases.json', 'utf8'));
describe('shared status output contract', () => {
  for (const entry of cases) it(entry.name, () => {
    expect(parseRemoteResult('5A_UI_RESULT=' + JSON.stringify(entry.input))).toEqual(entry.expected);
  });
});
