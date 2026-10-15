#!/usr/bin/env python3
"""Authenticated 3x-ui API access. Loaded with the inspector in memory over SSH.

No credentials, requests, responses or databases are written to disk. The
operation allowlist is generated from audited upstream interface definitions.
"""
import base64
import ctypes
from contextlib import closing
import hashlib
import http.cookiejar
import http.client
import json
import os
from pathlib import Path
import re
import socket
import sqlite3
import ssl
import subprocess
import urllib.error
import urllib.parse
import urllib.request

MAX_DATA = 2 * 1024 * 1024
API_PREFIX = '/panel/api'
VOLATILE = {'up', 'down', 'allTime', 'lastOnline', 'lastOnlineAt', 'online', 'clientStats', 'traffic_used', 'upload_bytes', 'download_bytes', 'last_seen', 'updated_at'}


class PanelError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message
        super().__init__(message)


def revision(value):
    def stable(v):
        if isinstance(v, dict):
            return {k: stable(x) for k, x in v.items() if k not in VOLATILE}
        if isinstance(v, list):
            return [stable(x) for x in v]
        return v
    return hashlib.sha256(json.dumps(stable(value), sort_keys=True, separators=(',', ':')).encode()).hexdigest()


def read_settings(instance, inspector):
    keys = ('webPort', 'webListen', 'webBasePath', 'webCertFile', 'webDomain')
    env = instance['_env']
    if env.get('XUI_DB_TYPE', '').lower() in ('postgres', 'postgresql', 'pg'):
        if not env.get('XUI_DB_DSN'):
            raise PanelError('PANEL_DATABASE', '无法读取面板连接设置。')
        sql = "SELECT json_object_agg(key,value) FROM settings WHERE key IN (" + ','.join("'" + key + "'" for key in keys) + ');'
        value = inspector.run(['psql', '-X', '-q', '-A', '-t', '-w', '-v', 'ON_ERROR_STOP=1'],
                              env={**os.environ, 'PGDATABASE': env['XUI_DB_DSN'], 'PGCONNECT_TIMEOUT': '3',
                                   'PGOPTIONS': '-c default_transaction_read_only=on -c statement_timeout=3000'}, input=sql)
        return json.loads(value or '{}')
    path = Path(instance['_database'])
    # sqlite3's context manager ends transactions, but does not close the
    # connection. Release it before an API restore replaces the live database;
    # otherwise the old WAL can survive and overwrite the restored contents.
    with closing(sqlite3.connect(path.resolve().as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
        db.execute('PRAGMA query_only=ON')
        return dict(db.execute('SELECT key,value FROM settings WHERE key IN (' + ','.join('?' for _ in keys) + ')', keys))


def version_of(instance, inspector):
    cmd = (['docker', 'exec', instance['_container'], '/app/x-ui', '-v']
           if instance['kind'] == 'docker' else [instance['_binary'], '-v'])
    match = re.search(r'\bv?(\d+)\.(\d+)\.(\d+)\b', inspector.run(cmd))
    if not match:
        raise PanelError('PANEL_VERSION', '无法确认面板版本，暂时只提供状态读取。')
    version = tuple(map(int, match.groups()))
    if version < (3, 6, 0):
        raise PanelError('PANEL_VERSION', '管理接口目前支持 3x-ui 3.6.0 及以上；此版本仍可读取状态。')
    return version


def enter_network(instance, inspector):
    if instance['kind'] != 'docker':
        return
    # No ports are published or changed. Use the selected container's loopback.
    pid = int(inspector.run(['docker', 'inspect', '--format', '{{.State.Pid}}', instance['_container']]))
    if pid <= 0:
        raise PanelError('PANEL_STOPPED', '此容器已停止，请先启动服务。')
    with open(f'/proc/{pid}/ns/net', 'rb') as namespace:
        if ctypes.CDLL(None, use_errno=True).setns(namespace.fileno(), 0) != 0:
            raise PanelError('PANEL_PERMISSION', '无法进入容器网络，请使用具有免密 sudo 权限的 SSH 账号。')


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise PanelError('PANEL_REDIRECT', '面板返回重定向，请检查实例地址和认证状态。')


class Panel:
    product = '3x-ui'
    def __init__(self, settings, auth, public_host=''):
        port = int(settings.get('webPort') or 2053)
        if not 0 < port < 65536:
            raise PanelError('PANEL_ADDRESS', '面板端口无效。')
        host = settings.get('webListen') or '127.0.0.1'
        if host in ('0.0.0.0', '::'):
            host = '127.0.0.1' if host == '0.0.0.0' else '::1'
        # Database settings may select a local listen IP, never an arbitrary URL.
        import ipaddress
        ipaddress.ip_address(host)
        path = settings.get('webBasePath') or '/'
        if not path.startswith('/') or any(c in path for c in ('?', '#', '\r', '\n', '\\')):
            raise PanelError('PANEL_ADDRESS', '面板访问路径无效。')
        scheme = 'https' if settings.get('webCertFile') else 'http'
        self.base = f'{scheme}://{"[" + host + "]" if ":" in host else host}:{port}' + path.rstrip('/')
        self.cookies = http.cookiejar.CookieJar()
        # Traffic is confined to the SSH host/container network namespace. A
        # panel's public-domain certificate does not match its local listen IP.
        context = ssl._create_unverified_context()
        domain = settings.get('webDomain') or ''
        if domain and not re.fullmatch(r'[A-Za-z0-9.-]+', domain):
            raise PanelError('PANEL_ADDRESS', '面板域名格式无效。')
        class LocalHTTPSConnection(http.client.HTTPSConnection):
            def connect(connection):
                http.client.HTTPConnection.connect(connection)
                connection.sock = connection._context.wrap_socket(connection.sock, server_hostname=domain or connection.host)
        class LocalHTTPSHandler(urllib.request.HTTPSHandler):
            def https_open(handler, request):
                return handler.do_open(LocalHTTPSConnection, request, context=context)
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect(),
            urllib.request.HTTPCookieProcessor(self.cookies), LocalHTTPSHandler(context=context))
        self.headers = {'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json'}
        domain = settings.get('webDomain')
        if domain and re.fullmatch(r'[A-Za-z0-9.-]+', domain):
            self.headers['Host'] = domain
        elif public_host:
            # Link generation uses the HTTP Host. The transport still connects
            # only to the panel's local address through SSH.
            address = ipaddress.ip_address(public_host)
            self.headers['Host'] = f'[{address}]' if address.version == 6 else str(address)
        self.auth = auth
        if self.product == '3m-ui':
            self.login(auth)
        elif auth.get('token'):
            self.headers['Authorization'] = 'Bearer ' + auth['token']
        elif auth.get('session'):
            self.headers.update({'Cookie': auth['session']['cookie'], 'X-CSRF-Token': auth['session']['csrf']})
        else:
            if not auth.get('username') or not auth.get('password'):
                raise PanelError('PANEL_AUTH_REQUIRED', '请输入现有面板账号和密码，或 API token。接入不会重置账号。')
            self.headers['X-CSRF-Token'] = self.request('/csrf-token')
            try:
                self.request('/login', 'POST', {key: auth.get(key, '') for key in ('username', 'password', 'twoFactorCode')})
            except PanelError as error:
                if error.code == 'PANEL_REJECTED':
                    raise PanelError('PANEL_AUTH', '面板登录失败，请核对账号、密码和二步验证码。') from None
                raise
            self.headers['X-CSRF-Token'] = self.request('/csrf-token')

    def session(self):
        if self.auth.get('token'):
            return None
        return {'cookie': self.headers.get('Cookie') or '; '.join(f'{c.name}={c.value}' for c in self.cookies),
                'csrf': self.headers.get('X-CSRF-Token', '')}

    def request(self, path, method='GET', data=None, encoding='application/json', binary=False, raw_json=False):
        headers = dict(self.headers)
        payload = None
        if method != 'GET':
            if encoding == 'multipart/form-data':
                field = 'database' if self.product == '3m-ui' else 'db'
                raw = base64.b64decode(data.get(field, ''), validate=True)
                if len(raw) > MAX_DATA or not raw:
                    raise PanelError('PANEL_SIZE', '备份必须为非空文件，最大支持 2 MiB。')
                boundary = '5a-ui-' + os.urandom(16).hex()
                keep = 'true' if data.get('keepHostSettings', True) else 'false'
                payload = (f'--{boundary}\r\nContent-Disposition: form-data; name="keepHostSettings"\r\n\r\n{keep}\r\n'
                           f'--{boundary}\r\nContent-Disposition: form-data; name="{field}"; filename="backup.db"\r\n'
                           'Content-Type: application/octet-stream\r\n\r\n').encode() + raw + f'\r\n--{boundary}--\r\n'.encode()
                headers['Content-Type'] = f'multipart/form-data; boundary={boundary}'
            elif encoding == 'application/x-www-form-urlencoded':
                def field(v):
                    return json.dumps(v, separators=(',', ':')) if isinstance(v, (dict, list, bool)) else str(v)
                fields = []
                for key, value in (data or {}).items():
                    # SubBalancerController uses PostFormArray for IDs, but
                    # expects memberWeights and other nested values as JSON.
                    if re.fullmatch(r'/panel/api/sub-balancers(?:/\d+)?', path) and key == 'inboundIds' and isinstance(value, list):
                        fields.extend((key, field(item)) for item in value)
                    else:
                        fields.append((key, field(value)))
                payload = urllib.parse.urlencode(fields).encode()
                headers['Content-Type'] = encoding
            else:
                payload = json.dumps(data if data is not None else {}, separators=(',', ':')).encode()
                headers['Content-Type'] = 'application/json'
        request = urllib.request.Request(self.base + path, data=payload, headers=headers, method=method)
        try:
            with self.opener.open(request, timeout=16) as response:
                raw = response.read(MAX_DATA + 1)
                mime = response.headers.get('Content-Type', '')
        except urllib.error.HTTPError as error:
            if error.code in (401, 403):
                raise PanelError('PANEL_PERMISSION', '面板拒绝访问：认证已过期或账号 / token 权限不足，请重新认证。') from None
            if error.code == 404:
                raise PanelError('PANEL_UNSUPPORTED', '此面板没有提供该接口，当前版本无法执行此操作。') from None
            raise PanelError('PANEL_HTTP', '面板请求失败，请检查输入并重新读取当前状态。') from None
        except (urllib.error.URLError, TimeoutError, socket.timeout, OSError):
            raise PanelError('PANEL_UNCERTAIN', '面板连接中断或超时。写操作可能已经生效，请先重新读取，勿直接重试。') from None
        if len(raw) > MAX_DATA:
            raise PanelError('PANEL_SIZE', '面板响应超过 2 MiB；请缩小查询范围或在原面板导出。')
        if binary and 'json' not in mime:
            extension = 'db' if raw.startswith(b'SQLite format 3') else 'zip' if raw.startswith(b'PK') else 'yaml' if 'yaml' in mime else 'dump'
            return {'file': base64.b64encode(raw).decode(), 'name': self.product + '-export.' + extension}
        try:
            value = json.loads(raw)
        except ValueError:
            raise PanelError('PANEL_RESPONSE', '面板未返回有效 JSON，请检查认证和版本。') from None
        if self.product == '3m-ui':
            if isinstance(value,dict) and (value.get('valid') is False or value.get('error')):
                raise PanelError('PANEL_REJECTED','3m-ui 校验失败，请检查必填字段和配置格式；请回读当前状态。')
            return value
        if raw_json and isinstance(value, dict) and isinstance(value.get('paths'), dict):
            return value
        if not isinstance(value, dict) or value.get('success') is not True:
            # Raw errors may contain SQL, secrets or entered configuration.
            message = str(value.get('msg', '')) if isinstance(value, dict) else ''
            if 'pg_dump not found' in message or 'pg_restore not found' in message:
                raise PanelError('PANEL_DEPENDENCY', '此面板的 PostgreSQL 备份 / 恢复需要在面板所在环境安装匹配版本的 PostgreSQL 客户端工具。')
            raise PanelError('PANEL_REJECTED', '面板拒绝此操作，请检查必填字段、重复名称、端口与配置格式；重新读取以确认当前状态。')
        return value.get('obj')


def route(operation, parameters, prefix=API_PREFIX):
    path = operation['path']
    for name in re.findall(r'\{(\w+)\}', path):
        value = str(parameters.get(name, ''))
        if path == '/server/installXray/{version}' and name == 'version':
            if not re.fullmatch(r'v?\d+\.\d+\.\d+(?:[-.][A-Za-z0-9.-]+)?', value):
                raise PanelError('PANEL_INPUT', '请选择有效的 Xray 发布版本，例如 v26.10.10。')
            value = 'v' + value.lstrip('v')
        if not value or len(value) > 256 or value in ('.', '..') or any(c in value for c in '/\\?#%\r\n\0'):
            raise PanelError('PANEL_INPUT', '操作路径参数不正确。')
        path = path.replace('{' + name + '}', urllib.parse.quote(value, safe=''))
    queries = {p['name']: parameters[p['name']] for p in operation.get('parameters', [])
               if p.get('in') == 'query' and p['name'] in parameters}
    if queries:
        path += '?' + urllib.parse.urlencode(queries, doseq=True)
    return prefix + path


def service_command(instance, action):
    if instance['kind'] == 'docker':
        return ['docker', action, instance['_container']]
    if re.fullmatch(r'[A-Za-z0-9_.@-]+\.service', instance['name']):
        return ['systemctl', action, '--', instance['name']]
    raise PanelError('PANEL_UNSUPPORTED', '独立进程没有可识别的服务管理器，无法安全启停。')


def run_service(instance, action):
    try:
        subprocess.run(service_command(instance, action), check=True, capture_output=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        raise PanelError('PANEL_UNCERTAIN', '服务操作未确认完成，请重新读取状态后判断。') from None


def unavailable_operations(instance, instances, operations):
    reasons = {}
    shared_binary = any(other['id'] != instance['id'] and other.get('kind') == 'native'
                        and other.get('_binary') == instance.get('_binary') for other in instances)
    for op in operations:
        if op['path'] == '/server/updatePanel':
            if instance.get('kind') == 'docker':
                reasons[op['id']] = 'Docker 面板应通过原有 Compose / 容器编排更新镜像；面板内置更新器面向 systemd，不能保留容器部署方式。'
            elif instance.get('name') != 'x-ui.service' or shared_binary:
                reasons[op['id']] = '上游更新器固定操作 x-ui.service。此实例为自定义服务或共享程序，无法保证仅更新选中实例，请使用原部署方式升级。'
        if op['path'] == '/server/installXray/{version}' and instance.get('kind') == 'native' and shared_binary:
            reasons[op['id']] = '多个实例共享 Xray 程序目录；版本切换会影响其他实例，请先将程序目录隔离。'
    return reasons


def perform(request, inspector, operations, public_host=''):
    if not isinstance(request, dict) or not isinstance(request.get('auth', {}), dict):
        raise PanelError('PANEL_INPUT', '管理请求格式不正确。')
    identifier = request.get('instanceId')
    found, discovery_failed = [], False
    for discover in (inspector.discover_native, inspector.discover_docker):
        try:
            found.extend(discover())
        except Exception:
            discovery_failed = True
    instance = next((item for item in found if item['id'] == identifier), None)
    if instance is None:
        if discovery_failed:
            raise PanelError('INSTANCE_DISCOVERY', '部分实例无法发现，请检查对应服务管理器与 SSH 权限；未执行任何写入。')
        raise PanelError('INSTANCE_MISSING', '此实例已不存在，请刷新实例列表。')
    operation_id = request.get('operation')
    if operation_id in ('service.start', 'service.stop', 'service.restart'):
        if request.get('confirmed') is not True:
            raise PanelError('PANEL_CONFIRM', '请确认目标实例和服务操作。')
        action = operation_id.split('.')[1]
        run_service(instance, action)
        return {'result': {'accepted': True}, 'message': '服务操作已返回，请刷新状态确认。'}
    if instance.get('panelType') == '3m-ui':
        return perform_three_m(request, instance, found, inspector, operations, public_host)
    version = version_of(instance, inspector)
    available = {op['id']: {**op, **(op.get('legacy', {}) if version < (3, 10, 0) else {})}
                 for op in operations if op.get('panelType','3x-ui') == '3x-ui' and tuple(map(int, op['since'].split('.'))) <= version}
    unavailable = unavailable_operations(instance, found, list(available.values()))
    if operation_id in unavailable:
        raise PanelError('PANEL_UNSUPPORTED', unavailable[operation_id])
    operation = available.get(operation_id)
    if operation_id != 'catalog' and operation is None:
        raise PanelError('PANEL_UNSUPPORTED', '此版本不支持所选操作。')
    if operation and operation['write'] and request.get('confirmed') is not True:
        raise PanelError('PANEL_CONFIRM', '写入前需要确认目标和变更内容。')
    if operation and '/setting/apiTokens/' in operation['path'] and version < (3, 10, 0):
        token_data = request.get('data') or {}
        if (token_data.get('scope', 'admin') not in ('', 'admin')
                or token_data.get('expectedScope', 'admin') not in ('', 'admin')
                or token_data.get('expiresAt', 0) not in (None, 0)):
            raise PanelError('PANEL_UNSUPPORTED', '此版本的 token 不支持权限范围和到期时间，不能创建受限 token。已有 token 均具有完整管理权限。')
    restoring = operation and operation['path'] == '/server/importDB'
    if restoring:
        service_command(instance, 'restart')  # Validate before any database change.
        if version < (3, 10, 0) and request.get('data', {}).get('keepHostSettings', True):
            raise PanelError('PANEL_UNSUPPORTED', '此版本不支持保留主机设置的恢复。只能明确选择全量恢复，或先升级面板。')
    endpoint = request.get('endpoint')
    if endpoint:
        # An explicit existing endpoint supports PostgreSQL instances whose DB
        # client is unavailable on the SSH host. Never probe or guess ports.
        settings = {'webPort': endpoint['port'], 'webBasePath': endpoint['path'],
                    'webListen': endpoint.get('listen', '127.0.0.1'),
                    'webCertFile': 'https' if endpoint.get('https') else '',
                    'webDomain': endpoint.get('domain', '')}
    else:
        settings = read_settings(instance, inspector)
    enter_network(instance, inspector)
    auth = request.get('auth', {})
    if not any(auth.get(key) for key in ('token', 'session', 'username', 'password')) and inspector.owned_installation(instance):
        managed = inspector.read_json(inspector.ROOT / 'connection.json', {})
        if managed.get('apiToken'):
            auth = {'token': managed['apiToken']}
    panel = Panel(settings, auth, public_host)
    if operation_id == 'catalog':
        panel.request(API_PREFIX + '/server/status')
        try:
            spec = panel.request(API_PREFIX + '/openapi.json', raw_json=True)
            available = {key: op for key, op in available.items()
                         if op['method'].lower() in spec['paths'].get(API_PREFIX + op['path'], {})}
            capability_source = 'live'
        except PanelError as error:
            if error.code == 'PANEL_PERMISSION':
                # Limited-scope tokens can read status but cannot inspect the
                # complete API. Do not advertise admin writes for these tokens.
                available = {key: op for key, op in available.items() if op['path'] == '/server/status'}
                capability_source = 'restricted'
            elif error.code not in ('PANEL_UNSUPPORTED', 'PANEL_RESPONSE', 'PANEL_REJECTED'):
                raise
            else:
                capability_source = 'version'
        result = {'version': '.'.join(map(str, version)), 'operations': list(available),
                  'unavailable': unavailable, 'capabilitySource': capability_source,
                  'tokenScopes': version >= (3, 10, 0),
                  'restoreKeepsHostSettings': version >= (3, 10, 0)}
    else:
        before = request.get('precondition')
        if before:
            read = available.get(before.get('operation'))
            if not read or read['write']:
                raise PanelError('PANEL_INPUT', '编辑校验请求无效。')
            current = panel.request(route(read, before.get('parameters', {})), read['method'],
                                    before.get('data'), read['encoding'])
            if revision(current) != before.get('revision'):
                raise PanelError('PANEL_CONFLICT', '配置已被其他会话修改，请重新读取后合并修改。')
        result = panel.request(route(operation, request.get('parameters', {})), operation['method'],
                               request.get('data'), operation['encoding'], operation['path'] in ('/server/getDb', '/server/getMigration'))
        if restoring:
            # Older panels keep the pre-restore settings cache alive. Restart the
            # selected instance, never a guessed global x-ui service. Re-auth is
            # necessary because the restored DB may contain different users.
            run_service(instance, 'restart')
            return {'result': {'restored': True, 'reauthenticate': True},
                    'message': '数据库已恢复并重启当前实例，请重新认证并读取配置确认。'}
    return {'result': result, 'revision': revision(result), 'session': panel.session(),
            'message': '面板已接受请求，请回读确认最终状态。' if operation and operation['write'] else '已读取面板数据。'}



class MihomoPanel(Panel):
    product = '3m-ui'

    def login(self, auth):
        token = auth.get('token') or auth.get('session', {}).get('bearer')
        if not token:
            if not auth.get('username') or not auth.get('password'):
                raise PanelError('PANEL_AUTH_REQUIRED', '请输入现有 3m-ui 管理员账号和密码，或登录 JWT。订阅 token 不能管理面板。')
            result = self.request('/api/v1/auth/login', 'POST', {
                'username':auth['username'],'password':auth['password'],'totp_code':auth.get('twoFactorCode','')})
            token = result.get('token')
            if not token:
                raise PanelError('PANEL_AUTH', '3m-ui 登录失败，请核对密码和二步验证码。')
        self.headers['Authorization'] = 'Bearer '+token

    def session(self):
        return {'cookie':'','csrf':'','bearer':self.headers['Authorization'].removeprefix('Bearer ')}


def three_m_settings(instance, inspector):
    cfg=inspector.three_m_config(instance)['server']
    settings={'webPort':cfg.get('port',8080),'webListen':cfg.get('listen',''),'webBasePath':cfg.get('web_path') or '/'}
    # HTTPS replaces the HTTP listener. Only connection facts leave this
    # function; ACME tokens and private-key paths are never returned.
    with closing(sqlite3.connect(Path(instance['_database']).resolve().as_uri()+'?mode=ro',uri=True,timeout=2)) as db:
        db.execute('PRAGMA query_only=ON')
        if db.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='panel_settings'").fetchone():
            row=db.execute("SELECT value FROM panel_settings WHERE key='panel_ssl'").fetchone()
            ssl_settings=json.loads(row[0]) if row else {}
            if ssl_settings.get('enabled'):
                address=urllib.parse.urlsplit('//'+(ssl_settings.get('listen_tls') or ':443'))
                settings.update(webPort=address.port,webListen=address.hostname or '127.0.0.1',
                    webCertFile='https',webDomain=ssl_settings.get('domain',''))
    return settings


def perform_three_m(request, instance, instances, inspector, operations, public_host):
    text = inspector.run(inspector.three_m_version_command(instance), merge_stderr=True)
    match = re.search(r'\bv?(\d+)\.(\d+)\.(\d+)\b',text)
    if not match or tuple(map(int,match.groups())) < (1,4,1):
        raise PanelError('PANEL_VERSION', '3m-ui 管理目前兼容 v1.4.1 及以上；旧版仍可读取状态。')
    available = {op['id']:op for op in operations if op.get('panelType')=='3m-ui'}
    identifier=request['operation']
    operation=available.get(identifier)
    if identifier!='catalog' and not operation:
        raise PanelError('PANEL_UNSUPPORTED','此操作不属于 3m-ui。')
    if operation and operation['write'] and request.get('confirmed') is not True:
        raise PanelError('PANEL_CONFIRM','写入前需要确认目标和变更内容。')
    unavailable={}
    shared = any(other['id']!=instance['id'] and other.get('kind')=='native' and
        (other.get('_binary')==instance.get('_binary') or
         (instance.get('_core_binary') and other.get('_core_binary')==instance['_core_binary'])) for other in instances)
    for op in available.values():
        if op['path']=='/system/update' and (instance['kind']=='docker' or instance['name']!='3m-ui.service' or shared):
            unavailable[op['id']]='此实例是容器、自定义服务或共享程序；上游升级器固定操作 3m-ui.service，请使用原部署方式升级。'
        if op['path'] in ('/mihomo/update','/mihomo/update/rollback') and op['write'] and shared:
            unavailable[op['id']]='Mihomo 程序由其他实例共享，不能只为当前实例切换版本。'
        # Upstream offers an arbitrary remote proxy. It bypasses this client's
        # audited operation allowlist (including read/write classification).
        if op['path']=='/cluster/{id}/proxy':
            unavailable[op['id']]='通用远端代理未开放；请使用明确的集群操作，或直接接入目标服务器管理。'
    if identifier in unavailable: raise PanelError('PANEL_UNSUPPORTED',unavailable[identifier])
    restoring=operation and operation['path']=='/system/backup/restore-db'
    if restoring: service_command(instance,'restart')
    endpoint=request.get('endpoint')
    if endpoint:
        settings={'webPort':endpoint['port'],'webBasePath':endpoint['path'],'webListen':endpoint.get('listen','127.0.0.1'),
                  'webCertFile':'https' if endpoint.get('https') else '', 'webDomain':endpoint.get('domain','')}
    else:
        settings=three_m_settings(instance, inspector)
    auth=request.get('auth',{})
    if not any(auth.get(k) for k in ('token','session','username','password')) and inspector.owned_installation(instance):
        managed=inspector.read_json(inspector.ROOT/'3m-connection.json',{})
        auth={'username':managed.get('username',''),'password':managed.get('password','')}
    enter_network(instance,inspector)
    panel=MihomoPanel(settings,auth,public_host)
    account=panel.request('/api/v1/auth/me')
    if account.get('role')!='admin':
        raise PanelError('PANEL_PERMISSION','3m-ui 管理需要管理员权限。')
    if account.get('must_change_password'):
        available={key:op for key,op in available.items() if op['path'] in ('/auth/me','/auth/password')}
        if identifier!='catalog' and identifier not in available:
            raise PanelError('PANEL_PASSWORD_REQUIRED','此管理员必须先修改初始密码。请在账号管理中完成改密，再重新认证。')
    if identifier=='catalog':
        result={'panelType':'3m-ui','version':'.'.join(match.groups()),'operations':list(available),
            'unavailable':unavailable,'capabilitySource':'audited-version',
            'mustChangePassword':bool(account.get('must_change_password')),'restoreKeepsHostSettings':False}
    else:
        def call(op, params=None, data=None):
            path=route(op,params or {},prefix='/api/v1')
            return panel.request(path,op['method'],data,op['encoding'],op['path'] in ('/system/backup','/config/download'))
        before=request.get('precondition')
        if before:
            read=available.get(before.get('operation'))
            if not read or read['write']: raise PanelError('PANEL_INPUT','编辑校验请求无效。')
            if revision(call(read,before.get('parameters'),before.get('data')))!=before.get('revision'):
                raise PanelError('PANEL_CONFLICT','配置已被其他会话修改，请重新读取后合并修改。')
        result=call(operation,request.get('parameters'),request.get('data'))
        if operation['path']=='/auth/password':
            if result.get('token'): panel.headers['Authorization']='Bearer '+result['token']
            else: result={'reauthenticate':True}
        if restoring:
            # Upstream exits after 500ms; restart only after that exit, otherwise
            # it can terminate a freshly restarted process with no restart policy.
            import time
            time.sleep(1)
            run_service(instance,'restart')
            return {'result':{'restored':True,'reauthenticate':True},'message':'3m-ui 备份已恢复，当前实例已重启，请重新认证并回读。'}
    return {'result':result,'revision':revision(result),'session':panel.session(),
            'message':'面板已接受请求；配置保存与 Mihomo 应用是独立步骤，请回读运行状态。' if operation and operation['write'] else '已读取 3m-ui 数据。'}


def main(request, inspector, operations, public_host=''):
    try:
        result = perform(request, inspector, operations, public_host)
        print('5A_UI_RESULT=' + json.dumps({'phase': 'ready', 'message': result.pop('message'), 'management': result}, separators=(',', ':')))
    except PanelError as error:
        print('5A_UI_RESULT=' + json.dumps({'error': {'code': error.code, 'message': error.message}}))
    except Exception:
        print('5A_UI_RESULT=' + json.dumps({'error': {'code': 'PANEL_FAILED', 'message': '无法完成面板操作，请检查服务、数据库与 SSH 权限。写操作请先回读确认。'}}))
