import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/controller.dart';
import 'package:five_a_ui/widgets/status_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_test.dart' show FakeGateway;

void main() {
  final cases = jsonDecode(
    File('contracts/status-cases.json').readAsStringSync(),
  ) as List;
  for (final size in [
    const Size(320, 740),
    const Size(390, 844),
    const Size(1280, 900),
  ]) {
    testWidgets('select existing instances and share clients at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ServerController(FakeGateway());
      addTearDown(controller.dispose);
      await controller.initialize();
      final first = cases[0]['input'] as Map<String, dynamic>;
      final second = cases[1]['input'] as Map<String, dynamic>;
      controller.status = parseStatus({
        ...first,
        'instances': [
          ...first['instances'] as List,
          ...second['instances'] as List,
        ],
      });
      final view = MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: StatusPanel(controller: controller, onConnect: () {}),
          ),
        ),
      );
      await tester.pumpWidget(view);
      await tester.pumpAndSettle();
      expect(find.text('Existing VLESS'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);
      await tester.ensureVisible(find.text('alice'));
      await tester.tap(find.text('alice'));
      await tester.pumpAndSettle();
      expect(find.text('复制节点链接'), findsOneWidget);
      expect(find.text('www.example.com'), findsOneWidget);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.ensureVisible(find.text('复制节点链接'));
      await tester.tap(find.text('复制节点链接'));
      await tester.pumpAndSettle();
      expect(copied, startsWith('vless://client-uuid@'));
      Navigator.of(tester.element(find.text('导出节点'))).pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('existing-container').last);
      await tester.pumpAndSettle();
      expect(find.text('数据库不可读'), findsOneWidget);
      expect(find.text('服务已停止'), findsOneWidget);
      expect(find.text('alice'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
