import { useEffect, useRef, useState } from 'react';
import { ArrowDownToLine, Check, CheckCircle2, ChevronDown, CircleHelp, Copy, Eye, EyeOff, Leaf, LoaderCircle, RefreshCw, Upload, X } from 'lucide-react';
import QRCode from 'qrcode';
import type { ApiErrorBody, ConnectionInput, LoginMethod, ServerStatus } from './shared/types';
import { Turnstile } from './components/Turnstile';

const repository = 'https://github.com/freephilx/5a-ui';
const activePhases = ['queued', 'preparing', 'installing', 'configuring', 'checking'];
const stages = [
  { key: 'preparing', label: '检查服务器' },
  { key: 'installing', label: '安装 3x-ui' },
  { key: 'configuring', label: '创建节点' },
  { key: 'checking', label: '检查连接' },
];

function bytes(value?: number) {
  if (value === undefined || !Number.isFinite(value)) return '—';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) { value /= 1024; unit++; }
  return value.toFixed(unit > 0 ? 1 : 0) + ' ' + units[unit];
}

function sleep(ms: number, signal: AbortSignal) {
  return new Promise<void>((resolve, reject) => {
    const abort = () => { clearTimeout(timer); reject(new DOMException('Aborted', 'AbortError')); };
    const timer = setTimeout(() => { signal.removeEventListener('abort', abort); resolve(); }, ms);
    signal.addEventListener('abort', abort, { once: true });
    if (signal.aborted) abort();
  });
}

function NodeResult({ status, onNotice }: { status: ServerStatus; onNotice: (message: string) => void }) {
  const [qr, setQr] = useState('');
  const [copied, setCopied] = useState(false);
  const notice = useRef(onNotice);
  notice.current = onNotice;
  useEffect(() => {
    let cancelled = false;
    setQr('');
    setCopied(false);
    if (status.node) {
      QRCode.toDataURL(status.node.link, { width: 240, margin: 2, errorCorrectionLevel: 'M', color: { dark: '#203f32', light: '#ffffff' } })
        .then((url) => { if (!cancelled) setQr(url); })
        .catch(() => { if (!cancelled) notice.current('二维码生成失败，请复制链接导入客户端。'); });
    }
    return () => { cancelled = true; };
  }, [status.node?.link]);
  useEffect(() => {
    if (!copied) return;
    const timer = setTimeout(() => setCopied(false), 2500);
    return () => clearTimeout(timer);
  }, [copied]);
  if (!status.node) return null;

  async function copy() {
    try { await navigator.clipboard.writeText(status.node!.link); setCopied(true); }
    catch { onNotice('复制失败，请展开「连接详情」手动复制。'); }
  }
  function download() {
    const url = URL.createObjectURL(new Blob([status.node!.link + '\n'], { type: 'text/plain;charset=utf-8' }));
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = '5a-ui-vless.txt';
    anchor.click();
    setTimeout(() => URL.revokeObjectURL(url), 1000);
  }

  return <div className="node-result">
    <div className="node-overview">
      <span className={status.running ? 'positive' : 'caution'}><span className="status-dot" />{status.running ? '运行中' : '未运行'}</span>
      <span className="traffic-summary"><span aria-label={'上传流量 ' + bytes(status.traffic?.up)}>↑ {bytes(status.traffic?.up)}</span><span aria-label={'下载流量 ' + bytes(status.traffic?.down)}>↓ {bytes(status.traffic?.down)}</span></span>
    </div>
    <div className="node-access">
      <div className="qr-code">{qr ? <img src={qr} alt="VLESS 节点连接二维码" width="136" height="136" /> : <LoaderCircle className="spin" size={22} />}</div>
      <div className="node-access-actions">
        <p className="protocol-label">VLESS + REALITY</p>
        <button type="button" className="button primary copy-button" onClick={() => void copy()}>{copied ? <Check size={17} /> : <Copy size={17} />}{copied ? '已复制' : '复制链接'}</button>
        <button type="button" className="text-button download-button" onClick={download}><ArrowDownToLine size={14} />下载节点</button>
      </div>
    </div>
    {status.portReachable === false && <div className="inline-note warning"><CircleHelp size={17} /><p>节点端口暂时不可达。{status.firewall || '请在云平台安全组放行节点 TCP 端口。'}</p></div>}
    <details className="result-details">
      <summary>连接详情<ChevronDown size={15} /></summary>
      <label className="sr-only" htmlFor="node-link">连接链接</label>
      <textarea id="node-link" className="node-link" readOnly value={status.node.link} rows={4} onFocus={(event) => event.target.select()} spellCheck={false} />
      <dl className="technical-details">
        <div><dt>节点端口</dt><dd>{status.node.port}</dd></div>
        <div><dt>端口可达性</dt><dd>{status.portReachable === true ? '可达' : status.portReachable === false ? '不可达' : '待检查'}</dd></div>
        <div><dt>CPU</dt><dd>{typeof status.cpu === 'number' ? status.cpu.toFixed(1) + '%' : '—'}</dd></div>
        <div><dt>内存</dt><dd>{bytes(status.memory?.current)}</dd></div>
        <div><dt>Xray</dt><dd>{status.xrayVersion || '—'}</dd></div>
        <div><dt>3x-ui</dt><dd>{status.panelVersion || '—'}</dd></div>
      </dl>
      <p className="field-hint">链接和二维码是访问凭据，请妥善保存。</p>
      {status.hostFingerprint && <div className="fingerprint"><span>SSH 主机指纹</span><code>{status.hostFingerprint}</code></div>}
    </details>
  </div>;
}

export default function App() {
  const [authMethod, setAuthMethod] = useState<LoginMethod>('password');
  const [host, setHost] = useState('');
  const [password, setPassword] = useState('');
  const [privateKey, setPrivateKey] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [keyName, setKeyName] = useState('');
  const [pasteKey, setPasteKey] = useState(false);
  const [username, setUsername] = useState('root');
  const [port, setPort] = useState('22');
  const [nodePort, setNodePort] = useState('443');
  const [target, setTarget] = useState('');
  const [fingerprint, setFingerprint] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [status, setStatus] = useState<ServerStatus | null>(null);
  const [action, setAction] = useState<'install' | 'status' | null>(null);
  const [error, setError] = useState('');
  const [notice, setNotice] = useState('');
  const [config, setConfig] = useState<{ turnstileSiteKey: string | null } | null>(null);
  const [configAttempt, setConfigAttempt] = useState(0);
  const [turnstileToken, setTurnstileToken] = useState('');
  const [proofToken, setProofToken] = useState('');
  const [challenge, setChallenge] = useState(0);
  const [paused, setPaused] = useState(false);
  const form = useRef<HTMLFormElement>(null);
  const keyFile = useRef<HTMLInputElement>(null);
  const keyText = useRef<HTMLTextAreaElement>(null);
  const hostField = useRef<HTMLInputElement>(null);
  const operation = useRef<AbortController | null>(null);
  const resultRef = useRef<HTMLElement>(null);
  const busy = action !== null;
  const canRequest = !busy && !!config && (!config.turnstileSiteKey || !!turnstileToken || !!proofToken);
  const installing = !!status && activePhases.includes(status.phase);
  const ready = status?.phase === 'ready';
  const step = Math.max(0, stages.findIndex((stage) => stage.key === status?.phase));
  const resultTitle = ready ? '你的节点' : paused ? '已暂停刷新' : busy || installing
    ? !status ? action === 'status' ? '正在读取状态' : '正在连接服务器' : '正在搭建节点'
    : status?.phase === 'existing' ? '服务器已有 3x-ui' : status?.phase === 'failed' ? '安装未完成' : '服务器还没有节点';

  useEffect(() => {
    const controller = new AbortController();
    fetch('/api/config', { signal: controller.signal }).then(async (response) => {
      if (!response.ok) throw new Error();
      setConfig(await response.json());
    }).catch(() => { if (!controller.signal.aborted) setError('网站配置加载失败，请重试。'); });
    return () => controller.abort();
  }, [configAttempt]);
  useEffect(() => () => operation.current?.abort(), []);
  useEffect(() => {
    if (action) resultRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }, [action]);
  useEffect(() => { setProofToken(''); setFingerprint(''); setStatus(null); setPaused(false); setError(''); }, [host, port]);
  useEffect(() => { setProofToken(''); setStatus(null); setPaused(false); }, [username]);
  useEffect(() => {
    if (!notice) return;
    const timer = setTimeout(() => setNotice(''), 4500);
    return () => clearTimeout(timer);
  }, [notice]);

  function switchAuth(method: LoginMethod) {
    if (method === authMethod) return;
    setAuthMethod(method); setPassword(''); setPrivateKey(''); setPassphrase(''); setKeyName('');
    setPasteKey(false); setShowPassword(false); setError('');
  }
  async function readKey(file?: File) {
    if (!file) return;
    if (file.size > 64 * 1024) { setError('私钥文件最大支持 64 KB。'); return; }
    try {
      const value = await file.text();
      if (!value.trim()) { setError('私钥文件为空，请重新选择。'); return; }
      setPrivateKey(value); setKeyName(file.name); setPasteKey(false); setError('');
    } catch { setError('无法读取私钥文件，请重新选择或粘贴私钥。'); }
  }

  async function perform(nextAction: 'install' | 'status') {
    if (operation.current || !canRequest || !form.current) return;
    if (!form.current.checkValidity()) {
      form.current.querySelector('input:invalid, textarea:invalid')?.closest('details')?.setAttribute('open', '');
      form.current.reportValidity();
      return;
    }
    if (authMethod === 'key' && !privateKey.trim()) {
      setError('请选择私钥文件，或粘贴 SSH 私钥。');
      setPasteKey(true);
      setTimeout(() => keyText.current?.focus(), 0);
      return;
    }
    const controller = new AbortController();
    operation.current = controller;
    setAction(nextAction); setError(''); setPaused(false);
    if (!ready) setStatus(null);
    const input: ConnectionInput = {
      host: host.trim(), username: username.trim(), port: Number(port), authMethod, nodePort: Number(nodePort),
      realityServerName: target.trim() || undefined, hostFingerprint: fingerprint || undefined,
      turnstileToken: turnstileToken || undefined, proofToken: proofToken || undefined,
      ...(authMethod === 'password' ? { password } : { privateKey, passphrase: passphrase || undefined }),
    };
    async function request(endpoint: 'install' | 'status') {
      const response = await fetch('/api/' + endpoint, {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(input),
        signal: AbortSignal.any([controller.signal, AbortSignal.timeout(45_000)]),
      });
      const body = await response.json() as ServerStatus & ApiErrorBody;
      if (!response.ok) {
        if (body.error?.code.startsWith('CAPTCHA_') || (config?.turnstileSiteKey && !input.proofToken)) {
          setProofToken(''); setTurnstileToken(''); setChallenge((value) => value + 1);
        }
        throw new Error(body.error?.message || '操作失败，请稍后重试。');
      }
      input.hostFingerprint = body.hostFingerprint;
      input.proofToken = body.proofToken || input.proofToken;
      input.turnstileToken = undefined;
      setFingerprint(body.hostFingerprint || '');
      if (body.proofToken) setProofToken(body.proofToken);
      setStatus(body);
      return body;
    }
    try {
      let current = await request(nextAction);
      const until = Date.now() + 30 * 60_000;
      while (activePhases.includes(current.phase) && Date.now() < until) {
        await sleep(6000, controller.signal);
        current = await request('status');
      }
      if (activePhases.includes(current.phase)) setPaused(true);
    } catch (error) {
      if (!controller.signal.aborted) {
        setError(error instanceof Error && !['TimeoutError', 'TypeError'].includes(error.name) ? error.message : '网络连接中断或响应超时。已启动的安装会继续，请重新读取状态。');
        if (window.matchMedia('(max-width: 760px)').matches) form.current?.scrollIntoView({ behavior: 'smooth', block: 'end' });
      }
    } finally {
      if (operation.current === controller) { setAction(null); operation.current = null; }
    }
  }

  function pause() { operation.current?.abort(); setPaused(true); }
  function clear() {
    setPassword(''); setPrivateKey(''); setPassphrase(''); setKeyName(''); setPasteKey(false); setShowPassword(false);
    setProofToken(''); setTurnstileToken(''); setChallenge((value) => value + 1);
    setFingerprint(''); setStatus(null); setError(''); setPaused(false); setNotice('登录凭据已清除');
  }

  return <>
    <a className="skip-link" href="#connection">跳到服务器连接</a>
    <header className="site-header">
      <div className="header-inner">
        <a href="#" className="brand" aria-label="5a-ui 首页"><Leaf size={21} strokeWidth={1.8} /><span>5a-ui</span></a>
        <a className="source-link" href={repository} target="_blank" rel="noreferrer">GitHub</a>
      </div>
    </header>

    <main className="app-shell">
      <div className="workspace">
        <section className="connection-card" id="connection" aria-labelledby="connection-title">
          <div className="card-heading"><h1 id="connection-title">自建节点</h1></div>
          <form ref={form} onSubmit={(event) => { event.preventDefault(); void perform('install'); }} autoComplete="off" noValidate>
            <fieldset disabled={busy}>
              <legend className="sr-only">服务器登录信息</legend>
              <div className="server-fields">
                <div className="field"><label htmlFor="server-ip">服务器 IP</label><input ref={hostField} id="server-ip" name="server-ip" placeholder="公网 IPv4 / IPv6" value={host} onChange={(event) => setHost(event.target.value)} required maxLength={64} autoCapitalize="none" autoCorrect="off" spellCheck={false} /></div>
                <div className="field"><label htmlFor="server-username">用户名</label><input id="server-username" list="ssh-usernames" value={username} onChange={(event) => setUsername(event.target.value)} required maxLength={32} autoCapitalize="none" autoCorrect="off" spellCheck={false} /><datalist id="ssh-usernames"><option value="root" /><option value="ubuntu" /><option value="debian" /></datalist></div>
              </div>

              <div className="auth-switch" role="group" aria-label="登录方式">
                <button type="button" aria-pressed={authMethod === 'password'} onClick={() => switchAuth('password')}>密码登录</button>
                <button type="button" aria-pressed={authMethod === 'key'} onClick={() => switchAuth('key')}>SSH 私钥</button>
              </div>

              {authMethod === 'password' ? <div className="field credential-field">
                <label className="sr-only" htmlFor="server-password">服务器密码</label>
                <div className="password-input"><input id="server-password" type={showPassword ? 'text' : 'password'} placeholder="服务器密码" value={password} onChange={(event) => setPassword(event.target.value)} required maxLength={4096} autoComplete="off" /><button type="button" className="icon-button" aria-label={showPassword ? '隐藏密码' : '显示密码'} aria-pressed={showPassword} onClick={() => setShowPassword(!showPassword)}>{showPassword ? <EyeOff size={18} /> : <Eye size={18} />}</button></div>
              </div> : <div className="key-fields">
                <input className="sr-only" ref={keyFile} type="file" tabIndex={-1} aria-label="选择 SSH 私钥文件" onChange={(event) => { void readKey(event.target.files?.[0]); event.target.value = ''; }} />
                <button type="button" className={'key-upload ' + (privateKey ? 'has-key' : '')} onClick={() => keyFile.current?.click()}>{privateKey ? <Check size={18} /> : <Upload size={18} />}<span>{keyName || (privateKey ? '已填写私钥' : '选择私钥文件')}</span>{privateKey && <small>更换</small>}</button>
                <button className="text-button paste-toggle" type="button" aria-expanded={pasteKey} aria-controls="private-key-entry" onClick={() => setPasteKey(!pasteKey)}>{pasteKey ? '收起私钥文本' : privateKey ? '查看或编辑私钥' : '或粘贴私钥文本'}<ChevronDown size={14} className={pasteKey ? 'rotate' : ''} /></button>
                {pasteKey && <div className="field" id="private-key-entry"><label className="sr-only" htmlFor="private-key">SSH 私钥内容</label><textarea ref={keyText} id="private-key" placeholder="粘贴完整的 SSH 私钥内容" value={privateKey} onChange={(event) => { setPrivateKey(event.target.value); setKeyName(''); }} maxLength={65536} rows={4} spellCheck={false} autoComplete="off" /></div>}
                <div className="field passphrase-field"><label htmlFor="key-passphrase">私钥口令<span className="optional">选填</span></label><input id="key-passphrase" type="password" placeholder="仅加密私钥需要填写" value={passphrase} onChange={(event) => setPassphrase(event.target.value)} maxLength={4096} autoComplete="off" /></div>
              </div>}

              <details className="advanced-settings">
                <summary>更多设置<ChevronDown size={15} /></summary>
                <div className="advanced-fields">
                  <div className="field"><label htmlFor="ssh-port">SSH 端口</label><input id="ssh-port" type="number" min="1" max="65535" step="1" value={port} onChange={(event) => setPort(event.target.value)} required /></div>
                  <div className="field"><label htmlFor="node-port">节点端口</label><input id="node-port" type="number" min="1" max="65535" step="1" value={nodePort} onChange={(event) => setNodePort(event.target.value)} required /></div>
                  <div className="field full-width"><label htmlFor="reality-target">REALITY 目标<span className="optional">选填</span></label><input id="reality-target" value={target} onChange={(event) => setTarget(event.target.value)} placeholder="自动选择可用网站" maxLength={253} spellCheck={false} /></div>
                  <div className="field full-width"><label htmlFor="host-fingerprint">SSH 主机指纹<span className="optional">选填</span></label><input id="host-fingerprint" value={fingerprint} onChange={(event) => setFingerprint(event.target.value)} placeholder="SHA256:…" maxLength={64} spellCheck={false} /><p className="field-hint">留空时首次信任，后续连接自动校验。</p></div>
                </div>
              </details>
            </fieldset>

            {config?.turnstileSiteKey && <Turnstile key={challenge} siteKey={config.turnstileSiteKey} onToken={setTurnstileToken} onError={setError} />}
            {error && <div className="error-message" role="alert"><CircleHelp size={17} /><div>{error}{!config && <button type="button" className="text-button" onClick={() => { setError(''); setConfigAttempt((value) => value + 1); }}>重新加载</button>}</div><button type="button" className="icon-button" aria-label="关闭错误提示" onClick={() => setError('')}><X size={16} /></button></div>}
            <div className="form-actions">
              <button type="submit" className="button primary" disabled={!canRequest}>{action === 'install' && <LoaderCircle size={18} className="spin" />}{action === 'install' ? '正在自建…' : !config && !error ? '加载配置…' : '一键自建'}</button>
              <button type="button" className="button secondary" onClick={() => void perform('status')} disabled={!canRequest}>{action === 'status' && <LoaderCircle size={17} className="spin" />}{action === 'status' ? '读取中…' : '读取状态'}</button>
            </div>
            <div className="form-caption"><span>登录信息不保存</span>{(password || privateKey || passphrase) && <button type="button" className="text-button" disabled={busy} onClick={clear}>清除凭据</button>}</div>
          </form>
        </section>

        {(busy || status || paused) && <section className="result-card" ref={resultRef} aria-labelledby="result-title">
          <div className="card-heading">{busy && !ready && <LoaderCircle size={19} className="spin" />}<div><h2 id="result-title">{resultTitle}</h2>{ready && <p>{host}</p>}</div>{ready && <button type="button" className="icon-button refresh-button" disabled={!canRequest} aria-label="刷新节点状态" title="刷新节点状态" onClick={() => void perform('status')}><RefreshCw size={17} className={busy ? 'spin' : ''} /></button>}</div>
          <div className="sr-only" role="status" aria-live="polite">{busy && !status ? '正在连接服务器' : paused ? '已暂停刷新' : status?.message || '等待连接服务器'}</div>

          {ready ? <>
            {!status.running && <div className="inline-note warning"><CircleHelp size={17} /><p>{status.message || '服务暂未运行，请检查服务器。'}</p></div>}
            <NodeResult status={status} onNotice={setNotice} />
          </> : busy || installing || paused ? <div className="progress-content">
            {status?.message && <p className="progress-message">{status.message}</p>}
            {(action === 'install' || installing) && <ol className="progress-steps">{stages.map((stage, index) => <li key={stage.key} className={index < step ? 'done' : index === step ? 'current' : ''}><span>{index < step ? <Check size={14} /> : index + 1}</span>{stage.label}{index === step && busy && <LoaderCircle size={14} className="spin" />}</li>)}</ol>}
            <div className="progress-footer">{(action === 'install' || installing) && <p>关闭页面后，安装仍会继续。</p>}{busy ? <button type="button" className="text-button" onClick={pause}>暂停刷新</button> : <button type="button" className="button secondary" disabled={!canRequest} onClick={() => void perform('status')}>继续读取状态</button>}</div>
          </div> : status ? <div className="status-content">
            <p>{status.message}</p>
            {status.phase === 'existing' ? <button type="button" className="button secondary" onClick={() => { hostField.current?.focus(); hostField.current?.select(); }}>更换服务器</button> : <button type="button" className="button primary" disabled={!canRequest} onClick={() => void perform('install')}>{status.phase === 'failed' ? '重试自建' : '开始自建'}</button>}
          </div> : null}

          {!ready && status?.hostFingerprint && <details className="fingerprint-details"><summary>SSH 主机指纹<ChevronDown size={14} /></summary><code>{status.hostFingerprint}</code><p>首次信任，可通过云平台控制台核对。</p></details>}
        </section>}
      </div>

      <details className="help-section" id="help">
        <summary>使用说明<ChevronDown size={15} /></summary>
        <div className="help-grid">
          <article><h3>服务器</h3><p>公网 IP，Debian 11+ / Ubuntu 20.04+，x86_64 / arm64。使用 root 或免密 sudo 账号；云服务器也可能使用 ubuntu 或 debian。首次自建需未安装 3x-ui。</p></article>
          <article><h3>登录信息</h3><p>服务端通过 SSH 连接，不保存凭据。刷新页面或清除凭据后需重新输入。</p></article>
          <article><h3>安装与连接</h3><p>关闭页面不影响安装，回来后读取状态即可。云平台需放行 SSH 和节点 TCP 端口（默认 443），使用支持 VLESS + REALITY 的客户端。</p></article>
        </div>
      </details>
    </main>

    {notice && <div className="toast" role="status"><CheckCircle2 size={17} />{notice}<button type="button" className="icon-button" aria-label="关闭提示" onClick={() => setNotice('')}><X size={15} /></button></div>}
  </>;
}
