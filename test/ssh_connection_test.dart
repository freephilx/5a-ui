import 'dart:async';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeGateway;
import 'profile_test_storage.dart';

const key =
    '-----BEGIN OPENSSH PRIVATE KEY-----\nsynthetic-only\n-----END OPENSSH PRIVATE KEY-----\n';

Finder field(String label) => find.widgetWithText(TextField, label);
String value(WidgetTester tester, String label) =>
    tester.widget<TextField>(field(label)).controller!.text;

Future<void> tap(WidgetTester tester, String label) async {
  await tester.pumpAndSettle();
  final finder = ['密码登录', 'SSH 私钥', 'SSH 命令'].contains(label)
      ? find.widgetWithText(OutlinedButton, label)
      : find.text(label);
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> importCommand(WidgetTester tester, String command) async {
  await tap(tester, 'SSH 命令');
  expect(find.byType(AlertDialog), findsNothing);
  expect(find.text('连接并读取'), findsNothing);
  expect(find.text('自动登录'), findsNothing);
  await tester.enterText(field('SSH 命令'), command);
  await tap(tester, '解析并填入');
}

Future<void> openForm(
  WidgetTester tester,
  FakeGateway gateway,
  Future<String> Function(String) reader, {
  Size size = const Size(1280, 1000),
  TestProfileStorage? storage,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    FiveAApp(
      gateway: gateway,
      profileStorage: storage ?? TestProfileStorage(),
      privateKeyReader: reader,
    ),
  );
  await tester.pumpAndSettle();
  await tap(tester, '连接服务器，一键自建');
}

void main() {
  testWidgets(
    'automatic selection, explicit command and resolved login stay in sync',
    (tester) async {
      final gateway = FakeGateway()
        ..response = () async => ServerStatus({
          'phase': 'not-installed',
          'message': 'ok',
          'sshUsername': 'ubuntu',
          'hostFingerprint': 'SHA256:${'A' * 43}',
        });
      await openForm(tester, gateway, (_) async => key);
      expect(value(tester, '用户名'), isEmpty);
      expect(tester.widget<TextField>(field('用户名')).decoration!.hintText, '自动');
      await tester.tap(find.byTooltip('选择登录用户名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('root').last);
      await tester.pumpAndSettle();
      expect(value(tester, '用户名'), 'root');
      await tester.tap(find.byTooltip('选择登录用户名'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('自动').last);
      await tester.pumpAndSettle();
      expect(value(tester, '用户名'), isEmpty);
      await tester.enterText(field('公网 IP'), '8.8.8.8');
      await tester.enterText(field('SSH 密码'), 'test-only');
      await tap(tester, '连接并读取');
      expect(gateway.calls.single.username, isEmpty);
      expect(value(tester, '用户名'), 'ubuntu');
      await tap(tester, '连接并读取');
      expect(gateway.calls.last.username, 'ubuntu');
      await importCommand(tester, 'ssh root@8.8.8.8');
      expect(value(tester, '用户名'), 'root');
      await importCommand(tester, 'ssh 1.1.1.1');
      expect(value(tester, '用户名'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'empty commands cannot submit and clear follows available drafts',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final gateway = FakeGateway();
      await openForm(tester, gateway, (_) async => key);
      expect(find.text('清除登录凭据'), findsNothing);
      await tap(tester, 'SSH 命令');
      final parse = find.widgetWithText(FilledButton, '解析并填入');
      expect(tester.widget<FilledButton>(parse).onPressed, isNull);
      await tester.enterText(field('SSH 命令'), '   ');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(parse).onPressed, isNull);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(field('SSH 命令')).decoration!.errorText,
        isNull,
      );
      await tap(tester, '清除登录凭据');
      expect(find.text('清除登录凭据'), findsNothing);
      await tap(tester, '命令示例');
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester.getSemantics(find.widgetWithText(TextButton, '命令示例')).label,
          '命令示例',
        );
      } finally {
        semantics.dispose();
      }
      expect(find.text('ssh -p 22 ubuntu@公网IP'), findsOneWidget);
      expect(value(tester, 'SSH 命令'), isEmpty);
      await tester.enterText(field('SSH 命令'), 'ssh ubuntu@8.8.8.8');
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(parse).onPressed, isNotNull);
      await tap(tester, '密码登录');
      // A command hidden by switching modes must still be clearable.
      await tap(tester, '清除登录凭据');
      expect(find.text('清除登录凭据'), findsNothing);
      await tester.enterText(field('SSH 密码'), 'synthetic-password');
      await tap(tester, 'SSH 命令');
      expect(value(tester, 'SSH 命令'), isEmpty);
      expect(tester.widget<FilledButton>(parse).onPressed, isNull);
      await tap(tester, '清除登录凭据');
      await tap(tester, '密码登录');
      expect(value(tester, 'SSH 密码'), isEmpty);
      expect(find.text('清除登录凭据'), findsNothing);
      expect(gateway.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final size in [const Size(320, 740), const Size(1280, 1000)]) {
    testWidgets(
      'command imports key fields and resolves only on connect at $size',
      (tester) async {
        final gateway = FakeGateway();
        final reads = <String>[];
        await openForm(tester, gateway, (path) async {
          reads.add(path);
          return key;
        }, size: size);
        await tester.enterText(field('SSH 密码'), 'old-secret');
        await importCommand(
          tester,
          'ssh -i "~/synthetic key" -p 2222 ubuntu@8.8.8.8',
        );
        expect(value(tester, '公网 IP'), '8.8.8.8');
        expect(value(tester, '用户名'), 'ubuntu');
        expect(value(tester, 'SSH 端口'), '2222');
        expect(value(tester, 'SSH 私钥路径（可选）'), '~/synthetic key');
        expect(reads, isEmpty);
        expect(gateway.calls, isEmpty);
        await tap(tester, '连接并读取');
        expect(reads, ['~/synthetic key']);
        expect(gateway.calls.single.privateKey, key);
        expect(gateway.calls.single.password, isNull);
        expect(
          gateway.calls.single.toJson().toString(),
          isNot(contains('~/synthetic key')),
        );
        await importCommand(tester, 'ssh -p 2223 debian@1.1.1.1');
        expect(value(tester, 'SSH 密码'), isEmpty);
        await tester.enterText(field('SSH 密码'), 'new-password');
        await tap(tester, '连接并读取');
        expect(reads.length, 1);
        expect(gateway.calls.last.password, 'new-password');
        expect(gateway.calls.last.privateKey, isNull);
        expect(gateway.calls.last.passphrase, isNull);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'invalid command leaves draft unchanged and sshpass stays masked',
    (tester) async {
      final gateway = FakeGateway();
      await openForm(tester, gateway, (_) async => key);
      await tester.enterText(field('公网 IP'), '8.8.8.8');
      await tester.enterText(field('SSH 密码'), 'old-password');
      await tap(tester, 'SSH 命令');
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester.getSemantics(field('SSH 命令')).label,
          startsWith('SSH 命令'),
        );
      } finally {
        semantics.dispose();
      }
      await tester.enterText(field('SSH 命令'), 'ssh -Z ubuntu@1.1.1.1');
      await tap(tester, '解析并填入');
      expect(find.textContaining('暂不支持此 SSH 选项'), findsOneWidget);
      await tap(tester, '密码登录');
      expect(value(tester, '公网 IP'), '8.8.8.8');
      expect(value(tester, 'SSH 密码'), 'old-password');
      await tap(tester, 'SSH 命令');
      expect(value(tester, 'SSH 命令'), 'ssh -Z ubuntu@1.1.1.1');
      await tester.enterText(
        field('SSH 命令'),
        "sshpass -p 'synthetic password' ssh ubuntu@1.1.1.1",
      );
      await tester.pump();
      expect(tester.widget<TextField>(field('SSH 命令')).obscureText, isTrue);
      await tap(tester, 'SSH 私钥');
      await tap(tester, 'SSH 命令');
      expect(tester.widget<TextField>(field('SSH 命令')).obscureText, isTrue);
      await tap(tester, '解析并填入');
      expect(value(tester, 'SSH 密码'), 'synthetic password');
      expect(tester.widget<TextField>(field('SSH 密码')).obscureText, isTrue);
      expect(gateway.calls, isEmpty);
      await tap(tester, '清除登录凭据');
      expect(value(tester, 'SSH 密码'), isEmpty);
      await tap(tester, 'SSH 命令');
      expect(value(tester, 'SSH 命令'), isEmpty);
      await tester.enterText(
        field('SSH 命令'),
        "sshpass -p 'temporary' ssh user@8.8.8.8",
      );
      await tap(tester, '清除登录凭据');
      expect(value(tester, 'SSH 命令'), isEmpty);
      expect(tester.widget<TextField>(field('SSH 命令')).obscureText, isFalse);
      expect(gateway.calls, isEmpty);
    },
  );

  testWidgets(
    'file errors prevent requests and path/content replace each other',
    (tester) async {
      final gateway = FakeGateway();
      var fail = true;
      await openForm(tester, gateway, (_) async {
        if (fail) throw const AppException('KEY_FILE_READ', '合成文件读取失败');
        return key;
      });
      await importCommand(tester, 'ssh -i ~/synthetic ubuntu@8.8.8.8');
      await tap(tester, '连接并读取');
      expect(gateway.calls, isEmpty);
      expect(find.text('合成文件读取失败'), findsOneWidget);
      expect(find.text('合成文件读取失败').hitTestable(), findsOneWidget);
      await tester.ensureVisible(field('或粘贴 SSH 私钥'));
      await tester.enterText(field('或粘贴 SSH 私钥'), key);
      expect(value(tester, 'SSH 私钥路径（可选）'), isEmpty);
      await tester.ensureVisible(field('SSH 私钥路径（可选）'));
      await tester.enterText(field('SSH 私钥路径（可选）'), '~/new-synthetic');
      expect(value(tester, '或粘贴 SSH 私钥'), isEmpty);
      fail = false;
      await tap(tester, '连接并读取');
      expect(gateway.calls.single.privateKey, key);
    },
  );

  testWidgets(
    'clear discards pending file reads and duplicate submissions are disabled',
    (tester) async {
      final gateway = FakeGateway();
      final pending = Completer<String>();
      var reads = 0;
      await openForm(tester, gateway, (_) {
        reads++;
        return pending.future;
      });
      await importCommand(tester, 'ssh -i ~/synthetic ubuntu@8.8.8.8');
      await tap(tester, '连接并读取');
      expect(reads, 1);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '正在读取…'))
            .onPressed,
        isNull,
      );
      await tap(tester, '清除登录凭据');
      pending.complete(key);
      await tester.pumpAndSettle();
      expect(gateway.calls, isEmpty);
      expect(value(tester, 'SSH 私钥路径（可选）'), isEmpty);
      expect(value(tester, '或粘贴 SSH 私钥'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final includeCredentials in [false, true]) {
    testWidgets(
      'key paths read once on connection and save only with auto login=$includeCredentials',
      (tester) async {
        final gateway = FakeGateway();
        final storage = TestProfileStorage();
        var reads = 0;
        await openForm(tester, gateway, (_) async {
          reads++;
          return key;
        }, storage: storage);
        await importCommand(tester, 'ssh -i ~/synthetic ubuntu@8.8.8.8');
        if (!includeCredentials) await tap(tester, '自动登录');
        expect(reads, 0);
        expect(storage.value, isNull);
        await tap(tester, '连接并读取');
        expect(reads, 1);
        expect(gateway.calls.single.privateKey, key);
        if (includeCredentials) {
          expect(storage.value, isNotNull);
          expect(storage.value, isNot(contains('~/synthetic')));
          expect(storage.value, contains('synthetic-only'));
        } else {
          expect(storage.value, isNull);
        }
      },
    );
  }
}
