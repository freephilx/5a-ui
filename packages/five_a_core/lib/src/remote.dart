import 'dart:convert';

import 'models.dart';
import 'remote_generated.dart' as embedded;

String statusScript() => embedded.statusScript;
String installScript(ConnectionInput input) {
  final config = jsonEncode({
    'host': input.host,
    'nodePort': input.nodePort,
    'realityServerName': input.realityServerName ?? '',
  });
  return embedded.installTemplate
      .replaceAll('@@CONFIG@@', base64Encode(utf8.encode(config)))
      .replaceAll('@@JOB@@', base64Encode(utf8.encode(embedded.jobScript)))
      .replaceAll(
        '@@MANAGER@@',
        base64Encode(utf8.encode(embedded.managerScript)),
      )
      .replaceAll('@@NODE_PORT@@', input.nodePort.toString());
}

ServerStatus parseRemoteResult(String stdout) {
  final line = const LineSplitter()
      .convert(stdout)
      .where((s) => s.startsWith('5A_UI_RESULT='))
      .lastOrNull;
  if (line == null) {
    throw const AppException('REMOTE_RESULT', '无法读取服务器状态，请确认系统环境或稍后重试。', 502);
  }
  Object? value;
  try {
    value = jsonDecode(line.substring('5A_UI_RESULT='.length));
  } catch (_) {
    throw const AppException('REMOTE_RESULT', '服务器状态格式不正确，请稍后重试。', 502);
  }
  return parseStatus(value);
}

ServerStatus parseStatus(Object? value) {
  if (value is! Map<String, dynamic>) {
    throw const AppException('REMOTE_RESULT', '服务器状态格式不正确。', 502);
  }
  if (value['error'] case final Map<String, dynamic> error) {
    throw AppException(
      error['code'] is String ? error['code'] as String : 'REMOTE_ERROR',
      error['message'] is String ? error['message'] as String : '服务器操作失败。',
    );
  }
  if (!phases.contains(value['phase']) || value['message'] is! String) {
    throw const AppException('REMOTE_RESULT', '服务器状态格式不正确。', 502);
  }
  final message = value['message'] as String;
  final result = <String, dynamic>{
    'phase': value['phase'],
    'message': message.length > 500 ? message.substring(0, 500) : message,
  };
  for (final key in [
    'updatedAt',
    'panelVersion',
    'xrayVersion',
    'firewall',
    'hostFingerprint',
    'proofToken',
  ]) {
    if (value[key] is String) result[key] = value[key];
  }
  for (final key in ['installed', 'running', 'portReachable']) {
    if (value[key] is bool) result[key] = value[key];
  }
  for (final key in ['cpu', 'uptime']) {
    if (value[key] is num && (value[key] as num).isFinite) {
      result[key] = value[key];
    }
  }
  for (final entry in {
    'memory': ['current', 'total'],
    'traffic': ['up', 'down'],
  }.entries) {
    final nested = value[entry.key];
    if (nested is Map &&
        entry.value.every(
          (key) =>
              nested[key] is num &&
              (nested[key] as num).isFinite &&
              (nested[key] as num) >= 0,
        )) {
      result[entry.key] = {for (final key in entry.value) key: nested[key]};
    }
  }
  final node = value['node'];
  if (node is Map &&
      node['host'] is String &&
      node['serverName'] is String &&
      node['port'] is int &&
      (node['port'] as int) > 0 &&
      (node['port'] as int) <= 65535 &&
      node['link'] is String) {
    final uri = Uri.tryParse(node['link'] as String);
    if (uri != null &&
        uri.scheme == 'vless' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isNotEmpty) {
      result['node'] = {
        for (final key in ['host', 'port', 'serverName', 'link'])
          key: node[key],
      };
    }
  }
  return ServerStatus(result);
}
