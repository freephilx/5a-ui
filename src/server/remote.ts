import type { ConnectionInput, ServerStatus } from '../shared/types';
import { JOB_SCRIPT, MANAGER_SCRIPT, INSTALL_TEMPLATE, STATUS_SCRIPT } from './remote.generated';
import { AppError } from './errors';

export function statusScript(): string { return STATUS_SCRIPT; }

export function installScript(input: ConnectionInput): string {
  const b64 = (text: string) => Buffer.from(text).toString('base64');
  const config = JSON.stringify({ host: input.host, nodePort: input.nodePort ?? 443, realityServerName: input.realityServerName || '' });
  return INSTALL_TEMPLATE.replaceAll('@@CONFIG@@', b64(config))
    .replaceAll('@@JOB@@', b64(JOB_SCRIPT)).replaceAll('@@MANAGER@@', b64(MANAGER_SCRIPT))
    .replaceAll('@@NODE_PORT@@', String(input.nodePort ?? 443));
}

export function parseRemoteResult(stdout: string): ServerStatus {
  const line = stdout.split(/\r?\n/).filter((value) => value.startsWith('5A_UI_RESULT=')).at(-1);
  if (!line) throw new AppError('REMOTE_RESULT', '无法读取服务器状态，请确认系统环境或稍后重试。', 502);
  let parsed: Record<string, unknown>;
  try {
    const value: unknown = JSON.parse(line.slice('5A_UI_RESULT='.length));
    if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error();
    parsed = value as Record<string, unknown>;
  } catch { throw new AppError('REMOTE_RESULT', '服务器状态格式不正确，请稍后重试。', 502); }
  if (parsed.error && typeof parsed.error === 'object') {
    const error = parsed.error as Record<string, unknown>;
    throw new AppError(typeof error.code === 'string' ? error.code : 'REMOTE_ERROR', typeof error.message === 'string' ? error.message : '服务器操作失败。');
  }
  if (!['not-installed', 'existing', 'queued', 'preparing', 'installing', 'configuring', 'checking', 'ready', 'failed'].includes(String(parsed.phase)) || typeof parsed.message !== 'string') throw new AppError('REMOTE_RESULT', '服务器状态格式不正确。', 502);
  const status: Record<string, unknown> = { phase: parsed.phase, message: parsed.message.slice(0, 500) };
  for (const field of ['updatedAt', 'panelVersion', 'xrayVersion', 'firewall']) if (typeof parsed[field] === 'string') status[field] = parsed[field];
  for (const field of ['installed', 'running']) if (typeof parsed[field] === 'boolean') status[field] = parsed[field];
  for (const field of ['cpu', 'uptime']) if (typeof parsed[field] === 'number' && Number.isFinite(parsed[field])) status[field] = parsed[field];
  for (const [field, keys] of Object.entries({ memory: ['current', 'total'], traffic: ['up', 'down'] })) {
    const value = parsed[field] as Record<string, unknown> | undefined;
    if (value && keys.every((key) => typeof value[key] === 'number' && Number.isFinite(value[key]) && value[key] >= 0)) status[field] = Object.fromEntries(keys.map((key) => [key, value[key]]));
  }
  const node = parsed.node as Record<string, unknown> | undefined;
  if (node && typeof node.host === 'string' && typeof node.serverName === 'string' && typeof node.port === 'number' && Number.isInteger(node.port) && node.port > 0 && node.port <= 65535 && typeof node.link === 'string') {
    try {
      const url = new URL(node.link);
      if (url.protocol === 'vless:' && url.hostname && url.username) status.node = Object.fromEntries(['host', 'port', 'serverName', 'link'].map((key) => [key, node[key]]));
    } catch { /* Ignore malformed nodes; do not probe arbitrary destinations. */ }
  }
  return status as unknown as ServerStatus;
}
