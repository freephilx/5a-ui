import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_core/ssh.dart';

Future<void> main() async {
  final config = jsonDecode(await stdin.transform(utf8.decoder).join()) as Map;
  final runner = SshRunner();
  ConnectionInput input(Map auth, {String? fingerprint}) => ConnectionInput(
    host: '127.0.0.1',
    port: config['port'] as int,
    authMethod: auth['authMethod'] as String,
    password: auth['password'] as String?,
    privateKey: auth['privateKey'] as String?,
    passphrase: auth['passphrase'] as String?,
    hostFingerprint: fingerprint ?? config['fingerprint'] as String,
  );
  for (final auth in config['auths'] as List) {
    final result = await runner.run(input(auth as Map), 'ok');
    if (result.stdout != 'fixture-中文-ok' ||
        result.fingerprint != config['fingerprint']) {
      throw StateError('Invalid SSH result');
    }
    stdout.writeln('Dart SSH ${auth['label']}: passed');
  }
  Future<void> rejects(
    String expected,
    Future<Object?> Function() request,
  ) async {
    try {
      await request();
    } on AppException catch (e) {
      if (e.code != expected) {
        throw StateError('Expected $expected, got ${e.code}');
      }
      stdout.writeln('Dart SSH $expected: passed');
      return;
    }
    throw StateError('Expected $expected');
  }

  final base = config['auths'][0] as Map;
  await rejects(
    'SSH_AUTH',
    () => runner.run(input({...base, 'password': 'wrong'}), 'ok'),
  );
  await rejects(
    'HOST_KEY_CHANGED',
    () => runner.run(input(base, fingerprint: 'SHA256:${'A' * 43}'), 'ok'),
  );
  await rejects('REMOTE_OUTPUT', () => runner.run(input(base), 'large'));
  await rejects('SUDO_REQUIRED', () => runner.run(input(base), 'sudo'));
  await rejects(
    'SSH_TIMEOUT',
    () => runner.run(
      input(base),
      'hang',
      timeout: const Duration(milliseconds: 250),
    ),
  );
  await rejects('CANCELLED', () {
    final request = runner.run(input(base), 'hang');
    Timer(const Duration(milliseconds: 100), runner.cancel);
    return request;
  });
}
