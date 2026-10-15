export type LoginMethod = 'password' | 'key';

export interface ConnectionInput {
  management?: Record<string, unknown>;
  host: string;
  /** Empty selects automatic login; explicit names never fall back. */
  username: string;
  port: number;
  authMethod: LoginMethod;
  password?: string;
  privateKey?: string;
  passphrase?: string;
  hostFingerprint?: string;
  nodePort?: number;
  panelType?: '3x-ui' | '3m-ui';
  realityServerName?: string;
  turnstileToken?: string;
  proofToken?: string;
}

export type Phase = 'not-installed' | 'existing' | 'queued' | 'preparing' | 'installing' | 'configuring' | 'checking' | 'ready' | 'failed';

export interface ClientStatus {
  id: string;
  name: string;
  enabled?: boolean;
  available?: boolean;
  message?: string;
  linkMessage?: string;
  expiryTime?: number;
  total?: number;
  traffic?: { up: number; down: number };
  host?: string;
  port?: number;
  serverName?: string;
  link?: string;
}

export interface InboundStatus {
  id: string;
  name: string;
  protocol: string;
  port: number;
  enabled?: boolean;
  message?: string;
  traffic?: { up: number; down: number };
  clients: ClientStatus[];
}

export interface InstanceStatus {
  id: string;
  name: string;
  kind: 'native' | 'docker';
  panelType?: '3x-ui' | '3m-ui';
  running?: boolean;
  readable?: boolean;
  truncated?: boolean;
  message?: string;
  panelVersion?: string;
  inbounds: InboundStatus[];
}

export interface ServerStatus {
  management?: { result?: unknown; revision?: string; session?: unknown };
  phase: Phase;
  message: string;
  updatedAt?: string;
  hostFingerprint?: string;
  sshUsername?: string;
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
  instances?: InstanceStatus[];
  truncated?: boolean;
}

export interface ApiErrorBody {
  error: { code: string; message: string };
}
