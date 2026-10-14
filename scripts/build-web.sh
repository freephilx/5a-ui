#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=$(node -p "JSON.parse(require('fs').readFileSync('.fvmrc', 'utf8')).flutter")
if command -v fvm >/dev/null 2>&1; then
  flutter_cmd=(fvm flutter)
  dart_cmd=(fvm dart)
elif command -v flutter >/dev/null 2>&1; then
  flutter_cmd=(flutter)
  dart_cmd=(dart)
else
  # Vercel/Workers build machines do not ship Flutter. Cache a pinned SDK there.
  sdk_dir="${FLUTTER_SDK_CACHE:-$PWD/.tmp/flutter-sdks}/$version"
  if [ ! -x "$sdk_dir/bin/flutter" ]; then
    git clone --depth 1 --branch "$version" https://github.com/flutter/flutter.git "$sdk_dir"
  fi
  flutter_cmd=("$sdk_dir/bin/flutter")
  dart_cmd=("$sdk_dir/bin/dart")
fi
actual=$("${flutter_cmd[@]}" --version --machine | node -e "let s='';process.stdin.on('data',c=>s+=c);process.stdin.on('end',()=>console.log(JSON.parse(s.slice(s.indexOf('{'))).frameworkVersion))")
if [ "$actual" != "$version" ]; then
  printf 'Expected Flutter %s from .fvmrc; found %s. Update the SDK first.\n' "$version" "$actual" >&2
  exit 1
fi
"${dart_cmd[@]}" run tool/generate.dart
"${flutter_cmd[@]}" pub get
"${flutter_cmd[@]}" build web --release --no-web-resources-cdn
