import type { ConnectionInput, ServerStatus } from '../shared/types';
import { MIHOMO_JOB_SCRIPT, MIHOMO_MANAGER_SCRIPT, JOB_SCRIPT, MANAGER_SCRIPT, INSTALL_TEMPLATE, STATUS_SCRIPT, INSPECTOR_SCRIPT } from './remote.generated';
import { AppError } from './errors';

const inspect = (script: string, host: string) => script
  .replaceAll('@@INSPECTOR@@', Buffer.from(INSPECTOR_SCRIPT).toString('base64'))
  .replaceAll('@@HOST@@', Buffer.from(host).toString('base64'));
export function statusScript(host: string): string { return inspect(STATUS_SCRIPT, host); }

export function installScript(input: ConnectionInput): string {
  const b64 = (text: string) => Buffer.from(text).toString('base64');
  const config = JSON.stringify({ host: input.host, panelType: input.panelType ?? '3x-ui', nodePort: input.nodePort ?? 443, realityServerName: input.realityServerName || '' });
  return inspect(INSTALL_TEMPLATE, input.host).replaceAll('@@CONFIG@@', b64(config))
    .replaceAll('@@JOB@@', b64(JOB_SCRIPT)).replaceAll('@@MANAGER@@', b64(MANAGER_SCRIPT))
    .replaceAll('@@MIHOMO_JOB@@', Buffer.from(MIHOMO_JOB_SCRIPT).toString('base64'))
    .replaceAll('@@MIHOMO_MANAGER@@', Buffer.from(MIHOMO_MANAGER_SCRIPT).toString('base64'))
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
  for (const field of ['installed', 'running', 'truncated']) if (typeof parsed[field] === 'boolean') status[field] = parsed[field];
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
  if (Array.isArray(parsed.instances)) status.instances = instances(parsed.instances);
  if (object(parsed.management)) {
    const management = parsed.management;
    status.management = Object.fromEntries(['result', 'revision', 'session'].filter(k => k in management).map(k => [k, management[k]]));
  }
  return status as unknown as ServerStatus;
}

type Raw = Record<string, unknown>;
const object = (value: unknown): value is Raw => !!value && typeof value === 'object' && !Array.isArray(value);
function fields(value: Raw, strings: string[], booleans: string[], numbers: string[]): Raw {
  const result: Raw = {};
  for (const key of strings) if (typeof value[key] === 'string') result[key] = value[key].slice(0, 500);
  for (const key of booleans) if (typeof value[key] === 'boolean') result[key] = value[key];
  for (const key of numbers) if (typeof value[key] === 'number' && Number.isInteger(value[key]) && (key === 'expiryTime' || value[key] >= 0)) result[key] = value[key];
  const traffic = value.traffic;
  if (object(traffic) && ['up', 'down'].every(key => typeof traffic[key] === 'number' && Number.isFinite(traffic[key]) && traffic[key] >= 0)) result.traffic = { up: traffic.up, down: traffic.down };
  return result;
}

function shareLink(value: unknown): boolean {
  if (typeof value !== 'string' || value.length > 4096) return false;
  try {
    if (value.startsWith('vmess://')) {
      if (!/^[A-Za-z0-9+/_-]+={0,2}$/.test(value.slice(8))) return false;
      const node = JSON.parse(Buffer.from(value.slice(8), 'base64').toString('utf8'));
      return object(node) && typeof node.add === 'string' && !!node.add && typeof node.id === 'string' && !!node.id &&
        /^\d+$/.test(String(node.port)) && Number(node.port) > 0 && Number(node.port) <= 65535;
    }
    const url = new URL(value);
    return ['vless:', 'trojan:', 'ss:'].includes(url.protocol) && !!url.hostname && !!url.username && !!url.port && Number(url.port) > 0 && Number(url.port) <= 65535;
  } catch { return false; }
}

function instances(values: unknown[]): Raw[] {
  return values.filter((item): item is Raw => object(item) && typeof item.id === 'string' && typeof item.name === 'string' &&
    ['native', 'docker'].includes(String(item.kind)) && Array.isArray(item.inbounds)).map(item => {
    const instance = fields(item, ['id', 'name', 'kind', 'message', 'panelVersion', 'panelType'], ['running', 'readable', 'truncated'], []);
    instance.inbounds = (item.inbounds as unknown[]).filter((row): row is Raw => object(row) && typeof row.id === 'string' && typeof row.name === 'string' &&
      typeof row.protocol === 'string' && typeof row.port === 'number' && Number.isInteger(row.port) && row.port >= 0 && row.port <= 65535 && Array.isArray(row.clients)).map(row => {
      const inbound = fields(row, ['id', 'name', 'protocol', 'message'], ['enabled'], ['port']);
      inbound.clients = (row.clients as unknown[]).filter((client): client is Raw => object(client) && typeof client.id === 'string' && typeof client.name === 'string').map(client => {
        const node = fields(client, ['id', 'name', 'message', 'linkMessage'], ['enabled', 'available'], ['expiryTime', 'total']);
        if (shareLink(client.link) && typeof client.host === 'string' && typeof client.serverName === 'string' && typeof client.port === 'number' && Number.isInteger(client.port) && client.port > 0 && client.port <= 65535) {
          for (const field of ['host', 'port', 'serverName', 'link']) node[field] = client[field];
        }
        return node;
      });
      return inbound;
    });
    return instance;
  });
}
