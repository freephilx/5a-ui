import ssh2 from 'ssh2';
import { createHash, createPrivateKey } from 'node:crypto';
import { StringDecoder } from 'node:string_decoder';
import type { ConnectionInput } from '../shared/types';
import { AppError } from './errors';

const { Client, utils } = ssh2;
const MAX_OUTPUT = 128 * 1024;

export function validatePrivateKey(input: ConnectionInput): string | undefined {
  if (input.authMethod !== 'key') return;
  let material = input.privateKey!;
  if (/-----BEGIN (?:ENCRYPTED )?PRIVATE KEY-----/.test(material)) {
    try {
      const key = createPrivateKey({ key: material, passphrase: input.passphrase || undefined });
      if (key.asymmetricKeyType === 'rsa') material = key.export({ type: 'pkcs1', format: 'pem' }).toString();
      else if (key.asymmetricKeyType === 'ec') material = key.export({ type: 'sec1', format: 'pem' }).toString();
    } catch { throw new AppError('INVALID_KEY', '无法读取 SSH 私钥，请检查私钥内容和密钥口令。'); }
  }
  const parsed = utils.parseKey(material, input.passphrase || undefined);
  if (parsed instanceof Error) {
    throw new AppError('INVALID_KEY', '无法读取 SSH 私钥。请检查私钥格式；加密的私钥还需要正确的密钥口令。');
  }
  const keys = Array.isArray(parsed) ? parsed : [parsed];
  if (!keys.length || !keys.every((key) => key.isPrivateKey())) {
    throw new AppError('INVALID_KEY', '请选择 SSH 私钥文件（例如 id_ed25519），并确认对应公钥已添加到服务器。');
  }
  return material;
}

function connectionError(error: Error & { level?: string }): AppError {
  if (error.level === 'client-authentication') return new AppError('SSH_AUTH', 'SSH 登录失败，请检查用户名、密码或私钥，以及服务器是否允许此登录方式。', 401);
  if (/timed out|timeout/i.test(error.message)) return new AppError('SSH_TIMEOUT', '连接服务器超时，请检查 IP、SSH 端口和云平台安全组。', 504);
  if (/ECONNREFUSED/.test(error.message)) return new AppError('SSH_REFUSED', '服务器拒绝连接，请确认 SSH 服务正在运行且端口填写正确。', 502);
  return new AppError('SSH_CONNECTION', '无法建立 SSH 连接，请检查服务器网络和 SSH 设置。', 502);
}

export async function runSSH(input: ConnectionInput, script: string, timeoutMs = 30_000): Promise<{ stdout: string; fingerprint: string }> {
  const privateKey = validatePrivateKey(input);
  return new Promise((resolve, reject) => {
    const client = new Client();
    let settled = false;
    let fingerprint = '';
    let stdout = '';
    const decoder = new StringDecoder('utf8');
    const timer = setTimeout(() => finish(new AppError('SSH_TIMEOUT', '服务器响应超时。已启动的安装任务会继续运行，可重新读取状态。', 504)), timeoutMs);
    function finish(error?: Error) {
      if (settled) return;
      settled = true;
      clearTimeout(timer);
      client.end();
      if (error) reject(error); else resolve({ stdout, fingerprint });
    }
    client.on('error', (error) => { const wrapped = connectionError(error); wrapped.cause = error; finish(wrapped); });
    client.on('close', () => { if (!settled) finish(new AppError('SSH_CLOSED', 'SSH 连接提前断开，请重新读取状态。', 502)); });
    client.on('ready', () => {
      // The command is fixed. All script content is sent over encrypted stdin.
      // Only root or passwordless sudo is supported; sudo never consumes script input as a password.
      client.exec('if [ "$(id -u)" = 0 ]; then exec /bin/bash -s; elif sudo -n true 2>/dev/null; then exec sudo -n /bin/bash -s; else exit 77; fi', (error, stream) => {
        if (error) { finish(connectionError(error)); return; }
        stream.on('data', (chunk: Buffer) => {
          stdout += decoder.write(chunk);
          if (Buffer.byteLength(stdout) > MAX_OUTPUT) finish(new AppError('REMOTE_OUTPUT', '服务器返回的数据过大。', 502));
        });
        // Remote stderr may contain secrets from the upstream installer. Never return or log it.
        stream.stderr.on('data', () => {});
        stream.on('error', () => finish(new AppError('REMOTE_COMMAND', '读取服务器结果失败，请重试。', 502)));
        stream.on('close', (code: number | undefined) => {
          stdout += decoder.end();
          if (code === 77) finish(new AppError('SUDO_REQUIRED', '此账号没有安装权限。请使用 root，或具有免密 sudo 权限的账号。', 403));
          else if (code !== 0) finish(new AppError('REMOTE_COMMAND', '服务器操作失败，请确认系统支持 Bash，并使用 root 或具有免密 sudo 权限的账号。', 502));
          else finish();
        });
        stream.end(script);
      });
    });
    try {
      client.connect({
        host: input.host, port: input.port, username: input.username,
        ...(input.authMethod === 'password' ? { password: input.password } : { privateKey, passphrase: input.passphrase || undefined }),
        readyTimeout: 15_000,
        keepaliveInterval: 5_000,
        keepaliveCountMax: 2,
        hostVerifier(key: Buffer) {
          fingerprint = `SHA256:${createHash('sha256').update(key).digest('base64').replace(/=+$/, '')}`;
          if (input.hostFingerprint && fingerprint !== input.hostFingerprint) {
            finish(new AppError('HOST_KEY_CHANGED', 'SSH 主机指纹与记录不一致。请核对服务器是否重装或更换；确认后再更新指纹。', 409));
            return false;
          }
          return true;
        },
        // Workers' CommonJS crypto lacks diffieHellman; its GCM requires the tag before update().
        // NIST P-256 + AES-CTR + SHA-2 HMAC works in both runtimes and default OpenSSH servers.
        algorithms: {
          kex: ['ecdh-sha2-nistp256'],
          cipher: ['aes128-ctr', 'aes256-ctr'],
          serverHostKey: ['ssh-ed25519', 'ecdsa-sha2-nistp256', 'rsa-sha2-512', 'rsa-sha2-256'],
          hmac: ['hmac-sha2-256-etm@openssh.com', 'hmac-sha2-512-etm@openssh.com', 'hmac-sha2-256', 'hmac-sha2-512'],
          compress: ['none'],
        },
      });
    } catch (error) {
      const wrapped = new AppError('SSH_CONFIGURATION', '无法使用这些 SSH 登录信息，请检查私钥和连接设置。');
      wrapped.cause = error;
      finish(wrapped);
    }
  });
}
