"""Synthetic 3m-ui integration boundaries; no personal server information."""
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

ROOT=Path(__file__).resolve().parents[1]
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,ROOT/path)
    value=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value
inspector=module('inspector','scripts/remote/inspect.py')
panel=module('panel','scripts/remote/panel.py')
OPS=json.loads((ROOT/'contracts/3m-operations.json').read_text())

def op(method,path):return next(o for o in OPS if o['method']==method and o['path']==path)['id']

class ThreeMTest(unittest.TestCase):
    def setUp(self):
        temp=tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root=Path(temp.name)
        self.config=self.root/'config.yaml'
        self.db=self.root/'3m-ui.db'
        self.config.write_text(json.dumps({'server':{'port':8080,'listen':'127.0.0.1','web_path':'/secret'},'database':{'path':str(self.db)}}))
        self.item={'id':'native:3m-ui-test.service','name':'3m-ui-test.service','kind':'native','running':True,
            '_binary':'/synthetic/3m-ui-bin','_env':{'THREE_M_UI_CONFIG':str(self.config)}}
        self.item=inspector.three_m_instance(self.item)

    def test_connection_facts_json_and_yaml_without_optional_parser(self):
        with patch.dict('sys.modules',{'yaml':None}):
            self.assertEqual(inspector.three_m_config(self.item)['server']['port'],8080)
            self.config.write_text('server:\n  port: 8081\n  web_path: /other\ndatabase:\n  path: '+str(self.db)+'\nsecurity:\n  credential_key: secret-never-return\n')
            value=inspector.three_m_config(self.item)
            self.assertEqual(value['server']['port'],'8081')
            self.assertNotIn('secret-never-return',json.dumps(value))

    def test_yaml_fallback_fails_closed_on_anchors_and_duplicate_fields(self):
        for value in ('server: &alias','server:\n  port: 80\n  port: 90','server:\n  port: *alias'):
            with self.subTest(value=value),patch.dict('sys.modules',{'yaml':None}):
                self.config.write_text(value+'\ndatabase:\n  path: /synthetic/database\n')
                with self.assertRaises(inspector.InspectError):inspector.three_m_config(self.item)

    def test_cli_config_wins_and_environment_port_overrides_yaml(self):
        self.item['_env']['THREE_M_UI_PORT']='9091'
        value=inspector.three_m_instance(self.item,'3m-ui --config '+str(self.config))
        self.assertEqual(inspector.three_m_config(value)['server']['port'],'9091')

    def test_unreadable_existing_config_is_discovered_and_not_owned(self):
        self.config.unlink()
        value=inspector.three_m_instance(self.item)
        self.assertTrue(value['_config_error'])
        self.assertFalse(inspector.owned_installation(value))
        result=inspector.inspect_instance(value,'8.8.8.8')
        self.assertFalse(result['readable'])
        self.assertEqual(result['panelType'],'3m-ui')

    def test_native_discovery_uses_custom_unit_and_config_without_default_database(self):
        output='Id=custom.service\nExecStart={ path=/synthetic/3m-ui-bin ; argv[]=/synthetic/3m-ui-bin --config '+str(self.config)+' ; }\nMainPID=0\nActiveState=active\nWorkingDirectory=/\n'
        with patch.object(inspector,'run',side_effect=['custom.service enabled',output]),patch.object(inspector.shutil,'which',return_value='/bin/systemctl'),patch.object(inspector,'PROC',self.root/'proc'),patch.object(inspector,'DEFAULT_DB',self.root/'absent'),patch.object(inspector,'DEFAULT_BINARY',self.root/'absent'):
            found=inspector.discover_native()
        self.assertEqual(found[0]['panelType'],'3m-ui')
        self.assertEqual(found[0]['_database'],str(self.db))

    def test_docker_config_volume_and_command_are_resolved(self):
        data={'Id':'fixture-container','Name':'/fixture','Config':{'Image':'custom-image','Entrypoint':['/usr/local/bin/3m-ui'],'Cmd':['--config','/config/custom.yaml']},
            'State':{'Running':False,'Pid':0},'Mounts':[{'Source':str(self.root),'Destination':'/config'}]}
        (self.root/'custom.yaml').write_text(self.config.read_text())
        with patch.object(inspector,'run',side_effect=['fixture-container',json.dumps([data])]),patch.object(inspector.shutil,'which',return_value='/bin/docker'):
            found=inspector.discover_docker()
        self.assertEqual(found[0]['panelType'],'3m-ui')
        self.assertFalse(found[0]['running'])

    def test_readonly_database_includes_wal_and_omits_credentials(self):
        with sqlite3.connect(self.db) as db:
            db.executescript('CREATE TABLE listeners (id INTEGER,name TEXT,protocol TEXT,port TEXT,enabled INTEGER); CREATE TABLE proxy_users (id INTEGER,username TEXT,password_encrypted TEXT,uuid TEXT,traffic_limit INTEGER,traffic_used INTEGER,enabled INTEGER); CREATE TABLE listener_users (listener_id INTEGER,proxy_user_id INTEGER); INSERT INTO listeners VALUES (1,"fixture","vless","8443",1); INSERT INTO proxy_users VALUES (2,"fixture-user","hidden-secret","hidden-uuid",100,120,1); INSERT INTO listener_users VALUES (1,2);')
        db=sqlite3.connect(self.db)
        self.addCleanup(db.close)
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('UPDATE listeners SET name="wal-visible"');db.commit()
        before=(self.db.read_bytes(),Path(str(self.db)+'-wal').read_bytes())
        result=inspector.inspect_instance(self.item,'8.8.8.8')
        self.assertTrue(result['readable'])
        self.assertEqual(result['inbounds'][0]['name'],'wal-visible')
        self.assertFalse(result['inbounds'][0]['clients'][0]['available'])
        self.assertNotIn('hidden-',json.dumps(result))
        self.assertEqual(before,(self.db.read_bytes(),Path(str(self.db)+'-wal').read_bytes()))

    def test_https_settings_replace_http_and_exclude_secrets(self):
        with sqlite3.connect(self.db) as db:
            db.execute('CREATE TABLE panel_settings (key TEXT, value TEXT)')
            db.execute('INSERT INTO panel_settings VALUES (?, ?)', ('panel_ssl', json.dumps({
                'enabled':True, 'listen_tls':'[::]:9443', 'domain':'panel.example.test',
                'key_file':'private-key-path', 'acme_token':'private-acme-token'})))
        before=self.db.read_bytes()
        result=panel.three_m_settings(self.item,inspector)
        self.assertEqual(result,{'webPort':9443,'webListen':'::','webBasePath':'/secret',
            'webCertFile':'https','webDomain':'panel.example.test'})
        self.assertEqual(before,self.db.read_bytes())

    def test_settings_without_ssl_table_keep_http(self):
        with sqlite3.connect(self.db) as db: db.execute('CREATE TABLE fixture (id INTEGER)')
        result=panel.three_m_settings(self.item,inspector)
        self.assertEqual(result,{'webPort':8080,'webListen':'127.0.0.1','webBasePath':'/secret'})


class ThreeMDeploy(unittest.TestCase):
    def test_prepare_is_idempotent_and_does_not_precreate_upstream_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            values={'request.json':{'host':'8.8.8.8','nodePort':8443}}
            common=types.SimpleNamespace(ROOT=root,read=lambda key,*_:values.get(key),
                write=lambda key,value:values.__setitem__(key,value))
            with patch.dict('sys.modules',{'manage':common}):
                deploy=module('managed_three_m','scripts/remote/manage_3m.py')
            deploy.CONFIG=root/'config.yaml'
            deploy.prepare()
            connection=dict(values['3m-connection.json'])
            deploy.prepare()
            self.assertEqual(connection,values['3m-connection.json'])
            self.assertFalse(deploy.CONFIG.exists())
            env=root/'3m-panel.env'
            self.assertEqual(env.stat().st_mode & 0o777,0o600)
            self.assertIn('THREE_M_UI_LISTEN=127.0.0.1',env.read_text())
            self.assertIn('THREE_M_UI_SUB_PORT=0',env.read_text())
            self.assertNotEqual(connection['panelPort'],8443)

    def test_prepare_refuses_existing_unowned_config(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            common=types.SimpleNamespace(ROOT=root,read=lambda *args:None)
            with patch.dict('sys.modules',{'manage':common}):
                deploy=module('managed_three_m','scripts/remote/manage_3m.py')
            deploy.CONFIG=root/'config.yaml'
            deploy.CONFIG.write_text('existing installation')
            with self.assertRaises(RuntimeError):deploy.prepare()
            self.assertEqual(deploy.CONFIG.read_text(),'existing installation')
            self.assertFalse((root/'3m-panel.env').exists())


class ThreeMAPI(unittest.TestCase):
    def setUp(self):
        self.requests=[]
        self.must_change=False
        owner=self
        class Handler(BaseHTTPRequestHandler):
            def log_message(self,*_): pass
            def do_GET(self): self.handle_request()
            def do_POST(self): self.handle_request()
            def do_PUT(self): self.handle_request()
            def do_DELETE(self): self.handle_request()
            def handle_request(self):
                body=self.rfile.read(int(self.headers.get('Content-Length',0)))
                owner.requests.append((self.path,dict(self.headers),body))
                if self.path.endswith('/auth/login'): value={'token':'synthetic-jwt','must_change_password':owner.must_change}
                elif self.path.endswith('/auth/me'):value={'role':'admin','must_change_password':owner.must_change}
                elif self.path.endswith('/config/validate'):value={'valid':False,'error':'hidden-config-secret'}
                elif self.path.endswith('/auth/password'):value={'token':'new-synthetic-jwt'}
                else:value=[]
                self.send_response(200);self.send_header('Content-Type','application/json');self.end_headers();self.wfile.write(json.dumps(value).encode())
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        self.addCleanup(server.server_close);self.addCleanup(server.shutdown)
        threading.Thread(target=server.serve_forever,daemon=True).start()
        self.endpoint={'port':server.server_port,'path':'/fixture'}
        self.item={'id':'native:fixture.service','kind':'native','name':'fixture.service','panelType':'3m-ui','_binary':'/synthetic/3m-ui','_env':{}}
        self.inspector=types.SimpleNamespace(discover_native=lambda:[self.item],discover_docker=lambda:[],
            run=lambda *_,**kw:'3m-ui v1.4.1',three_m_version_command=lambda _:['fixture'],owned_installation=lambda _:False)
    def call(self,operation='catalog',**kwargs):
        return panel.perform({'instanceId':self.item['id'],'operation':operation,'endpoint':self.endpoint,
            'auth':{'username':'fixture','password':'synthetic-password','twoFactorCode':'123456'},**kwargs},self.inspector,OPS)

    def test_jwt_login_raw_array_and_session_resume(self):
        result=self.call(op('GET','/listeners'))
        self.assertEqual(result['result'],[])
        self.assertEqual(json.loads(self.requests[0][2])['totp_code'],'123456')
        self.assertEqual(self.requests[-1][1]['Authorization'],'Bearer synthetic-jwt')
        count=len(self.requests)
        self.call(auth={'session':result['session']})
        self.assertEqual(len(self.requests),count+1)

    def test_initial_password_restricts_catalog_and_mutations(self):
        self.must_change=True
        result=self.call()['result']
        self.assertTrue(result['mustChangePassword'])
        self.assertEqual(set(result['operations']),{op('GET','/auth/me'),op('POST','/auth/password')})
        with self.assertRaises(panel.PanelError) as error:self.call(op('GET','/users'))
        self.assertEqual(error.exception.code,'PANEL_PASSWORD_REQUIRED')

    def test_password_change_refreshes_session(self):
        result=self.call(op('POST','/auth/password'),confirmed=True,data={'current_password':'synthetic','new_password':'new-synthetic'})
        self.assertEqual(result['session']['bearer'],'new-synthetic-jwt')

    def test_confirmation_required_before_login_and_write(self):
        with self.assertRaises(panel.PanelError) as error:self.call(op('POST','/listeners'))
        self.assertEqual(error.exception.code,'PANEL_CONFIRM')
        self.assertEqual(self.requests,[])

    def test_validation_200_failure_is_not_success_or_secret_leak(self):
        with self.assertRaises(panel.PanelError) as error:self.call(op('POST','/config/validate'),confirmed=True,data={'config':'bad'})
        self.assertEqual(error.exception.code,'PANEL_REJECTED')
        self.assertNotIn('hidden-config-secret',str(error.exception))

    def test_revision_precondition_prevents_mutation(self):
        with self.assertRaises(panel.PanelError) as error:
            self.call(op('POST','/listeners'),confirmed=True,precondition={'operation':op('GET','/listeners'),'revision':'stale'})
        self.assertEqual(error.exception.code,'PANEL_CONFLICT')
        self.assertFalse(any(p.endswith('/listeners') and b for p,_,b in self.requests))

    def test_xray_operations_cannot_reach_mihomo(self):
        with self.assertRaises(panel.PanelError) as error:self.call('get_panel_api_inbounds_list')
        self.assertEqual(error.exception.code,'PANEL_UNSUPPORTED')
        self.assertEqual(self.requests,[])

    def test_custom_unit_self_upgrade_is_disabled(self):
        result=self.call()['result']
        self.assertIn(op('POST','/system/update'),result['unavailable'])
        with self.assertRaises(panel.PanelError):self.call(op('POST','/system/update'),confirmed=True)

    def test_restore_uses_3m_multipart_field(self):
        with patch.object(panel,'run_service') as restart,patch('time.sleep'):
            self.call(op('POST','/system/backup/restore-db'),confirmed=True,data={'database':base64.b64encode(b'fixture database').decode()})
        self.assertIn(b'name="database"',self.requests[-1][2])
        restart.assert_called_once_with(self.item,'restart')

    def test_unverified_old_version_is_readonly(self):
        self.inspector.run=lambda *_,**kw:'3m-ui v1.0.0'
        with self.assertRaises(panel.PanelError) as error:self.call()
        self.assertEqual(error.exception.code,'PANEL_VERSION')
        self.assertEqual(self.requests,[])

if __name__=='__main__':unittest.main()
