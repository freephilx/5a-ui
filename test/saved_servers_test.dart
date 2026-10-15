import 'dart:async';
import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/main.dart';
import 'package:five_a_ui/saved_servers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeGateway;
import 'profile_test_storage.dart';

const connection = ConnectionInput(
  host: '8.8.8.8',
  password: 'synthetic-password',
  privateKey: 'inactive-private-key',
  passphrase: 'inactive-passphrase',
  proofToken: 'proof-never-store',
  turnstileToken: 'captcha-never-store',
  management: {'cookie': 'session-never-store'},
);
const syntheticKey =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nsynthetic-only\n-----END OPENSSH PRIVATE KEY-----\n';

void main() {
  test('auto login roundtrips, preserves identity and disabling strips all credentials', () async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    addTearDown(saved.dispose);
    await saved.initialize();
    final profile = (await saved.save(
      input: const ConnectionInput(
        host: '8.8.8.8',
        username: '',
        authMethod: 'key',
        privateKey: syntheticKey,
        passphrase: 'synthetic-passphrase',
      ),
      name: 'My server',
      includeCredentials: true,
      autoLogin: true,
    ))!;
    final fingerprint = 'SHA256:${'A' * 43}';
    await saved.save(
      input: profile.connection.withTrust(
        resolvedUsername: 'ubuntu',
        fingerprint: fingerprint,
      ),
      name: profile.name,
      includeCredentials: true,
      autoLogin: true,
      previousId: profile.id,
    );
    await saved.initialize();
    expect(saved.servers.length, 1);
    expect(saved.selected!.id, profile.id);
    expect(saved.selected!.connection.username, 'ubuntu');
    expect(saved.selected!.autoLogin, isTrue);
    await saved.rememberFingerprint(
      profile.id,
      saved.selected!.connection,
      fingerprint,
    );
    expect(saved.selected!.autoLogin, isTrue);
    final raw = storage.value;
    storage.failWrite = true;
    expect(await saved.disableAutoLogin(profile.id), isFalse);
    expect(saved.selected!.autoLogin, isTrue);
    expect(storage.value, raw);
    storage.failWrite = false;
    expect(await saved.disableAutoLogin(profile.id), isTrue);
    await saved.initialize();
    expect(saved.selected!.id, profile.id);
    expect(saved.selected!.name, 'My server');
    expect(saved.selected!.connection.hostFingerprint, fingerprint);
    expect(saved.selected!.autoLogin, isFalse);
    expect(saved.selected!.includesCredentials, isFalse);
    expect(storage.value, isNot(contains('PRIVATE KEY')));
    expect(storage.value, isNot(contains('synthetic-passphrase')));
    await saved.remove(profile.id);
    expect(
      await saved.save(
        input: profile.connection,
        name: profile.name,
        includeCredentials: true,
        autoLogin: true,
        previousId: profile.id,
      ),
      isNull,
    );
    expect(storage.value, isNull);
  });

  test('legacy and metadata-only profiles never opt into automatic login', () {
    final record = SavedServer.create(
      id: 'legacy',
      name: 'Legacy',
      input: connection,
      includeCredentials: true,
    ).toJson()..remove('autoLogin');
    final legacy = SavedServer.fromJson(record);
    expect(legacy.autoLogin, isFalse);
    expect(legacy.connection.password, connection.password);
    expect(
      SavedServer.create(
        id: 'metadata',
        name: '',
        input: connection,
        includeCredentials: false,
        autoLogin: true,
      ).autoLogin,
      isFalse,
    );
  });

  test('automatic saved profile remembers resolved user without adding credentials', () async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    addTearDown(saved.dispose);
    await saved.initialize();
    const auto = ConnectionInput(
      host: '8.8.8.8',
      username: '',
      password: 'not-saved',
    );
    final profile = (await saved.save(
      input: auto,
      name: 'auto',
      includeCredentials: false,
    ))!;
    final fingerprint = 'SHA256:${'A' * 43}';
    await saved.rememberFingerprint(
      profile.id,
      auto,
      fingerprint,
      resolvedUsername: 'ubuntu',
    );
    expect(saved.selected!.id, profile.id);
    expect(saved.selected!.connection.username, 'ubuntu');
    expect(saved.selected!.connection.password, isNull);
    expect(saved.selected!.connection.hostFingerprint, fingerprint);
    await saved.initialize();
    expect(saved.selected!.connection.username, 'ubuntu');
    await saved.rememberFingerprint(
      profile.id,
      auto,
      fingerprint,
      resolvedUsername: 'debian',
    );
    expect(saved.selected!.connection.username, 'ubuntu');
  });

  test(
    'explicit metadata save never persists secrets, proof or sessions',
    () async {
      final storage = TestProfileStorage();
      final saved = SavedServers(storage);
      addTearDown(saved.dispose);
      await saved.initialize();
      expect(storage.writes, 0);
      await saved.save(
        input: connection,
        name: 'Test server',
        includeCredentials: false,
      );
      final raw = storage.value!;
      for (final value in [
        'synthetic-password',
        'inactive-private-key',
        'inactive-passphrase',
        'proof-never-store',
        'captcha-never-store',
        'session-never-store',
        'metadata-validation',
      ]) {
        expect(raw, isNot(contains(value)));
      }
      final restored = SavedServers(storage);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.selected!.connection.host, connection.host);
      expect(restored.selected!.connection.password, isNull);
    },
  );

  test('only active credentials survive; updating and disabling storage removes old secrets', () async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    addTearDown(saved.dispose);
    await saved.initialize();
    final first = await saved.save(
      input: connection,
      name: 'Password',
      includeCredentials: true,
    );
    expect(storage.value, contains('synthetic-password'));
    expect(storage.value, isNot(contains('inactive-private-key')));
    const keyInput = ConnectionInput(
      host: '8.8.8.8',
      authMethod: 'key',
      privateKey: syntheticKey,
      passphrase: 'synthetic-passphrase',
      password: 'inactive-password',
    );
    final second = await saved.save(
      input: keyInput,
      name: 'Key',
      includeCredentials: true,
    );
    expect(first!.id, second!.id);
    expect(saved.servers.length, 1);
    expect(storage.value, isNot(contains('synthetic-password')));
    expect(storage.value, isNot(contains('inactive-password')));
    final restored = SavedServers(storage);
    addTearDown(restored.dispose);
    await restored.initialize();
    expect(restored.selected!.connection.privateKey, syntheticKey);
    expect(restored.selected!.connection.passphrase, 'synthetic-passphrase');
    await restored.save(
      input: keyInput,
      name: 'Metadata only',
      includeCredentials: false,
    );
    expect(storage.value, isNot(contains('PRIVATE KEY')));
    expect(storage.value, isNot(contains('synthetic-passphrase')));
  });

  test(
    'serialized updates preserve both servers, default selection and deletion',
    () async {
      final storage = TestProfileStorage();
      final saved = SavedServers(storage);
      addTearDown(saved.dispose);
      await saved.initialize();
      final records = await Future.wait([
        saved.save(input: connection, name: 'First', includeCredentials: true),
        saved.save(
          input: const ConnectionInput(host: '1.1.1.1'),
          name: 'Second',
          includeCredentials: false,
        ),
      ]);
      expect(saved.servers.length, 2);
      await saved.select(records.first!.id);
      final restored = SavedServers(storage);
      addTearDown(restored.dispose);
      await restored.initialize();
      expect(restored.selected!.name, 'First');
      await restored.remove(records.first!.id);
      expect(restored.selected!.name, 'Second');
      expect(storage.value, isNot(contains('synthetic-password')));
      await restored.remove(null);
      expect(storage.value, isNull);
      expect(restored.servers, isEmpty);
    },
  );

  test('known fingerprint is retained, credentials are not silently updated and deleted records stay deleted', () async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    addTearDown(saved.dispose);
    await saved.initialize();
    final profile = (await saved.save(
      input: connection,
      name: 'Server',
      includeCredentials: false,
    ))!;
    final fingerprint = 'SHA256:${'A' * 43}';
    await saved.rememberFingerprint(profile.id, connection, fingerprint);
    expect(saved.selected!.connection.hostFingerprint, fingerprint);
    expect(storage.value, isNot(contains('synthetic-password')));
    await saved.rememberFingerprint(
      profile.id,
      connection,
      'SHA256:${'B' * 43}',
    );
    expect(saved.selected!.connection.hostFingerprint, fingerprint);
    await saved.remove(profile.id);
    await saved.rememberFingerprint(profile.id, connection, fingerprint);
    expect(storage.value, isNull);
  });

  test(
    'unreadable, corrupt or newer storage is preserved and never overwritten',
    () async {
      for (final raw in [
        'broken',
        jsonEncode({'version': 2, 'servers': []}),
      ]) {
        final storage = TestProfileStorage()..value = raw;
        final saved = SavedServers(storage);
        addTearDown(saved.dispose);
        expect(await saved.initialize(), isFalse);
        expect(
          await saved.save(
            input: connection,
            name: 'x',
            includeCredentials: false,
          ),
          isNull,
        );
        expect(storage.value, raw);
        expect(storage.writes, 0);
        storage.value = null;
        expect(await saved.initialize(), isTrue);
      }
    },
  );

  test('failed or unverified writes/deletes never report success', () async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    addTearDown(saved.dispose);
    await saved.initialize();
    storage.ignoreWrite = true;
    expect(
      await saved.save(input: connection, name: 'x', includeCredentials: true),
      isNull,
    );
    expect(saved.servers, isEmpty);
    storage.ignoreWrite = false;
    final profile = (await saved.save(
      input: connection,
      name: 'original',
      includeCredentials: true,
    ))!;
    final raw = storage.value;
    storage.failWrite = true;
    expect(
      await saved.save(
        input: connection,
        name: 'changed',
        includeCredentials: false,
      ),
      isNull,
    );
    expect(saved.selected!.name, 'original');
    expect(storage.value, raw);
    storage.failDelete = true;
    expect(await saved.remove(profile.id), isFalse);
    expect(saved.servers.length, 1);
    expect(storage.value, raw);
  });

  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    for (final enabled in [false, true]) {
      testWidgets(
        'automatic login, restart, disable and delete at $size enabled=$enabled',
        (tester) async {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final storage = TestProfileStorage();
          final gateway = FakeGateway()
            ..response = () async => ServerStatus({
              'phase': 'not-installed',
              'message': 'ok',
              'sshUsername': 'ubuntu',
              'hostFingerprint': 'SHA256:${'A' * 43}',
            });
          Future<void> tap(String text) async {
            await tester.pumpAndSettle();
            final finder = find.text(text);
            await tester.ensureVisible(finder);
            await tester.pumpAndSettle();
            await tester.tap(finder);
            await tester.pumpAndSettle();
          }

          Future<void> restart() async {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpAndSettle();
            await tester.pumpWidget(
              FiveAApp(gateway: gateway, profileStorage: storage),
            );
            await tester.pumpAndSettle();
          }

          String password() => tester
              .widget<TextField>(find.widgetWithText(TextField, 'SSH 密码'))
              .controller!
              .text;

          await restart();
          await tap('连接服务器，一键自建');
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isTrue,
          );
          expect(find.text('保存服务器'), findsNothing);
          if (!enabled) await tap('自动登录');
          await tester.enterText(
            find.widgetWithText(TextField, '公网 IP'),
            '8.8.8.8',
          );
          await tester.enterText(
            find.widgetWithText(TextField, 'SSH 密码'),
            'synthetic-password',
          );
          expect(storage.value, isNull);
          await tap('连接并读取');
          expect(gateway.calls.length, 1);
          if (!enabled) {
            expect(storage.value, isNull);
            await restart();
            expect(gateway.calls.length, 1);
            expect(find.text('连接服务器，一键自建'), findsOneWidget);
            return;
          }
          final records = jsonDecode(storage.value!)['servers'] as List;
          expect(records.single['username'], 'ubuntu');
          expect(records.single['autoLogin'], isTrue);
          final id = records.single['id'];
          await restart();
          expect(password(), 'synthetic-password');
          expect(gateway.calls.length, 2);
          expect(gateway.actions, everyElement(ServerAction.status));
          expect(gateway.calls.last.username, 'ubuntu');
          expect(gateway.calls.last.hostFingerprint, 'SHA256:${'A' * 43}');
          expect(
            (jsonDecode(storage.value!)['servers'] as List).single['id'],
            id,
          );
          await tap('自动登录');
          expect(password(), 'synthetic-password');
          expect(storage.value, isNot(contains('synthetic-password')));
          await restart();
          expect(gateway.calls.length, 2);
          expect(password(), isEmpty);
          expect(
            tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
            isFalse,
          );
          await tap('设置');
          final delete = find.byTooltip('删除 8.8.8.8');
          await tester.ensureVisible(delete);
          await tester.tap(delete);
          await tester.pumpAndSettle();
          await tap('删除');
          expect(storage.value, isNull);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('late storage read never overwrites a new connection draft', (
    tester,
  ) async {
    final storage = TestProfileStorage();
    final saved = SavedServers(storage);
    await saved.initialize();
    await saved.save(input: connection, name: 'Old', includeCredentials: true);
    saved.dispose();
    final pending = Completer<void>();
    storage.beforeRead = pending.future;
    await tester.pumpWidget(
      FiveAApp(gateway: FakeGateway(), profileStorage: storage),
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '连接服务器，一键自建'));
    await tester.pump();
    pending.complete();
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.widgetWithText(TextField, '公网 IP'))
          .controller!
          .text,
      isEmpty,
    );
  });
}
