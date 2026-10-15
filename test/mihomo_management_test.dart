import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/controller.dart';
import 'package:five_a_ui/screens/management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MihomoGateway implements ServerGateway {
  final requests = <Map<String, dynamic>>[];
  final listeners = <Map<String, dynamic>>[];
  @override
  Future<String?> loadSiteKey() async => null;
  @override
  Future<ServerStatus> perform(
    ServerAction action,
    ConnectionInput input,
  ) async {
    if (action != ServerAction.manage) {
      return ServerStatus({'phase': 'ready', 'message': 'fixture'});
    }
    final r = input.management!;
    requests.add(r);
    Object? result;
    switch (r['operation']) {
      case 'catalog':
        result = {
          'version': '1.4.1',
          'operations': panelOperations
              .where((o) => o['panelType'] == '3m-ui')
              .map((o) => o['id'])
              .toList(),
        };
      case '3m.get.listeners':
        result = listeners.map((r) => Map<String, dynamic>.from(r)).toList();
      case '3m.post.listeners':
        listeners.add({...r['data'] as Map<String, dynamic>, 'id': 1});
      case '3m.get.listeners.{id}':
        result = Map<String, dynamic>.from(listeners.first);
      case '3m.put.listeners.{id}':
        listeners[0] = Map<String, dynamic>.from(r['data'] as Map);
      default:
        result = {};
    }
    return ServerStatus({
      'phase': 'ready',
      'message': 'fixture',
      'management': {
        'result': result,
        'revision': 'synthetic',
        'session': {'cookie': '', 'csrf': '', 'bearer': 'synthetic-jwt'},
      },
    });
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    testWidgets(
      '3m listener create/edit preserves string port and JSON at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = MihomoGateway();
        final controller = ServerController(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.start(
          ServerAction.status,
          const ConnectionInput(host: '8.8.8.8', password: 'synthetic'),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: ManagementScreen(
              controller: controller,
              instance: const {
                'id': 'native:3m-ui.service',
                'name': 'Synthetic Mihomo',
                'panelType': '3m-ui',
              },
            ),
          ),
        );
        await tester.enterText(
          find.widgetWithText(TextField, '面板账号'),
          'fixture',
        );
        await tester.enterText(
          find.widgetWithText(TextField, '面板密码'),
          'synthetic',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        expect(find.textContaining('3m-ui · Mihomo'), findsOneWidget);
        await tester.ensureVisible(find.text('新增 Listener'));
        await tester.tap(find.text('新增 Listener'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, '名称'),
          'Synthetic listener',
        );
        await tester.tap(find.text('检查并继续'));
        await tester.pumpAndSettle();
        expect(gateway.listeners, isEmpty);
        await tester.tap(find.text('确认执行'));
        await tester.pumpAndSettle();
        expect(gateway.listeners.single['port'], '8443');
        expect(
          jsonDecode(
            gateway.listeners.single['config'] as String,
          )['security_layer'],
          'reality',
        );
        final write = gateway.requests.firstWhere(
          (r) => r['operation'] == '3m.post.listeners',
        );
        expect((write['auth'] as Map)['session']['bearer'], 'synthetic-jwt');
        expect(gateway.requests.last['operation'], '3m.get.listeners');
        await tester.ensureVisible(find.text('Synthetic listener'));
        await tester.ensureVisible(find.text('Synthetic listener'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Synthetic listener'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextFormField, '监听端口 / 范围'),
          '19000-19010',
        );
        await tester.tap(find.text('检查并继续'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认执行'));
        await tester.pumpAndSettle();
        expect(gateway.listeners.single['port'], '19000-19010');
        expect(
          gateway.requests
              .where((r) => r['operation'] == '3m.put.listeners.{id}')
              .single['precondition'],
          isNotNull,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
