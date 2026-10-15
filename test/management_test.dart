import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/controller.dart';
import 'package:five_a_ui/screens/management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class PanelGateway implements ServerGateway {
  final requests = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> inbounds = [];
  bool rejectNext = false;
  bool maintenanceOnly = false;
  String updateRun = 'stale-run', updateState = 'success';
  @override
  Future<String?> loadSiteKey() async => null;
  @override
  Future<ServerStatus> perform(
    ServerAction action,
    ConnectionInput input,
  ) async {
    if (action != ServerAction.manage) {
      return ServerStatus({'phase': 'ready', 'message': 'connected'});
    }
    final request = input.management!;
    requests.add(request);
    if (rejectNext) {
      rejectNext = false;
      throw const AppException('PANEL_CONFLICT', '配置已被其他会话修改');
    }
    Object? result;
    switch (request['operation']) {
      case 'catalog':
        result = {
          'operations': panelOperations
              .where(
                (op) =>
                    op['panelType'] != '3m-ui' &&
                    (!maintenanceOnly || op['group'] == 'server'),
              )
              .map((op) => op['id'])
              .toList(),
          'version': '3.10.0',
        };
      case 'get_panel_api_inbounds_list':
        result = inbounds.map((r) => Map<String, dynamic>.from(r)).toList();
      case 'post_panel_api_inbounds_add':
        inbounds.add({...request['data'] as Map<String, dynamic>, 'id': 1});
      case 'get_panel_api_inbounds_get_id':
        result = Map<String, dynamic>.from(inbounds.first);
      case 'post_panel_api_inbounds_update_id':
        inbounds[0] = Map<String, dynamic>.from(request['data'] as Map);
      case 'post_panel_api_server_updatePanel':
        result = {'runId': 'current-run'};
      case 'get_panel_api_server_getUpdateStatus':
        result = {'runId': updateRun, 'state': updateState};
      default:
        result = {};
    }
    return ServerStatus({
      'phase': 'ready',
      'message': 'ok',
      'management': {
        'result': result,
        'revision': 'revision-${requests.length}',
        'session': {'cookie': 'fixture', 'csrf': 'fixture'},
      },
    });
  }

  @override
  void cancel() {}
  @override
  void dispose() {}
}

void main() {
  testWidgets('upgrade checks its own run and never replays the mutation', (
    tester,
  ) async {
    final gateway = PanelGateway()..maintenanceOnly = true;
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
          instance: const {'id': 'native:x-ui.service', 'name': 'Fixture'},
        ),
      ),
    );
    await tester.enterText(find.widgetWithText(TextField, '面板账号'), 'fixture');
    await tester.enterText(find.widgetWithText(TextField, '面板密码'), 'synthetic');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('连接面板管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('连接面板管理'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(TextField, '搜索操作'));
    await tester.enterText(find.widgetWithText(TextField, '搜索操作'), '更新面板版本');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.widgetWithText(ListTile, '更新面板版本'));
    await tester.tap(find.widgetWithText(ListTile, '更新面板版本'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查并继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认执行'));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未读到本次升级结果'), findsOneWidget);
    gateway.updateRun = 'current-run';
    await tester.ensureVisible(find.text('刷新本次面板升级进度'));
    await tester.tap(find.text('刷新本次面板升级进度'));
    await tester.pumpAndSettle();
    expect(find.textContaining('已重新连接并确认面板版本为 3.10.0'), findsOneWidget);
    expect(
      gateway.requests.where(
        (r) => r['operation'] == 'post_panel_api_server_updatePanel',
      ),
      hasLength(1),
    );
    expect(gateway.requests.last['operation'], 'catalog');
    expect(tester.takeException(), isNull);
  });
  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    testWidgets(
      'search, status filter, group navigation and auth mode at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = PanelGateway()
          ..inbounds = [
            {
              'id': 1,
              'remark': 'Tokyo sample',
              'enable': true,
              'protocol': 'vless',
              'port': 8443,
            },
            {
              'id': 2,
              'remark': 'Backup sample',
              'enable': false,
              'protocol': 'trojan',
              'port': 9443,
            },
          ];
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
                'id': 'native:fixture.service',
                'name': 'Synthetic panel',
              },
            ),
          ),
        );
        await tester.tap(find.text('API Token'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'API token'),
          'hidden-token',
        );
        await tester.tap(find.text('账号密码'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '面板账号'),
          'fixture',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        expect(gateway.requests.first['auth'], isNot(contains('token')));
        expect(find.widgetWithText(TextField, '搜索操作'), findsNothing);
        await tester.enterText(
          find.widgetWithText(TextField, '搜索名称、协议或端口'),
          '9443',
        );
        await tester.pumpAndSettle();
        expect(find.text('Tokyo sample'), findsNothing);
        expect(find.text('Backup sample'), findsOneWidget);
        await tester.tap(find.text('已启用'));
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的项目。'), findsOneWidget);
        await tester.ensureVisible(find.text('清除筛选'));
        await tester.tap(find.text('清除筛选'));
        await tester.pumpAndSettle();
        expect(find.text('Tokyo sample'), findsOneWidget);
        await tester.ensureVisible(find.text('已停用'));
        await tester.tap(find.text('已停用'));
        await tester.pumpAndSettle();
        expect(find.text('Tokyo sample'), findsNothing);
        expect(find.text('Backup sample'), findsOneWidget);
        if (size.width >= 900) {
          await tester.tap(find.text('面板设置'));
        } else {
          final menu = find.byType(DropdownButtonFormField<String>);
          await tester.scrollUntilVisible(
            menu,
            -300,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(menu);
          await tester.pumpAndSettle();
          await tester.tap(find.text('面板设置').last);
        }
        await tester.pumpAndSettle();
        expect(find.text('查看与编辑完整配置'), findsOneWidget);
        expect(
          gateway.requests.last['operation'],
          'post_panel_api_setting_all',
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final size in [const Size(320, 740), const Size(1280, 900)]) {
    testWidgets(
      'management login, confirmed create, readback and reauthentication at $size',
      (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final gateway = PanelGateway();
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
                'id': 'native:fixture.service',
                'name': 'Fixture',
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
          'synthetic-password',
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('连接面板管理'));
        await tester.pumpAndSettle();
        expect(find.text('当前列表为空。'), findsOneWidget);
        await tester.tap(find.text('新增入站'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('完整 JSON'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, '完整 JSON 配置'),
          '{"remark":"Synthetic inbound","enable":true,"port":8443,"protocol":"vless","settings":{"clients":[],"decryption":"none"},"customFutureField":true}',
        );
        await tester.ensureVisible(find.text('检查并继续'));
        await tester.tap(find.text('检查并继续'));
        await tester.pumpAndSettle();
        expect(
          gateway.requests.where(
            (r) => r['operation'] == 'post_panel_api_inbounds_add',
          ),
          isEmpty,
        );
        await tester.tap(find.text('确认执行'));
        await tester.pumpAndSettle();
        expect(find.text('Synthetic inbound'), findsOneWidget);
        final write = gateway.requests.firstWhere(
          (r) => r['operation'] == 'post_panel_api_inbounds_add',
        );
        expect(write['confirmed'], isTrue);
        expect((write['data'] as Map)['customFutureField'], isTrue);
        expect((write['auth'] as Map).containsKey('password'), isFalse);
        expect(
          gateway.requests.last['operation'],
          'get_panel_api_inbounds_list',
        );
        await tester.tap(find.text('Synthetic inbound'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('检查并继续'));
        await tester.pumpAndSettle();
        gateway.rejectNext = true;
        await tester.tap(find.text('确认执行'));
        await tester.pumpAndSettle();
        expect(find.text('配置已被其他会话修改'), findsOneWidget);
        expect(
          gateway.requests
              .where(
                (r) => r['operation'] == 'post_panel_api_inbounds_update_id',
              )
              .length,
          1,
        );
        await tester.tap(find.byTooltip('重新认证'));
        await tester.pumpAndSettle();
        expect(find.text('连接面板管理'), findsOneWidget);
        expect(
          tester
              .widget<TextField>(find.widgetWithText(TextField, '面板密码'))
              .controller!
              .text,
          isEmpty,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
