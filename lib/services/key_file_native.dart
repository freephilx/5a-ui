import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/services.dart';

import 'key_file_common.dart';

Future<String> _resolvePath(String path) async {
  var userDirectory =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (Platform.isMacOS && RegExp(r'''^["']?~''').hasMatch(path.trim())) {
    try {
      userDirectory =
          await const MethodChannel('app.fivea/window')
              .invokeMethod<String>('userHomeDirectory') ??
          userDirectory;
    } on MissingPluginException {
      // Pure Dart/widget tests do not create the native window channel.
    }
  }
  return expandPrivateKeyPath(path, userDirectory);
}

Future<String?> privateKeyInitialDirectory(String path) async {
  if (path.trim().isEmpty) return null;
  try {
    return File(await _resolvePath(path)).absolute.parent.path;
  } on PlatformException {
    return null;
  }
}

Future<String> readPrivateKeyFile(String path) async {
  try {
    final file = File(await _resolvePath(path));
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      throw const AppException(
        'KEY_FILE_MISSING',
        '找不到或无法访问此路径的私钥，请检查路径，或选择私钥文件授权读取。',
      );
    }
    if (stat.size > maxPrivateKeyBytes) {
      throw const AppException('KEY_FILE_SIZE', '私钥文件最大支持 64 KB。');
    }
    final bytes = await file
        .openRead(0, maxPrivateKeyBytes + 1)
        .fold<List<int>>([], (all, chunk) => all..addAll(chunk));
    return decodePrivateKey(bytes);
  } on AppException {
    rethrow;
  } on FileSystemException {
    throw const AppException(
      'KEY_FILE_READ',
      '无法读取此路径的私钥，请检查权限，或点击“选择私钥文件”授权读取。',
    );
  } on PlatformException {
    throw const AppException('KEY_FILE_READ', '无法解析用户目录，请填写绝对路径或选择私钥文件。');
  }
}
