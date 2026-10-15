import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import 'models.dart';
import 'remote_generated.dart';

final cfnewRelease = jsonDecode(cfnewReleaseJson) as Map<String, dynamic>;
const cfnewSteps = ['prepare', 'upload', 'activate', 'verify'];

String newCfnewUuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

class CfnewInput {
  CfnewInput._(
    this.accountId,
    this.apiToken,
    this.workerName,
    this.uuid,
    this.step,
    this.namespaceId,
    this.turnstileToken,
    this.proofToken,
  );
  final String accountId, apiToken, workerName, uuid, step;
  final String? namespaceId, turnstileToken, proofToken;
  String get owner =>
      sha256.convert(utf8.encode('5a-ui-cfnew:$uuid')).toString();
  String get namespaceTitle => '5a-ui-$workerName-${owner.substring(0, 16)}';
  Map<String, dynamic> toJson() => {
    'accountId': accountId,
    'apiToken': apiToken,
    'workerName': workerName,
    'uuid': uuid,
    'step': step,
    if (namespaceId != null) 'namespaceId': namespaceId,
    if (turnstileToken != null) 'turnstileToken': turnstileToken,
    if (proofToken != null) 'proofToken': proofToken,
  };
  factory CfnewInput.parse(Object? raw) {
    if (raw is! Map) {
      throw const AppException('CF_INPUT', 'Cloudflare 部署参数格式不正确。');
    }
    String field(String key, String pattern, String message) {
      final value = raw[key];
      if (value is! String ||
          RegExp(pattern).firstMatch(value)?.group(0) != value) {
        throw AppException('CF_INPUT', message);
      }
      return value;
    }

    final account = field(
      'accountId',
      r'^[a-f0-9]{32}$',
      '账号 ID 应为 32 位小写十六进制字符。',
    );
    final token = field(
      'apiToken',
      r'^[A-Za-z0-9_-]{20,256}$',
      '请输入有效的 Cloudflare API Token。',
    );
    final name = field(
      'workerName',
      r'^[a-z][a-z0-9-]{1,61}[a-z0-9]$',
      'Worker 名称须为 3–63 位小写字母、数字或连字符，以字母开头，不能以连字符结尾。',
    );
    final uuid = field(
      'uuid',
      r'^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$',
      '请输入有效的 UUID v4，或使用自动生成的值。',
    );
    final step = raw['step'];
    if (step is! String || !cfnewSteps.contains(step)) {
      throw const AppException('CF_INPUT', '未知的部署阶段。');
    }
    final namespace = raw['namespaceId'];
    if (namespace != null &&
        (namespace is! String ||
            (namespace.length != 32 ||
                !RegExp(r'^[a-f0-9]{32}$').hasMatch(namespace)))) {
      throw const AppException('CF_INPUT', '配置存储标识不正确。');
    }
    if (step != 'prepare' && namespace == null) {
      throw const AppException('CF_INPUT', '请先准备配置存储。');
    }
    for (final key in ['turnstileToken', 'proofToken']) {
      if (raw[key] != null &&
          (raw[key] is! String || (raw[key] as String).length > 4096)) {
        throw const AppException('CF_INPUT', '验证参数不正确。');
      }
    }
    return CfnewInput._(
      account,
      token,
      name,
      uuid,
      step,
      namespace as String?,
      raw['turnstileToken'] as String?,
      raw['proofToken'] as String?,
    );
  }
  ConnectionInput get captchaIdentity => ConnectionInput(
    host: 'cfnew:$accountId',
    port: 0,
    username: '$workerName:$uuid',
    turnstileToken: turnstileToken,
    proofToken: proofToken,
  );
}

abstract interface class CfnewGateway {
  Future<Map<String, dynamic>> perform(CfnewInput input);
  void dispose();
}

/// Direct Cloudflare API transport for native apps and the Dart Web backend.
/// Tokens are sent only to the fixed API origin; upstream and Worker reads are
/// unauthenticated. No body, URL containing UUID, or provider error is logged.
class CfnewDeployer implements CfnewGateway {
  CfnewDeployer({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  @override
  void dispose() => _client.close();

  Future<http.Response> _send(
    http.BaseRequest request, {
    int limit = 2 * 1024 * 1024,
  }) async {
    request.followRedirects = false;
    try {
      return await (() async {
        final streamed = await _client.send(request);
        final bytes = <int>[];
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > limit) {
            throw const AppException('CF_RESPONSE', '远端响应过大，已停止处理。', 502);
          }
          bytes.addAll(chunk);
        }
        return http.Response.bytes(bytes, streamed.statusCode);
      })().timeout(const Duration(seconds: 15));
    } on AppException {
      rethrow;
    } catch (_) {
      throw const AppException(
        'CF_NETWORK',
        'Cloudflare 请求未能确认。保持原账号、名称和 UUID 重试，可继续未完成的部署。',
        502,
      );
    }
  }

  Future<Map<String, dynamic>?> _api(
    CfnewInput input,
    String path, {
    String method = 'GET',
    Object? body,
    String? multipart,
    String? contentType,
    bool missingScript = false,
  }) async {
    final request = http.Request(
      method,
      Uri.parse(
        'https://api.cloudflare.com/client/v4/accounts/${input.accountId}/$path',
      ),
    );
    request.headers['Authorization'] = 'Bearer ${input.apiToken}';
    if (body != null || multipart != null) {
      request.headers['Content-Type'] = contentType ?? 'application/json';
      request.body = multipart ?? jsonEncode(body);
    }
    final response = await _send(request);
    Object? value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {}
    final codes = value is Map && value['errors'] is List
        ? (value['errors'] as List)
              .whereType<Map>()
              .map((e) => e['code'])
              .toList()
        : const [];
    if (missingScript && response.statusCode == 404 && codes.contains(10007)) {
      return null;
    }
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        codes.contains(10000) ||
        codes.contains(9109)) {
      throw const AppException(
        'CF_AUTH',
        'Cloudflare 拒绝访问。请检查 Token、账号范围，以及 Workers Scripts 和 Workers KV Storage 编辑权限。',
        403,
      );
    }
    if (response.statusCode == 429) {
      throw const AppException(
        'CF_LIMIT',
        'Cloudflare 限流或额度不足，请稍后重试并检查账号额度。',
        429,
      );
    }
    if (response.statusCode < 200 ||
        response.statusCode >= 300 ||
        value is! Map<String, dynamic> ||
        value['success'] != true) {
      throw AppException(
        'CF_API',
        'Cloudflare 操作未成功（HTTP ${response.statusCode}）。请检查账号状态后使用相同参数重试；已创建的资源会保留。',
        502,
      );
    }
    return value;
  }

  Future<String> _source() async {
    final response = await _send(
      http.Request('GET', Uri.parse(cfnewRelease['sourceUrl'] as String)),
      limit: 1024 * 1024,
    );
    if (response.statusCode != 200 ||
        sha256.convert(response.bodyBytes).toString() !=
            cfnewRelease['sha256']) {
      throw const AppException('CF_SOURCE', 'cfnew 上游源码下载或完整性校验失败，未上传代码。', 502);
    }
    return utf8.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>?> _settings(CfnewInput input) async {
    final envelope = await _api(
      input,
      'workers/scripts/${input.workerName}/settings',
      missingScript: true,
    );
    if (envelope == null) return null;
    final settings = envelope['result'];
    if (settings is! Map<String, dynamic> || settings['bindings'] is! List) {
      throw const AppException('CF_RESPONSE', '无法核对 Worker 配置。', 502);
    }
    final bindings = (settings['bindings'] as List).whereType<Map>();
    bool binding(String name, String type, String key, String value) => bindings
        .any((b) => b['name'] == name && b['type'] == type && b[key] == value);
    if (!binding('FIVE_A_CFNEW_OWNER', 'plain_text', 'text', input.owner) ||
        !binding(
          'FIVE_A_CFNEW_REVISION',
          'plain_text',
          'text',
          cfnewRelease['commit'] as String,
        ) ||
        !bindings.any((b) => b['name'] == 'u' && b['type'] == 'secret_text') ||
        settings['compatibility_date'] != cfnewRelease['compatibilityDate']) {
      throw const AppException(
        'CF_CONFLICT',
        '已有同名 Worker，或其配置已改变。本次不会覆盖，请更换名称；恢复本次部署需使用原 UUID。',
        409,
      );
    }
    return settings;
  }

  String _boundNamespace(Map<String, dynamic> settings) {
    final bindings = settings['bindings'] as List;
    final binding = bindings
        .whereType<Map>()
        .where((b) => b['name'] == 'C' && b['type'] == 'kv_namespace')
        .firstOrNull;
    final id = binding?['namespace_id'];
    if (id is! String || !RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
      throw const AppException(
        'CF_CONFLICT',
        'Worker 的配置存储绑定不匹配，请在 Cloudflare 控制台检查。',
        409,
      );
    }
    return id;
  }

  Future<void> _namespace(CfnewInput input, String id) async {
    final value = await _api(input, 'storage/kv/namespaces/$id');
    final result = value?['result'];
    if (result is! Map ||
        result['id'] != id ||
        result['title'] != input.namespaceTitle) {
      throw const AppException('CF_CONFLICT', '配置存储不属于本次部署，已停止操作。', 409);
    }
  }

  Future<String> _subdomain(CfnewInput input) async {
    final value = await _api(input, 'workers/subdomain');
    final result = value?['result'];
    final name = result is Map ? result['subdomain'] : null;
    if (name is! String ||
        !RegExp(r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$').hasMatch(name)) {
      throw const AppException(
        'CF_SUBDOMAIN',
        '请先在 Cloudflare 控制台启用账号的 workers.dev 子域名。',
      );
    }
    return name;
  }

  @override
  Future<Map<String, dynamic>> perform(CfnewInput input) async {
    final path = 'workers/scripts/${input.workerName}';
    final settings = await _settings(input);
    var namespace = input.namespaceId;
    if (input.step == 'prepare') {
      await _subdomain(input);
      if (settings != null) {
        namespace = _boundNamespace(settings);
        await _namespace(input, namespace);
      } else {
        // Check the fixed artifact before allocating any Cloudflare resource.
        await _source();
        for (var page = 1; page <= 10; page++) {
          final value = (await _api(
            input,
            'storage/kv/namespaces?per_page=100&page=$page',
          ))!;
          final list = value['result'];
          if (list is! List) {
            throw const AppException('CF_RESPONSE', '无法核对配置存储列表。', 502);
          }
          final matches = list
              .whereType<Map>()
              .where((n) => n['title'] == input.namespaceTitle)
              .toList();
          if (matches.length > 1) {
            throw const AppException(
              'CF_CONFLICT',
              '存在重复的部署存储，请在 Cloudflare 控制台检查。',
              409,
            );
          }
          if (matches.isNotEmpty) {
            namespace = matches.single['id'] as String;
            break;
          }
          if (list.length < 100) break;
          if (page == 10) {
            throw const AppException(
              'CF_NAMESPACES',
              '配置存储数量过多，请在 Cloudflare 控制台整理后重试。',
            );
          }
        }
        if (namespace == null) {
          final value = await _api(
            input,
            'storage/kv/namespaces',
            method: 'POST',
            body: {'title': input.namespaceTitle},
          );
          final result = value?['result'];
          namespace = result is Map ? result['id'] as String? : null;
        }
        if (namespace == null ||
            (namespace.length != 32 ||
                !RegExp(r'^[a-f0-9]{32}$').hasMatch(namespace))) {
          throw const AppException('CF_RESPONSE', '未能确认配置存储，请使用相同参数重试。', 502);
        }
        await _namespace(input, namespace);
      }
      return {'step': input.step, 'namespaceId': namespace};
    }
    await _namespace(input, namespace!);
    if (settings != null && _boundNamespace(settings) != namespace) {
      throw const AppException('CF_CONFLICT', 'Worker 绑定的配置存储与本次部署不同。', 409);
    }
    if (input.step == 'upload') {
      if (settings == null) {
        final source = await _source();
        // Recheck immediately before writing to reduce accidental name races.
        if (await _settings(input) == null) {
          final metadata = cfnewMetadata(input, namespace);
          final boundary = 'fivea${newCfnewUuid().replaceAll('-', '')}';
          final multipart =
              '--$boundary\r\nContent-Disposition: form-data; name="metadata"\r\nContent-Type: application/json\r\n\r\n${jsonEncode(metadata)}\r\n--$boundary\r\nContent-Disposition: form-data; name="worker.js"; filename="worker.js"\r\nContent-Type: application/javascript+module\r\n\r\n$source\r\n--$boundary--\r\n';
          await _api(
            input,
            path,
            method: 'PUT',
            multipart: multipart,
            contentType: 'multipart/form-data; boundary=$boundary',
          );
        }
      }
      final saved = await _settings(input);
      if (saved == null || _boundNamespace(saved) != namespace) {
        throw const AppException('CF_VERIFY', 'Worker 上传后未能确认，请重试。', 502);
      }
      return {'step': input.step, 'namespaceId': namespace};
    }
    if (settings == null) {
      throw const AppException('CF_MISSING', 'Worker 尚未上传，请重新部署。', 409);
    }
    if (input.step == 'activate') {
      await _api(
        input,
        '$path/subdomain',
        method: 'POST',
        body: {'enabled': true, 'previews_enabled': false},
      );
    }
    final access = (await _api(input, '$path/subdomain'))?['result'];
    if (access is! Map || access['enabled'] != true) {
      throw const AppException('CF_VERIFY', 'workers.dev 访问尚未启用，请重试。', 502);
    }
    final domain = await _subdomain(input);
    final base = 'https://${input.workerName}.$domain.workers.dev';
    var verified = false;
    if (input.step == 'verify') {
      try {
        final response = await _send(
          http.Request('GET', Uri.parse('$base/${input.uuid}/api/config')),
          limit: 128 * 1024,
        );
        final config = jsonDecode(response.body);
        verified =
            response.statusCode == 200 &&
            config is Map &&
            config['kvEnabled'] == true;
      } catch (_) {
        /* Propagation/region failures do not undo a deployment. */
      }
    }
    return {
      'step': input.step,
      'namespaceId': namespace,
      'phase': 'deployed',
      'runtimeVerified': verified,
      'workerUrl': base,
      'managementUrl': '$base/${input.uuid}',
      'subscriptionUrl': '$base/${input.uuid}/sub',
      'clashUrl': '$base/${input.uuid}/sub?target=clash',
      'dashboardUrl':
          'https://dash.cloudflare.com/${input.accountId}/workers/services/view/${input.workerName}/production',
    };
  }
}

Map<String, dynamic> cfnewMetadata(CfnewInput input, String namespaceId) => {
  'main_module': 'worker.js',
  'compatibility_date': cfnewRelease['compatibilityDate'],
  'logpush': false,
  'observability': {'enabled': false},
  'bindings': [
    {'type': 'kv_namespace', 'name': 'C', 'namespace_id': namespaceId},
    {'type': 'secret_text', 'name': 'u', 'text': input.uuid},
    {'type': 'plain_text', 'name': 'FIVE_A_CFNEW_OWNER', 'text': input.owner},
    {
      'type': 'plain_text',
      'name': 'FIVE_A_CFNEW_REVISION',
      'text': cfnewRelease['commit'],
    },
    for (final entry in (cfnewRelease['defaults'] as Map).entries)
      {'type': 'plain_text', 'name': entry.key, 'text': entry.value},
  ],
};
