import 'package:five_a_ui/screens/management_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'common fields validate and preserve unedited protocol and future fields',
    (tester) async {
      Object? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async => saved = await showManagementEditor(
                  context,
                  '编辑入站',
                  {
                    'remark': 'before',
                    'port': 8443,
                    'enable': true,
                    'total': 0,
                    'expiryTime': 0,
                    'protocol': 'vless',
                    'listen': '',
                    'futureField': {
                      'nested': [1, 2],
                    },
                    'streamSettings': {
                      'network': 'xhttp',
                      'security': 'reality',
                      'unknownTransport': true,
                    },
                  },
                  help: 'fixture',
                  kind: 'inbound',
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, '监听端口'),
        '70000',
      );
      await tester.tap(find.text('检查并继续'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      expect(find.text('端口必须为 1–65535。'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, '监听端口'),
        '9443',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '备注'), 'after');
      await tester.tap(find.text('完整 JSON'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.widgetWithText(TextField, '完整 JSON 配置'))
            .controller!
            .text,
        contains('unknownTransport'),
      );
      await tester.tap(find.text('常用字段'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查并继续'));
      await tester.pumpAndSettle();
      final result = saved as Map;
      expect(result['port'], 9443);
      expect(result['remark'], 'after');
      expect(result['futureField'], {
        'nested': [1, 2],
      });
      expect((result['streamSettings'] as Map)['unknownTransport'], true);
      expect(tester.takeException(), isNull);
    },
  );
}
