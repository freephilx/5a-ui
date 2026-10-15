import 'dart:async';
import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/main.dart';
import 'package:five_a_ui/saved_servers.dart';
import 'package:five_a_ui/screens/home.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeGateway;
import 'profile_test_storage.dart';
import 'ssh_connection_test.dart' show field, tap, value;

class DelayedConfigGateway extends FakeGateway {
  final config = Completer<String?>();
  @override
  Future<String?> loadSiteKey() => config.future;
}

Future<TestProfileStorage> savedFixture({bool autoLogin = true}) async {
  final storage = TestProfileStorage();
  final servers = SavedServers(storage);
  await servers.initialize();
  await servers.save(
    input: const ConnectionInput(
      host: '8.8.8.8',
      password: 'synthetic-password',
    ),
    name: 'Fixture',
    includeCredentials: true,
    autoLogin: autoLogin,
  );
  servers.dispose();
  return storage;
}

Future<void> mount(
  WidgetTester tester,
  FakeGateway gateway,
  TestProfileStorage storage,
) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(FiveAApp(gateway: gateway, profileStorage: storage));
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('legacy records restore without automatically connecting', (
    tester,
  ) async {
    final storage = await savedFixture(autoLogin: false);
    final raw = jsonDecode(storage.value!);
    (raw['servers'] as List).single.remove('autoLogin');
    storage.value = jsonEncode(raw);
    final gateway = FakeGateway();
    await mount(tester, gateway, storage);
    await tester.pumpAndSettle();
    expect(gateway.calls, isEmpty);
    expect(value(tester, 'SSH 密码'), 'synthetic-password');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    await tap(tester, '连接并读取');
    expect(gateway.calls.length, 1);
    expect(
      (jsonDecode(storage.value!)['servers'] as List).single['autoLogin'],
      isNull,
    );
  });

  for (final cancel in [
    'edit',
    'navigate',
    'clear',
    'switch',
    'dispose',
    'none',
  ]) {
    testWidgets('auto login waits for configuration and respects $cancel', (
      tester,
    ) async {
      final storage = await savedFixture();
      final gateway = DelayedConfigGateway();
      await mount(tester, gateway, storage);
      expect(gateway.calls, isEmpty);
      expect(find.text('自动登录'), findsOneWidget);
      switch (cancel) {
        case 'edit':
          await tester.enterText(field('SSH 密码'), 'changed');
        case 'navigate':
          await tester.tap(find.text('设置'));
        case 'clear':
          await tester.ensureVisible(find.text('清除登录凭据'));
          await tester.tap(find.text('清除登录凭据'));
        case 'switch':
          await tester.ensureVisible(find.text('自动登录'));
          await tester.tap(find.text('自动登录'));
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
      }
      await tester.pump();
      gateway.config.complete(null);
      await tester.pumpAndSettle();
      expect(gateway.calls.length, cancel == 'none' ? 1 : 0);
      if (cancel == 'none') {
        expect(gateway.actions, [ServerAction.status]);
        await tester.pump(const Duration(seconds: 20));
        expect(gateway.calls.length, 1);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'auto login waits for CAPTCHA and does not retry authentication failures',
    (tester) async {
      final storage = await savedFixture();
      final gateway = DelayedConfigGateway()
        ..response = () async => throw const AppException('SSH_AUTH', '合成认证失败');
      await mount(tester, gateway, storage);
      gateway.config.complete('synthetic-site-key');
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
      final controller = tester
          .widget<HomeScreen>(find.byType(HomeScreen))
          .controller;
      controller.setToken('synthetic-human-token');
      await tester.pumpAndSettle();
      expect(gateway.calls.single.turnstileToken, 'synthetic-human-token');
      expect(find.text('合成认证失败'), findsOneWidget);
      final writes = storage.writes;
      controller.setToken('another-token');
      await tester.pumpAndSettle();
      expect(gateway.calls.length, 1);
      expect(storage.writes, writes);
    },
  );

  for (final failure in [
    'validation',
    'authentication',
    'cancelled',
    'storage',
  ]) {
    testWidgets('$failure never reports a successful credential save', (
      tester,
    ) async {
      final storage = TestProfileStorage();
      final pending = Completer<ServerStatus>();
      final gateway = FakeGateway();
      if (failure == 'authentication') {
        gateway.response = () async =>
            throw const AppException('SSH_AUTH', '合成认证失败');
      }
      if (failure == 'cancelled') gateway.response = () => pending.future;
      await mount(tester, gateway, storage);
      await tester.pumpAndSettle();
      await tap(tester, '连接服务器，一键自建');
      await tester.enterText(field('公网 IP'), '8.8.8.8');
      if (failure != 'validation') {
        await tester.enterText(field('SSH 密码'), 'synthetic-password');
      }
      if (failure == 'storage') storage.failWrite = true;
      if (failure == 'cancelled') {
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('连接并读取'));
        await tester.tap(find.text('连接并读取'));
        await tester.pump();
        await tester.ensureVisible(find.text('清除登录凭据'));
        await tester.tap(find.text('清除登录凭据'));
        pending.complete(
          ServerStatus({'phase': 'not-installed', 'message': 'ok'}),
        );
        await tester.pumpAndSettle();
      } else {
        await tap(tester, '连接并读取');
      }
      expect(storage.value, isNull);
      if (failure == 'storage') {
        expect(find.textContaining('保存未能确认'), findsOneWidget);
        expect(find.text('已保存的服务器'), findsNothing);
        expect(
          tester.widget<HomeScreen>(find.byType(HomeScreen)).controller.status,
          isNotNull,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed disable keeps the switch on and credentials intact', (
    tester,
  ) async {
    final storage = await savedFixture();
    await mount(tester, FakeGateway(), storage);
    await tester.pumpAndSettle();
    storage.failWrite = true;
    await tap(tester, '自动登录');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );
    expect(find.textContaining('关闭自动登录未能确认'), findsOneWidget);
    expect(storage.value, contains('synthetic-password'));
    storage.failWrite = false;
    await tap(tester, '自动登录');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(storage.value, isNot(contains('synthetic-password')));
    expect(value(tester, 'SSH 密码'), 'synthetic-password');
  });
}
