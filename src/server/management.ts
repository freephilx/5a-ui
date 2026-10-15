import { AppError } from './errors';
import { INSPECTOR_SCRIPT, PANEL_SCRIPT, PANEL_OPERATIONS_JSON, MIHOMO_OPERATIONS_JSON } from './remote.generated';

export const MAX_MANAGEMENT_BYTES = 3 * 1024 * 1024;
export const panelOperations = [...JSON.parse(PANEL_OPERATIONS_JSON), ...JSON.parse(MIHOMO_OPERATIONS_JSON)] as Array<{ id: string }>;
const record = (v: unknown): v is Record<string, any> => !!v && typeof v === 'object' && !Array.isArray(v);

export function validateManagement(value: unknown): Record<string, unknown> {
  const invalid = () => new AppError('PANEL_INPUT', '管理请求格式不正确。');
  if (!record(value) || typeof value.instanceId !== 'string' || value.instanceId.length > 500 ||
      !/^(native|docker):/.test(value.instanceId) ||
      !['catalog', 'service.start', 'service.stop', 'service.restart', ...panelOperations.map(op => op.id)].includes(value.operation)) throw invalid();
  if (Buffer.byteLength(JSON.stringify(value)) > MAX_MANAGEMENT_BYTES) throw new AppError('BODY_TOO_LARGE', '管理请求过大，备份最大支持 2 MiB。', 413);
  const auth = value.auth ?? {};
  if (!record(auth)) throw invalid();
  const cleanAuth: Record<string, unknown> = {};
  for (const key of ['username', 'password', 'token', 'twoFactorCode']) if (auth[key] != null) {
    if (typeof auth[key] !== 'string' || auth[key].length > 4096 || /[\r\n\0]/.test(auth[key])) throw invalid();
    cleanAuth[key] = auth[key];
  }
  if (auth.session != null) {
    if (!record(auth.session) || ['cookie', 'csrf'].some(k => typeof auth.session[k] !== 'string' || auth.session[k].length > 8192 || /[\r\n\0]/.test(auth.session[k]))) throw invalid();
    if (auth.session.bearer != null && (typeof auth.session.bearer !== 'string' || auth.session.bearer.length > 8192 || /[\r\n\0]/.test(auth.session.bearer))) throw invalid();
    cleanAuth.session = { ...(auth.session.bearer != null ? { bearer: auth.session.bearer } : {}), cookie: auth.session.cookie, csrf: auth.session.csrf };
  }
  for (const key of ['parameters', 'precondition']) if (value[key] != null && !record(value[key])) throw invalid();
  const endpoint = value.endpoint;
  if (endpoint != null && (!record(endpoint) || !Number.isInteger(endpoint.port) || endpoint.port < 1 || endpoint.port > 65535 ||
      typeof endpoint.path !== 'string' || !endpoint.path.startsWith('/') || endpoint.path.length > 1024 || /[?#\\\r\n\0]/.test(endpoint.path) ||
      ![null, undefined, '127.0.0.1', '::1'].includes(endpoint.listen) ||
      (endpoint.https != null && typeof endpoint.https !== 'boolean') ||
      (endpoint.domain != null && (typeof endpoint.domain !== 'string' || !/^[A-Za-z0-9.-]{1,253}$/.test(endpoint.domain))))) throw invalid();
  return { instanceId: value.instanceId, operation: value.operation, auth: cleanAuth,
    ...(endpoint != null ? { endpoint: Object.fromEntries(['port', 'path', 'listen', 'https', 'domain'].filter(k => endpoint[k] != null).map(k => [k, endpoint[k]])) } : {}),
    ...(value.confirmed === true ? { confirmed: true } : {}),
    ...Object.fromEntries(['parameters', 'data', 'precondition'].filter(k => value[k] != null).map(k => [k, value[k]])) };
}

export function managementScript(request: unknown, host = ''): string {
  const b64 = (s: string) => Buffer.from(s).toString('base64');
  return "set -eu\npython3 - <<'FIVE_A_PANEL'\n" +
    'import base64,json,types\n' +
    "inspector=types.ModuleType('five_a_inspector')\n" +
    `exec(base64.b64decode('${b64(INSPECTOR_SCRIPT)}'),inspector.__dict__)\n` +
    `exec(base64.b64decode('${b64(PANEL_SCRIPT)}'))\n` +
    `main(json.loads(base64.b64decode('${b64(JSON.stringify(validateManagement(request)))}')),inspector,` +
    `json.loads(base64.b64decode('${b64(JSON.stringify(panelOperations))}')),base64.b64decode('${b64(host)}').decode())\nFIVE_A_PANEL\n`;
}
