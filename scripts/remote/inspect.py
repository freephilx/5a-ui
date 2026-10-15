#!/usr/bin/env python3
"""Read existing 3x-ui / 3m-ui instances without changing their configuration."""
import base64
from contextlib import closing
import ipaddress
import json
import os
from pathlib import Path
import re
import shlex
import shutil
import sqlite3
import subprocess
import sys
import time
import urllib.parse

ROOT = Path('/var/lib/5a-ui')
PROC = Path('/proc')
DEFAULT_DB = Path('/etc/x-ui/x-ui.db')
DEFAULT_BINARY = Path('/usr/local/x-ui/x-ui')
INSTALL_OVERRIDE = Path('/etc/systemd/system/x-ui.service.d/20-5a-ui.conf')
DEADLINE = None
MAX_ROWS = 1000
MAX_OUTPUT = 120 * 1024
ACTIVE = {'queued', 'preparing', 'installing', 'configuring', 'checking'}
TABLES = ('inbounds', 'client_traffics', 'clients', 'client_inbounds', 'hosts')


class InspectError(Exception):
    pass


def run(args, *, env=None, input=None, merge_stderr=False):
    remaining = DEADLINE - time.monotonic() if DEADLINE is not None else 4
    if remaining <= 0:
        raise InspectError('读取超时，部分实例未能读取，请稍后重试。')
    try:
        return subprocess.run(args, input=input, env=env, text=True,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT if merge_stderr else subprocess.DEVNULL,
                              timeout=min(4, remaining), check=True).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        raise InspectError('无法读取服务信息，请检查服务状态和 SSH 账号权限。') from None


def read_json(path, default=None):
    try:
        return json.loads(path.read_text())
    except (OSError, ValueError):
        return default


def mapping(value):
    if isinstance(value, str):
        value = json.loads(value or '{}')
    if not isinstance(value, dict):
        raise ValueError('Expected an object')
    return value


def number(value, default=0):
    try:
        return int(value)
    except (ValueError, TypeError, OverflowError):
        return default


def short(value, limit=256):
    return str(value or '')[:limit]


def traffic(value):
    return {key: max(0, number(value.get(key))) for key in ('up', 'down')}


def environment(items):
    # Read values as data; never source an environment file as a shell program.
    return {key: value for item in items if '=' in item
            for key, value in [item.split('=', 1)] if key.startswith(('XUI_', 'THREE_M_UI_')) or key in ('PANEL_PORT','PANEL_LISTEN')}


def env_file(path):
    try:
        return environment(shlex.split(Path(path).read_text(), comments=True))
    except (OSError, ValueError):
        return {}


def process_env(pid):
    try:
        return environment((PROC / str(pid) / 'environ').read_text().split('\0'))
    except (OSError, ValueError):
        return {}


def native_instance(name, binary, env, running, pid=0):
    directory = env.get('XUI_DB_FOLDER') or str(DEFAULT_DB.parent)
    return {'id': 'native:' + name, 'name': name, 'kind': 'native', 'panelType': '3x-ui',
            'running': running, '_binary': binary, '_pid': pid, '_env': env,
            '_database': str(Path(directory) / 'x-ui.db')}


def discover_native():
    instances, seen, pids = [], set(), set()
    discovery_error = None
    try:
        if shutil.which('systemctl'):
            units = run(['systemctl', 'list-unit-files', '--type=service', '--no-legend', '--no-pager'])
            names = [line.split()[0] for line in units.splitlines()
                     if line.strip() and not line.split()[0].endswith('@.service')]
            if names:
                fields = 'Id,ExecStart,Environment,EnvironmentFiles,MainPID,ActiveState,WorkingDirectory'
                detail = run(['systemctl', 'show', '--no-pager', '--property=' + fields, '--', *names])
                for block in detail.split('\n\n'):
                    values = dict(line.split('=', 1) for line in block.splitlines() if '=' in line)
                    name, command = values.get('Id', ''), values.get('ExecStart', '')
                    if not (re.search(r'(^|/|\s)(?:3x-ui|x-ui|3m-ui|3m-ui-bin)(?:\s|;|$)', command)
                            or re.match(r'(?:3x-ui|x-ui|3m-ui)(?:[.@-]|$)', name)):
                        continue
                    match = re.search(r'path=([^ ;]+)', command)
                    binary = match[1] if match else str(DEFAULT_BINARY)
                    env = {}
                    paths = re.findall(r'(\S+)\s+\(ignore_errors=', values.get('EnvironmentFiles', ''))
                    for path in ['/etc/default/x-ui', '/etc/conf.d/x-ui', '/etc/sysconfig/x-ui', *paths]:
                        env.update(env_file(path))
                    env.update(environment(shlex.split(values.get('Environment', ''))))
                    pid = number(values.get('MainPID'))
                    if pid:
                        env.update(process_env(pid))
                        pids.add(pid)
                    if env.get('XUI_DB_FOLDER') and not Path(env['XUI_DB_FOLDER']).is_absolute():
                        env['XUI_DB_FOLDER'] = str(Path(values.get('WorkingDirectory') or '/') / env['XUI_DB_FOLDER'])
                    item = native_instance(name, binary, env, values.get('ActiveState') == 'active', pid)
                    if '3m-ui' in command or name.startswith('3m-ui'):
                        args = re.search(r'argv\[\]=(.*?)(?: ;|$)', command)
                        item = three_m_instance(item, args[1] if args else '', values.get('WorkingDirectory') or '/')
                    seen.add(str(Path(item['_database']).resolve()))
                    instances.append(item)
    except (InspectError, ValueError) as error:
        discovery_error = error
    # Standalone processes and custom launchers need no systemd unit name.
    for path in PROC.glob('[0-9]*/exe'):
        pid = number(path.parent.name)
        if pid in pids:
            continue
        try:
            binary = os.readlink(path)
            if Path(binary).name not in ('x-ui', '3x-ui', '3m-ui', '3m-ui-bin'):
                continue
            # Container processes are represented by Docker discovery instead.
            if (path.parent / 'ns/mnt').stat().st_ino != (PROC / '1/ns/mnt').stat().st_ino:
                continue
            item = native_instance(f'{Path(binary).name} (PID {pid})', binary, process_env(pid), True, pid)
            if '3m-ui' in Path(binary).name:
                item = three_m_instance(item, (path.parent / 'cmdline').read_text().replace('\0', ' '), os.readlink(path.parent / 'cwd'))
            db = str(Path(item['_database']).resolve())
            if db not in seen:
                instances.append(item)
                seen.add(db)
        except OSError:
            continue
    if str(DEFAULT_DB.resolve()) not in seen and (DEFAULT_DB.exists() or DEFAULT_BINARY.exists()):
        env = {}
        for path in ('/etc/default/x-ui', '/etc/conf.d/x-ui', '/etc/sysconfig/x-ui'):
            env.update(env_file(path))
        instances.append(native_instance('x-ui', str(DEFAULT_BINARY), env, None))
    if not any(i.get('panelType') == '3m-ui' for i in instances) and (Path('/etc/3m-ui/config.yaml').exists() or Path('/usr/local/lib/3m-ui/3m-ui-bin').exists()):
        instances.append(three_m_instance(native_instance('3m-ui', '/usr/local/lib/3m-ui/3m-ui-bin', {}, None)))
    if discovery_error:
        if not instances:
            raise InspectError('无法检查 systemd 服务，请检查 SSH 权限和服务环境。')
        for instance in instances:
            instance['_discovery_warning'] = True
    return instances


def container_database(container, directory):
    return container_path(container, str(Path(directory) / 'x-ui.db'))


def container_path(container, path):
    path = Path(path)
    mounts = sorted(container.get('Mounts') or [], key=lambda m: len(m.get('Destination', '')), reverse=True)
    for mount in mounts:
        try:
            relative = path.relative_to(mount['Destination'])
            return str(Path(mount['Source']) / relative)
        except (KeyError, ValueError):
            continue
    pid = number(container.get('State', {}).get('Pid'))
    if pid:
        return str(PROC / str(pid) / 'root' / str(path).lstrip('/'))
    return ''


def discover_docker():
    if not shutil.which('docker'):
        return []
    ids = run(['docker', 'ps', '-aq', '--no-trunc']).split()
    if not ids:
        return []
    containers = json.loads(run(['docker', 'inspect', *ids]))
    result = []
    for container in containers:
        config = container.get('Config') or {}
        env = environment(config.get('Env') or [])
        image = config.get('Image', '')
        cmd = ' '.join([*(config.get('Entrypoint') or []), *(config.get('Cmd') or [])])
        paths = [mount.get('Destination', '') for mount in container.get('Mounts') or []]
        if not (re.search(r'(^|[/\s])(?:3x-ui|x-ui|3m-ui)(?:[:/\s]|$)', image + ' ' + cmd)
                or env.get('XUI_IN_DOCKER') == 'true' or '/etc/x-ui' in paths or '/etc/3m-ui' in paths):
            continue
        identifier = container['Id']
        item = {'id': 'docker:' + identifier, 'name': container.get('Name', '').lstrip('/') or identifier[:12],
                       'kind': 'docker', 'running': bool(container.get('State', {}).get('Running')),
                       '_container': identifier, '_env': env,
                       '_database': container_database(container, env.get('XUI_DB_FOLDER') or '/etc/x-ui'),
                       '_network': container.get('HostConfig', {}).get('NetworkMode', ''),
                       '_ports': container.get('NetworkSettings', {}).get('Ports')
                       or container.get('HostConfig', {}).get('PortBindings') or {}}
        item['panelType'] = '3x-ui'
        if '3m-ui' in image+' '+cmd or '/etc/3m-ui' in paths:
            item['_container_info'] = container
            item['_binary'] = '/usr/local/bin/3m-ui'
            item = three_m_instance(item, cmd, config.get('WorkingDir') or '/')
        result.append(item)
    return result


def read_tables(instance):
    env = instance['_env']
    if env.get('XUI_DB_TYPE', '').lower() in ('postgres', 'postgresql', 'pg'):
        # libpq accepts a connection URI/keyword string in PGDATABASE. Credentials
        # stay in the remote process environment, never in argv or returned data.
        if not shutil.which('psql') or not env.get('XUI_DB_DSN'):
            raise InspectError('此实例使用 PostgreSQL；需要服务器可用的 psql 和 XUI_DB_DSN 才能读取。')
        pg_env = {**os.environ, 'PGDATABASE': env['XUI_DB_DSN'], 'PGCONNECT_TIMEOUT': '3',
                  'PGOPTIONS': '-c default_transaction_read_only=on -c statement_timeout=3000'}
        names = ','.join("'" + table + "'" for table in TABLES)
        queries = ("BEGIN READ ONLY;\nSELECT format("
                   "'SELECT json_build_object(%L, coalesce(json_agg(t), ''[]''::json)) "
                   f"FROM (SELECT * FROM %I LIMIT {MAX_ROWS + 1}) t;', name, name) "
                   f"FROM unnest(ARRAY[{names}]) AS names(name) "
                   "WHERE to_regclass(name) IS NOT NULL\n\\gexec\nROLLBACK;")
        output = run(['psql', '-X', '-q', '-A', '-t', '-w', '-v', 'ON_ERROR_STOP=1'], env=pg_env, input=queries)
        data = {}
        for line in output.splitlines():
            data.update(json.loads(line))
        if 'inbounds' not in data:
            raise InspectError('数据库中没有 3x-ui 入站表，请检查该实例的数据库配置。')
        return data
    path = instance['_database']
    if not path or not Path(path).is_file():
        raise InspectError('已发现 3x-ui，但数据库不可读；请检查数据库挂载、服务环境和 SSH 权限。')
    try:
        # mode=ro (not immutable) includes committed WAL records from a live panel.
        with closing(sqlite3.connect(Path(path).resolve().as_uri() + '?mode=ro', uri=True, timeout=2)) as db:
            db.row_factory = sqlite3.Row
            db.execute('PRAGMA query_only=ON')
            db.execute('BEGIN')
            tables = {row[0] for row in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if 'inbounds' not in tables:
                raise InspectError('数据库中没有 3x-ui 入站表，请检查该实例的数据库配置。')
            return {table: [dict(row) for row in db.execute(f'SELECT * FROM "{table}" LIMIT ?', (MAX_ROWS + 1,))]
                    for table in TABLES if table in tables}
    except sqlite3.Error:
        raise InspectError('3x-ui 数据库暂时无法读取，请检查文件权限、数据库锁和版本。') from None


def public_key(private):
    """X25519 public key (RFC 7748); the server private key never leaves SSH."""
    raw = base64.urlsafe_b64decode(private + '=' * (-len(private) % 4))
    if len(raw) != 32:
        raise ValueError('Invalid X25519 key')
    scalar = bytearray(raw)
    scalar[0] &= 248
    scalar[31] = (scalar[31] & 127) | 64
    k, p = int.from_bytes(scalar, 'little'), 2 ** 255 - 19
    x1, x2, z2, x3, z3, swap = 9, 1, 0, 9, 1, 0
    for bit in range(254, -1, -1):
        kt = (k >> bit) & 1
        swap ^= kt
        if swap:
            x2, x3, z2, z3 = x3, x2, z3, z2
        swap = kt
        a, b, c, d = (x2 + z2) % p, (x2 - z2) % p, (x3 + z3) % p, (x3 - z3) % p
        aa, bb, da, cb = a * a % p, b * b % p, d * a % p, c * b % p
        e = (aa - bb) % p
        x3, z3 = (da + cb) ** 2 % p, x1 * (da - cb) ** 2 % p
        x2, z2 = aa * bb % p, e * (aa + 121665 * e) % p
    if swap:
        x2, z2 = x3, z3
    key = (x2 * pow(z2, p - 2, p) % p).to_bytes(32, 'little')
    return base64.urlsafe_b64encode(key).decode().rstrip('=')


def endpoint(instance, inbound, host):
    if inbound.get('node_id') or inbound.get('origin_node_guid'):
        raise InspectError('此入站属于面板的远程节点，请使用面板提供的分享地址。')
    port = number(inbound.get('port'))
    if not 0 < port <= 65535:
        raise InspectError('此入站没有可导出的网络端口。')
    strategy = inbound.get('share_addr_strategy')
    address = inbound.get('share_addr') if strategy == 'custom' else host
    if strategy == 'listen' and inbound.get('listen') not in (None, '', '*', '0.0.0.0', '::'):
        address = inbound['listen']
    address = address or host
    try:
        ipaddress.ip_address(address)
    except ValueError:
        if not re.fullmatch(r'(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?', address):
            raise InspectError('分享地址格式无法识别，请从原面板导出。') from None
    listen = inbound.get('listen', '')
    try:
        if listen and ipaddress.ip_address(listen).is_loopback:
            raise InspectError('此入站仅监听回环地址，请使用现有反向代理或面板的分享链接。')
    except ValueError:
        if listen and listen not in ('*', '0.0.0.0', '::'):
            raise InspectError('此入站使用特殊监听地址，请从原面板导出连接配置。') from None
    if instance['kind'] == 'docker' and instance.get('_network') != 'host':
        protocol = 'udp' if inbound.get('protocol') in ('hysteria', 'hysteria2', 'tuic') else 'tcp'
        bindings = instance.get('_ports', {}).get(f'{port}/{protocol}') or []
        public = [b for b in bindings if b.get('HostIp', '') in ('', '0.0.0.0', '::', host)]
        if not public:
            raise InspectError('容器的节点端口未发布到服务器公网，请检查端口映射。')
        port = number(public[0].get('HostPort'))
        if not 0 < port <= 65535:
            raise InspectError('容器端口映射无效。')
    return address, port


def link_for(inbound, client, host, port):
    protocol = inbound.get('protocol')
    settings, stream = mapping(inbound.get('settings', '{}')), mapping(inbound.get('stream_settings', '{}'))
    network, security = stream.get('network') or 'tcp', stream.get('security') or 'none'
    if network not in ('tcp', 'raw', 'ws', 'grpc', 'httpupgrade', 'xhttp'):
        raise InspectError('此传输方式暂不生成分享链接，请从原面板导出；状态和流量仍可查看。')
    if stream.get('externalProxy') or stream.get('finalmask'):
        raise InspectError('此入站包含额外代理/传输参数，请使用原面板生成的分享链接。')
    params = {'type': network, 'security': security}
    sni = ''
    if security == 'reality':
        reality = mapping(stream.get('realitySettings', {}))
        options = mapping(reality.get('settings', {}))
        key = options.get('publicKey') or public_key(reality.get('privateKey', ''))
        names, ids = reality.get('serverNames') or [], reality.get('shortIds') or []
        if not names or not ids or not key:
            raise InspectError('REALITY 参数不完整，无法生成可靠的分享链接。')
        sni = names[0]
        params.update({'sni': sni, 'pbk': key, 'sid': ids[0], 'fp': options.get('fingerprint') or 'chrome',
                       'spx': options.get('spiderX') or '/'})
    elif security == 'tls':
        tls = mapping(stream.get('tlsSettings', {}))
        options = mapping(tls.get('settings', {}))
        sni = tls.get('serverName') or ''
        if sni:
            params['sni'] = sni
        for source, target in [('fingerprint', 'fp'), ('echConfigList', 'ech'), ('verifyPeerCertByName', 'vcn')]:
            if options.get(source):
                params[target] = options[source]
        if tls.get('alpn'):
            params['alpn'] = ','.join(tls['alpn'])
        if options.get('allowInsecure'):
            params['allowInsecure'] = '1'
    elif security != 'none':
        raise InspectError('此安全协议暂不生成分享链接。')
    if network in ('tcp', 'raw'):
        header = mapping(mapping(stream.get('tcpSettings') or stream.get('rawSettings') or {}).get('header', {}))
        if header.get('type') not in (None, 'none'):
            raise InspectError('此 TCP 入站带有自定义头部，请从原面板导出完整链接。')
    elif network == 'grpc':
        transport = mapping(stream.get('grpcSettings', {}))
        params.update({'serviceName': transport.get('serviceName', ''), 'authority': transport.get('authority', '')})
        if transport.get('multiMode'):
            params['mode'] = 'multi'
    else:
        transport = mapping(stream.get(network + 'Settings', {}))
        params.update({'path': transport.get('path') or '/',
                       'host': transport.get('host') or mapping(transport.get('headers', {})).get('Host', '')})
        if network == 'xhttp':
            params['mode'] = transport.get('mode') or 'auto'
            if transport.get('extra'):
                params['extra'] = json.dumps(transport['extra'], separators=(',', ':'))
    label = short(inbound.get('remark') or f'{protocol}:{port}') + ' · ' + short(client.get('email') or 'client')
    address = f'[{host}]' if ':' in host else host
    if protocol == 'vless':
        identity = client.get('id')
        if settings.get('decryption', 'none') != 'none' or client.get('reverse'):
            raise InspectError('此 VLESS 入站使用额外加密或反向代理，请从原面板导出。')
        params['encryption'] = 'none'
        if client.get('flow') and security in ('tls', 'reality') and not inbound.get('disable_flow'):
            params['flow'] = client['flow']
    elif protocol == 'trojan':
        identity = client.get('password')
    elif protocol == 'vmess':
        if not client.get('id') or security == 'reality':
            raise InspectError('VMess 参数不完整或不支持此安全模式。')
        data = {'v': '2', 'ps': label, 'add': host, 'port': port, 'id': client['id'],
                'aid': number(client.get('alterId')), 'scy': client.get('security') or 'auto',
                'net': network, 'tls': security if security == 'tls' else '', 'sni': sni,
                'type': 'multi' if params.get('mode') == 'multi' else 'none',
                'host': params.get('host', ''), 'path': params.get('serviceName', params.get('path', ''))}
        for field in ('fp', 'alpn', 'authority', 'ech', 'vcn', 'extra'):
            if field in params:
                data[field] = params[field]
        return 'vmess://' + base64.b64encode(json.dumps(data, separators=(',', ':'), ensure_ascii=False).encode()).decode(), sni
    elif protocol == 'shadowsocks':
        method, password = settings.get('method'), client.get('password') or settings.get('password')
        if not method or not password or security != 'none' or network not in ('tcp', 'raw'):
            raise InspectError('此 Shadowsocks 配置需要从原面板导出完整链接。')
        if method.startswith('2022'):
            passwords = [settings.get('password')]
            if not client.get('_single_user'):
                passwords.append(client.get('password'))
            if not all(passwords):
                raise InspectError('Shadowsocks 2022 密钥不完整。')
            identity = ':'.join(urllib.parse.quote(part, safe='') for part in [method, *passwords])
        else:
            identity = base64.urlsafe_b64encode(f'{method}:{password}'.encode()).decode().rstrip('=')
        return f'ss://{identity}@{address}:{port}#{urllib.parse.quote(label, safe="")}', sni
    else:
        raise InspectError('此协议可查看状态和流量，连接配置请从原面板导出。')
    if not identity:
        raise InspectError('客户端连接凭据不完整。')
    query = urllib.parse.urlencode(params, quote_via=urllib.parse.quote)
    return f'{protocol}://{urllib.parse.quote(identity, safe="")}@{address}:{port}?{query}#{urllib.parse.quote(label, safe="")}', sni


def inbound_status(instance, inbound, data, host):
    identifier = number(inbound.get('id'))
    result = {'id': str(identifier), 'name': short(inbound.get('remark') or inbound.get('tag') or identifier),
              'protocol': short(inbound.get('protocol')), 'port': number(inbound.get('port')),
              'enabled': bool(inbound.get('enable')), 'traffic': traffic(inbound), 'clients': []}
    try:
        settings = mapping(inbound.get('settings', '{}'))
        clients = settings.get('clients') or []
        if 'clients' in data and 'client_inbounds' in data:
            records = {row['id']: row for row in data['clients']}
            clients = []
            for binding in data['client_inbounds']:
                row = records.get(binding.get('client_id'))
                if binding.get('inbound_id') == identifier and row:
                    clients.append({**row, 'id': row.get('uuid'), 'expiryTime': row.get('expiry_time'),
                                    'flow': binding.get('flow_override') or row.get('flow')})
        if not isinstance(clients, list):
            raise ValueError('Invalid clients')
        if len(clients) > MAX_ROWS:
            result['message'] = f'客户端数量较多，本次仅显示前 {MAX_ROWS} 条记录。'
        if not clients and settings.get('password') and inbound.get('protocol') in ('trojan', 'shadowsocks'):
            clients = [{'email': 'default', 'password': settings['password'], 'enable': True, '_single_user': True}]
        stats = {row.get('email'): row for row in data.get('client_traffics', []) if row.get('inbound_id') == identifier}
        for index, client in enumerate(clients[:MAX_ROWS]):
            if not isinstance(client, dict):
                result['message'] = '部分客户端配置格式无法识别；原有配置未修改。'
                continue
            current = stats.get(client.get('email'), {})
            expiry = number(current.get('expiry_time', client.get('expiryTime')))
            total = number(current.get('total', client.get('totalGB', client.get('total_gb'))))
            used = traffic(current)
            enabled = bool(client.get('enable', True)) and bool(current.get('enable', True))
            expired = expiry > 0 and expiry <= int(time.time() * 1000)
            exhausted = total > 0 and used['up'] + used['down'] >= total
            node = {'id': str(index), 'name': short(client.get('email') or f'客户端 {index + 1}'),
                    'enabled': enabled, 'expiryTime': expiry, 'total': total, 'traffic': used,
                    'available': result['enabled'] and enabled and not expired and not exhausted}
            if expired:
                node['message'] = '已过期'
            elif exhausted:
                node['message'] = '流量已用尽'
            elif not node['available']:
                node['message'] = '已停用'
            else:
                node['message'] = '已启用'
            try:
                if any(row.get('inbound_id') == identifier and not row.get('is_disabled') for row in data.get('hosts', [])):
                    raise InspectError('此入站使用自定义分享地址，请从原面板导出包含地址覆盖的完整链接。')
                address, port = endpoint(instance, inbound, host)
                link, sni = link_for(inbound, client, address, port)
                if len(link) > 4096:
                    raise InspectError('连接配置较长，请从原面板导出。')
                node.update({'host': address, 'port': port, 'serverName': sni, 'link': link})
            except (ValueError, TypeError, KeyError, InspectError) as error:
                node['linkMessage'] = str(error) if isinstance(error, InspectError) else '连接配置不完整，请从原面板检查或导出。'
            result['clients'].append(node)
    except (ValueError, TypeError, KeyError):
        result['message'] = '入站配置格式无法识别；原有配置未修改。'
    return result


def inspect_instance(instance, host):
    result = {key: instance[key] for key in ('id', 'name', 'kind', 'running')}
    result.update({'inbounds': [], 'readable': False, 'panelType': instance.get('panelType','3x-ui')})
    try:
        if DEADLINE is not None and time.monotonic() >= DEADLINE:
            raise InspectError('读取超时，此实例暂未读取，请稍后重试。')
        if instance.get('panelType') == '3m-ui':
            result['inbounds'], result['truncated'] = three_m_status(instance)
        else:
            data = read_tables(instance)
            result['truncated'] = any(len(rows) > MAX_ROWS for rows in data.values())
            result['inbounds'] = [inbound_status(instance, inbound, data, host) for inbound in data['inbounds'][:MAX_ROWS]]
        result['readable'] = True
        result['message'] = '已读取现有配置' if result['inbounds'] else '服务已接入，尚未配置入站'
    except (InspectError, ValueError, KeyError) as error:
        result['message'] = str(error) if isinstance(error, InspectError) else '数据库结构暂时无法识别；原有配置未修改。'
    try:
        if instance.get('panelType') == '3m-ui':
            version = run(three_m_version_command(instance), merge_stderr=True)
        elif instance['kind'] == 'docker' and instance['running']:
            version = run(['docker', 'exec', instance['_container'], '/app/x-ui', '-v'])
        elif instance.get('_binary') and Path(instance['_binary']).is_file():
            version = run([instance['_binary'], '-v'])
        else:
            version = ''
        match = re.search(r'\bv?\d+\.\d+\.\d+(?:[-.][\w]+)*', version)
        if match:
            result['panelVersion'] = match[0].lstrip('v')
    except InspectError:
        pass
    return result


def host_metrics():
    result = {}
    try:
        values = dict(line.split(':', 1) for line in (PROC / 'meminfo').read_text().splitlines())
        total = int(values['MemTotal'].split()[0]) * 1024
        available = int(values.get('MemAvailable', values['MemFree']).split()[0]) * 1024
        result['memory'] = {'current': max(0, total - available), 'total': total}
        result['uptime'] = float((PROC / 'uptime').read_text().split()[0])
        def cpu():
            return [int(value) for value in (PROC / 'stat').read_text().splitlines()[0].split()[1:9]]
        before = cpu()
        time.sleep(0.1)
        after = cpu()
        delta = sum(after) - sum(before)
        if delta > 0:
            result['cpu'] = max(0, min(100, 100 * (1 - (after[3] + after[4] - before[3] - before[4]) / delta)))
    except (OSError, ValueError, KeyError, IndexError):
        pass
    return result


def installation_state():
    state = read_json(ROOT / 'state.json', {})
    if (ROOT / '.managed').exists() and state.get('phase') in ACTIVE:
        try:
            run(['systemctl', 'is-active', '--quiet', '5a-ui-install.service'])
        except InspectError:
            state = {'phase': 'failed', 'message': '安装任务已中断，可重新点击部署继续。'}
        return state
    if (ROOT / '.managed').exists() and state.get('phase') == 'failed':
        return {'phase': 'failed', 'message': '上次安装未完成，可重新点击部署继续。'}
    return None


def owned_installation(instance):
    # An old .managed marker alone must never authorize overwriting a service.
    if instance.get('panelType') == '3m-ui':
        if (instance['kind'] != 'native' or
                Path(instance.get('_database') or '/').resolve() != Path('/var/lib/3m-ui/3m-ui.db') or
                Path(instance.get('_binary') or '/').resolve() != Path('/usr/local/lib/3m-ui/3m-ui-bin') or
                instance.get('_config') != '/etc/3m-ui/config.yaml' or
                not (ROOT / '3m-connection.json').is_file()):
            return False
        try:
            return f'EnvironmentFile={ROOT}/3m-panel.env' in Path('/etc/systemd/system/3m-ui.service.d/20-5a-ui.conf').read_text().splitlines()
        except OSError:
            return False
    if (instance['kind'] != 'native'
            or Path(instance.get('_database', '')).resolve() != DEFAULT_DB.resolve()
            or Path(instance.get('_binary', '')).resolve() != DEFAULT_BINARY.resolve()
            or instance['_env'].get('XUI_DB_TYPE', 'sqlite') != 'sqlite'
            or not (ROOT / 'panel.env').is_file()):
        return False
    try:
        return f'ExecStartPre=/usr/bin/python3 {ROOT}/manage.py restrict-services' in INSTALL_OVERRIDE.read_text().splitlines()
    except OSError:
        return False


def status(host, only_existing=False):
    progress = installation_state()
    if progress and progress['phase'] in ACTIVE:
        return progress
    instances, warnings = [], []
    for discover in (discover_native, discover_docker):
        try:
            found = discover()
            instances.extend(found)
            if any(item.get('_discovery_warning') for item in found):
                warnings.append('部分服务无法识别，请检查 systemd 是否可用以及 SSH 账号权限。')
        except (InspectError, ValueError):
            warnings.append('部分服务无法识别，请检查 systemd / Docker 是否可用以及 SSH 账号权限。')
    if progress and not warnings and all(owned_installation(item) for item in instances):
        return None if only_existing else progress
    if not instances:
        if warnings:
            return {'error': {'code': 'DISCOVERY_FAILED', 'message': warnings[0]}}
        if only_existing:
            return None
        return {'phase': 'not-installed', 'message': '这台服务器还没有部署面板，可以选择 3x-ui 或 3m-ui 一键部署。'}
    results = [inspect_instance(instance, host) for instance in instances]
    readable = sum(item['readable'] for item in results)
    result = {'phase': 'ready' if readable else 'existing', 'installed': True,
            'running': any(item.get('running') is True for item in results), 'instances': results,
              'message': f'发现 {len(results)} 个面板实例，已读取 {readable} 个。', **host_metrics()}
    if warnings:
        result['message'] += warnings[0]
    result['traffic'] = {key: sum(inbound['traffic'][key] for item in results for inbound in item['inbounds']) for key in ('up', 'down')}
    return result


def encode_result(result):
    # Keep within the SSH transport limit and make any truncation visible.
    while len(json.dumps(result, ensure_ascii=False).encode()) > MAX_OUTPUT:
        inbounds = [inbound for item in result.get('instances', []) for inbound in item['inbounds']]
        largest = max(inbounds, key=lambda inbound: len(inbound['clients']), default=None)
        if largest and largest['clients']:
            largest['clients'].pop()
        else:
            largest_instance = max(result.get('instances', []), key=lambda item: len(item['inbounds']), default=None)
            if not largest_instance or not largest_instance['inbounds']:
                return json.dumps({'error': {'code': 'REMOTE_OUTPUT', 'message': '实例数量过多，请从各实例面板查看完整数据。'}})
            largest_instance['inbounds'].pop()
        result['truncated'] = True
    return json.dumps(result, ensure_ascii=False, separators=(',', ':'))



def three_m_config(instance):
    """Read connection facts only. Never initialize/reset an existing config.

    Prefer PyYAML when installed. The dependency-free fallback accepts the
    scalar mappings emitted by 3m-ui; complex syntax fails closed.
    """
    if instance.get('_config_error'):
        raise InspectError(instance['_config_error'])
    path = instance['_config']
    if instance.get('_container_info'):
        path = container_path(instance['_container_info'], path)
    try:
        raw = Path(path).read_text()
        try:
            import yaml
        except ImportError:
            if raw.lstrip().startswith('{'):
                values = json.loads(raw)
                raw = ''
            else:
                values = {}
            section, seen = None, set()
            for line in raw.splitlines():
                if not line.strip() or line.lstrip().startswith('#'):
                    continue
                if not line.startswith(' '):
                    match = re.fullmatch(r'([a-z_]+):\s*(?:#.*)?', line)
                    if not match or match[1] in seen:
                        raise ValueError('Unsupported YAML')
                    section = match[1]
                    seen.add(section)
                    values[section] = {}
                elif section in ('server','database','mihomo'):
                    match = re.fullmatch(r' +([a-z_]+):\s*(.*)',line)
                    if not match or match[1] in values[section]:
                        raise ValueError('Unsupported YAML')
                    key, value = match.groups()
                    if value.startswith('"'):
                        value = json.loads(value)
                    elif value.startswith("'"):
                        if not value.endswith("'"): raise ValueError('Unsupported YAML')
                        value = value[1:-1].replace("''", "'")
                    else:
                        value = re.split(r'\s+#',value)[0].strip()
                        if any(c in value for c in '{}[]&*!|>\t'):
                            raise ValueError('Unsupported YAML')
                    values[section][key] = value
        else:
            values = yaml.safe_load(raw)
        if not isinstance(values,dict): raise ValueError('Invalid YAML')
        server = dict(values.get('server',{}))
        env = instance['_env']
        for key, aliases in {'port':('THREE_M_UI_PORT','PANEL_PORT'), 'listen':('THREE_M_UI_LISTEN','PANEL_LISTEN')}.items():
            for alias in aliases:
                if env.get(alias):
                    server[key] = env[alias]
                    break
        database = values['database']['path']
        if not isinstance(database,str) or not database:
            raise ValueError('Missing database path')
        return {'server':server,'database':database,'mihomo':values.get('mihomo',{})}
    except (OSError, ValueError, KeyError, TypeError):
        raise InspectError('已发现 3m-ui，但配置无法安全读取。请检查配置路径 / 权限，或在管理页指定已有面板入口。') from None


def three_m_instance(item, command='', cwd='/'):
    item['panelType'] = '3m-ui'
    item['_config'] = item['_env'].get('THREE_M_UI_CONFIG') or '/etc/3m-ui/config.yaml'
    try:
        args = shlex.split(command)
        for index, value in enumerate(args):
            if value in ('--config','-c'):
                item['_config'] = args[index+1]
            elif value.startswith('--config='):
                item['_config'] = value.split('=',1)[1]
        if not Path(item['_config']).is_absolute():
            item['_config'] = str(Path(cwd) / item['_config'])
        cfg = three_m_config(item)
        path = str(Path(cwd) / cfg['database']) if not Path(cfg['database']).is_absolute() else cfg['database']
        item['_database'] = container_path(item['_container_info'],path) if item.get('_container_info') else path
        item['_core_binary'] = cfg['mihomo'].get('binary','')
    except (InspectError, ValueError, IndexError) as error:
        item['_database'] = ''
        item['_config_error'] = str(error) if isinstance(error,InspectError) else '3m-ui 启动参数无法识别，请手动指定面板入口。'
    return item


def three_m_tables(instance):
    if instance.get('_config_error'): raise InspectError(instance['_config_error'])
    tables = ('listeners','proxy_users','listener_users','user_node_traffics')
    try:
        with closing(sqlite3.connect(Path(instance['_database']).resolve().as_uri()+'?mode=ro',uri=True,timeout=2)) as db:
            db.row_factory=sqlite3.Row
            db.execute('PRAGMA query_only=ON')
            db.execute('BEGIN')
            names={r[0] for r in db.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            if 'listeners' not in names: raise ValueError('Unknown schema')
            return {name:[dict(r) for r in db.execute(f'SELECT * FROM "{name}" LIMIT ?', (MAX_ROWS+1,))]
                    for name in tables if name in names}
    except (sqlite3.Error,ValueError,OSError):
        raise InspectError('已发现 3m-ui，但数据库无法读取。原配置未修改，可在管理页使用现有账号接入。') from None


def three_m_status(instance):
    import datetime
    data = three_m_tables(instance)
    result=[]
    for listener in data['listeners'][:MAX_ROWS]:
        if listener.get('deleted_at'): continue
        identifier=listener['id']
        bindings={b['proxy_user_id'] for b in data.get('listener_users',[]) if b['listener_id']==identifier and not b.get('deleted_at')}
        clients=[]
        for user in data.get('proxy_users',[])[:MAX_ROWS]:
            if user['id'] not in bindings or user.get('deleted_at'): continue
            expiry=0
            try:
                expiry=max(0,int(datetime.datetime.fromisoformat(user.get('expire_time','').replace('Z','+00:00')).timestamp()*1000))
            except (ValueError,TypeError,OverflowError): pass
            quota=number(user.get('traffic_limit'))
            active=bool(user.get('enabled')) and (not quota or number(user.get('traffic_used'))<quota) and (not expiry or expiry>time.time()*1000)
            clients.append({'id':str(user['id']),'name':short(user.get('username')),
                'enabled':bool(user.get('enabled')),'available':active and bool(listener.get('enabled')),
                'total':quota,'expiryTime':expiry,
                'traffic':{'up':number(user.get('upload_bytes')),'down':number(user.get('download_bytes'))},
                'linkMessage':'进入面板管理生成分享链接 / 订阅；不从加密数据库推测凭据。'})
        rows=[t for t in data.get('user_node_traffics',[]) if t.get('listener_id')==identifier]
        result.append({'id':str(identifier),'name':short(listener.get('name')),'protocol':short(listener.get('protocol')),
            'port':number(listener.get('port')), 'enabled':bool(listener.get('enabled')), 'clients':clients,
            'message':'端口 '+short(listener.get('port'))+' · 配置已读取，运行情况请在管理页检查',
            'traffic':{'up':sum(number(t.get('upload_bytes')) for t in rows),'down':sum(number(t.get('download_bytes')) for t in rows)}})
    return result, any(len(rows)>MAX_ROWS for rows in data.values())


def three_m_version_command(instance):
    if instance['kind']=='docker':
        return ['docker','exec',instance['_container'],instance.get('_binary') or '/usr/local/bin/3m-ui','--version']
    return [instance['_binary'],'--version']


if __name__ == '__main__':
    try:
        host = base64.b64decode(sys.argv[1]).decode()
        ipaddress.ip_address(host)
        DEADLINE = time.monotonic() + 20
        result = status(host, '--if-existing' in sys.argv)
        if result is not None:
            print('5A_UI_RESULT=' + encode_result(result))
    except Exception:
        # Do not expose database DSNs, server paths or raw subprocess errors.
        print('5A_UI_RESULT=' + json.dumps({'error': {'code': 'INSPECT_FAILED', 'message': '无法读取已有面板，请检查服务环境、Python 3 和数据库权限。'}}, ensure_ascii=False))
