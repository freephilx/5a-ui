import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:test/test.dart';

void main() {
  final statuses = jsonDecode(
    File('../../contracts/status-cases.json').readAsStringSync(),
  ) as List;
  for (final entry in statuses) {
    test('shared status contract: ${entry['name']}', () {
      expect(parseStatus(entry['input']).toJson(), entry['expected']);
    });
  }
  final cases = jsonDecode(
    File('../../contracts/connection-cases.json').readAsStringSync(),
  ) as List;
  for (final entry in cases) {
    test('shared contract: ${entry['name']}', () {
      if (entry['error'] != null) {
        expect(
          () => validateInput(entry['input']),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', entry['error']),
          ),
        );
      } else {
        expect(validateInput(entry['input']).toJson(), entry['expected']);
      }
    });
  }
  test(
    'dispatch uses shared templates and does not persist SSH secrets',
    () async {
      final input = validateInput({
        'host': '8.8.8.8',
        'authMethod': 'password',
        'password': 'never-save-this-password',
      });
      final script = installScript(input);
      expect(script, isNot(contains(input.password!)));
      expect(
        script,
        contains('systemd-run --quiet --collect --unit=5a-ui-install'),
      );
      expect(script, isNot(contains('@@')));
      final config = RegExp(
        r"printf '%s' '([^']+)' \| base64 -d >'/var/lib/5a-ui/request.json'",
      ).firstMatch(script)!.group(1)!;
      expect(jsonDecode(utf8.decode(base64Decode(config))), {
        'host': '8.8.8.8',
        'nodePort': 443,
        'realityServerName': '',
      });
      if (!Platform.isWindows) {
        for (final value in [script, statusScript('8.8.8.8')]) {
          final process = await Process.start('/bin/bash', ['-n']);
          process.stdin.write(value);
          await process.stdin.close();
          expect(await process.exitCode, 0);
        }
      }
    },
  );
  test('result parser filters nested secrets and malformed node output', () {
    final result = parseRemoteResult(
      'password=secret\n5A_UI_RESULT={"phase":"ready","message":"ok","apiToken":"secret","traffic":{"up":1,"down":2,"token":"secret"},"node":{"port":70000,"link":"vless://abc@8.8.8.8"}}',
    );
    expect(result.toJson(), {
      'phase': 'ready',
      'message': 'ok',
      'traffic': {'up': 1, 'down': 2},
    });
    expect(
      () => parseRemoteResult('5A_UI_RESULT=null'),
      throwsA(isA<AppException>()),
    );
    expect(
      () => parseRemoteResult(
        '5A_UI_RESULT={"error":{"code":"NODE_PORT_BUSY","message":"端口被占用"}}',
      ),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'NODE_PORT_BUSY'),
      ),
    );
  });
}
