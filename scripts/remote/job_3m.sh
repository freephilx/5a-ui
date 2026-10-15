#!/bin/bash
# Sourced by job.sh: same background unit, lock, progress and error handling.
python3 manage_3m.py prepare
set -a
. ./3m-panel.env
set +a
install -d -m 755 /etc/systemd/system/3m-ui.service.d
cat >/etc/systemd/system/3m-ui.service.d/20-5a-ui.conf <<'UNIT'
[Service]
EnvironmentFile=/var/lib/5a-ui/3m-panel.env
Environment=THREE_M_UI_LISTEN=127.0.0.1
UNIT
systemctl daemon-reload
stage=installing
progress installing '正在安装 3m-ui 和 Mihomo…'
if [ ! -x /usr/local/lib/3m-ui/3m-ui-bin ] || [ ! -x /usr/local/lib/3m-ui/mihomo ] || ! systemctl cat 3m-ui.service >/dev/null 2>&1; then
  curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 --retry 3 \
    'https://raw.githubusercontent.com/kazeyukiro/3m-ui/v1.4.1/scripts/install.sh' -o upstream-3m-install.sh
  printf '%s  %s\n' '9256bff772d3e4958b8bbc8f40d3b841ea383fb37676a269f5abc5ca9dfd1d61' upstream-3m-install.sh | sha256sum --check --status
  bash upstream-3m-install.sh v1.4.1 --yes
fi
systemctl restart 3m-ui.service
stage=configuring
progress configuring '正在创建 Mihomo VLESS + REALITY 节点…'
python3 manage_3m.py configure
stage=checking
progress checking '正在检查 Mihomo 节点与分享配置…'
node_port=$(python3 -c 'import json; print(json.load(open("3m-connection.json"))["nodePort"])')
if command -v ufw >/dev/null 2>&1 && ufw status | head -n 1 | grep -q 'Status: active'; then
  ufw allow "$node_port/tcp" comment '5a-ui VLESS'
fi
python3 manage_3m.py check
progress ready '3m-ui 节点已创建，可以导入客户端使用。'
