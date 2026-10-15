// Local SSH fixture bridge; never reads user credentials or runs remote scripts.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_core/ssh.dart';

Future<void> main() async {
  final config = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final runner = SshRunner();
  final input = ConnectionInput(
    host: '127.0.0.1',
    port: config['port'] as int,
    username: config['username'] as String,
    authMethod: config['authMethod'] as String,
    password: config['password'] as String?,
    privateKey: config['privateKey'] as String?,
    hostFingerprint: config['hostFingerprint'] as String?,
  );
  Timer? timer;
  try {
    final result = runner.run(
      input,
      'fixture-script',
      timeout: Duration(milliseconds: config['timeout'] as int),
    );
    if (config['cancelAfter'] case final int delay) {
      timer = Timer(Duration(milliseconds: delay), runner.cancel);
    }
    final value = await result;
    stdout.write(
      jsonEncode({
        'stdout': value.stdout,
        'username': value.username,
        'fingerprint': value.fingerprint,
      }),
    );
  } on AppException catch (error) {
    stdout.write(jsonEncode({'error': error.code}));
  } finally {
    timer?.cancel();
  }
}
