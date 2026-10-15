import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';

const maxPrivateKeyBytes = 64 * 1024;
typedef PrivateKeyReader = Future<String> Function(String path);

String decodePrivateKey(List<int> bytes) {
  if (bytes.isEmpty || bytes.length > maxPrivateKeyBytes) {
    throw const AppException('KEY_FILE_SIZE', '私钥文件不能为空，最大支持 64 KB。');
  }
  try {
    final key = utf8.decode(bytes).replaceAll('\r\n', '\n').trim();
    if (!RegExp(
      r'^-----BEGIN (?:OPENSSH |RSA |EC |ENCRYPTED )?PRIVATE KEY-----',
    ).hasMatch(key)) {
      throw const FormatException();
    }
    return '$key\n';
  } on FormatException {
    throw const AppException('KEY_FILE_FORMAT', '请选择 SSH 私钥文件，不是公钥或其他文件。');
  }
}

String expandPrivateKeyPath(String value, String? homeDirectory) {
  var path = value.trim();
  if (path.length >= 2 &&
      ((path.startsWith('"') && path.endsWith('"')) ||
          (path.startsWith("'") && path.endsWith("'")))) {
    path = path.substring(1, path.length - 1);
  }
  if (path.isEmpty || path.contains(RegExp(r'[\x00-\x1f]'))) {
    throw const AppException('KEY_PATH', '请输入有效的 SSH 私钥路径。');
  }
  if (path == '~' || path.startsWith('~/') || path.startsWith('~\\')) {
    if (homeDirectory == null || homeDirectory.isEmpty) {
      throw const AppException('KEY_PATH_HOME', '无法确定用户目录，请填写私钥的绝对路径或选择文件。');
    }
    return '$homeDirectory${path.substring(1)}';
  }
  if (path.startsWith('~')) {
    throw const AppException('KEY_PATH_HOME', '请使用 ~/ 或填写私钥的绝对路径。');
  }
  return path;
}
