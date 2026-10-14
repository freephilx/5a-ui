import 'dart:convert';

import 'package:five_a_server/app.dart';
import 'package:five_a_core/ssh.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  const input = {
    'host': '8.8.8.8',
    'authMethod': 'password',
    'password': 'test-only',
  };
  Request request({
    Map<String, dynamic> data = input,
    String origin = 'https://test.example',
    String path = 'status',
    String contentType = 'application/json',
  }) => Request(
    'POST',
    Uri.parse('https://test.example/api/$path'),
    headers: {'origin': origin, 'content-type': contentType},
    body: jsonEncode(data),
    context: {'clientIp': 'client'},
  );

  test('rejects cross-origin and private destinations before SSH', () async {
    var calls = 0;
    final app = ApiApp(
      ssh: (_, _) async {
        calls++;
        return const SshResult('', '');
      },
    );
    addTearDown(app.close);
    expect(
      (await app.handle(request(origin: 'https://other.example'))).statusCode,
      403,
    );
    expect(
      (await app.handle(request(data: {...input, 'host': '169.254.169.254'})))
          .statusCode,
      400,
    );
    expect(calls, 0);
  });
  test('returns a pinned fingerprint, updates node host and never caches credentials', () async {
    final app = ApiApp(
      ssh: (_, _) async => const SshResult(
        '5A_UI_RESULT={"phase":"ready","message":"ok","node":{"host":"old","port":443,"serverName":"www.microsoft.com","link":"vless://abc@1.1.1.1:443?security=reality#node"}}',
        'SHA256:observed',
      ),
      probe: (host, port) async {
        expect(host, '2606:4700:4700::1111');
        expect(port, 443);
        return false;
      },
    );
    addTearDown(app.close);
    final response = await app.handle(
      request(data: {...input, 'host': '2606:4700:4700::1111'}),
    );
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    final body = jsonDecode(await response.readAsString());
    expect(body['hostFingerprint'], 'SHA256:observed');
    expect(body['node']['link'], contains('@[2606:4700:4700::1111]:443'));
    expect(body['portReachable'], false);
  });
  test('sanitizes unexpected exceptions', () async {
    final app = ApiApp(
      ssh: (_, _) async => throw StateError('password=test-only'),
    );
    addTearDown(app.close);
    final response = await app.handle(request());
    expect(response.statusCode, 500);
    expect(await response.readAsString(), isNot(contains('test-only')));
  });
  test('limits requests and rejects oversized input', () async {
    final app = ApiApp(
      ssh: (_, _) async => const SshResult(
        '5A_UI_RESULT={"phase":"queued","message":"started"}',
        'SHA256:observed',
      ),
    );
    addTearDown(app.close);
    for (var i = 0; i < 3; i++) {
      expect((await app.handle(request(path: 'install'))).statusCode, 200);
    }
    final limited = await app.handle(request(path: 'install'));
    expect(limited.statusCode, 429);
    expect(limited.headers['retry-after'], '60');
    expect(
      (await app.handle(request(data: {...input, 'privateKey': 'x' * 90000})))
          .statusCode,
      413,
    );
  });
  test('Turnstile proof supports polling, binds identity and rejects an expired proof', () async {
    var verifies = 0;
    final client = MockClient((_) async {
      verifies++;
      return http.Response('{"success":true,"hostname":"test.example"}', 200);
    });
    final app = ApiApp(
      env: {'TURNSTILE_SITE_KEY': 'site', 'TURNSTILE_SECRET_KEY': 'secret'},
      captchaClient: client,
      ssh: (_, _) async => const SshResult(
        '5A_UI_RESULT={"phase":"queued","message":"started"}',
        'SHA256:observed',
      ),
    );
    addTearDown(app.close);
    expect((await app.handle(request())).statusCode, 403);
    final initial = await app.handle(
      request(data: {...input, 'turnstileToken': 'challenge'}),
    );
    expect(initial.statusCode, 200);
    final proof = jsonDecode(await initial.readAsString())['proofToken'];
    expect(
      (await app.handle(request(data: {...input, 'proofToken': proof})))
          .statusCode,
      200,
    );
    expect(verifies, 1);
    expect(
      (await app.handle(
        request(data: {...input, 'proofToken': proof, 'username': 'ubuntu'}),
      )).statusCode,
      403,
    );
    expect(
      (await app.handle(
        request(data: {...input, 'proofToken': '$proof-tampered'}),
      )).statusCode,
      403,
    );
  });
}
