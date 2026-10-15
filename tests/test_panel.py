import base64
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import importlib.util
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import types
import unittest
from unittest.mock import Mock, patch
from urllib.parse import parse_qs

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('panel', ROOT / 'scripts/remote/panel.py')
panel = importlib.util.module_from_spec(spec)
spec.loader.exec_module(panel)
OPERATIONS = json.loads((ROOT / 'contracts/panel-operations.json').read_text())


class PanelTest(unittest.TestCase):
    def setUp(self):
        self.requests = []
        requests = self.requests
        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass
            def do_GET(self):
                self.handle_request()
            def do_POST(self):
                self.handle_request()
            def handle_request(self):
                data = self.rfile.read(int(self.headers.get('Content-Length', 0)))
                requests.append((self.path, dict(self.headers), data))
                if self.path.endswith('/redirect'):
                    self.send_response(302)
                    self.send_header('Location', 'http://untrusted.invalid/secret')
                    self.end_headers()
                    return
                status = 403 if self.path.endswith('/denied') else 200
                self.send_response(status)
                self.send_header('Content-Type', 'application/json')
                self.send_header('Set-Cookie', 'session=synthetic-session; Path=/')
                self.end_headers()
                value = {'success': True, 'obj': 'synthetic-csrf' if self.path.endswith('/csrf-token') else {'accepted': True}}
                if self.path.endswith('/reject'):
                    value = {'success': False, 'msg': 'raw-sensitive-database-error'}
                self.wfile.write(json.dumps(value).encode())
        server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.settings = {'webPort': server.server_port, 'webListen': '127.0.0.1', 'webBasePath': '/fixture/'}

    def test_login_csrf_cookie_and_resume_without_repeating_password(self):
        client = panel.Panel(self.settings, {'username': 'fixture-admin', 'password': 'synthetic-password'})
        client.request('/panel/api/inbounds/add', 'POST', {'port': 443})
        path, headers, payload = self.requests[-1]
        self.assertEqual(path, '/fixture/panel/api/inbounds/add')
        self.assertEqual(headers['X-Csrf-Token'], 'synthetic-csrf')
        self.assertIn('session=synthetic-session', headers['Cookie'])
        self.assertNotIn(b'synthetic-password', payload)
        before = len(self.requests)
        resumed = panel.Panel(self.settings, {'session': client.session()})
        resumed.request('/panel/api/server/status')
        self.assertEqual(len(self.requests), before + 1)

    def test_token_form_encoding_and_no_proxy_or_redirect_following(self):
        client = panel.Panel(self.settings, {'token': 'synthetic-token'})
        client.request('/panel/api/xray/update', 'POST', {'xraySetting': {'dns': {}}, 'enabled': False}, 'application/x-www-form-urlencoded')
        _, headers, raw = self.requests[-1]
        self.assertEqual(headers['Authorization'], 'Bearer synthetic-token')
        self.assertEqual(parse_qs(raw.decode())['enabled'], ['false'])
        self.assertEqual(json.loads(parse_qs(raw.decode())['xraySetting'][0]), {'dns': {}})
        with self.assertRaises(panel.PanelError) as error:
            client.request('/redirect')
        self.assertEqual(error.exception.code, 'PANEL_REDIRECT')

    def test_permission_and_validation_failures_do_not_leak_raw_errors(self):
        client = panel.Panel(self.settings, {'token': 'synthetic-token'})
        for path, code in [('/denied', 'PANEL_PERMISSION'), ('/reject', 'PANEL_REJECTED')]:
            with self.subTest(path=path), self.assertRaises(panel.PanelError) as error:
                client.request(path)
            self.assertEqual(error.exception.code, code)
            self.assertNotIn('raw-sensitive', str(error.exception))

    def test_subscription_balancer_preserves_repeated_ids_and_json_weights(self):
        client = panel.Panel(self.settings, {'token': 'synthetic-token'})
        for path in ('/panel/api/sub-balancers', '/panel/api/sub-balancers/7'):
            client.request(path, 'POST', {'inboundIds': [11, 22], 'memberWeights': {'11': 0.5}, 'enabled': False}, 'application/x-www-form-urlencoded')
            form = parse_qs(self.requests[-1][2].decode())
            self.assertEqual(form['inboundIds'], ['11', '22'])
            self.assertEqual(json.loads(form['memberWeights'][0]), {'11': 0.5})
            self.assertEqual(form['enabled'], ['false'])

    def test_binary_restore_is_multipart_and_keeps_host_settings(self):
        client = panel.Panel(self.settings, {'token': 'synthetic-token'})
        client.request('/panel/api/server/importDB', 'POST', {'db': base64.b64encode(b'SQLite fixture').decode()}, 'multipart/form-data')
        _, headers, raw = self.requests[-1]
        self.assertTrue(headers['Content-Type'].startswith('multipart/form-data; boundary='))
        self.assertIn(b'name="db"; filename="backup.db"', raw)
        self.assertIn(b'name="keepHostSettings"\r\n\r\ntrue', raw)

    def test_path_parameters_cannot_escape_allowlisted_operation(self):
        op = next(op for op in OPERATIONS if op['path'] == '/clients/get/{email}')
        self.assertTrue(panel.route(op, {'email': 'alice@example.test'}).endswith('/alice%40example.test'))
        for value in ('../server/status', '%2f', 'a?x=y', 'a\nHeader: value'):
            with self.subTest(value=value), self.assertRaises(panel.PanelError):
                panel.route(op, {'email': value})

    def test_xray_version_accepts_status_value_and_release_tag(self):
        op = next(op for op in OPERATIONS if op['path'] == '/server/installXray/{version}')
        self.assertEqual(panel.route(op, {'version': '26.10.10'}), panel.route(op, {'version': 'v26.10.10'}))
        with self.assertRaises(panel.PanelError):
            panel.route(op, {'version': 'latest'} )

    def test_settings_are_read_without_database_mutation_or_secret_selection(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'fixture.db'
            with sqlite3.connect(path) as db:
                db.execute('CREATE TABLE settings (key TEXT, value TEXT)')
                db.executemany('INSERT INTO settings VALUES (?,?)', [('webPort', '2053'), ('tgBotToken', 'do-not-read')])
            before = path.read_bytes()
            result = panel.read_settings({'_database': str(path), '_env': {}}, None)
            self.assertEqual(result, {'webPort': '2053'})
            self.assertEqual(path.read_bytes(), before)

    def test_settings_reader_closes_connection_before_restore(self):
        db = Mock()
        db.execute.return_value = [('webPort', '2053')]
        with patch.object(panel.sqlite3, 'connect', return_value=db):
            self.assertEqual(panel.read_settings({'_database': '/fixture.db', '_env': {}}, None), {'webPort': '2053'})
        db.close.assert_called_once()

    def test_link_host_uses_connected_address_but_transport_stays_local(self):
        client = panel.Panel(self.settings, {'token': 'synthetic'}, '8.8.8.8')
        client.request('/panel/api/clients/links/fixture')
        self.assertEqual(self.requests[-1][1]['Host'], '8.8.8.8')
        self.assertIn('127.0.0.1', client.base)

    def test_restore_rejects_old_keep_setting_and_restarts_only_selected_instance(self):
        instance = {'id': 'docker:fixture', 'kind': 'docker', '_container': 'fixture'}
        inspector = types.SimpleNamespace(discover_native=lambda: [], discover_docker=lambda: [instance])
        request = {'instanceId': instance['id'], 'operation': 'post_panel_api_server_importDB',
                   'confirmed': True, 'auth': {'token': 'synthetic'}, 'data': {'db': 'Zml4dHVyZQ==', 'keepHostSettings': True}}
        with patch.object(panel, 'version_of', return_value=(3, 6, 0)), patch.object(panel, 'Panel') as transport:
            with self.assertRaises(panel.PanelError) as error:
                panel.perform(request, inspector, OPERATIONS)
            self.assertEqual(error.exception.code, 'PANEL_UNSUPPORTED')
            transport.assert_not_called()
        request['data']['keepHostSettings'] = False
        with patch.object(panel, 'version_of', return_value=(3, 6, 0)), patch.object(panel, 'read_settings', return_value={}), \
                patch.object(panel, 'enter_network'), patch.object(panel, 'Panel'), patch.object(panel, 'run_service') as restart:
            result = panel.perform(request, inspector, OPERATIONS)
        restart.assert_called_once_with(instance, 'restart')
        self.assertTrue(result['result']['reauthenticate'])
        self.assertNotIn('session', result)

    def test_legacy_tokens_never_silently_broaden_scope_or_ignore_expiry(self):
        instance = {'id': 'docker:fixture', 'kind': 'docker'}
        inspector = types.SimpleNamespace(discover_native=lambda: [], discover_docker=lambda: [instance])
        for data in ({'scope': 'monitor'}, {'scope': 'node-sync'}, {'expiresAt': 123456789}, {'expectedScope': 'monitor'}):
            with self.subTest(data=data), patch.object(panel, 'version_of', return_value=(3, 6, 0)), patch.object(panel, 'Panel') as transport:
                with self.assertRaises(panel.PanelError) as error:
                    panel.perform({'instanceId': instance['id'], 'operation': 'post_panel_api_setting_apiTokens_create', 'confirmed': True, 'data': data}, inspector, OPERATIONS)
                self.assertEqual(error.exception.code, 'PANEL_UNSUPPORTED')
                transport.assert_not_called()

    def test_restricted_token_catalogue_contains_only_verified_status(self):
        instance = {'id': 'docker:fixture', 'kind': 'docker'}
        inspector = types.SimpleNamespace(discover_native=lambda: [], discover_docker=lambda: [instance])
        transport = Mock()
        transport.request.side_effect = [{}, panel.PanelError('PANEL_PERMISSION', 'restricted')]
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'read_settings', return_value={}), patch.object(panel, 'enter_network'), patch.object(panel, 'Panel', return_value=transport):
            result = panel.perform({'instanceId': instance['id'], 'operation': 'catalog', 'auth': {'token': 'synthetic'}}, inspector, OPERATIONS)
        self.assertEqual(result['result']['operations'], ['get_panel_api_server_status'])
        self.assertEqual(result['result']['capabilitySource'], 'restricted')

    def test_managed_token_requires_owned_identity_and_live_catalog_intersection(self):
        instance = {'id': 'native:fixture.service'}
        inspector = types.SimpleNamespace(discover_native=lambda: [instance], discover_docker=lambda: [],
            owned_installation=Mock(return_value=True), ROOT=Path('/fixture'),
            read_json=Mock(return_value={'apiToken': 'managed-synthetic'}))
        transport = Mock()
        transport.request.side_effect = [{}, {'paths': {'/panel/api/inbounds/list': {'get': {}}}}]
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'read_settings', return_value={}), \
                patch.object(panel, 'enter_network'), patch.object(panel, 'Panel', return_value=transport) as factory:
            result = panel.perform({'instanceId': instance['id'], 'operation': 'catalog'}, inspector, OPERATIONS, '8.8.8.8')
        self.assertEqual(factory.call_args.args[1], {'token': 'managed-synthetic'})
        self.assertEqual(result['result']['operations'], ['get_panel_api_inbounds_list'])
        self.assertEqual(result['result']['capabilitySource'], 'live')
        inspector.owned_installation.return_value = False
        inspector.read_json.reset_mock()
        transport.request.side_effect = [{}, {'paths': {}}]
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'read_settings', return_value={}), \
                patch.object(panel, 'enter_network'), patch.object(panel, 'Panel', return_value=transport) as factory:
            panel.perform({'instanceId': instance['id'], 'operation': 'catalog'}, inspector, OPERATIONS)
        inspector.read_json.assert_not_called()
        self.assertEqual(factory.call_args.args[1], {})

    def test_explicit_local_endpoint_does_not_require_database_client(self):
        instance = {'id': 'docker:fixture'}
        inspector = types.SimpleNamespace(discover_native=lambda: [], discover_docker=lambda: [instance])
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'read_settings') as read, \
                patch.object(panel, 'enter_network'), patch.object(panel, 'Panel') as factory:
            factory.return_value.request.return_value = []
            panel.perform({'instanceId': instance['id'], 'operation': 'get_panel_api_inbounds_list',
                'auth': {'token': 'synthetic'}, 'endpoint': {'port': 2053, 'path': '/fixture/', 'https': True}}, inspector, OPERATIONS)
        read.assert_not_called()
        self.assertEqual(factory.call_args.args[0]['webListen'], '127.0.0.1')
        self.assertEqual(factory.call_args.args[0]['webBasePath'], '/fixture/')

    def test_updater_never_targets_other_instances_or_container_installations(self):
        primary = {'id': 'native:x-ui.service', 'kind': 'native', 'name': 'x-ui.service', '_binary': '/usr/local/x-ui/x-ui'}
        custom = {**primary, 'id': 'native:custom.service', 'name': 'custom.service'}
        update = 'post_panel_api_server_updatePanel'
        xray = 'post_panel_api_server_installXray_version'
        self.assertNotIn(update, panel.unavailable_operations(primary, [primary], OPERATIONS))
        self.assertIn(update, panel.unavailable_operations(custom, [custom], OPERATIONS))
        blocked = panel.unavailable_operations(primary, [primary, custom], OPERATIONS)
        self.assertIn(update, blocked)
        self.assertIn(xray, blocked)
        docker = {'id': 'docker:fixture', 'kind': 'docker'}
        self.assertIn(update, panel.unavailable_operations(docker, [docker], OPERATIONS))

    def test_unavailable_docker_does_not_hide_known_native_instance(self):
        instance = {'id': 'native:fixture.service', 'kind': 'native', 'name': 'fixture.service'}
        inspector = types.SimpleNamespace(discover_native=lambda: [instance], discover_docker=Mock(side_effect=RuntimeError()))
        with patch.object(panel, 'run_service') as service:
            panel.perform({'instanceId': instance['id'], 'operation': 'service.restart', 'confirmed': True}, inspector, OPERATIONS)
        service.assert_called_once_with(instance, 'restart')

    def test_missing_instance_and_unconfirmed_write_never_send_requests(self):
        inspector = types.SimpleNamespace(discover_native=lambda: [], discover_docker=lambda: [])
        with self.assertRaises(panel.PanelError) as error:
            panel.perform({'instanceId': 'native:missing', 'operation': 'service.stop'}, inspector, OPERATIONS)
        self.assertEqual(error.exception.code, 'INSTANCE_MISSING')
        instance = {'id': 'native:fixture.service', 'kind': 'native', 'name': 'fixture.service'}
        inspector.discover_native = lambda: [instance]
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'Panel') as transport:
            with self.assertRaises(panel.PanelError) as error:
                panel.perform({'instanceId': instance['id'], 'operation': 'post_panel_api_inbounds_add'}, inspector, OPERATIONS)
            self.assertEqual(error.exception.code, 'PANEL_CONFIRM')
            transport.assert_not_called()

    def test_stale_edit_is_rejected_before_write_and_traffic_does_not_conflict(self):
        self.assertEqual(panel.revision({'id': 1, 'up': 1}), panel.revision({'id': 1, 'up': 999}))
        self.assertNotEqual(panel.revision({'port': 443}), panel.revision({'port': 8443}))
        instance = {'id': 'native:fixture.service'}
        inspector = types.SimpleNamespace(discover_native=lambda: [instance], discover_docker=lambda: [])
        request = {'instanceId': instance['id'], 'operation': 'post_panel_api_inbounds_update_id', 'confirmed': True, 'auth': {'token': 'synthetic'},
                   'parameters': {'id': 1}, 'data': {'port': 8443}, 'precondition': {
                       'operation': 'get_panel_api_inbounds_get_id', 'parameters': {'id': 1}, 'revision': panel.revision({'port': 443})}}
        transport = Mock()
        transport.request.return_value = {'port': 9443}
        with patch.object(panel, 'version_of', return_value=(3, 10, 0)), patch.object(panel, 'read_settings', return_value={}), \
                patch.object(panel, 'enter_network'), patch.object(panel, 'Panel', return_value=transport):
            with self.assertRaises(panel.PanelError) as error:
                panel.perform(request, inspector, OPERATIONS)
        self.assertEqual(error.exception.code, 'PANEL_CONFLICT')
        self.assertEqual(transport.request.call_count, 1)
        self.assertEqual(transport.request.call_args.args[1], 'GET')


if __name__ == '__main__':
    unittest.main()
