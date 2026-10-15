import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:five_a_core/five_a_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

final fixture = {
  'accountId': 'a' * 32,
  'apiToken': 'synthetic-token-0000000000',
  'workerName': 'cfnew-fixture',
  'uuid': '12345678-1234-4123-8123-123456789abc',
  'step': 'prepare',
};
final namespaceId = 'b' * 32;
const code = 'export default {fetch(){return new Response("fixture")}};';

class Cloud {
  Map<String, dynamic>? settings;
  bool exists = false,
      enabled = false,
      deny = false,
      activationFails = false,
      runtimeOk = true;
  int creates = 0, uploads = 0;
  final requests = <http.Request>[];
  late final client = MockClient((r) async {
    requests.add(r);
    final input = CfnewInput.parse(fixture);
    if (r.url.host == 'raw.githubusercontent.com') {
      expect(r.headers.containsKey('authorization'), false);
      return http.Response(code, 200);
    }
    if (r.url.host.endsWith('.workers.dev')) {
      expect(r.headers.containsKey('authorization'), false);
      return http.Response(jsonEncode({'kvEnabled': runtimeOk}), 200);
    }
    expect(r.url.host, 'api.cloudflare.com');
    expect(r.headers['authorization'], 'Bearer ${fixture['apiToken']}');
    Object? value;
    if (deny) {
      return http.Response(
        '{"success":false,"errors":[{"code":9109,"message":"token secret"}]}',
        403,
      );
    }
    final path = r.url.path;
    if (path.endsWith('/settings')) {
      if (settings == null) {
        return http.Response(
          '{"success":false,"errors":[{"code":10007}]}',
          404,
        );
      }
      value = settings;
    } else if (path.endsWith('/workers/subdomain')) {
      value = {'subdomain': 'fixture'};
    } else if (path.endsWith('/storage/kv/namespaces')) {
      if (r.method == 'POST') {
        creates++;
        exists = true;
        value = {'id': namespaceId};
      } else {
        value = exists
            ? [
                {'id': namespaceId, 'title': input.namespaceTitle},
              ]
            : [];
      }
    } else if (path.endsWith('/namespaces/$namespaceId')) {
      value = {'id': namespaceId, 'title': input.namespaceTitle};
    } else if (path.endsWith('/scripts/cfnew-fixture') && r.method == 'PUT') {
      expect(r.body, contains(code));
      expect(r.body, contains('application/javascript+module'));
      expect(r.body, isNot(contains(fixture['apiToken']!)));
      settings = cfnewMetadata(input, namespaceId);
      uploads++;
      value = {};
    } else if (path.endsWith('/subdomain')) {
      if (r.method == 'POST') {
        if (activationFails) return http.Response('{"success":false}', 500);
        enabled = true;
      }
      value = {'enabled': enabled};
    } else {
      throw StateError('Unexpected ${r.method} $path');
    }
    return http.Response(jsonEncode({'success': true, 'result': value}), 200);
  });
}

void main() {
  test('shared validation and allowlist', () {
    final cases = jsonDecode(
      File('../../contracts/cfnew-cases.json').readAsStringSync(),
    ) as List;
    for (final c in cases) {
      final raw = {...fixture, ...c['patch'] as Map};
      if (c['valid'] == true) {
        final parsed = CfnewInput.parse(raw);
        expect(parsed.toJson().containsKey('sourceUrl'), false);
        expect(parsed.toJson().containsKey('password'), false);
      } else {
        expect(
          () => CfnewInput.parse(raw),
          throwsA(isA<AppException>()),
          reason: c['name'] as String,
        );
      }
    }
    expect(List.generate(20, (_) => newCfnewUuid()).toSet().length, 20);
  });
  setUp(() {
    final original = cfnewRelease['sha256'];
    cfnewRelease['sha256'] = sha256.convert(utf8.encode(code)).toString();
    addTearDown(() => cfnewRelease['sha256'] = original);
  });
  test('create, readback, activate and retry preserve resources and token boundaries', () async {
    final cloud = Cloud();
    final d = CfnewDeployer(client: cloud.client);
    addTearDown(d.dispose);
    for (var round = 0; round < 2; round++) {
      String? id;
      for (final step in cfnewSteps) {
        final result = await d.perform(
          CfnewInput.parse({...fixture, 'step': step, 'namespaceId': ?id}),
        );
        id = result['namespaceId'] as String;
        if (step == 'verify') {
          expect(result['runtimeVerified'], true);
          expect(
            result['clashUrl'],
            'https://cfnew-fixture.fixture.workers.dev/${fixture['uuid']}/sub?target=clash',
          );
        }
      }
    }
    expect(cloud.creates, 1);
    expect(cloud.uploads, 1);
  });
  test('existing worker and invalid source never allocate or upload', () async {
    final c = Cloud()..settings = {'bindings': []};
    final d = CfnewDeployer(client: c.client);
    addTearDown(d.dispose);
    await expectLater(
      d.perform(CfnewInput.parse(fixture)),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'CF_CONFLICT')),
    );
    c.settings = null;
    cfnewRelease['sha256'] = '0' * 64;
    await expectLater(
      d.perform(CfnewInput.parse(fixture)),
      throwsA(isA<AppException>().having((e) => e.code, 'code', 'CF_SOURCE')),
    );
    expect(c.creates, 0);
    expect(c.uploads, 0);
  });
  test(
    'activation failure resumes without overwriting Worker or deleting KV',
    () async {
      final c = Cloud();
      final gateway = CfnewDeployer(client: c.client);
      addTearDown(gateway.dispose);
      await gateway.perform(CfnewInput.parse(fixture));
      final raw = {...fixture, 'namespaceId': namespaceId};
      await gateway.perform(CfnewInput.parse({...raw, 'step': 'upload'}));
      c.activationFails = true;
      await expectLater(
        gateway.perform(CfnewInput.parse({...raw, 'step': 'activate'})),
        throwsA(isA<AppException>()),
      );
      c.activationFails = false;
      await gateway.perform(CfnewInput.parse({...raw, 'step': 'upload'}));
      await gateway.perform(CfnewInput.parse({...raw, 'step': 'activate'}));
      c.runtimeOk = false;
      expect(
        (await gateway.perform(
          CfnewInput.parse({...raw, 'step': 'verify'}),
        ))['runtimeVerified'],
        false,
      );
      expect(c.uploads, 1);
      expect(c.requests.any((r) => r.method == 'DELETE'), false);
    },
  );
  test(
    'permission errors do not reveal provider messages or mutate state',
    () async {
      final c = Cloud()..deny = true;
      final d = CfnewDeployer(client: c.client);
      addTearDown(d.dispose);
      await expectLater(
        d.perform(CfnewInput.parse(fixture)),
        throwsA(
          isA<AppException>()
              .having((e) => e.code, 'code', 'CF_AUTH')
              .having(
                (e) => e.message,
                'safe',
                isNot(contains('token secret')),
              ),
        ),
      );
      expect(c.creates, 0);
    },
  );
}
