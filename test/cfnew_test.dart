import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/screens/cfnew.dart';
import 'package:five_a_ui/main.dart';

import 'profile_test_storage.dart';
import 'app_test.dart' show FakeGateway;

import 'package:five_a_ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloud implements CfnewGateway {
  final calls = <CfnewInput>[];
  bool fail = true;
  @override
  void dispose() {}
  @override
  Future<Map<String, dynamic>> perform(CfnewInput input) async {
    calls.add(input);
    if (input.step == 'upload' && fail) {
      throw const AppException('CF_AUTH', '测试：权限不足');
    }
    return {
      'step': input.step,
      'namespaceId': 'b' * 32,
      if (['activate', 'verify'].contains(input.step)) ...{
        'phase': 'deployed',
        'runtimeVerified': input.step == 'verify',
        'managementUrl': 'https://fixture.example/manage',
        'subscriptionUrl': 'https://fixture.example/sub',
        'clashUrl': 'https://fixture.example/sub?target=clash',
        'dashboardUrl': 'https://dash.cloudflare.com/example',
      },
    };
  }
}

void main() {
  testWidgets('Cloudflare draft and UUID survive navigation', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      FiveAApp(gateway: FakeGateway(), profileStorage: TestProfileStorage()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare'));
    await tester.pumpAndSettle();
    final account = find.widgetWithText(TextField, 'Cloudflare 账号 ID');
    final name = find.widgetWithText(TextField, 'Worker 名称');
    await tester.enterText(account, 'a' * 32);
    final oldName = tester.widget<TextField>(name).controller!.text;
    await tester.tap(find.text('服务器'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cloudflare'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(account).controller!.text, 'a' * 32);
    expect(tester.widget<TextField>(name).controller!.text, oldName);
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 1280.0]) {
    testWidgets(
      'cfnew validates, resumes with same UUID and displays verified result at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final cloud = FakeCloud();
        await tester.pumpWidget(
          MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              body: SingleChildScrollView(
                child: CfnewPanel(configLoaded: true, gateway: cloud),
              ),
            ),
          ),
        );
        Future<void> tap(String label) async {
          final f = find.text(label);
          await tester.ensureVisible(f);
          await tester.tap(f);
          await tester.pumpAndSettle();
        }

        await tap('一键部署 cfnew');
        expect(cloud.calls, isEmpty);
        expect(find.textContaining('账号 ID 应为'), findsOneWidget);
        await tester.enterText(
          find.widgetWithText(TextField, 'Cloudflare 账号 ID'),
          'a' * 32,
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Cloudflare API Token'),
          'synthetic-token-0000000000',
        );
        await tap('一键部署 cfnew');
        expect(cloud.calls.map((c) => c.step), ['prepare', 'upload']);
        expect(find.text('测试：权限不足'), findsOneWidget);
        final uuid = cloud.calls.first.uuid;
        cloud.fail = false;
        await tap('继续 / 重新检查部署');
        expect(cloud.calls.last.step, 'verify');
        expect(cloud.calls.every((c) => c.uuid == uuid), true);
        expect(find.text('cfnew 已就绪'), findsOneWidget);
        await tap('清除 API Token');
        expect(
          tester
              .widget<TextField>(
                find.widgetWithText(TextField, 'Cloudflare API Token'),
              )
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
