import type { ConnectionInput, ServerStatus } from '../shared/types';
import { JOB_SCRIPT, MANAGER_SCRIPT } from './remote.generated';
import { AppError } from './errors';

const ROOT = '/var/lib/huarunying';
const b64 = (text: string) => Buffer.from(text).toString('base64');
const result = (value: object) => `printf '%s\\n' 'HUARUNYING_RESULT=${JSON.stringify(value)}'\nexit 0\n`;
const existingInstallation = `existing_xui() {
  [ -e /usr/local/x-ui/x-ui ] || [ -e /etc/x-ui/x-ui.db ] || systemctl cat x-ui.service >/dev/null 2>&1 || {
    command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Image}} {{.Names}}' 2>/dev/null | grep -Eiq '(^|[/[:space:]])(3x-ui|x-ui|mhsanaei)([:/[:space:]]|$)'
  }
}
`;
const emitState = `if command -v python3 >/dev/null 2>&1 && [ -f '${ROOT}/manage.py' ]; then
  python3 '${ROOT}/manage.py' status
elif [ -f '${ROOT}/state.json' ]; then
  printf 'HUARUNYING_RESULT='; cat '${ROOT}/state.json'; printf '\\n'
else
  ${result({ phase: 'not-installed', message: '这台服务器还没有部署节点，点击一键自建开始。' })}
fi`;

export function statusScript(): string {
  return `set -eu
${existingInstallation}
if [ ! -f '${ROOT}/.managed' ]; then
  if existing_xui; then
    ${result({ phase: 'existing', message: '检测到已有 3x-ui 安装。当前版本仅管理本项目创建的节点，请使用现有面板管理。' })}
  fi
  ${result({ phase: 'not-installed', message: '这台服务器还没有部署节点，点击一键自建开始。' })}
fi
${emitState}
`;
}

export function installScript(input: ConnectionInput): string {
  // Only non-secret, validated settings are persisted on the VPS.
  const config = JSON.stringify({ host: input.host, nodePort: input.nodePort ?? 443, realityServerName: input.realityServerName || '' });
  return `set -eu
umask 077
${existingInstallation}
if [ ! -f '${ROOT}/.managed' ] && existing_xui; then
  ${result({ error: { code: 'EXISTING_INSTALLATION', message: '检测到已有 3x-ui 安装。为保留现有配置，请使用现有面板；首次自建需要一台尚未安装 3x-ui 的服务器。' } })}
fi
if [ ! -f /etc/os-release ]; then
  ${result({ error: { code: 'UNSUPPORTED_OS', message: '当前支持 Debian 11+ 或 Ubuntu 20.04+。' } })}
fi
. /etc/os-release
case "$ID" in debian|ubuntu) ;; *)
  ${result({ error: { code: 'UNSUPPORTED_OS', message: '当前支持 Debian 11+ 或 Ubuntu 20.04+。' } })}
esac
os_major=$(printf '%s' "$VERSION_ID" | cut -d. -f1)
if { [ "$ID" = debian ] && [ "$os_major" -lt 11 ]; } || { [ "$ID" = ubuntu ] && [ "$os_major" -lt 20 ]; }; then
  ${result({ error: { code: 'UNSUPPORTED_OS', message: '请使用 Debian 11+ 或 Ubuntu 20.04+。' } })}
fi
case "$(uname -m)" in x86_64|aarch64) ;; *)
  ${result({ error: { code: 'UNSUPPORTED_ARCH', message: '当前支持 x86_64 和 arm64 服务器。' } })}
esac
if ! command -v systemd-run >/dev/null 2>&1 || ! command -v flock >/dev/null 2>&1 || ! command -v ss >/dev/null 2>&1; then
  ${result({ error: { code: 'SYSTEMD_REQUIRED', message: '需要使用 systemd 管理服务的完整 Debian 或 Ubuntu 服务器。' } })}
fi
if [ -L '${ROOT}' ]; then exit 1; fi
install -d -m 700 '${ROOT}'
exec 9>'${ROOT}/dispatch.lock'
flock -x -w 5 9
if systemctl is-active --quiet huarunying-install.service; then
  ${emitState}
  exit 0
fi
if [ -f '${ROOT}/.managed' ] && [ -f '${ROOT}/state.json' ] && grep -Eq '"phase"[[:space:]]*:[[:space:]]*"ready"' '${ROOT}/state.json'; then
  ${emitState}
  exit 0
fi
if [ ! -f '${ROOT}/.managed' ]; then
  if existing_xui; then
    ${result({ error: { code: 'EXISTING_INSTALLATION', message: '检测到已有 3x-ui 安装。为保留现有配置，请使用现有面板；首次自建需要一台尚未安装 3x-ui 的服务器。' } })}
  fi
  if [ -n "$(ss -H -ltn 'sport = :${input.nodePort ?? 443}')" ]; then
    ${result({ error: { code: 'NODE_PORT_BUSY', message: `节点端口 ${input.nodePort ?? 443} 已被占用，请在高级设置中选择其他端口。` } })}
  fi
fi
printf '%s' '${b64(config)}' | base64 -d >'${ROOT}/request.json'
printf '%s' '${b64(JOB_SCRIPT)}' | base64 -d >'${ROOT}/job.sh'
printf '%s' '${b64(MANAGER_SCRIPT)}' | base64 -d >'${ROOT}/manage.py'
chmod 600 '${ROOT}/request.json' '${ROOT}/job.sh' '${ROOT}/manage.py'
touch '${ROOT}/.managed'
printf '%s\\n' '{"phase":"queued","message":"已连接服务器，安装任务正在启动…"}' >'${ROOT}/state.json.tmp'
mv '${ROOT}/state.json.tmp' '${ROOT}/state.json'
systemctl reset-failed huarunying-install.service 2>/dev/null || true
if ! systemd-run --quiet --collect --unit=huarunying-install --property=RuntimeMaxSec=1800 /bin/bash '${ROOT}/job.sh'; then
  printf '%s\\n' '{"phase":"failed","message":"无法启动安装任务，请检查 systemd 服务。"}' >'${ROOT}/state.json.tmp'
  mv '${ROOT}/state.json.tmp' '${ROOT}/state.json'
fi
printf 'HUARUNYING_RESULT='; cat '${ROOT}/state.json'; printf '\\n'
`;
}

export function parseRemoteResult(stdout: string): ServerStatus {
  const line = stdout.split(/\r?\n/).filter((line) => line.startsWith('HUARUNYING_RESULT=')).at(-1);
  if (!line) throw new AppError('REMOTE_RESULT', '无法读取服务器状态，请确认系统环境或稍后重试。', 502);
  let parsed: ServerStatus & { error?: { code?: string; message?: string } };
  try { parsed = JSON.parse(line.slice('HUARUNYING_RESULT='.length)); } catch { throw new AppError('REMOTE_RESULT', '服务器状态格式不正确，请稍后重试。', 502); }
  if (parsed.error) throw new AppError(parsed.error.code || 'REMOTE_ERROR', parsed.error.message || '服务器操作失败。');
  if (!['not-installed', 'existing', 'queued', 'preparing', 'installing', 'configuring', 'checking', 'ready', 'failed'].includes(parsed.phase) || typeof parsed.message !== 'string') throw new AppError('REMOTE_RESULT', '服务器状态格式不正确。', 502);
  // Whitelist fields: never forward arbitrary remote stdout, installation logs, or panel credentials.
  const status: ServerStatus = { phase: parsed.phase, message: parsed.message.slice(0, 500) };
  for (const field of ['updatedAt', 'installed', 'running', 'panelVersion', 'xrayVersion', 'cpu', 'memory', 'uptime', 'traffic', 'node', 'firewall'] as const) if (parsed[field] !== undefined) Object.assign(status, { [field]: parsed[field] });
  if (status.node && (!status.node.link?.startsWith('vless://') || typeof status.node.port !== 'number')) delete status.node;
  return status;
}
