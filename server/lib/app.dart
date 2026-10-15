import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_core/ssh.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';

const contentSecurityPolicy =
    "default-src 'self'; script-src 'self' 'wasm-unsafe-eval' https://challenges.cloudflare.com; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' https://fonts.gstatic.com data:; connect-src 'self' https://challenges.cloudflare.com https://fonts.gstatic.com; worker-src 'self' blob:; frame-src https://challenges.cloudflare.com; base-uri 'self'; form-action 'self'; frame-ancestors 'none'; object-src 'none'";
const securityHeaders = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'DENY',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  'Content-Security-Policy': contentSecurityPolicy,
};

class ApiApp {
  ApiApp({
    this.env = const {},
    this.ssh,
    this.probe,
    http.Client? captchaClient,
    CfnewGateway? cfnew,
  }) : _captchaClient = captchaClient ?? http.Client(),
       _cfnew = cfnew ?? CfnewDeployer();
  final Map<String, String> env;
  final SshExecutor? ssh;
  final PortProbe? probe;
  final http.Client _captchaClient;
  final CfnewGateway _cfnew;
  final _buckets = <String, ({int count, int expires})>{};

  void close() {
    _captchaClient.close();
    _cfnew.dispose();
  }

  Response _json(Object data, [int status = 200]) => Response(
    status,
    body: jsonEncode(data),
    headers: {
      ...securityHeaders,
      'Content-Type': 'application/json; charset=utf-8',
      'Cache-Control': 'no-store',
      if (status == 429) 'Retry-After': '60',
    },
  );

  Future<Response> handle(Request request) async {
    try {
      final path = request.url.path;
      if (path == 'api/health' && request.method == 'GET') {
        return _json({'ok': true});
      }
      if (path == 'api/config' && request.method == 'GET') {
        return _json({
          'turnstileSiteKey': _nonempty(env['TURNSTILE_SITE_KEY']),
        });
      }
      final action = switch (path) {
        'api/cfnew' => ServerAction.status,
        'api/install' => ServerAction.install,
        'api/status' => ServerAction.status,
        'api/manage' => ServerAction.manage,
        _ => null,
      };
      if (action == null) throw const AppException('NOT_FOUND', '此接口不存在。', 404);
      if (request.method != 'POST') {
        throw const AppException('METHOD_NOT_ALLOWED', '此操作需要 POST 请求。', 405);
      }
      final origin =
          _nonempty(env['PUBLIC_ORIGIN']) ?? request.requestedUri.origin;
      if (request.headers['origin'] != origin ||
          request.headers['sec-fetch-site'] == 'cross-site') {
        throw const AppException('CROSS_ORIGIN', '请在本网站页面中操作。', 403);
      }
      final ip = request.context['clientIp'] as String? ?? 'unknown';
      _limit(ip, action);
      final bodyLimit = action == ServerAction.manage
          ? maxManagementBytes + maxBodyBytes
          : maxBodyBytes;
      if (!(request.headers['content-type'] ?? '').startsWith(
        'application/json',
      )) {
        throw const AppException('CONTENT_TYPE', '请使用 JSON 格式提交连接信息。', 415);
      }
      if ((request.contentLength ?? 0) > bodyLimit) {
        throw const AppException(
          'BODY_TOO_LARGE',
          '连接信息过大，私钥文件最大支持 64 KB。',
          413,
        );
      }
      final bytes = <int>[];
      await for (final chunk in request.read().timeout(
        const Duration(seconds: 10),
      )) {
        if (bytes.length + chunk.length > bodyLimit) {
          throw const AppException(
            'BODY_TOO_LARGE',
            '连接信息过大，私钥文件最大支持 64 KB。',
            413,
          );
        }
        bytes.addAll(chunk);
      }
      Object? raw;
      try {
        raw = jsonDecode(utf8.decode(bytes));
      } catch (_) {
        throw const AppException('INVALID_JSON', '连接信息格式不正确。');
      }
      if (path == 'api/cfnew') {
        final input = CfnewInput.parse(raw);
        if (input.step == 'prepare') _limit(ip, ServerAction.install);
        final proof = await _authorize(
          input.captchaIdentity,
          ip,
          Uri.parse(origin).host,
        );
        final result = await _cfnew.perform(input);
        return _json({...result, 'proofToken': ?proof});
      }
      final input = validateInput(raw);
      final proof = await _authorize(input, ip, Uri.parse(origin).host);
      var status = await executeAction(action, input, ssh: ssh, probe: probe);
      if (proof != null) status = status.withFields({'proofToken': proof});
      return _json(status.toJson());
    } catch (error) {
      final safe = error is AppException
          ? error
          : const AppException('INTERNAL_ERROR', '暂时无法完成操作，请稍后重试。', 500);
      return _json({
        'error': {'code': safe.code, 'message': safe.message},
      }, safe.statusCode);
    }
  }

  void _limit(String ip, ServerAction action) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_buckets.length > 10000) {
      _buckets.removeWhere((_, bucket) => bucket.expires <= now);
    }
    for (final rule in {
      'request:$ip': 60,
      if (action == ServerAction.install) 'install:$ip': 3,
    }.entries) {
      if (_buckets.length >= 20000 && !_buckets.containsKey(rule.key)) {
        throw const AppException('RATE_LIMIT', '网站暂时繁忙，请稍后再试。', 429);
      }
      final previous = _buckets[rule.key];
      final bucket = previous == null || previous.expires <= now
          ? (count: 1, expires: now + 60000)
          : (count: previous.count + 1, expires: previous.expires);
      _buckets[rule.key] = bucket;
      if (bucket.count > rule.value) {
        throw const AppException('RATE_LIMIT', '操作过于频繁，请稍后再试。', 429);
      }
    }
  }

  Future<String?> _authorize(
    ConnectionInput input,
    String ip,
    String hostname,
  ) async {
    final siteKey = _nonempty(env['TURNSTILE_SITE_KEY']);
    final secret = _nonempty(env['TURNSTILE_SECRET_KEY']);
    if (siteKey == null && secret == null) return null;
    if (siteKey == null || secret == null) {
      throw const AppException('CAPTCHA_SETUP', '网站的人机验证尚未配置完成。', 503);
    }
    final identity = '$ip|${input.host}|${input.port}|${input.username}';
    final hmac = Hmac(sha256, utf8.encode('5a-ui-proof-v1:$secret'));
    final now = DateTime.now().millisecondsSinceEpoch;
    if (input.proofToken != null) {
      try {
        final parts = input.proofToken!.split('.');
        if (parts.length == 2) {
          final expected = hmac.convert(utf8.encode(parts[0])).bytes;
          final received = base64Url.decode(base64Url.normalize(parts[1]));
          var difference = expected.length ^ received.length;
          for (var i = 0; i < expected.length; i++) {
            difference |= expected[i] ^ (i < received.length ? received[i] : 0);
          }
          final payload = jsonDecode(
            utf8.decode(base64Url.decode(base64Url.normalize(parts[0]))),
          ) as Map;
          if (difference == 0 &&
              payload['identity'] == identity &&
              payload['expires'] is int &&
              payload['expires'] > now &&
              payload['expires'] < now + 31 * 60000) {
            return input.proofToken;
          }
        }
      } catch (_) {
        /* A fresh challenge is required. */
      }
    }
    if (input.turnstileToken == null || input.turnstileToken!.isEmpty) {
      throw const AppException('CAPTCHA_REQUIRED', '请完成人机验证后再试。', 403);
    }
    Object? verified;
    try {
      final response = await _captchaClient
          .post(
            Uri.parse(
              'https://challenges.cloudflare.com/turnstile/v0/siteverify',
            ),
            body: {
              'secret': secret,
              'response': input.turnstileToken!,
              'remoteip': ip,
            },
          )
          .timeout(const Duration(seconds: 10));
      verified = jsonDecode(response.body);
    } catch (_) {
      throw const AppException(
        'CAPTCHA_UNAVAILABLE',
        '人机验证服务暂时不可用，请稍后重试。',
        503,
      );
    }
    if (verified is! Map ||
        verified['success'] != true ||
        verified['hostname'] != hostname) {
      throw const AppException('CAPTCHA_FAILED', '人机验证已过期或失败，请重新验证。', 403);
    }
    final data = base64Url
        .encode(
          utf8.encode(
            jsonEncode({'identity': identity, 'expires': now + 30 * 60000}),
          ),
        )
        .replaceAll('=', '');
    return '$data.${base64Url.encode(hmac.convert(utf8.encode(data)).bytes).replaceAll('=', '')}';
  }
}

String? _nonempty(String? value) =>
    value == null || value.isEmpty ? null : value;
