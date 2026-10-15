import 'package:ipaddr/ipaddr.dart';

import 'models.dart';
import 'management.dart';
import 'remote_generated.dart' show networkRanges;

const maxBodyBytes = 80 * 1024;

String publicIP(Object? value) {
  if (value is! String ||
      value.trim().isEmpty ||
      value.length > 64 ||
      value.contains('%')) {
    throw const AppException('INVALID_HOST', '请输入服务器的公网 IPv4 或 IPv6 地址。');
  }
  final host = value.trim();
  try {
    if (host.contains(':')) {
      var normalized = host;
      if (host.contains('.')) {
        final split = host.lastIndexOf(':');
        final tail = host.substring(split + 1);
        if (!RegExp(r'^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$')
            .hasMatch(tail)) {
          throw const FormatException();
        }
        final ipv4 = IPv4Address(tail).toBigInt();
        normalized =
            '${host.substring(0, split + 1)}${(ipv4 >> 16).toRadixString(16)}:${(ipv4 & BigInt.from(65535)).toRadixString(16)}';
      }
      final address = IPv6Address(normalized);
      final number = address.toBigInt();
      if (number >> 32 == BigInt.from(0xffff)) {
        return publicIP(
          IPv4Address.fromInt((number & BigInt.from(0xffffffff)).toInt())
              .toString(),
        );
      }
      for (final cidr in networkRanges['ipv6']!) {
        final parts = cidr.split('/');
        final shift = 128 - int.parse(parts[1]);
        if (number >> shift == IPv6Address(parts[0]).toBigInt() >> shift) {
          throw const AppException('PRIVATE_HOST', '请使用公网 IP，无法连接内网、保留或本机地址。');
        }
      }
      return address.toString();
    }
    if (!RegExp(r'^(0|[1-9]\d{0,2})(\.(0|[1-9]\d{0,2})){3}$').hasMatch(host)) {
      throw const FormatException();
    }
    final address = IPv4Address(host);
    for (final cidr in networkRanges['ipv4']!) {
      final parts = cidr.split('/');
      final shift = 32 - int.parse(parts[1]);
      if (address.toBigInt() >> shift ==
          IPv4Address(parts[0]).toBigInt() >> shift) {
        throw const AppException('PRIVATE_HOST', '请使用公网 IP，无法连接内网、保留或本机地址。');
      }
    }
    return address.toString();
  } on AppException {
    rethrow;
  } catch (_) {
    throw const AppException('INVALID_HOST', '请输入有效的公网 IP 地址，不支持域名。');
  }
}

String _text(Object? value, int limit, String label) {
  if (value is! String || value.length > limit || value.contains('\x00')) {
    throw AppException('INVALID_INPUT', '$label格式不正确。');
  }
  return value;
}

int _port(Object? value, int fallback) {
  if (value == null) return fallback;
  if (value is! int || value < 1 || value > 65535) {
    throw const AppException('INVALID_PORT', '端口需要是 1–65535 之间的整数。');
  }
  return value;
}

ConnectionInput validateInput(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const AppException('INVALID_INPUT', '连接信息格式不正确。');
  }
  final host = publicIP(value['host']);
  final username = _text(value['username'] ?? 'root', 32, '用户名').trim();
  if (username.isNotEmpty &&
      !RegExp(
        r'^[a-z_][a-z0-9_-]{0,31}$',
        caseSensitive: false,
      ).hasMatch(username)) {
    throw const AppException(
      'INVALID_USERNAME',
      '请输入有效的服务器用户名，例如 root、ubuntu 或 debian。',
    );
  }
  final auth = value['authMethod'];
  if (auth != 'password' && auth != 'key') {
    throw const AppException('INVALID_AUTH', '请选择密码登录或私钥登录。');
  }
  final panelType = value['panelType'] ?? '3x-ui';
  if (!{'3x-ui', '3m-ui'}.contains(panelType)) {
    throw const AppException('INVALID_PANEL_TYPE', '请选择 3x-ui 或 3m-ui。');
  }
  final port = _port(value['port'], 22);
  final nodePort = _port(value['nodePort'], 443);
  if (port == nodePort) {
    throw const AppException('PORT_CONFLICT', '节点端口需要与 SSH 端口不同。');
  }
  String? password, privateKey, passphrase, fingerprint, target;
  if (auth == 'password') {
    password = _text(value['password'], 4096, '密码');
    if (password.isEmpty) {
      throw const AppException('MISSING_PASSWORD', '请输入服务器密码。');
    }
  } else {
    privateKey =
        '${_text(value['privateKey'], 64 * 1024, '私钥').replaceAll('\r\n', '\n').trim()}\n';
    if (!RegExp(r'-----BEGIN (?:OPENSSH |RSA |EC |ENCRYPTED )?PRIVATE KEY-----')
        .hasMatch(privateKey)) {
      throw const AppException('INVALID_KEY', '请选择或粘贴 SSH 私钥。对应公钥需要已经配置在服务器上。');
    }
    if (value['passphrase'] != null) {
      passphrase = _text(value['passphrase'], 4096, '密钥口令');
    }
  }
  if (value['hostFingerprint'] != null && value['hostFingerprint'] != '') {
    fingerprint = _text(value['hostFingerprint'], 64, 'SSH 指纹').trim();
    if (!RegExp(r'^SHA256:[A-Za-z0-9+/]{43}$').hasMatch(fingerprint)) {
      throw const AppException(
        'INVALID_FINGERPRINT',
        'SSH 指纹格式应为 SHA256: 后跟 43 位字符。',
      );
    }
  }
  if (value['realityServerName'] != null && value['realityServerName'] != '') {
    target = _text(
      value['realityServerName'],
      253,
      'REALITY 目标',
    ).trim().toLowerCase();
    if (!RegExp(
      r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$',
    ).hasMatch(target)) {
      throw const AppException(
        'INVALID_REALITY_TARGET',
        'REALITY 目标需要是网站域名，例如 www.microsoft.com；不包含协议或端口。',
      );
    }
  }
  return ConnectionInput(
    management: value['management'] == null
        ? null
        : validateManagement(value['management']),
    host: host,
    username: username,
    port: port,
    authMethod: auth as String,
    password: password,
    privateKey: privateKey,
    passphrase: passphrase,
    hostFingerprint: fingerprint,
    nodePort: nodePort,
    panelType: panelType as String,
    realityServerName: target,
    turnstileToken: value['turnstileToken'] == null
        ? null
        : _text(value['turnstileToken'], 4096, '验证信息'),
    proofToken: value['proofToken'] == null
        ? null
        : _text(value['proofToken'], 4096, '验证信息'),
  );
}
