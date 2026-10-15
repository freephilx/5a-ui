import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:test/test.dart';

void main() {
  final cases = jsonDecode(
    File('../../contracts/management-cases.json').readAsStringSync(),
  ) as List;
  for (final entry in cases) {
    test(entry['name'] as String, () {
      if (entry['error'] != null) {
        expect(
          () => validateManagement(entry['input']),
          throwsA(
            isA<AppException>().having((e) => e.code, 'code', entry['error']),
          ),
        );
      } else {
        expect(validateManagement(entry['input']), entry['expected']);
      }
    });
  }
  test(
    'management response is deliberate, regular status still strips secrets',
    () {
      final result = parseRemoteResult(
        '5A_UI_RESULT=${jsonEncode({
          'phase': 'ready',
          'message': 'ok',
          'password': 'server-secret',
          'management': {
            'result': {
              'settings': {'futureProtocolField': 1},
            },
            'revision': 'fixture',
            'session': {'cookie': 'fixture', 'csrf': 'fixture'},
            'unknown': 'discard',
          },
        })}',
      );
      expect(result.data.containsKey('password'), isFalse);
      expect(
        (result.data['management'] as Map).containsKey('unknown'),
        isFalse,
      );
      expect((result.data['management'] as Map)['result'], {
        'settings': {'futureProtocolField': 1},
      });
    },
  );
}
