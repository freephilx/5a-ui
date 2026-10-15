import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/services/key_file.dart';
import 'package:five_a_ui/services/key_file_web.dart' as web;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const syntheticKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nsynthetic-only\n-----END OPENSSH PRIVATE KEY-----\n';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('expands the current home, quotes and paths containing spaces', () {
    expect(
      expandPrivateKeyPath('~/.ssh/key', '/users/test'),
      '/users/test/.ssh/key',
    );
    expect(
      expandPrivateKeyPath('"~/key file"', '/users/test'),
      '/users/test/key file',
    );
    expect(expandPrivateKeyPath("'/tmp/key file'", null), '/tmp/key file');
    expect(
      expandPrivateKeyPath(r'C:\Users\test\key', null),
      r'C:\Users\test\key',
    );
    for (final path in ['', '~other/key', '/tmp/key\x00bad']) {
      expect(
        () => expandPrivateKeyPath(path, '/users/test'),
        throwsA(isA<AppException>()),
      );
    }
    expect(
      () => expandPrivateKeyPath('~/key', null),
      throwsA(isA<AppException>()),
    );
  });

  test('reads a bounded temporary file and normalizes key content', () async {
    final directory = await Directory.systemTemp.createTemp('fivea-key-test-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/synthetic key');
    await file.writeAsString(syntheticKey.replaceAll('\n', '\r\n'));
    expect(await readPrivateKeyFile('"${file.path}"'), syntheticKey);
    expect(await privateKeyInitialDirectory(file.path), directory.path);
    await file.writeAsBytes(List.filled(maxPrivateKeyBytes + 1, 65));
    await expectLater(
      readPrivateKeyFile(file.path),
      throwsA(isA<AppException>()),
    );
    await file.writeAsString('ssh-ed25519 synthetic-public-key');
    await expectLater(
      readPrivateKeyFile(file.path),
      throwsA(isA<AppException>()),
    );
    await file.writeAsBytes([255]);
    await expectLater(
      readPrivateKeyFile(file.path),
      throwsA(isA<AppException>()),
    );
    await file.writeAsBytes([]);
    await expectLater(
      readPrivateKeyFile(file.path),
      throwsA(isA<AppException>()),
    );
    await expectLater(
      readPrivateKeyFile(directory.path),
      throwsA(isA<AppException>()),
    );
    await file.delete();
    await expectLater(
      readPrivateKeyFile(file.path),
      throwsA(isA<AppException>()),
    );
  });

  test(
    'uses the real macOS home channel even for quoted tilde paths',
    () async {
      if (!Platform.isMacOS) return;
      const channel = MethodChannel('app.fivea/window');
      final directory = await Directory.systemTemp.createTemp(
        'fivea-home-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'userHomeDirectory');
            return directory.path;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await File('${directory.path}/synthetic').writeAsString(syntheticKey);
      expect(await readPrivateKeyFile('"~/synthetic"'), syntheticKey);
    },
  );

  test(
    'browser never resolves local paths and key decoding rejects other files',
    () async {
      await expectLater(
        web.readPrivateKeyFile('~/synthetic'),
        throwsA(isA<AppException>()),
      );
      expect(await web.privateKeyInitialDirectory('~/synthetic'), isNull);
      expect(decodePrivateKey(utf8.encode(syntheticKey)), syntheticKey);
      expect(
        () => decodePrivateKey(utf8.encode('not a key')),
        throwsA(isA<AppException>()),
      );
    },
  );
}
