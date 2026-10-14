export type LoginMethod = 'password' | 'key';

export interface ConnectionInput {
  host: string;
  username: string;
  port: number;
  authMethod: LoginMethod;
  password?: string;
  privateKey?: string;
  passphrase?: string;
  hostFingerprint?: string;
  nodePort?: number;
  realityServerName?: string;
  turnstileToken?: string;
  proofToken?: string;
}

export type Phase = 'not-installed' | 'existing' | 'queued' | 'preparing' | 'installing' | 'configuring' | 'checking' | 'ready' | 'failed';

export interface ServerStatus {
  phase: Phase;
  message: string;
  updatedAt?: string;
  hostFingerprint?: string;
  installed?: boolean;
  running?: boolean;
  panelVersion?: string;
  xrayVersion?: string;
  cpu?: number;
  memory?: { current: number; total: number };
  uptime?: number;
  traffic?: { up: number; down: number };
  node?: { host: string; port: number; serverName: string; link: string };
  portReachable?: boolean;
  firewall?: string;
  proofToken?: string;
}

export interface ApiErrorBody {
  error: { code: string; message: string };
}
