import base64
import importlib.util
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('xui_inspect', ROOT / 'scripts/remote/inspect.py')
inspect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(inspect)


class InspectTest(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.db = self.root / 'x-ui.db'
        self.instance = {'id': 'native:x-ui.service', 'name': 'x-ui.service', 'kind': 'native',
                         'running': True, '_env': {}, '_database': str(self.db)}
        self.client = {'id': 'test-client-uuid', 'email': 'alice', 'enable': True, 'flow': 'xtls-rprx-vision'}
        self.inbound = {'id': 3, 'remark': 'Existing VLESS', 'protocol': 'vless', 'port': 443, 'enable': 1,
                        'up': 42, 'down': 84, 'listen': '',
                        'settings': json.dumps({'clients': [self.client], 'decryption': 'none'}),
                        'stream_settings': json.dumps({'network': 'tcp', 'security': 'reality', 'realitySettings': {
                            'privateKey': 'private-never-return', 'serverNames': ['www.example.com'],
                            'shortIds': ['abc123'], 'settings': {'publicKey': 'public-key', 'fingerprint': 'chrome'}}})}
        self.create_db()
        for name, value in [('ROOT', self.root / 'managed'), ('PROC', self.root / 'proc'),
                            ('DEFAULT_DB', self.db), ('DEFAULT_BINARY', self.root / 'x-ui')]:
            mock = patch.object(inspect, name, value)
            mock.start()
            self.addCleanup(mock.stop)

    def create_db(self):
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE inbounds (id INTEGER, remark TEXT, protocol TEXT, port INTEGER, enable INTEGER, up INTEGER, down INTEGER, listen TEXT, settings TEXT, stream_settings TEXT)')
            db.execute('INSERT INTO inbounds VALUES (:id,:remark,:protocol,:port,:enable,:up,:down,:listen,:settings,:stream_settings)', self.inbound)
            db.execute('CREATE TABLE client_traffics (inbound_id INTEGER, email TEXT, enable INTEGER, up INTEGER, down INTEGER, total INTEGER, expiry_time INTEGER)')
            db.execute('INSERT INTO client_traffics VALUES (3,"alice",1,12,34,1000,0)')
            db.execute('CREATE TABLE users (username TEXT, password TEXT)')
            db.execute('INSERT INTO users VALUES ("panel-admin", "panel-password-never-return")')

    def read(self):
        return inspect.inspect_instance(self.instance, '8.8.8.8')

    def test_unmanaged_installation_is_read_without_writes_or_panel_secrets(self):
        before = self.db.read_bytes()
        result = self.read()
        self.assertTrue(result['readable'])
        self.assertTrue(result['running'])
        node = result['inbounds'][0]['clients'][0]
        self.assertEqual(node['traffic'], {'up': 12, 'down': 34})
        self.assertTrue(node['available'])
        uri = urlparse(node['link'])
        self.assertEqual(uri.hostname, '8.8.8.8')
        self.assertEqual(uri.port, 443)
        self.assertEqual(parse_qs(uri.query)['pbk'], ['public-key'])
        serialized = json.dumps(result)
        for secret in ('private-never-return', 'panel-password-never-return', 'panel-admin', 'settings', '_database'):
            self.assertNotIn(secret, serialized)
        self.assertEqual(self.db.read_bytes(), before)
        self.assertFalse((self.root / 'managed').exists())

    def test_modern_client_tables_are_joined_without_stale_embedded_clients(self):
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE clients (id INTEGER, uuid TEXT, email TEXT, enable INTEGER, flow TEXT, expiry_time INTEGER, password TEXT)')
            db.execute('CREATE TABLE client_inbounds (client_id INTEGER, inbound_id INTEGER, flow_override TEXT)')
            db.execute('INSERT INTO clients VALUES (7,"new-uuid","bob",1,"",0,"do-not-leak")')
            db.execute('INSERT INTO client_inbounds VALUES (7,3,"xtls-rprx-vision")')
        clients = self.read()['inbounds'][0]['clients']
        self.assertEqual([node['name'] for node in clients], ['bob'])
        self.assertIn('new-uuid@', clients[0]['link'])
        self.assertIn('flow=xtls-rprx-vision', clients[0]['link'])
        self.assertNotIn('do-not-leak', json.dumps(clients))

    def test_live_wal_changes_are_visible_in_read_only_snapshot(self):
        db = sqlite3.connect(self.db)
        self.addCleanup(db.close)
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('UPDATE inbounds SET down=999')
        db.commit()
        before = (self.db.read_bytes(), Path(str(self.db) + '-wal').read_bytes())
        self.assertEqual(self.read()['inbounds'][0]['traffic']['down'], 999)
        self.assertEqual((self.db.read_bytes(), Path(str(self.db) + '-wal').read_bytes()), before)

    def test_disabled_expired_and_exhausted_clients_remain_visible(self):
        for updates in ('enable=0', 'expiry_time=1', 'total=10'):
            with self.subTest(updates=updates), sqlite3.connect(self.db) as db:
                db.execute('UPDATE client_traffics SET enable=1,expiry_time=0,total=1000')
                db.execute('UPDATE client_traffics SET ' + updates)
                db.commit()
                node = self.read()['inbounds'][0]['clients'][0]
                self.assertFalse(node['available'])
                self.assertIn('link', node)

    @patch.object(inspect, 'run', return_value='3.10.0')
    def test_container_ports_are_mapped_without_assuming_internal_port_is_public(self, _):
        self.instance.update({'kind': 'docker', '_container': 'fixture', '_network': 'bridge', '_ports': {
            '443/tcp': [{'HostIp': '0.0.0.0', 'HostPort': '8443'}]}})
        node = self.read()['inbounds'][0]['clients'][0]
        self.assertEqual(node['port'], 8443)
        self.assertIn(':8443?', node['link'])
        self.instance['_ports']['443/tcp'][0]['HostIp'] = '127.0.0.1'
        node = self.read()['inbounds'][0]['clients'][0]
        self.assertNotIn('link', node)
        self.assertIn('未发布', node['linkMessage'])

    def test_stopped_container_database_mount_and_custom_directory_are_discovered(self):
        container = {'Id': 'a' * 64, 'Name': '/custom-panel', 'Config': {
            'Image': 'example/private-image', 'Env': ['XUI_DB_FOLDER=/data/db', 'XUI_IN_DOCKER=true']},
            'State': {'Running': False, 'Pid': 0},
            'Mounts': [{'Source': str(self.root), 'Destination': '/data/db'}],
            'HostConfig': {'NetworkMode': 'host'}}
        with patch.object(inspect.shutil, 'which', return_value='/bin/docker'), \
                patch.object(inspect, 'run', side_effect=['a' * 64, json.dumps([container])]):
            found = inspect.discover_docker()
        self.assertEqual(len(found), 1)
        self.assertFalse(found[0]['running'])
        self.assertEqual(found[0]['_database'], str(self.db))
        result = inspect.inspect_instance(found[0], '8.8.8.8')
        self.assertTrue(result['readable'])

    def test_custom_systemd_name_and_environment_database_path(self):
        detail = (f'Id=proxy-panel.service\nExecStart={{ path=/opt/panel/x-ui ; argv[]=/opt/panel/x-ui ; }}\n'
                  f'Environment=XUI_DB_FOLDER={self.root}\nEnvironmentFiles=\nMainPID=0\nActiveState=inactive\n')
        with patch.object(inspect.shutil, 'which', return_value='/bin/systemctl'), \
                patch.object(inspect, 'run', side_effect=['proxy-panel.service enabled', detail]):
            found = inspect.discover_native()
        self.assertEqual(len(found), 1)
        self.assertEqual(found[0]['name'], 'proxy-panel.service')
        self.assertEqual(found[0]['_database'], str(self.db))
        self.assertFalse(found[0]['running'])

    def test_systemd_failure_keeps_default_installation_visible(self):
        with patch.object(inspect.shutil, 'which', return_value='/bin/systemctl'), \
                patch.object(inspect, 'run', side_effect=inspect.InspectError('no bus')), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            result = inspect.status('8.8.8.8', only_existing=True)
        self.assertEqual(result['phase'], 'ready')
        self.assertTrue(result['installed'])
        self.assertIsNone(result['instances'][0]['running'])
        self.assertIn('部分服务无法识别', result['message'])

    def test_multiple_instances_are_read_even_with_missing_or_invalid_database(self):
        second = {**self.instance, 'id': 'native:other', 'name': 'other', '_database': str(self.root / 'missing.db')}
        with patch.object(inspect, 'discover_native', return_value=[self.instance, second]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            result = inspect.status('8.8.8.8')
        self.assertEqual(result['phase'], 'ready')
        self.assertEqual(len(result['instances']), 2)
        self.assertFalse(result['instances'][1]['readable'])
        self.assertFalse((self.root / 'missing.db').exists())
        self.db.write_bytes(b'not a sqlite database')
        self.assertFalse(self.read()['readable'])

    def test_discovery_failure_cannot_start_installation(self):
        with patch.object(inspect, 'discover_native', side_effect=inspect.InspectError('not available')), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            result = inspect.status('8.8.8.8', only_existing=True)
        self.assertEqual(result['error']['code'], 'DISCOVERY_FAILED')

    def test_empty_server_and_existing_server_have_distinct_install_preflight(self):
        with patch.object(inspect, 'discover_native', return_value=[]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            self.assertIsNone(inspect.status('8.8.8.8', only_existing=True))
            self.assertEqual(inspect.status('8.8.8.8')['phase'], 'not-installed')
        with patch.object(inspect, 'discover_native', return_value=[self.instance]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            result = inspect.status('8.8.8.8', only_existing=True)
        self.assertTrue(result['installed'])
        self.assertEqual(result['phase'], 'ready')

    def test_managed_ready_uses_same_inventory_and_interrupted_job_remains_retryable(self):
        managed = self.root / 'managed'
        managed.mkdir()
        (managed / '.managed').touch()
        (managed / 'state.json').write_text('{"phase":"ready"}')
        with patch.object(inspect, 'discover_native', return_value=[self.instance]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            self.assertEqual(len(inspect.status('8.8.8.8')['instances']), 1)
        (managed / 'state.json').write_text('{"phase":"installing"}')
        with patch.object(inspect, 'run', side_effect=inspect.InspectError('stopped')), \
                patch.object(inspect, 'discover_native', return_value=[]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            self.assertEqual(inspect.status('8.8.8.8')['phase'], 'failed')
            self.assertIsNone(inspect.status('8.8.8.8', only_existing=True))

    def test_failed_install_marker_cannot_authorize_modifying_external_services(self):
        managed = self.root / 'managed'
        managed.mkdir()
        (managed / '.managed').touch()
        (managed / 'state.json').write_text('{"phase":"failed"}')
        override = self.root / '20-5a-ui.conf'
        override.write_text(f'ExecStartPre=/usr/bin/python3 {managed}/manage.py restrict-services\n')
        self.instance['_binary'] = str(inspect.DEFAULT_BINARY)
        with patch.object(inspect, 'INSTALL_OVERRIDE', override), \
                patch.object(inspect, 'discover_native', return_value=[self.instance]), \
                patch.object(inspect, 'discover_docker', return_value=[]):
            # No installer credentials: even a matching service is not owned.
            self.assertTrue(inspect.status('8.8.8.8', only_existing=True)['installed'])
            (managed / 'panel.env').touch()
            self.assertIsNone(inspect.status('8.8.8.8', only_existing=True))
            self.assertEqual(inspect.status('8.8.8.8')['phase'], 'failed')
            # Any second external instance prevents the retry from altering it.
            external = {**self.instance, 'id': 'native:external', 'name': 'external',
                        '_database': str(self.root / 'external.db')}
            with patch.object(inspect, 'discover_native', return_value=[self.instance, external]):
                self.assertEqual(len(inspect.status('8.8.8.8', only_existing=True)['instances']), 2)

    def test_read_deadline_preserves_unreadable_instances(self):
        with patch.object(inspect, 'DEADLINE', 0):
            result = self.read()
        self.assertFalse(result['readable'])
        self.assertEqual(result['id'], self.instance['id'])
        self.assertIn('超时', result['message'])

    def test_public_key_derivation_matches_rfc7748(self):
        private = bytes.fromhex('77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a')
        expected = bytes.fromhex('8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a')
        encoded = base64.urlsafe_b64encode(private).decode().rstrip('=')
        self.assertEqual(inspect.public_key(encoded), base64.urlsafe_b64encode(expected).decode().rstrip('='))

    def test_vmess_trojan_and_shadowsocks_link_credentials_and_transport(self):
        client = {'id': 'uuid', 'email': 'demo', 'password': 'p@ss:word', 'security': 'auto'}
        stream = {'network': 'ws', 'security': 'tls', 'wsSettings': {'path': '/ws', 'headers': {'Host': 'cdn.example.com'}},
                  'tlsSettings': {'serverName': 'sni.example.com', 'alpn': ['h2']}}
        inbound = {**self.inbound, 'protocol': 'vmess', 'settings': '{}', 'stream_settings': json.dumps(stream)}
        link, _ = inspect.link_for(inbound, client, '2606:4700:4700::1111', 8443)
        vmess = json.loads(base64.b64decode(link[8:]))
        self.assertEqual((vmess['add'], vmess['path'], vmess['host'], vmess['sni']),
                         ('2606:4700:4700::1111', '/ws', 'cdn.example.com', 'sni.example.com'))
        inbound['protocol'] = 'trojan'
        link, _ = inspect.link_for(inbound, client, '8.8.8.8', 443)
        self.assertIn('trojan://p%40ss%3Aword@', link)
        inbound.update({'protocol': 'shadowsocks', 'settings': '{"method":"aes-128-gcm"}', 'stream_settings': '{}'})
        link, _ = inspect.link_for(inbound, client, '8.8.8.8', 443)
        self.assertTrue(link.startswith('ss://'))
        identity = urlparse(link).username
        self.assertEqual(base64.urlsafe_b64decode(identity + '=' * (-len(identity) % 4)), b'aes-128-gcm:p@ss:word')

    def test_unknown_protocol_or_corrupt_inbound_does_not_hide_other_inbounds(self):
        with sqlite3.connect(self.db) as db:
            other = {**self.inbound, 'id': 4, 'protocol': 'wireguard', 'remark': 'wireguard'}
            db.execute('INSERT INTO inbounds VALUES (:id,:remark,:protocol,:port,:enable,:up,:down,:listen,:settings,:stream_settings)', other)
        result = self.read()
        self.assertEqual(len(result['inbounds']), 2)
        self.assertIn('link', result['inbounds'][0]['clients'][0])
        self.assertNotIn('link', result['inbounds'][1]['clients'][0])
        self.assertIn('原面板', result['inbounds'][1]['clients'][0]['linkMessage'])

    def test_single_user_shadowsocks_2022_does_not_duplicate_the_server_key(self):
        inbound = {**self.inbound, 'protocol': 'shadowsocks', 'stream_settings': '{}',
                   'settings': json.dumps({'method': '2022-blake3-chacha20-poly1305', 'password': 'server/key='})}
        result = inspect.inbound_status(self.instance, inbound, {}, '8.8.8.8')
        self.assertIn('ss://2022-blake3-chacha20-poly1305:server%2Fkey%3D@', result['clients'][0]['link'])

    def test_custom_share_address_keeps_container_port_and_disable_flow(self):
        self.instance.update({'kind': 'docker', '_container': 'fixture', '_network': 'bridge', '_ports': {
            '443/tcp': [{'HostIp': '0.0.0.0', 'HostPort': '8443'}]}})
        inbound = {**self.inbound, 'share_addr_strategy': 'custom', 'share_addr': 'edge.example.com', 'disable_flow': True}
        result = inspect.inbound_status(self.instance, inbound, {}, '8.8.8.8')['clients'][0]
        self.assertIn('@edge.example.com:8443?', result['link'])
        self.assertNotIn('flow=', result['link'])

    def test_custom_host_overrides_do_not_produce_incomplete_links(self):
        data = {'hosts': [{'inbound_id': 3, 'is_disabled': False}]}
        node = inspect.inbound_status(self.instance, self.inbound, data, '8.8.8.8')['clients'][0]
        self.assertNotIn('link', node)
        self.assertIn('自定义分享地址', node['linkMessage'])

    def test_postgres_credentials_stay_in_process_environment_and_queries_are_read_only(self):
        self.instance['_env'] = {'XUI_DB_TYPE': 'postgres', 'XUI_DB_DSN': 'postgres://user:private-password@db/app'}
        lines = '\n'.join(json.dumps({table: []}) for table in inspect.TABLES)
        with patch.object(inspect.shutil, 'which', return_value='/bin/psql'), \
                patch.object(inspect, 'run', return_value=lines) as command:
            result = self.read()
        self.assertTrue(result['readable'])
        self.assertNotIn('private-password', json.dumps(result))
        self.assertNotIn('private-password', ' '.join(command.call_args.args[0]))
        self.assertIn('BEGIN READ ONLY', command.call_args.kwargs['input'])
        self.assertIn('default_transaction_read_only=on', command.call_args.kwargs['env']['PGOPTIONS'])

    def test_large_responses_are_explicitly_truncated_below_transport_limit(self):
        result = {'phase': 'ready', 'message': 'ok', 'instances': [self.read()]}
        clients = result['instances'][0]['inbounds'][0]['clients']
        clients.extend([dict(clients[0], id=str(index)) for index in range(1000)])
        text = inspect.encode_result(result)
        self.assertLess(len(text.encode()), 128 * 1024)
        self.assertTrue(json.loads(text)['truncated'])

    def test_install_script_returns_existing_instance_before_any_provisioning(self):
        template = (ROOT / 'scripts/remote/install.sh.template').read_text()
        output = {'phase': 'ready', 'installed': True, 'message': 'existing fixture'}
        script = 'print(' + repr('5A_UI_RESULT=' + json.dumps(output)) + ')'
        template = template.replace('@@INSPECTOR@@', base64.b64encode(script.encode()).decode()).replace('@@HOST@@', base64.b64encode(b'8.8.8.8').decode())
        # Only the two read-preflight programs exist in PATH. Provisioning commands
        # are unavailable, and this script must return before touching /var/lib.
        bindir = self.root / 'bin'
        bindir.mkdir()
        (bindir / 'python3').symlink_to(sys.executable)
        (bindir / 'base64').symlink_to(shutil.which('base64'))
        result = subprocess.run(['/bin/bash'], input=template, env={**os.environ, 'PATH': str(bindir)}, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout.strip().split('=', 1)[1]), output)


if __name__ == '__main__':
    unittest.main()
