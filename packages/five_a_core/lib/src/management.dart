import 'dart:convert';

import 'models.dart';
import 'remote_generated.dart' as embedded;

const maxManagementBytes = 3 * 1024 * 1024;
final panelOperations = [
  ...(jsonDecode(embedded.panelOperationsJson) as List)
      .cast<Map<String, dynamic>>(),
  ...(jsonDecode(embedded.mihomoOperationsJson) as List)
      .cast<Map<String, dynamic>>(),
];

Map<String, dynamic> validateManagement(Object? value) {
  const invalid = AppException('PANEL_INPUT', '管理请求格式不正确。');
  if (value is! Map<String, dynamic> ||
      value['instanceId'] is! String ||
      (value['instanceId'] as String).length > 500 ||
      !(value['instanceId'] as String).startsWith(
        RegExp(r'(native|docker):'),
      ) ||
      !{
        'catalog',
        'service.start',
        'service.stop',
        'service.restart',
        ...panelOperations.map((op) => op['id']),
      }.contains(value['operation'])) {
    throw invalid;
  }
  if (utf8.encode(jsonEncode(value)).length > maxManagementBytes) {
    throw const AppException('BODY_TOO_LARGE', '管理请求过大，备份最大支持 2 MiB。', 413);
  }
  final auth = value['auth'] ?? <String, dynamic>{};
  if (auth is! Map) throw invalid;
  final cleanAuth = <String, dynamic>{};
  for (final key in ['username', 'password', 'token', 'twoFactorCode']) {
    if (auth[key] != null) {
      if (auth[key] is! String ||
          (auth[key] as String).length > 4096 ||
          RegExp(r'[\r\n\x00]').hasMatch(auth[key] as String)) {
        throw invalid;
      }
      cleanAuth[key] = auth[key];
    }
  }
  if (auth['session'] != null) {
    final session = auth['session'];
    if (session is! Map ||
        ['cookie', 'csrf'].any(
          (k) =>
              session[k] is! String ||
              (session[k] as String).length > 8192 ||
              RegExp(r'[\r\n\x00]').hasMatch(session[k] as String),
        )) {
      throw invalid;
    }
    if (session['bearer'] != null &&
        (session['bearer'] is! String ||
            (session['bearer'] as String).length > 8192 ||
            RegExp(r'[\r\n\x00]').hasMatch(session['bearer'] as String))) {
      throw invalid;
    }
    cleanAuth['session'] = {
      if (session['bearer'] != null) 'bearer': session['bearer'],
      for (final k in ['cookie', 'csrf']) k: session[k],
    };
  }
  for (final key in ['parameters', 'precondition']) {
    if (value[key] != null && value[key] is! Map<String, dynamic>) {
      throw invalid;
    }
  }
  final endpoint = value['endpoint'];
  if (endpoint != null &&
      (endpoint is! Map ||
          endpoint['port'] is! int ||
          endpoint['port'] < 1 ||
          endpoint['port'] > 65535 ||
          endpoint['path'] is! String ||
          !(endpoint['path'] as String).startsWith('/') ||
          (endpoint['path'] as String).length > 1024 ||
          RegExp(r'[?#\\\r\n\x00]').hasMatch(endpoint['path'] as String) ||
          ![null, '127.0.0.1', '::1'].contains(endpoint['listen']) ||
          (endpoint['https'] != null && endpoint['https'] is! bool) ||
          (endpoint['domain'] != null &&
              (endpoint['domain'] is! String ||
                  !RegExp(r'^[A-Za-z0-9.-]{1,253}$')
                      .hasMatch(endpoint['domain'] as String))))) {
    throw invalid;
  }
  return {
    'instanceId': value['instanceId'],
    'operation': value['operation'],
    'auth': cleanAuth,
    if (endpoint != null)
      'endpoint': {
        for (final k in ['port', 'path', 'listen', 'https', 'domain'])
          if (endpoint[k] != null) k: endpoint[k],
      },
    if (value['confirmed'] == true) 'confirmed': true,
    for (final key in ['parameters', 'data', 'precondition'])
      if (value[key] != null) key: value[key],
  };
}

String managementScript(Map<String, dynamic> request, {String host = ''}) {
  String b64(String value) => base64Encode(utf8.encode(value));
  return "set -eu\npython3 - <<'FIVE_A_PANEL'\n"
      "import base64,json,types\n"
      "inspector=types.ModuleType('five_a_inspector')\n"
      "exec(base64.b64decode('${b64(embedded.inspectorScript)}'),inspector.__dict__)\n"
      "exec(base64.b64decode('${b64(embedded.panelScript)}'))\n"
      "main(json.loads(base64.b64decode('${b64(jsonEncode(validateManagement(request)))}')),inspector,"
      "json.loads(base64.b64decode('${b64(jsonEncode(panelOperations))}')),"
      "base64.b64decode('${b64(host)}').decode())\n"
      "FIVE_A_PANEL\n";
}
