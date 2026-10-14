import importlib.util
import json
import sqlite3
from pathlib import Path
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("remote", Path(__file__).parents[1] / "scripts/remote/manage.py")
remote = importlib.util.module_from_spec(spec)
spec.loader.exec_module(remote)


class ProvisioningTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.inbounds = []
        self.created = 0
        self.restarts = 0
        test = self

        class Panel(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def respond(self, obj):
                test.assertEqual(self.headers.get("Authorization"), "Bearer panel-token")
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(json.dumps({"success": True, "obj": obj}).encode())

            def do_GET(self):
                if self.path.endswith("/inbounds/list"):
                    self.respond(test.inbounds)
                elif self.path.endswith("/server/getNewX25519Cert"):
                    self.respond({"privateKey": "private-reality-key", "publicKey": "public-reality-key"})
                elif self.path.endswith("/server/status"):
                    self.respond({"xray": {"state": "running", "version": "26.10"}, "cpu": 5.0, "mem": {"current": 1024, "total": 8192}, "panelVersion": "3.10.0", "uptime": 123})
                elif "/inbounds/get/" in self.path:
                    self.respond({**test.inbounds[0], "up": 42, "down": 64})
                else:
                    self.send_error(404)

            def do_POST(self):
                body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
                if self.path.endswith("/inbounds/add"):
                    inbound = {**json.loads(body), "id": 1}
                    test.inbounds.append(inbound)
                    test.created += 1
                    self.respond(inbound)
                elif self.path.endswith("/server/restartXrayService"):
                    test.restarts += 1
                    self.respond(None)
                else:
                    self.send_error(404)

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Panel)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.root_patch = patch.object(remote, "ROOT", self.root)
        self.root_patch.start()
        (self.root / "panel.env").write_text(f"XUI_PANEL_PORT={self.server.server_port}\nXUI_WEB_BASE_PATH=test-path\nXUI_USERNAME=panel-user\nXUI_PASSWORD=panel-password\n")
        remote.write("request.json", {"host": "8.8.8.8", "nodePort": 443, "realityServerName": ""})
        remote.write("connection.json", {"host": "8.8.8.8", "nodePort": 443, "apiToken": "panel-token"})

    def tearDown(self):
        self.root_patch.stop()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()
        self.directory.cleanup()

    def configure(self):
        with patch.object(remote, "choose_target", return_value="www.microsoft.com"):
            remote.configure()

    def test_retry_reuses_one_inbound_and_the_same_identity(self):
        self.configure()
        first = remote.read("connection.json")
        self.configure()
        second = remote.read("connection.json")
        self.assertEqual(self.created, 1)
        for key in ("uuid", "publicKey", "shortId", "inboundId"):
            self.assertEqual(first[key], second[key])
        self.assertEqual(json.loads(self.inbounds[0]["settings"])["clients"][0]["flow"], "xtls-rprx-vision")
        self.assertEqual(json.loads(self.inbounds[0]["streamSettings"])["realitySettings"]["target"], "www.microsoft.com:443")
        self.assertEqual((self.root / "connection.json").stat().st_mode & 0o777, 0o600)

    def test_status_returns_client_link_and_traffic_without_panel_secrets(self):
        self.configure()
        remote.write("state.json", {"phase": "ready", "message": "ready"})
        status = remote.status()
        self.assertTrue(status["running"])
        self.assertEqual(status["traffic"], {"up": 42, "down": 64})
        self.assertIn("pbk=public-reality-key", status["node"]["link"])
        serialized = json.dumps(status)
        for secret in ("panel-token", "panel-password", "private-reality-key"):
            self.assertNotIn(secret, serialized)

    def test_unrelated_inbound_is_preserved(self):
        self.inbounds.append({"id": 99, "port": 443, "remark": "user node"})
        with self.assertRaisesRegex(RuntimeError, "another inbound"):
            self.configure()
        self.assertEqual(self.created, 0)
        self.assertEqual(self.inbounds[0]["id"], 99)

    def test_manually_changed_managed_node_is_not_overwritten(self):
        self.inbounds.append({"id": 99, "port": 443, "tag": "huarunying-vless", "settings": '{"clients":[]}', "streamSettings": '{"realitySettings":{}}'})
        with self.assertRaisesRegex(RuntimeError, "refusing to overwrite"):
            self.configure()
        self.assertEqual(self.created, 0)

    def test_interrupted_job_is_reported_as_retryable(self):
        remote.write("state.json", {"phase": "installing", "message": "installing"})
        with patch.object(remote.subprocess, "run") as run:
            run.return_value.returncode = 3
            self.assertEqual(remote.status()["phase"], "failed")

    def test_subscription_server_is_disabled_without_changing_other_settings(self):
        path = self.root / 'x-ui.db'
        with sqlite3.connect(path) as database:
            database.execute('CREATE TABLE settings (id INTEGER PRIMARY KEY, key TEXT UNIQUE, value TEXT)')
            database.executemany('INSERT INTO settings (key, value) VALUES (?, ?)', [('webPort', '52711'), ('subEnable', 'true')])
        with patch.object(remote, 'DATABASE', path):
            remote.restrict_services()
            remote.restrict_services()
        with sqlite3.connect(path) as database:
            settings = dict(database.execute('SELECT key, value FROM settings'))
        self.assertEqual(settings, {'webPort': '52711', 'subEnable': 'false', 'subListen': '127.0.0.1'})


if __name__ == "__main__":
    unittest.main()
