import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:http/http.dart' as http;

ServerGateway createGateway() => HttpGateway();

class HttpGateway implements ServerGateway {
  http.Client? _active;
  @override
  Future<String?> loadSiteKey() async {
    final client = http.Client();
    try {
      final response = await client
          .get(Uri.base.resolve('/api/config'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const AppException('CONFIG', '服务配置加载失败，请重试。');
      }
      return (jsonDecode(response.body) as Map)['turnstileSiteKey'] as String?;
    } finally {
      client.close();
    }
  }

  @override
  Future<ServerStatus> perform(
    ServerAction action,
    ConnectionInput input,
  ) async {
    final client = http.Client();
    _active = client;
    try {
      final response = await client
          .post(
            Uri.base.resolve('/api/${action.name}'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(input.toJson()),
          )
          .timeout(const Duration(seconds: 45));
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final error = value is Map ? value['error'] : null;
        throw AppException(
          error is Map && error['code'] is String
              ? error['code'] as String
              : 'REQUEST_FAILED',
          error is Map && error['message'] is String
              ? error['message'] as String
              : '请求失败，请稍后重试。',
          response.statusCode,
        );
      }
      return parseStatus(value);
    } finally {
      client.close();
      if (identical(_active, client)) _active = null;
    }
  }

  @override
  void cancel() {
    _active?.close();
    _active = null;
  }

  @override
  void dispose() => cancel();
}
