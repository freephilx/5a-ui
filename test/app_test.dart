import 'dart:async';

import 'profile_test_storage.dart';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/controller.dart';
import 'package:five_a_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGateway implements ServerGateway {
  final calls = <ConnectionInput>[];
  final actions = <ServerAction>[];
  Future<ServerStatus> Function()? response;
  @override
  Future<String?> loadSiteKey() async => null;
  @override
  Future<ServerStatus> perform(
    ServerAction action,
    ConnectionInput input,
  ) async {
    calls.add(input);
    actions.add(action);
    return response?.call() ??
        ServerStatus({'phase': 'not-installed', 'message': '尚未安装'});
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
  test('resolved username and proof are reused by refresh, deployment and management', () async {
    final gateway = FakeGateway()
      ..response = () async => ServerStatus({
        'phase': 'not-installed',
        'message': 'ok',
        'sshUsername': 'ubuntu',
        'proofToken': 'resolved-proof',
      });
    final controller = ServerController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start(
      ServerAction.status,
      const ConnectionInput(
        host: '8.8.8.8',
        username: '',
        password: 'test-only',
      ),
    );
    expect(controller.connectedUsername, 'ubuntu');
    await controller.refresh();
    expect(gateway.calls.last.username, 'ubuntu');
    expect(gateway.calls.last.proofToken, 'resolved-proof');
    await controller.start(
      ServerAction.install,
      const ConnectionInput(
        host: '8.8.8.8',
        username: 'ubuntu',
        password: 'test-only',
      ),
    );
    expect(gateway.actions.last, ServerAction.install);
    expect(gateway.calls.last.username, 'ubuntu');
    gateway.response = () async => ServerStatus({
      'phase': 'existing',
      'message': 'ok',
      'management': <String, dynamic>{'result': 'ok'},
    });
    await controller.manage({
      'instanceId': 'native:3x-ui',
      'operation': 'catalog',
    });
    expect(gateway.calls.last.username, 'ubuntu');
    expect(gateway.calls.last.proofToken, 'resolved-proof');
  });

  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets(
      'connect, validate, inspect a node, settings and clear at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FakeGateway();
        await tester.pumpWidget(
          FiveAApp(gateway: gateway, profileStorage: TestProfileStorage()),
        );
        await tester.pumpAndSettle();
        expect(find.text('从一台服务器开始'), findsOneWidget);
        await tester.ensureVisible(
          find.widgetWithText(FilledButton, '连接服务器，一键自建'),
        );
        await tester.tap(find.widgetWithText(FilledButton, '连接服务器，一键自建'));
        await tester.pumpAndSettle();
        final host = find.widgetWithText(TextField, '公网 IP');
        await tester.enterText(host, '127.0.0.1');
        await tester.enterText(
          find.widgetWithText(TextField, 'SSH 密码'),
          'test-only',
        );
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.tap(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.pumpAndSettle();
        expect(gateway.calls, isEmpty);
        expect(find.textContaining('请使用公网 IP'), findsOneWidget);
        await tester.ensureVisible(host);
        await tester.enterText(host, '8.8.8.8');
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.tap(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.pumpAndSettle();
        expect(gateway.calls.single.host, '8.8.8.8');
        expect(find.text('尚未安装'), findsOneWidget);
        gateway.response = () async => ServerStatus({
          'phase': 'ready',
          'message': '节点已就绪',
          'running': true,
          'node': {
            'host': '8.8.8.8',
            'port': 443,
            'serverName': 'www.example.com',
            'link': 'vless://test-node@8.8.8.8:443?security=reality',
          },
        });
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.tap(find.widgetWithText(FilledButton, '连接并读取'));
        await tester.pumpAndSettle();
        expect(find.text('复制节点链接'), findsOneWidget);
        await tester.ensureVisible(find.text('连接详情'));
        await tester.tap(find.text('连接详情'));
        await tester.pumpAndSettle();
        expect(find.text('www.example.com'), findsOneWidget);
        await tester.ensureVisible(find.text('清除登录凭据'));
        await tester.tap(find.text('清除登录凭据'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'SSH 密码'))
              .controller!
              .text,
          isEmpty,
        );
        await tester.tap(find.byTooltip('切换深色主题'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('切换浅色主题'), findsOneWidget);
        await tester.tap(find.text('设置'));
        await tester.pumpAndSettle();
        expect(find.text('外观'), findsOneWidget);
        await tester.tap(find.text('浅色'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('切换深色主题'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    for (final product in ['3x-ui', '3m-ui']) {
      testWidgets('inspect first, then explicitly deploy $product at $size', (
        tester,
      ) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final pending = Completer<ServerStatus>();
        final gateway = FakeGateway()..response = () => pending.future;
        await tester.pumpWidget(
          FiveAApp(gateway: gateway, profileStorage: TestProfileStorage()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '连接服务器，一键自建'));
        await tester.pumpAndSettle();
        expect(find.text('已有面板'), findsNothing);
        expect(find.text('新服务器'), findsNothing);
        expect(find.text('一键部署'), findsNothing);
        expect(find.text('3x-ui · Xray（默认）'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, '公网 IP'),
          '8.8.8.8',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'SSH 密码'),
          'synthetic',
        );
        await tester.ensureVisible(find.text('连接并读取'));
        await tester.tap(find.text('连接并读取'));
        await tester.pump();
        expect(gateway.actions, [ServerAction.status]);
        expect(find.text('正在读取服务器'), findsOneWidget);
        expect(find.textContaining('安装在服务器上后台运行'), findsNothing);
        expect(find.text('一键部署'), findsNothing);
        pending.complete(
          ServerStatus({'phase': 'not-installed', 'message': '尚未安装'}),
        );
        await tester.pumpAndSettle();
        expect(gateway.actions, [ServerAction.status]);
        expect(find.text('未发现面板'), findsOneWidget);
        expect(find.text('3x-ui · Xray（默认）'), findsOneWidget);
        if (product == '3m-ui') {
          await tester.ensureVisible(find.text('3x-ui · Xray（默认）'));
          await tester.tap(find.text('3x-ui · Xray（默认）'));
          await tester.pumpAndSettle();
          await tester.tap(find.text('3m-ui · Mihomo').last);
          await tester.pumpAndSettle();
        }
        gateway.response = () async =>
            ServerStatus({'phase': 'ready', 'message': '节点就绪'});
        await tester.ensureVisible(find.text('一键部署'));
        await tester.tap(find.text('一键部署'));
        await tester.pumpAndSettle();
        expect(gateway.actions, [ServerAction.status, ServerAction.install]);
        expect(gateway.calls.last.panelType, product);
        expect(find.text('一键部署'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }
  }
  testWidgets(
    'discovery errors, existing panels and changing servers never offer deployment',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = FakeGateway();
      await tester.pumpWidget(
        FiveAApp(gateway: gateway, profileStorage: TestProfileStorage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '连接服务器，一键自建'));
      await tester.pumpAndSettle();
      final host = find.widgetWithText(TextField, '公网 IP');
      await tester.enterText(host, '8.8.8.8');
      await tester.enterText(
        find.widgetWithText(TextField, 'SSH 密码'),
        'synthetic',
      );
      Future<void> read() async {
        await tester.ensureVisible(find.text('连接并读取'));
        await tester.tap(find.text('连接并读取'));
        await tester.pumpAndSettle();
      }

      await read();
      expect(find.text('一键部署'), findsOneWidget);
      gateway.response = () async =>
          throw const AppException('DISCOVERY_FAILED', '无法识别服务，请检查权限。');
      await read();
      expect(find.text('无法识别服务，请检查权限。'), findsOneWidget);
      expect(find.text('一键部署'), findsNothing);
      for (final phase in ['ready', 'existing']) {
        gateway.response = () async => ServerStatus({
          'phase': phase,
          'installed': true,
          'message': '已有面板',
        });
        await read();
        expect(find.text('一键部署'), findsNothing);
      }
      gateway.response = () async =>
          ServerStatus({'phase': 'failed', 'message': '上次部署未完成'});
      await read();
      expect(find.text('重试部署'), findsOneWidget);
      await tester.ensureVisible(host);
      await tester.enterText(host, '1.1.1.1');
      await tester.pumpAndSettle();
      expect(find.text('重试部署'), findsNothing);
      expect(find.text('一键部署'), findsNothing);
      expect(
        gateway.actions.every((action) => action == ServerAction.status),
        isTrue,
      );
      await tester.tap(find.byTooltip('收起侧栏'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      expect(find.text('外观'), findsOneWidget);
      await tester.tap(find.byTooltip('展开侧栏'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    testWidgets(
      'auth cards retain drafts, send only selected credentials and clear both at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = FakeGateway();
        await tester.pumpWidget(
          FiveAApp(gateway: gateway, profileStorage: TestProfileStorage()),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '连接服务器，一键自建'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '公网 IP'),
          '8.8.8.8',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'SSH 密码'),
          'synthetic-password',
        );
        await tester.ensureVisible(find.byTooltip('显示密码'));
        await tester.tap(find.byTooltip('显示密码'));
        await tester.pumpAndSettle();
        final keyChoice = find.widgetWithText(OutlinedButton, 'SSH 私钥');
        final passwordChoice = find.widgetWithText(OutlinedButton, '密码登录');
        await tester.ensureVisible(keyChoice);
        await tester.tap(keyChoice);
        await tester.pumpAndSettle();
        expect(find.widgetWithText(TextField, 'SSH 密码'), findsNothing);
        expect(find.text('选择私钥文件'), findsOneWidget);
        const syntheticKey =
            '-----BEGIN OPENSSH PRIVATE KEY-----\nsynthetic-only\n-----END OPENSSH PRIVATE KEY-----';
        await tester.enterText(
          find.widgetWithText(TextField, '或粘贴 SSH 私钥'),
          syntheticKey,
        );
        await tester.enterText(
          find.widgetWithText(TextField, '密钥口令（如有）'),
          'synthetic-passphrase',
        );
        await tester.ensureVisible(passwordChoice);
        await tester.tap(passwordChoice);
        await tester.pumpAndSettle();
        final passwordField = tester.widget<TextField>(
          find.widgetWithText(TextField, 'SSH 密码'),
        );
        expect(passwordField.controller!.text, 'synthetic-password');
        expect(passwordField.obscureText, isTrue);
        await tester.ensureVisible(keyChoice);
        await tester.tap(keyChoice);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '或粘贴 SSH 私钥'))
              .controller!
              .text,
          syntheticKey,
        );
        await tester.ensureVisible(find.text('连接并读取'));
        await tester.tap(find.text('连接并读取'));
        await tester.pumpAndSettle();
        expect(gateway.calls.last.authMethod, 'key');
        expect(gateway.calls.last.password, isNull);
        expect(gateway.calls.last.passphrase, 'synthetic-passphrase');
        await tester.ensureVisible(passwordChoice);
        await tester.tap(passwordChoice);
        await tester.pumpAndSettle();
        final pending = Completer<ServerStatus>();
        gateway.response = () => pending.future;
        await tester.ensureVisible(find.text('连接并读取'));
        await tester.tap(find.text('连接并读取'));
        await tester.pump();
        expect(tester.widget<OutlinedButton>(keyChoice).onPressed, isNull);
        expect(tester.widget<OutlinedButton>(passwordChoice).onPressed, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'SSH 命令'),
              )
              .onPressed,
          isNull,
        );
        expect(gateway.calls.last.authMethod, 'password');
        expect(gateway.calls.last.privateKey, isNull);
        expect(gateway.calls.last.passphrase, isNull);
        pending.complete(
          ServerStatus({'phase': 'not-installed', 'message': 'synthetic'}),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('清除登录凭据'));
        await tester.tap(find.text('清除登录凭据'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, 'SSH 密码'))
              .controller!
              .text,
          isEmpty,
        );
        await tester.ensureVisible(keyChoice);
        await tester.tap(keyChoice);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '或粘贴 SSH 私钥'))
              .controller!
              .text,
          isEmpty,
        );
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '密钥口令（如有）'))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  test('deployment requires a fresh inspection of the same server', () async {
    final gateway = FakeGateway();
    final controller = ServerController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    const input = ConnectionInput(host: '8.8.8.8', password: 'synthetic');
    await controller.start(ServerAction.install, input);
    expect(gateway.calls, isEmpty);
    expect(controller.error, contains('请先连接并读取服务器'));
    await controller.start(ServerAction.status, input);
    expect(controller.canDeploy, isTrue);
    await controller.start(
      ServerAction.install,
      const ConnectionInput(host: '1.1.1.1', password: 'synthetic'),
    );
    expect(gateway.actions, [ServerAction.status]);
    await controller.start(
      ServerAction.install,
      const ConnectionInput(
        host: '8.8.8.8',
        password: 'synthetic',
        nodePort: -1,
      ),
    );
    expect(controller.error, isNotNull);
    expect(controller.canDeploy, isTrue);
    gateway.response = () async =>
        throw const AppException('DISCOVERY_FAILED', '权限不足');
    await controller.refresh();
    expect(controller.canDeploy, isFalse);
    await controller.start(ServerAction.install, input);
    expect(gateway.actions, [ServerAction.status, ServerAction.status]);
    for (final data in [
      {'phase': 'existing', 'message': '无法读取已有实例'},
      {'phase': 'not-installed', 'message': 'inconsistent', 'installed': true},
      {
        'phase': 'failed',
        'message': 'inconsistent',
        'instances': [
          {'id': 'synthetic'},
        ],
      },
    ]) {
      gateway.response = () async => ServerStatus(data);
      await controller.refresh();
      expect(controller.canDeploy, isFalse);
    }
    gateway.response = () async =>
        ServerStatus({'phase': 'failed', 'message': '上次部署未完成'});
    await controller.refresh();
    expect(controller.canDeploy, isTrue);
    controller.pause();
    expect(controller.canDeploy, isFalse);
  });
  test('cancel and clear discard late results', () async {
    final pending = Completer<ServerStatus>();
    final gateway = FakeGateway()..response = () => pending.future;
    final controller = ServerController(gateway);
    addTearDown(controller.dispose);
    await controller.initialize();
    final request = controller.start(
      ServerAction.status,
      const ConnectionInput(host: '8.8.8.8', password: 'test-only'),
    );
    controller.clear();
    pending.complete(ServerStatus({'phase': 'ready', 'message': 'late'}));
    await request;
    expect(controller.status, isNull);
    expect(controller.connectedHost, isNull);
    expect(controller.busy, isFalse);
  });
  testWidgets('polling pins fingerprint and stops when ready', (tester) async {
    final gateway = FakeGateway();
    var count = 0;
    final fingerprint = 'SHA256:${'A' * 43}';
    gateway.response = () async => ServerStatus({
      'phase': switch (count++) {
        0 => 'not-installed',
        1 => 'queued',
        _ => 'ready',
      },
      'message': 'ok',
      'hostFingerprint': fingerprint,
    });
    final controller = ServerController(
      gateway,
      pollInterval: const Duration(seconds: 1),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.start(
      ServerAction.status,
      const ConnectionInput(host: '8.8.8.8', password: 'test-only'),
    );
    await controller.start(
      ServerAction.install,
      const ConnectionInput(host: '8.8.8.8', password: 'test-only'),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(gateway.calls.length, 3);
    expect(gateway.calls.last.hostFingerprint, fingerprint);
    expect(controller.polling, isFalse);
  });
}
