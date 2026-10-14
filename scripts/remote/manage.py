#!/usr/bin/env python3
"""Runs only on the user's VPS. All persistent files belong to root and have mode 0600."""
import datetime
import ipaddress
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import socket
import sqlite3
import ssl
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parent
XUI = "/usr/local/x-ui/x-ui"
DATABASE = Path('/etc/x-ui/x-ui.db')
CANDIDATES = ["www.microsoft.com", "www.cloudflare.com", "www.nvidia.com", "www.amazon.com"]
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def read(name, default=None):
    path = ROOT / name
    return json.loads(path.read_text()) if path.exists() else default


def write(name, data):
    temp = ROOT / (name + ".tmp")
    with temp.open("w") as output:
        os.chmod(temp, 0o600)
        json.dump(data, output, ensure_ascii=False)
    temp.replace(ROOT / name)


def env():
    values = {}
    for line in (ROOT / "panel.env").read_text().splitlines():
        key, value = line.split("=", 1)
        values[key] = shlex.split(value)[0]
    return values


def prepare():
    request = read("request.json")
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        panel_port = sock.getsockname()[1]
    if panel_port == request["nodePort"]:
        return prepare()
    values = {
        "XUI_USERNAME": "5a_ui_" + secrets.token_hex(6),
        "XUI_PASSWORD": secrets.token_urlsafe(24),
        "XUI_WEB_BASE_PATH": secrets.token_hex(12),
        "XUI_PANEL_PORT": str(panel_port),
        "XUI_SERVER_IP": request["host"],
    }
    path = ROOT / "panel.env"
    with path.open("w") as output:
        os.chmod(path, 0o600)
        for key, value in values.items():
            output.write(key + "=" + shlex.quote(value) + "\n")


def restrict_services():
    # Runs after the upstream CLI initializes SQLite, before any server starts.
    # This app returns a VLESS URI directly and needs no public subscription server.
    with sqlite3.connect("file:" + str(DATABASE) + "?mode=rw", uri=True, timeout=20) as database:
        for key, value in (("subEnable", "false"), ("subListen", "127.0.0.1")):
            updated = database.execute("UPDATE settings SET value = ? WHERE key = ?", (value, key))
            if updated.rowcount == 0:
                database.execute("INSERT INTO settings (key, value) VALUES (?, ?)", (key, value))


def api(path, method="GET", data=None):
    config = read("connection.json") or {}
    values = env()
    base = "http://127.0.0.1:" + values["XUI_PANEL_PORT"] + "/" + values["XUI_WEB_BASE_PATH"].strip("/")
    headers = {"Authorization": "Bearer " + config.get("apiToken", ""), "Content-Type": "application/json"}
    payload = json.dumps(data).encode() if data is not None else (b"" if method == "POST" else None)
    request = urllib.request.Request(base + "/panel/api" + path, data=payload, headers=headers, method=method)
    with OPENER.open(request, timeout=8) as response:
        result = json.load(response)
    if not result.get("success", False):
        raise RuntimeError("Panel API rejected " + path)
    return result.get("obj")


def target(hostname):
    addresses = socket.getaddrinfo(hostname, 443, type=socket.SOCK_STREAM)
    if not addresses or any(not ipaddress.ip_address(addr[4][0]).is_global for addr in addresses):
        raise RuntimeError("REALITY target must resolve to public addresses")
    context = ssl.create_default_context()
    context.minimum_version = ssl.TLSVersion.TLSv1_3
    context.set_alpn_protocols(["h2", "http/1.1"])
    # Connect to the already checked IP to avoid a second DNS resolution.
    last_error = None
    for family, socktype, proto, _, address in addresses[:4]:
        try:
            with socket.socket(family, socktype, proto) as sock:
                sock.settimeout(4)
                sock.connect(address)
                with context.wrap_socket(sock, server_hostname=hostname) as secure:
                    if secure.version() == "TLSv1.3":
                        return hostname
        except (OSError, ssl.SSLError) as error:
            last_error = error
    raise RuntimeError("REALITY TLS 1.3 target unavailable") from last_error


def choose_target(request):
    candidates = [request["realityServerName"]] if request.get("realityServerName") else CANDIDATES
    for candidate in candidates:
        try:
            return target(candidate)
        except (OSError, ssl.SSLError, RuntimeError):
            pass
    raise RuntimeError("No reachable TLS 1.3 REALITY target")


def ensure_token(config):
    output = subprocess.check_output([XUI, "setting", "-getApiToken", "-tokenName", "5a-ui", "-tokenScope", "admin"], text=True)
    match = re.search(r"^apiToken:\s*(\S+)", output, re.MULTILINE)
    if not match:
        raise RuntimeError("Panel did not issue an API token")
    config["apiToken"] = match[1]
    write("connection.json", config)


def configure():
    request = read("request.json")
    config = read("connection.json") or {"host": request["host"], "nodePort": request["nodePort"]}
    if not config.get("apiToken"):
        ensure_token(config)
    for _ in range(20):
        try:
            existing = api("/inbounds/list") or []
            break
        except urllib.error.HTTPError as error:
            if error.code == 401:
                ensure_token(config)
            time.sleep(1)
        except (OSError, RuntimeError):
            time.sleep(1)
    else:
        raise RuntimeError("Panel API unavailable")
    managed = next((item for item in existing if item.get("tag") == "5a-ui-vless" or item.get("remark") == "5a-ui · VLESS"), None)
    if managed:
        settings = json.loads(managed["settings"])
        stream = json.loads(managed["streamSettings"])
        clients = settings.get("clients", [])
        client = next((item for item in clients if item.get("email") == "5a-ui"), None)
        reality = stream.get("realitySettings", {})
        public_key = reality.get("settings", {}).get("publicKey") or config.get("publicKey")
        if not client or not public_key or not reality.get("shortIds"):
            raise RuntimeError("Managed inbound was changed; refusing to overwrite")
        config.update({"inboundId": managed["id"], "nodePort": managed["port"], "uuid": client["id"], "publicKey": public_key, "shortId": reality["shortIds"][0], "serverName": reality["serverNames"][0]})
        write("connection.json", config)
    else:
        if any(item.get("port") == config["nodePort"] for item in existing):
            raise RuntimeError("Node port already belongs to another inbound")
        if not config.get("privateKey"):
            pair = api("/server/getNewX25519Cert")
            config.update({"privateKey": pair["privateKey"], "publicKey": pair["publicKey"], "uuid": str(uuid.uuid4()), "shortId": secrets.token_hex(8), "serverName": choose_target(request)})
            write("connection.json", config)
        stream = {"network": "tcp", "security": "reality", "realitySettings": {"show": False, "target": config["serverName"] + ":443", "xver": 0, "serverNames": [config["serverName"]], "privateKey": config["privateKey"], "shortIds": [config["shortId"]], "settings": {"publicKey": config["publicKey"], "fingerprint": "chrome", "spiderX": "/"}}}
        settings = {"clients": [{"id": config["uuid"], "flow": "xtls-rprx-vision", "email": "5a-ui", "enable": True, "subId": secrets.token_hex(8), "totalGB": 0, "expiryTime": 0}], "decryption": "none", "fallbacks": []}
        inbound = api("/inbounds/add", "POST", {"enable": True, "remark": "5a-ui · VLESS", "tag": "5a-ui-vless", "listen": "", "port": config["nodePort"], "protocol": "vless", "expiryTime": 0, "total": 0, "settings": json.dumps(settings), "streamSettings": json.dumps(stream), "sniffing": json.dumps({"enabled": False})})
        config["inboundId"] = inbound["id"]
        write("connection.json", config)
    api("/server/restartXrayService", "POST")


def check():
    config = read("connection.json")
    for _ in range(20):
        try:
            server = api("/server/status")
            if server.get("xray", {}).get("state") == "running":
                with socket.create_connection(("127.0.0.1", config["nodePort"]), timeout=3):
                    return
        except (OSError, RuntimeError):
            pass
        time.sleep(1)
    raise RuntimeError("Xray did not start listening")


def status():
    state = read("state.json", {"phase": "not-installed", "message": "这台服务器尚未通过本项目部署。"})
    config = read("connection.json")
    if state["phase"] in ("queued", "preparing", "installing", "configuring", "checking"):
        active = subprocess.run(["systemctl", "is-active", "--quiet", "5a-ui-install.service"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        if not active:
            state.update({"phase": "failed", "message": "安装任务已中断，可重新点击自建继续。"})
    if state["phase"] != "ready" or not config:
        return state
    state["installed"] = True
    host = config["host"]
    uri_host = "[" + host + "]" if ":" in host else host
    query = urllib.parse.urlencode({"encryption": "none", "security": "reality", "type": "tcp", "sni": config["serverName"], "fp": "chrome", "pbk": config["publicKey"], "sid": config["shortId"], "flow": "xtls-rprx-vision", "spx": "/"})
    link = "vless://" + config["uuid"] + "@" + uri_host + ":" + str(config["nodePort"]) + "?" + query + "#" + urllib.parse.quote("5a-ui")
    state["node"] = {"host": host, "port": config["nodePort"], "serverName": config["serverName"], "link": link}
    state["firewall"] = "如节点端口不可达，请在云平台安全组放行 TCP " + str(config["nodePort"]) + "。"
    try:
        server = api("/server/status")
        state.update({"running": server.get("xray", {}).get("state") == "running", "panelVersion": server.get("panelVersion", ""), "xrayVersion": server.get("xray", {}).get("version", ""), "cpu": server.get("cpu", 0), "memory": server.get("mem", {}), "uptime": server.get("uptime", 0)})
        inbound = api("/inbounds/get/" + str(config["inboundId"]))
        state["traffic"] = {"up": inbound.get("up", 0), "down": inbound.get("down", 0)}
        if not state["running"]:
            state["message"] = "节点已部署，但 Xray 当前未运行。"
    except (OSError, RuntimeError, ValueError):
        state.update({"running": False, "message": "节点已部署，但管理服务暂时不可用。"})
    return state


if __name__ == "__main__":
    os.umask(0o077)
    command = sys.argv[1]
    if command == "status":
        print("5A_UI_RESULT=" + json.dumps(status(), ensure_ascii=False))
    elif command == "prepare":
        prepare()
    elif command == "restrict-services":
        restrict_services()
    elif command == "configure":
        configure()
    elif command == "check":
        check()
    else:
        raise SystemExit("Unknown command")
