import 'dart:convert';

import 'models.dart';
import 'remote_generated.dart' as embedded;

String _inspect(String script, String host) => script
    .replaceAll(
      '@@INSPECTOR@@',
      base64Encode(utf8.encode(embedded.inspectorScript)),
    )
    .replaceAll('@@HOST@@', base64Encode(utf8.encode(host)));

String statusScript(String host) => _inspect(embedded.statusScript, host);
String installScript(ConnectionInput input) {
  final config = jsonEncode({
    'host': input.host,
    'panelType': input.panelType,
    'nodePort': input.nodePort,
    'realityServerName': input.realityServerName ?? '',
  });
  return _inspect(embedded.installTemplate, input.host)
      .replaceAll('@@CONFIG@@', base64Encode(utf8.encode(config)))
      .replaceAll(
        '@@MIHOMO_JOB@@',
        base64Encode(utf8.encode(embedded.mihomoJobScript)),
      )
      .replaceAll(
        '@@MIHOMO_MANAGER@@',
        base64Encode(utf8.encode(embedded.mihomoManagerScript)),
      )
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
  // Login identity is supplied by the SSH transport, never a remote script.
  if (value is Map) value.remove('sshUsername');
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
  final sshUsername = value['sshUsername'];
  if (sshUsername is String &&
      RegExp(
        r'^[a-z_][a-z0-9_-]{0,31}$',
        caseSensitive: false,
      ).hasMatch(sshUsername)) {
    result['sshUsername'] = sshUsername;
  }
  for (final key in ['installed', 'running', 'portReachable', 'truncated']) {
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
  if (value['instances'] is List) {
    result['instances'] = _instances(value['instances'] as List);
  }
  if (value['management'] is Map<String, dynamic>) {
    final management = value['management'] as Map<String, dynamic>;
    result['management'] = {
      for (final key in ['result', 'revision', 'session'])
        if (management.containsKey(key)) key: management[key],
    };
  }
  return ServerStatus(result);
}

Map<String, dynamic> _fields(
  Map value,
  List<String> strings,
  List<String> booleans,
  List<String> numbers,
) {
  final result = <String, dynamic>{};
  for (final key in strings) {
    if (value[key] case final String text) {
      result[key] = text.length > 500 ? text.substring(0, 500) : text;
    }
  }
  for (final key in booleans) {
    if (value[key] is bool) result[key] = value[key];
  }
  for (final key in numbers) {
    if (value[key] is int && (key == 'expiryTime' || value[key] >= 0)) {
      result[key] = value[key];
    }
  }
  final traffic = value['traffic'];
  if (traffic is Map &&
      ['up', 'down'].every(
        (key) =>
            traffic[key] is num &&
            (traffic[key] as num).isFinite &&
            traffic[key] >= 0,
      )) {
    result['traffic'] = {'up': traffic['up'], 'down': traffic['down']};
  }
  return result;
}

bool _shareLink(Object? value) {
  if (value is! String || value.length > 4096) return false;
  try {
    if (value.startsWith('vmess://')) {
      if (!RegExp(r'^[A-Za-z0-9+/_-]+={0,2}$').hasMatch(value.substring(8))) {
        return false;
      }
      final node = jsonDecode(
        utf8.decode(base64Decode(base64.normalize(value.substring(8)))),
      );
      final port =
          node is Map && RegExp(r'^[0-9]+$').hasMatch('${node['port']}')
          ? int.tryParse('${node['port']}')
          : null;
      return node is Map &&
          node['add'] is String &&
          (node['add'] as String).isNotEmpty &&
          node['id'] is String &&
          (node['id'] as String).isNotEmpty &&
          port != null &&
          port > 0 &&
          port <= 65535;
    }
    final uri = Uri.parse(value);
    return {'vless', 'trojan', 'ss'}.contains(uri.scheme) &&
        uri.host.isNotEmpty &&
        uri.userInfo.isNotEmpty &&
        uri.hasPort &&
        uri.port > 0 &&
        uri.port <= 65535;
  } catch (_) {
    return false;
  }
}

List<Map<String, dynamic>> _instances(List values) {
  final result = <Map<String, dynamic>>[];
  for (final item in values) {
    if (item is! Map ||
        item['id'] is! String ||
        item['name'] is! String ||
        !{'native', 'docker'}.contains(item['kind']) ||
        item['inbounds'] is! List) {
      continue;
    }
    final instance = _fields(
      item,
      ['id', 'name', 'kind', 'message', 'panelVersion', 'panelType'],
      ['running', 'readable', 'truncated'],
      [],
    );
    final inbounds = <Map<String, dynamic>>[];
    for (final row in item['inbounds'] as List) {
      if (row is! Map ||
          row['id'] is! String ||
          row['name'] is! String ||
          row['protocol'] is! String ||
          row['port'] is! int ||
          row['port'] < 0 ||
          row['port'] > 65535 ||
          row['clients'] is! List) {
        continue;
      }
      final inbound = _fields(
        row,
        ['id', 'name', 'protocol', 'message'],
        ['enabled'],
        ['port'],
      );
      final clients = <Map<String, dynamic>>[];
      for (final client in row['clients'] as List) {
        if (client is! Map ||
            client['id'] is! String ||
            client['name'] is! String) {
          continue;
        }
        final node = _fields(
          client,
          ['id', 'name', 'message', 'linkMessage'],
          ['enabled', 'available'],
          ['expiryTime', 'total'],
        );
        if (_shareLink(client['link']) &&
            client['host'] is String &&
            client['serverName'] is String &&
            client['port'] is int &&
            client['port'] > 0 &&
            client['port'] <= 65535) {
          for (final field in ['host', 'port', 'serverName', 'link']) {
            node[field] = client[field];
          }
        }
        clients.add(node);
      }
      inbound['clients'] = clients;
      inbounds.add(inbound);
    }
    instance['inbounds'] = inbounds;
    result.add(instance);
  }
  return result;
}
