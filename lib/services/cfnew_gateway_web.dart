import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:http/http.dart' as http;

CfnewGateway createCfnewGateway() => CfnewHttpGateway();

class CfnewHttpGateway implements CfnewGateway {
  final http.Client _client = http.Client();
  @override
  void dispose() => _client.close();
  @override
  Future<Map<String, dynamic>> perform(CfnewInput input) async {
    try {
      final response = await _client
          .post(
            Uri.base.resolve('/api/cfnew'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(input.toJson()),
          )
          .timeout(const Duration(seconds: 55));
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        final error = value is Map ? value['error'] : null;
        throw AppException(
          error is Map && error['code'] is String
              ? error['code'] as String
              : 'CF_REQUEST',
          error is Map && error['message'] is String
              ? error['message'] as String
              : '部署请求失败，请重试。',
          response.statusCode,
        );
      }
      if (value is! Map<String, dynamic>) throw const FormatException();
      return value;
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'CF_NETWORK',
        '部署结果尚未确认。请保留原账号、名称及 UUID 重试，已创建资源会保留。',
      );
    }
  }
}
