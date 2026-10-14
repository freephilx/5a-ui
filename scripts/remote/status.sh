set -eu
if ! command -v python3 >/dev/null 2>&1; then
  printf '%s\n' '5A_UI_RESULT={"error":{"code":"PYTHON_REQUIRED","message":"读取 3x-ui 需要服务器安装 Python 3，请先安装 python3 后重试。"}}'
  exit 0
fi
python3 -c "$(printf '%s' '@@INSPECTOR@@' | base64 -d)" '@@HOST@@'
