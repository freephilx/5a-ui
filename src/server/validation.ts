import ipaddr from 'ipaddr.js';
import type { ConnectionInput } from '../shared/types';
import { AppError } from './errors';
import networkRanges from '../../contracts/network-ranges.json';
import { MAX_MANAGEMENT_BYTES, validateManagement } from './management';

export const MAX_BODY_BYTES = 80 * 1024;

export function publicIP(value: unknown): string {
  if (typeof value !== 'string' || !value.trim() || value.length > 64 || value.includes('%')) throw new AppError('INVALID_HOST', '请输入服务器的公网 IPv4 或 IPv6 地址。');
  let address: ipaddr.IPv4 | ipaddr.IPv6;
  try {
    const host = value.trim();
    const dotted = host.includes(':') ? host.slice(host.lastIndexOf(':') + 1) : host;
    if ((!host.includes(':') || host.includes('.')) && !/^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$/.test(dotted)) throw new Error();
    address = ipaddr.parse(host);
  } catch { throw new AppError('INVALID_HOST', '请输入有效的公网 IP 地址，不支持域名。'); }
  if (address.kind() === 'ipv6' && (address as ipaddr.IPv6).isIPv4MappedAddress()) address = (address as ipaddr.IPv6).toIPv4Address();
  const ranges = address.kind() === 'ipv4' ? networkRanges.ipv4 : networkRanges.ipv6;
  if (ranges.some((cidr) => address.match(ipaddr.parseCIDR(cidr) as [typeof address, number]))) throw new AppError('PRIVATE_HOST', '请使用公网 IP，无法连接内网、保留或本机地址。');
  return address.toString();
}

function text(value: unknown, limit: number, label: string): string {
  if (typeof value !== 'string' || value.length > limit || value.includes('\0')) throw new AppError('INVALID_INPUT', `${label}格式不正确。`);
  return value;
}

function port(value: unknown, fallback: number): number {
  const number = value === undefined ? fallback : value;
  if (typeof number !== 'number' || !Number.isInteger(number) || number < 1 || number > 65535) throw new AppError('INVALID_PORT', '端口需要是 1–65535 之间的整数。');
  return number;
}

export function validateInput(value: unknown): ConnectionInput {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new AppError('INVALID_INPUT', '连接信息格式不正确。');
  const raw = value as Record<string, unknown>;
  const host = publicIP(raw.host);
  const username = raw.username === undefined ? 'root' : text(raw.username, 32, '用户名').trim();
  if (username && !/^[a-z_][a-z0-9_-]{0,31}$/i.test(username)) throw new AppError('INVALID_USERNAME', '请输入有效的服务器用户名，例如 root、ubuntu 或 debian。');
  if (raw.authMethod !== 'password' && raw.authMethod !== 'key') throw new AppError('INVALID_AUTH', '请选择密码登录或私钥登录。');
  const panelType = raw.panelType ?? '3x-ui';
  if (panelType !== '3x-ui' && panelType !== '3m-ui') throw new AppError('INVALID_PANEL_TYPE', '请选择 3x-ui 或 3m-ui。');
  const result: ConnectionInput = { host, username, panelType, port: port(raw.port, 22), authMethod: raw.authMethod, nodePort: port(raw.nodePort, 443) };
  if (raw.management != null) result.management = validateManagement(raw.management);
  if (result.port === result.nodePort) throw new AppError('PORT_CONFLICT', '节点端口需要与 SSH 端口不同。');
  if (result.authMethod === 'password') {
    result.password = text(raw.password, 4096, '密码');
    if (!result.password) throw new AppError('MISSING_PASSWORD', '请输入服务器密码。');
  } else {
    result.privateKey = text(raw.privateKey, 64 * 1024, '私钥').replace(/\r\n/g, '\n').trim() + '\n';
    if (!/-----BEGIN (?:OPENSSH |RSA |EC |ENCRYPTED )?PRIVATE KEY-----/.test(result.privateKey)) throw new AppError('INVALID_KEY', '请选择或粘贴 SSH 私钥。对应公钥需要已经配置在服务器上。');
    if (raw.passphrase !== undefined) result.passphrase = text(raw.passphrase, 4096, '密钥口令');
  }
  if (raw.hostFingerprint) {
    result.hostFingerprint = text(raw.hostFingerprint, 64, 'SSH 指纹').trim();
    if (!/^SHA256:[A-Za-z0-9+/]{43}$/.test(result.hostFingerprint)) throw new AppError('INVALID_FINGERPRINT', 'SSH 指纹格式应为 SHA256: 后跟 43 位字符。');
  }
  if (raw.realityServerName) {
    result.realityServerName = text(raw.realityServerName, 253, 'REALITY 目标').trim().toLowerCase();
    if (!/^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$/.test(result.realityServerName)) throw new AppError('INVALID_REALITY_TARGET', 'REALITY 目标需要是网站域名，例如 www.microsoft.com；不包含协议或端口。');
  }
  for (const field of ['turnstileToken', 'proofToken'] as const) if (raw[field]) result[field] = text(raw[field], 4096, '验证信息');
  return result;
}

export async function readInput(request: Request): Promise<ConnectionInput> {
  return validateInput(await readJsonBody(request));
}

export async function readJsonBody(request: Request): Promise<unknown> {
  const limit = new URL(request.url).pathname === '/api/manage' ? MAX_BODY_BYTES + MAX_MANAGEMENT_BYTES : MAX_BODY_BYTES;
  if (!request.headers.get('content-type')?.startsWith('application/json')) throw new AppError('CONTENT_TYPE', '请使用 JSON 格式提交连接信息。', 415);
  const length = Number(request.headers.get('content-length'));
  if (length > limit) throw new AppError('BODY_TOO_LARGE', '请求过大，私钥最大 64 KB，管理备份最大 2 MiB。', 413);
  const reader = request.body?.getReader();
  if (!reader) throw new AppError('INVALID_INPUT', '缺少连接信息。');
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > limit) { await reader.cancel(); throw new AppError('BODY_TOO_LARGE', '请求过大，私钥最大 64 KB，管理备份最大 2 MiB。', 413); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  let body: unknown;
  try { body = JSON.parse(new TextDecoder().decode(bytes)); } catch { throw new AppError('INVALID_JSON', '连接信息格式不正确。'); }
  return body;
}
