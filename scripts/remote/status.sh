set -eu
existing_xui() {
  [ -e /usr/local/x-ui/x-ui ] || [ -e /etc/x-ui/x-ui.db ] || systemctl cat x-ui.service >/dev/null 2>&1 || {
    command -v docker >/dev/null 2>&1 && docker ps -a --format '{{.Image}} {{.Names}}' 2>/dev/null | grep -Eiq '(^|[/[:space:]])(3x-ui|x-ui|mhsanaei)([:/[:space:]]|$)'
  }
}

if [ ! -f '/var/lib/5a-ui/.managed' ]; then
  if existing_xui; then
    printf '%s\n' '5A_UI_RESULT={"phase":"existing","message":"检测到已有 3x-ui 安装。当前版本仅管理本项目创建的节点，请使用现有面板管理。"}'
exit 0

  fi
  printf '%s\n' '5A_UI_RESULT={"phase":"not-installed","message":"这台服务器还没有部署节点，点击一键自建开始。"}'
exit 0

fi
if command -v python3 >/dev/null 2>&1 && [ -f '/var/lib/5a-ui/manage.py' ]; then
  python3 '/var/lib/5a-ui/manage.py' status
elif [ -f '/var/lib/5a-ui/state.json' ]; then
  printf '5A_UI_RESULT='; cat '/var/lib/5a-ui/state.json'; printf '\n'
else
  printf '%s\n' '5A_UI_RESULT={"phase":"not-installed","message":"这台服务器还没有部署节点，点击一键自建开始。"}'
exit 0

fi
