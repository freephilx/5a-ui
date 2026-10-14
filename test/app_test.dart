import 'dart:async';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/controller.dart';
import 'package:five_a_ui/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeGateway implements ServerGateway {
  final calls = <ConnectionInput>[];
  Future<ServerStatus> Function()? response;
  @override
  Future<String?> loadSiteKey() async => null;
  @override
  Future<ServerStatus> perform(
    ServerAction action,
    ConnectionInput input,
  ) async {
    calls.add(input);
    return response?.call() ??
        ServerStatus({'phase': 'not-installed', 'message': '尚未安装'});
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
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
        await tester.pumpWidget(FiveAApp(gateway: gateway));
        await tester.pumpAndSettle();
        expect(find.text('从一台服务器开始'), findsOneWidget);
        await tester.ensureVisible(find.widgetWithText(FilledButton, '连接服务器'));
        await tester.tap(find.widgetWithText(FilledButton, '连接服务器'));
        await tester.pumpAndSettle();
        final host = find.widgetWithText(TextField, '公网 IP');
        await tester.enterText(host, '127.0.0.1');
        await tester.enterText(
          find.widgetWithText(TextField, 'SSH 密码'),
          'test-only',
        );
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, '读取状态'));
        await tester.tap(find.widgetWithText(OutlinedButton, '读取状态'));
        await tester.pumpAndSettle();
        expect(gateway.calls, isEmpty);
        expect(find.textContaining('请使用公网 IP'), findsOneWidget);
        await tester.ensureVisible(host);
        await tester.enterText(host, '8.8.8.8');
        await tester.ensureVisible(find.widgetWithText(OutlinedButton, '读取状态'));
        await tester.tap(find.widgetWithText(OutlinedButton, '读取状态'));
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
        await tester.tap(find.widgetWithText(OutlinedButton, '读取状态'));
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
      'phase': count++ == 0 ? 'queued' : 'ready',
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
      ServerAction.install,
      const ConnectionInput(host: '8.8.8.8', password: 'test-only'),
    );
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(gateway.calls.length, 2);
    expect(gateway.calls.last.hostFingerprint, fingerprint);
    expect(controller.polling, isFalse);
  });
}
