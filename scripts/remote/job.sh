#!/bin/bash
set -Eeuo pipefail
umask 077
cd /var/lib/huarunying
exec >install.log 2>&1

progress() {
  printf '{"phase":"%s","message":"%s","updatedAt":"%s"}\n' "$1" "$2" "$(date -u +%FT%TZ)" >state.json.tmp
  mv state.json.tmp state.json
}

stage=preparing
failed() {
  case "$stage" in
    preparing) message='安装准备失败，请检查软件源和服务器网络。' ;;
    installing) message='3x-ui 安装失败，请检查服务器能否访问 GitHub。' ;;
    configuring) message='节点配置失败，可重新点击自建继续；详细原因在服务器安装日志中。' ;;
    *) message='节点检查失败，可重新读取状态或重试安装。' ;;
  esac
  progress failed "$message"
}
trap failed ERR
trap 'failed; exit 1' TERM INT

progress preparing '正在准备安装环境…'
export DEBIAN_FRONTEND=noninteractive
apt-get -o DPkg::Lock::Timeout=120 update
apt-get -o DPkg::Lock::Timeout=120 install -y curl ca-certificates python3

if [ ! -f panel.env ]; then
  python3 manage.py prepare
fi
. ./panel.env
export XUI_NONINTERACTIVE=1 XUI_DB_TYPE=sqlite XUI_SSL_MODE=none
export XUI_USERNAME XUI_PASSWORD XUI_PANEL_PORT XUI_WEB_BASE_PATH XUI_SERVER_IP

# Bind before the panel's very first start, including restarts performed by upstream install.sh.
install -d -m 755 /etc/systemd/system/x-ui.service.d
cat >/etc/systemd/system/x-ui.service.d/20-huarunying.conf <<'UNIT'
[Service]
ExecStartPre=/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1
ExecStartPre=/usr/bin/python3 /var/lib/huarunying/manage.py restrict-services
UNIT
systemctl daemon-reload

stage=installing
progress installing '正在安装 3x-ui 和 Xray…'
case "$(uname -m)" in
  x86_64) xray_binary=/usr/local/x-ui/bin/xray-linux-amd64 ;;
  aarch64) xray_binary=/usr/local/x-ui/bin/xray-linux-arm64 ;;
esac
if [ ! -x /usr/local/x-ui/x-ui ] || [ ! -x "$xray_binary" ] || ! systemctl cat x-ui.service >/dev/null 2>&1; then
  curl --fail --location --proto '=https' --tlsv1.2 --connect-timeout 15 --max-time 120 --retry 3 \
    'https://raw.githubusercontent.com/MHSanaei/3x-ui/v3.10.0/install.sh' -o upstream-install.sh
  printf '%s  %s\n' '9684bae4f769b2127fcceceb4f200045657381311867529e6ba76c6b58e2825d' upstream-install.sh | sha256sum --check --status
  bash upstream-install.sh v3.10.0
fi
/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1
systemctl restart x-ui

stage=configuring
progress configuring '正在创建 VLESS + REALITY 节点…'
python3 manage.py configure

stage=checking
progress checking '正在检查服务和节点端口…'
node_port=$(python3 -c 'import json; print(json.load(open("connection.json"))["nodePort"])')
if command -v ufw >/dev/null 2>&1 && ufw status | head -n 1 | grep -q 'Status: active'; then
  ufw allow "$node_port/tcp" comment 'huarunying VLESS'
fi
python3 manage.py check
progress ready '节点已创建，可以导入客户端使用。'
