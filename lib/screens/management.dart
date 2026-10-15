import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controller.dart';
import '../services/export.dart';
import '../widgets/ui.dart';
import 'management_labels.dart';
import 'management_editor.dart';

const _pretty = JsonEncoder.withIndent('  ');
const _groups = {
  '3m-listeners': 'Listener 入站',
  '3m-users': '用户与配额',
  '3m-config': 'Mihomo 配置',
  '3m-mihomo': '核心与日志',
  '3m-system': '备份与维护',
  '3m-panel-settings': '面板设置',
  '3m-auth': '账号与安全',
  '3m-traffic': '流量与连接',
  '3m-cluster': '集群',
  '3m-telegram': 'Telegram',
  '3m-nodes': '节点与分享',
  '3m-access-tokens': '订阅访问令牌',
  '3m-dashboard': '仪表盘',
  '3m-capabilities': '协议能力',
  'inbounds': '入站',
  'clients': '客户端',
  'xray': '出站 / 路由 / DNS',
  'setting': '面板设置',
  'server': '日志与维护',
  'nodes': '远程节点',
  'hosts': '分享地址',
  'sub-balancers': '订阅平衡',
  'backuptotgbot': '通知备份',
};

class ManagementScreen extends StatefulWidget {
  const ManagementScreen({
    super.key,
    required this.controller,
    required this.instance,
  });
  final ServerController controller;
  final Map<String, dynamic> instance;
  @override
  State<ManagementScreen> createState() => _ManagementScreenState();
}

class _ManagementScreenState extends State<ManagementScreen> {
  final _scroll = ScrollController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _token = TextEditingController();
  final _otp = TextEditingController();
  final _port = TextEditingController(text: '2053');
  final _path = TextEditingController(text: '/');
  final _domain = TextEditingController();
  final _resourceSearch = TextEditingController();
  bool _manualEndpoint = false, _https = false, _useToken = false;
  String _resourceFilter = 'all';
  Map<String, dynamic> _auth = {};
  Set<String>? _available;
  Map<String, dynamic> _unavailable = {};
  String _version = '';
  bool _modernApi = true;
  String _group = 'inbounds', _search = '';
  String? _error, _notice;
  bool _busy = false, _restoreKeepsHostSettings = false;
  Object? _data;
  Map<String, dynamic>? _snapshot;
  String? _readOperation;
  String? _panelUpdateRun;

  @override
  void initState() {
    super.initState();
    if (_mihomo) _port.text = '8080';
  }

  bool get _mihomo => widget.instance['panelType'] == '3m-ui';

  Future<void> _editThreeM([Map<String, dynamic>? row]) async {
    final listener = _group == '3m-listeners';
    final path = listener ? '/listeners' : '/users';
    Map<String, dynamic>? before;
    Object? value = listener
        ? {
            'name': '',
            'protocol': 'vless',
            'type': 'vless',
            'port': '8443',
            'bind_address': '0.0.0.0',
            'enabled': true,
            'config': {
              'security_layer': 'reality',
              'transport_layer': 'raw',
              'flow': 'xtls-rprx-vision',
              'reality-config': {
                'dest': 'www.microsoft.com:443',
                'server-names': ['www.microsoft.com'],
              },
            },
            'client_fingerprint': 'chrome',
          }
        : {
            'username': '',
            'enabled': true,
            'traffic_limit': 0,
            'expire_time': '0001-01-01T00:00:00Z',
          };
    if (row != null) {
      await _run(() async {
        before = await _call(
          _id('GET', '$path/{id}'),
          parameters: {'id': row['id']},
        );
      });
      if (before == null) return;
      final original = Map<String, dynamic>.from(before!['result'] as Map);
      if (listener) {
        value = original..['config'] = _decodeJson(original['config']);
      } else {
        final fields =
            (panelOperations.firstWhere(
                      (op) =>
                          op['panelType'] == '3m-ui' &&
                          op['method'] == 'PUT' &&
                          op['path'] == '/users/{id}',
                    )['body']
                    as Map)['properties']
                as Map;
        // SafeUser masks credentials. Never write a masked UUID/password back.
        value = {
          for (final key in fields.keys)
            if (original.containsKey(key)) '$key': original[key],
        };
      }
    }
    if (!mounted) return;
    final edited = await showManagementEditor(
      context,
      '${row == null ? '新增' : '编辑'}${listener ? 'Listener' : '用户'}',
      value,
      kind: listener ? '3m-listener' : '3m-user',
      help: listener
          ? '端口为字符串，支持上游允许的端口范围。config 保留完整协议、传输、TLS / REALITY 参数，缺少密钥时由面板生成。保存后使用“应用并检查 Mihomo”确认运行。'
          : 'traffic_limit 为字节，expire_time 为 ISO 日期，0001-01-01T00:00:00Z 表示不限。已有密码和 UUID 不回填，省略则保留；新增后需关联 Listener。',
    );
    if (edited is! Map || !mounted) return;
    final data = Map<String, dynamic>.from(edited);
    if (listener && data['config'] is! String) {
      data['config'] = jsonEncode(data['config']);
    }
    await _write(
      row == null ? path : '$path/{id}',
      method: row == null ? 'POST' : 'PUT',
      parameters: row == null ? {} : {'id': row['id']},
      data: data,
      before: before,
      readOperation: _id('GET', '$path/{id}'),
    );
  }

  Widget _shareResult(Object? result) {
    final links = <String>{};
    void collect(Object? value) {
      if (value is String &&
          RegExp(
            r'^(?:https?|vless|vmess|ss|trojan|hysteria2|hy2|tuic|snell)://',
          ).hasMatch(value) &&
          !value.contains('\n')) {
        links.add(value);
      } else if (value is List) {
        for (final entry in value) {
          collect(entry);
        }
      } else if (value is Map) {
        for (final entry in value.values) {
          collect(entry);
        }
      }
    }

    collect(result);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final link in links) ...[
          if (link.length <= 2000)
            Center(
              child: QrImageView(
                data: link,
                size: 170,
                backgroundColor: Colors.white,
              ),
            ),
          SelectableText(link),
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(text: link)),
                icon: const Icon(Icons.copy),
                label: const Text('复制链接'),
              ),
              TextButton.icon(
                onPressed: () => saveNode(link),
                icon: const Icon(Icons.download),
                label: const Text('导出'),
              ),
            ],
          ),
        ],
        ExpansionTile(
          title: const Text('完整分享结果 / 客户端配置'),
          children: [SelectableText(_pretty.convert(result))],
        ),
      ],
    );
  }

  Future<void> _applyMihomo() async {
    if (!await _confirm('应用并检查 Mihomo', '将面板保存的配置应用到当前实例核心。') || !mounted) {
      return;
    }
    await _run(() async {
      final generated = (await _call(_id('GET', '/config')))['result'] as Map;
      final data = {'config': generated['config']};
      await _call(_id('POST', '/config/validate'), data: data, confirmed: true);
      await _call(_id('POST', '/config/apply'), data: data, confirmed: true);
      final runtime = (await _call(
        _id('GET', '/listeners/runtime-status'),
      ))['result'];
      final core = (await _call(_id('GET', '/mihomo/status')))['result'];
      await _load();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('配置已应用 · 运行检查'),
          content: SingleChildScrollView(
            child: SelectableText(
              _pretty.convert({'core': core, 'listeners': runtime}),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    });
  }

  Widget _threeMRow(Map<String, dynamic> item) {
    final listener = _group == '3m-listeners';
    final path = listener ? '/listeners' : '/users';
    final name = '${item[listener ? 'name' : 'username']}';
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        title: _itemTitle(name, item['enabled'] == true),
        subtitle: Text(
          listener
              ? "${'${item['protocol']}'.toUpperCase()} · 端口 ${item['port']} · #${item['id']}"
              : '已用 ${formatBytes(item['traffic_used'])} · 配额 ${_quota(item['traffic_limit'])}\n到期 ${_expiryLabel(item['expire_time'])}',
        ),
        onTap: _busy ? null : () => _editThreeM(item),
        trailing: PopupMenuButton<String>(
          tooltip: '更多操作',
          enabled: !_busy,
          onSelected: (action) async {
            if (action == 'share') {
              await _advanced(
                panelOperations.firstWhere(
                  (op) =>
                      op['panelType'] == '3m-ui' &&
                      op['method'] == 'GET' &&
                      op['path'] ==
                          (listener
                              ? '/nodes/{id}/uri'
                              : '/users/{id}/subscription'),
                ),
                preset: {'id': item['id']},
              );
            } else if (action == 'bind') {
              await _advanced(
                panelOperations.firstWhere(
                  (op) =>
                      op['panelType'] == '3m-ui' &&
                      op['method'] == 'POST' &&
                      op['path'] == '/users/{id}/listeners',
                ),
                preset: {'id': item['id']},
              );
            } else if (action == 'delete') {
              await _write(
                '$path/{id}',
                method: 'DELETE',
                parameters: {'id': item['id']},
                title: '删除 $name',
              );
            } else {
              Map<String, dynamic>? before;
              await _run(() async {
                before = await _call(
                  _id('GET', '$path/{id}'),
                  parameters: {'id': item['id']},
                );
              });
              if (before == null) return;
              final current = before!['result'] as Map;
              await _write(
                '$path/{id}',
                method: 'PUT',
                parameters: {'id': item['id']},
                data: {
                  if (listener) ...Map<String, dynamic>.from(current),
                  'enabled': current['enabled'] != true,
                },
                before: before,
                readOperation: _id('GET', '$path/{id}'),
              );
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(item['enabled'] == true ? '停用' : '启用'),
            ),
            const PopupMenuItem(value: 'share', child: Text('分享与订阅')),
            if (!listener)
              const PopupMenuItem(value: 'bind', child: Text('关联 Listener')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  String _id(String method, String path) =>
      panelOperations.firstWhere(
            (op) =>
                op['method'] == method &&
                op['path'] == path &&
                (op['panelType'] ?? '3x-ui') == (_mihomo ? '3m-ui' : '3x-ui'),
          )['id']
          as String;

  Future<Map<String, dynamic>> _call(
    String operation, {
    Map<String, dynamic> parameters = const {},
    Object? data,
    bool confirmed = false,
    Map<String, dynamic>? precondition,
  }) async {
    final response = await widget.controller.manage({
      'instanceId': widget.instance['id'],
      'operation': operation,
      'auth': _auth,
      if (_manualEndpoint)
        'endpoint': {
          'port': int.tryParse(_port.text),
          'path': _path.text,
          'https': _https,
          if (_domain.text.isNotEmpty) 'domain': _domain.text.trim(),
        },
      'parameters': parameters,
      'data': ?data,
      if (confirmed) 'confirmed': true,
      'precondition': ?precondition,
    });
    if (!mounted) throw const AppException('CANCELLED', '管理页面已关闭。');
    if (response['session'] is Map) {
      _auth = {
        'session': Map<String, dynamic>.from(response['session'] as Map),
      };
    }
    return response;
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) {
        setState(
          () => _error = e is AppException ? e.message : '操作未完成，请重新读取确认当前状态。',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_error != null || _notice != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) {
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      }
    }
  }

  Future<void> _login() => _run(() async {
    _auth = _useToken
        ? {'token': _token.text.trim()}
        : {
            'username': _username.text,
            'password': _password.text,
            'twoFactorCode': _otp.text,
          };
    final response = await _call('catalog');
    if (!mounted) return;
    final catalog = response['result'] as Map;
    _unavailable = Map<String, dynamic>.from(
      catalog['unavailable'] as Map? ?? {},
    );
    _version = '${catalog['version'] ?? ''}';
    _modernApi = catalog['tokenScopes'] != false;
    _restoreKeepsHostSettings = catalog['restoreKeepsHostSettings'] == true;
    setState(
      () => _available = (catalog['operations'] as List).cast<String>().toSet(),
    );
    if (_mihomo) {
      _group = catalog['mustChangePassword'] == true
          ? '3m-auth'
          : '3m-listeners';
    }
    if (catalog['mustChangePassword'] == true) {
      _notice = '此管理员必须先修改初始密码。请执行修改密码，然后重新认证。';
    }
    final groups = panelOperations
        .where((op) => _available!.contains(op['id']))
        .map((op) => op['group'] as String)
        .toSet();
    if (!groups.contains(_group) && groups.isNotEmpty) _group = groups.first;
    if (catalog['capabilitySource'] == 'restricted') {
      _notice = '当前 token 无权读取完整接口清单，仅提供运行状态。管理配置请使用已有管理账号或 admin token。';
    }
    _password.clear();
    _token.clear();
    _otp.clear();
    await _load();
    if (_scroll.hasClients) _scroll.jumpTo(0);
  });

  Future<void> _load() async {
    final path = switch (_group) {
      '3m-listeners' => '/listeners',
      '3m-users' => '/users',
      '3m-config' => '/config/visual',
      '3m-panel-settings' => '/panel-settings',
      'inbounds' => '/inbounds/list',
      'clients' => '/clients/list',
      'setting' => '/setting/all',
      'xray' => '/xray/',
      _ => null,
    };
    if (path == null) {
      setState(() {
        _data = null;
        _snapshot = null;
      });
      return;
    }
    final method = {'setting', 'xray'}.contains(_group) ? 'POST' : 'GET';
    final op = _id(method, path);
    final response = await _call(op);
    if (!mounted) return;
    setState(() {
      _data = response['result'];
      _snapshot = response;
      _readOperation = op;
    });
  }

  Future<bool> _confirm(String title, Object? data) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('目标实例：${widget.instance['name']}'),
                  const SizedBox(height: 12),
                  const Text('确认后会修改此实例。重启、恢复和版本切换可能中断该实例的连接。'),
                  if (data != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(_pretty.convert(data)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认执行'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _write(
    String path, {
    String method = 'POST',
    Map<String, dynamic> parameters = const {},
    Object? data,
    Map<String, dynamic>? before,
    String? readOperation,
    Map<String, dynamic>? readParameters,
    String title = '确认修改',
  }) async {
    if (!await _confirm(title, data) || !mounted) return;
    await _run(() async {
      await _call(
        _id(method, path),
        parameters: parameters,
        data: data,
        confirmed: true,
        precondition: before == null
            ? null
            : {
                'operation': readOperation,
                'parameters': readParameters ?? parameters,
                'revision': before['revision'],
              },
      );
      await _load();
      if (mounted) {
        setState(
          () => _notice = _mihomo
              ? '保存请求已接受，已重新读取。请应用并检查 Mihomo 以确认运行状态。'
              : '请求已接受，当前列表 / 配置已重新读取。',
        );
      }
    });
  }

  Future<void> _editInbound([Map<String, dynamic>? row]) async {
    Map<String, dynamic>? before;
    var value = <String, dynamic>{
      'remark': '',
      'enable': true,
      'listen': '',
      'port': 8443,
      'protocol': 'vless',
      'total': 0,
      'expiryTime': 0,
      'settings': {'clients': [], 'decryption': 'none'},
      'streamSettings': {'network': 'tcp', 'security': 'none'},
      'sniffing': {
        'enabled': true,
        'destOverride': ['http', 'tls'],
      },
    };
    if (row != null) {
      await _run(() async {
        before = await _call(
          _id('GET', '/inbounds/get/{id}'),
          parameters: {'id': row['id']},
        );
      });
      if (before == null) return;
      value = Map<String, dynamic>.from(before!['result'] as Map);
      for (final key in [
        'settings',
        'streamSettings',
        'sniffing',
        'allocate',
      ]) {
        if (value[key] is String && (value[key] as String).isNotEmpty) {
          try {
            value[key] = jsonDecode(value[key] as String);
          } catch (_) {
            /* Preserve unknown representations. */
          }
        }
      }
    }
    if (!mounted) return;
    final edited = await showManagementEditor(
      context,
      row == null ? '新增入站' : '编辑入站',
      value,
      kind: 'inbound',
      help: 'total 为字节，expiryTime 为毫秒时间戳（0 不限）。完整协议、传输、TLS / REALITY 和嗅探参数均保留在 JSON 中。',
    );
    if (edited == null || !mounted) return;
    await _write(
      row == null ? '/inbounds/add' : '/inbounds/update/{id}',
      parameters: row == null ? {} : {'id': row['id']},
      data: edited,
      before: before,
      readOperation: _id('GET', '/inbounds/get/{id}'),
    );
  }

  Future<void> _editClient([Map<String, dynamic>? row]) async {
    Map<String, dynamic>? before;
    Object value = {
      'client': {'email': '', 'enable': true, 'totalGB': 0, 'expiryTime': 0},
      'inboundIds': <int>[],
    };
    if (row != null) {
      await _run(() async {
        before = await _call(
          _id('GET', '/clients/get/{email}'),
          parameters: {'email': row['email']},
        );
      });
      if (before == null) return;
      final payload = before!['result'] as Map;
      final client = Map<String, dynamic>.from(payload['client'] as Map);
      client['id'] = client.remove('uuid') ?? '';
      if (client['reverse'] is String) {
        client['reverse'] = (client['reverse'] as String).isEmpty
            ? null
            : _decodeJson(client['reverse']);
      }
      if (client['allowedIPs'] is String) {
        client['allowedIPs'] = (client['allowedIPs'] as String)
            .split(',')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (payload['tunnelAllowedIPs'] is Map) {
        client['allowedIPsByInbound'] = (payload['tunnelAllowedIPs'] as Map)
            .map(
              (k, v) => MapEntry(
                '$k',
                '$v'
                    .split(',')
                    .map((s) => s.trim())
                    .where((s) => s.isNotEmpty)
                    .toList(),
              ),
            );
      }
      for (final k in ['createdAt', 'updatedAt']) {
        client.remove(k);
      }
      value = client;
    }
    if (!mounted) return;
    final edited = await showManagementEditor(
      context,
      row == null ? '新增客户端' : '编辑客户端',
      value,
      kind: 'client',
      help: 'totalGB 使用字节单位；expiryTime 为毫秒时间戳，0 不限、负数为首次使用后的时长。新增时选择 inboundIds；未填写的协议密钥由面板生成。',
    );
    if (edited == null || !mounted) return;
    await _write(
      row == null ? '/clients/add' : '/clients/update/{email}',
      data: edited,
      parameters: row == null ? {} : {'email': row['email']},
      before: before,
      readOperation: _id('GET', '/clients/get/{email}'),
    );
  }

  Future<void> _editSettings() async {
    final snapshot = _snapshot;
    final readOperation = _readOperation;
    if (snapshot == null) return;
    dynamic value = _data;
    Map<String, dynamic>? wrapper;
    if (_group == 'xray') {
      final decoded = _decodeJson(value);
      if (decoded is! Map) {
        setState(() => _error = '面板返回的 Xray 配置格式无法识别，请重新读取或检查面板版本。');
        return;
      }
      wrapper = Map<String, dynamic>.from(decoded);
      value = _decodeJson(wrapper['xraySetting']);
      if (value is! Map) {
        setState(() => _error = '面板未返回完整 Xray 模板，无法安全编辑。');
        return;
      }
    }
    final edited = await showManagementEditor(
      context,
      _groups[_group]!,
      value,
      help: _group == 'xray'
          ? '编辑完整 Xray 模板中的 outbounds、routing、dns 等字段。保存会由面板校验并应用。'
          : '保留未修改字段。面板隐藏的密钥留空表示保持原值；清除密钥需使用对应 clear 字段。部分设置需要重启面板后生效。',
    );
    if (edited == null || !mounted) return;
    await _write(
      _mihomo
          ? (_group == '3m-config' ? '/config/visual' : '/panel-settings')
          : (_group == 'xray' ? '/xray/update' : '/setting/update'),
      method: _group == '3m-panel-settings' ? 'PUT' : 'POST',
      data: wrapper == null
          ? edited
          : {
              'xraySetting': edited,
              'outboundTestUrl': wrapper['outboundTestUrl'] ?? '',
            },
      before: snapshot,
      readOperation: readOperation,
    );
  }

  Future<void> _advanced(
    Map<String, dynamic> op, {
    Map<String, dynamic> preset = const {},
  }) async {
    if (!_modernApi && op['legacy'] is Map) {
      op = {...op, ...Map<String, dynamic>.from(op['legacy'] as Map)};
    }
    if (op['path'] == '/server/installXray/{version}') {
      await _switchXray();
      return;
    }
    final parameters = <String, dynamic>{};
    for (final p in op['parameters'] as List) {
      final s = p['schema'] as Map? ?? {};
      parameters[p['name'] as String] =
          s['default'] ??
          (s['type'] == 'integer' ? (p['name'] == 'count' ? 50 : 1) : '');
    }
    parameters.addAll(preset);
    Object? data = {};
    if (op['encoding'] == 'multipart/form-data') {
      final files = await FilePicker.platform.pickFiles(withData: true);
      final bytes = files?.files.single.bytes;
      if (bytes == null) return;
      if (bytes.length > 2 * 1024 * 1024) {
        setState(() => _error = '备份最大支持 2 MiB。');
        return;
      }
      data = {
        _mihomo ? 'database' : 'db': base64Encode(bytes),
        'keepHostSettings': _restoreKeepsHostSettings,
      };
    } else if (op['write'] == true ||
        (op['parameters'] as List).any((p) => !preset.containsKey(p['name']))) {
      if (!mounted) return;
      final body = op['body'] as Map;
      final edited = await showManagementEditor(
        context,
        managementLabel(op),
        {'parameters': parameters, 'data': _defaults(body)},
        help:
            '${!_modernApi && op['path'] == '/setting/apiTokens/create' ? '此版本只支持具有全部管理权限、不会自动过期的 token。\n' : ''}参数格式由当前兼容版本的面板接口决定。字段定义：\n${_pretty.convert(body)}',
      );
      if (edited == null || !mounted) return;
      if (edited is! Map || edited['parameters'] is! Map) {
        setState(() => _error = 'parameters 必须为对象。');
        return;
      }
      parameters
        ..clear()
        ..addAll(Map<String, dynamic>.from(edited['parameters'] as Map));
      data = edited['data'];
    }
    if (op['write'] == true &&
        (!mounted ||
            !await _confirm(
              managementLabel(op),
              op['encoding'] == 'multipart/form-data'
                  ? {
                      '恢复备份并重启当前实例': true,
                      '保留主机设置': _restoreKeepsHostSettings,
                      if (!_restoreKeepsHostSettings)
                        '旧版恢复限制': '将全量恢复，包括账号、访问路径与监听配置。请确认备份属于当前实例。',
                    }
                  : data,
            ))) {
      return;
    }
    await _run(() async {
      final response = await _call(
        op['id'] as String,
        parameters: parameters,
        data: data,
        confirmed: op['write'] == true,
      );
      if (!mounted) return;
      final result = response['result'];
      if (_mihomo && op['path'] == '/auth/password') {
        _available = null;
        _auth.clear();
        _notice = '密码已修改，请使用新密码重新认证。';
        return;
      }
      if (op['path'] == '/server/updatePanel' &&
          result is Map &&
          result['runId'] is String) {
        setState(() => _panelUpdateRun = result['runId'] as String);
        await _readPanelUpdate();
        return;
      }
      if (result is Map && result['reauthenticate'] == true) {
        setState(() {
          _auth.clear();
          _available = null;
          _data = null;
          _snapshot = null;
          _notice = '恢复已返回并重启实例，请使用恢复后的账号重新认证、回读验证。';
        });
        return;
      }
      if (result is Map && result['file'] is String) {
        await saveData(
          base64Decode(result['file'] as String),
          result['name'] as String? ?? '3x-ui-backup.db',
        );
      } else {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(op['write'] == true ? '面板已接受请求' : '读取结果'),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child:
                    _mihomo &&
                        (op['path'].endsWith('/uri') ||
                            op['path'].endsWith('/subscription'))
                    ? _shareResult(result)
                    : SelectableText(_pretty.convert(result)),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      }
      if (mounted && op['write'] == true) await _load();
    });
  }

  Future<void> _readPanelUpdate() async {
    final response = await _call(_id('GET', '/server/getUpdateStatus'));
    final result = response['result'];
    if (result is! Map || result['runId'] != _panelUpdateRun) {
      setState(() => _notice = '尚未读到本次升级结果，请稍后刷新进度。不会重复发起升级。');
      return;
    }
    if (result['state'] == 'failed') {
      setState(() {
        _panelUpdateRun = null;
        _error = '面板升级失败（退出码 ${result['exitCode']}）。请查看面板日志并重新读取状态后再决定。';
      });
    } else if (result['state'] == 'success') {
      final catalog = (await _call('catalog'))['result'] as Map;
      setState(() {
        _version = '${catalog['version']}';
        _available = (catalog['operations'] as List).cast<String>().toSet();
        _unavailable = Map<String, dynamic>.from(
          catalog['unavailable'] as Map? ?? {},
        );
        _modernApi = catalog['tokenScopes'] != false;
        _restoreKeepsHostSettings = catalog['restoreKeepsHostSettings'] == true;
        _panelUpdateRun = null;
        _notice = '本次升级已完成，已重新连接并确认面板版本为 $_version。';
      });
    } else {
      setState(() => _notice = '面板正在后台升级，可稍后刷新进度。连接中断时请重新认证，勿重复发起升级。');
    }
  }

  Future<void> _switchXray() async {
    List<String>? versions;
    await _run(() async {
      final response = await _call(_id('GET', '/server/getXrayVersion'));
      versions = (response['result'] as List).whereType<String>().toList();
    });
    if (!mounted || versions == null || versions!.isEmpty) return;
    var selected = versions!.first;
    final target = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换 Xray 版本'),
        content: SizedBox(
          width: 440,
          child: DropdownButtonFormField<String>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '面板提供的发布版本'),
            items: [
              for (final version in versions!)
                DropdownMenuItem(value: version, child: Text(version)),
            ],
            onChanged: (value) => selected = value!,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, selected),
            child: const Text('检查并继续'),
          ),
        ],
      ),
    );
    if (target == null ||
        !mounted ||
        !await _confirm('切换 Xray 版本', {'version': target})) {
      return;
    }
    await _run(() async {
      await _call(
        _id('POST', '/server/installXray/{version}'),
        parameters: {'version': target},
        confirmed: true,
      );
      for (var attempt = 0; attempt < 5; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        final status = await _call(_id('GET', '/server/status'));
        final data = status['result'] as Map;
        final version = '${(data['xray'] as Map?)?['version'] ?? ''}';
        if (version.replaceFirst(RegExp('^v'), '') ==
            target.replaceFirst(RegExp('^v'), '')) {
          setState(() => _notice = '已回读确认 Xray 版本为 $version。');
          return;
        }
      }
      if (mounted) {
        setState(() => _notice = '版本切换请求已接受，尚未确认生效。请读取运行状态后再决定是否重试。');
      }
    });
  }

  Future<void> _service(String action) async {
    if (!await _confirm('服务 $action', null) || !mounted) return;
    await _run(() async {
      await _call('service.$action', confirmed: true);
      await widget.controller.refresh();
      if (mounted) setState(() => _notice = '服务操作已返回，已重新读取服务器状态。');
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _auth.clear();
    _data = null;
    _snapshot = null;
    for (final field in [
      _username,
      _password,
      _token,
      _otp,
      _port,
      _path,
      _domain,
      _resourceSearch,
    ]) {
      field.dispose();
    }
    super.dispose();
  }

  List<String> get _visibleGroups {
    final groups = panelOperations
        .where((op) => _available?.contains(op['id']) == true)
        .map((op) => op['group'] as String)
        .toSet();
    return [
      ..._groups.keys.where(groups.contains),
      ...groups.where((g) => !_groups.containsKey(g)),
    ];
  }

  bool get _hasResources =>
      {'inbounds', 'clients', '3m-listeners', '3m-users'}.contains(_group);
  bool get _hasConfig =>
      {'setting', 'xray', '3m-config', '3m-panel-settings'}.contains(_group);

  IconData _groupIcon(String group) => switch (group) {
    'inbounds' || '3m-listeners' => Icons.dns_outlined,
    'clients' || '3m-users' => Icons.people_outline,
    'xray' || '3m-config' => Icons.alt_route_rounded,
    'setting' || '3m-panel-settings' => Icons.tune_rounded,
    'server' || '3m-system' => Icons.build_outlined,
    '3m-auth' || '3m-access-tokens' => Icons.shield_outlined,
    '3m-traffic' || '3m-dashboard' => Icons.show_chart_rounded,
    '3m-mihomo' => Icons.memory_outlined,
    _ => Icons.hub_outlined,
  };

  String get _groupHelp => switch (_group) {
    'inbounds' => '管理监听端口、协议和传输配置。点击入站查看或编辑。',
    'clients' => '管理客户端、流量配额与到期时间，通过更多菜单分享节点。',
    '3m-listeners' => '管理 Mihomo 监听入站。保存后可应用配置并检查运行状态。',
    '3m-users' => '管理用户、流量与有效期，通过更多菜单关联入站和分享订阅。',
    'xray' || '3m-config' => '查看和编辑出站、路由与 DNS，保留完整配置中的其他字段。',
    'setting' || '3m-panel-settings' => '管理面板配置，保存前检查变更内容。',
    _ => '仅显示当前面板可用的操作。选择一项继续。',
  };

  void _selectGroup(String value) {
    if (_busy || value == _group) return;
    setState(() {
      _group = value;
      _data = null;
      _snapshot = null;
      _search = '';
      _resourceSearch.clear();
      _resourceFilter = 'all';
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _run(_load);
  }

  Widget _card(Widget child, {double padding = 20}) => Card(
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );

  Widget _loginCard() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: StatusBadge(
            'SSH 已连接',
            active: true,
            icon: Icons.check_circle_outline,
          ),
        ),
        const SizedBox(height: 20),
        Text('使用现有面板认证', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '输入面板凭据以继续管理，仅在当前会话使用。本应用部署的实例可留空，使用服务器上已有的授权。',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        SegmentedButton<bool>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: false, label: Text('账号密码')),
            ButtonSegment(value: true, label: Text('API Token')),
          ],
          selected: {_useToken},
          onSelectionChanged: _busy
              ? null
              : (v) => setState(() => _useToken = v.first),
        ),
        const SizedBox(height: 20),
        if (_useToken)
          TextField(
            controller: _token,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: _mihomo ? '3m-ui 登录 JWT' : 'API token',
            ),
          )
        else ...[
          TextField(
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(labelText: '面板账号'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: '面板密码'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otp,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: '二步验证码（若已启用）'),
          ),
        ],
        const SizedBox(height: 16),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('手动指定面板入口'),
          subtitle: const Text('自动读取地址失败时使用'),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('指定本机面板入口'),
              value: _manualEndpoint,
              onChanged: _busy
                  ? null
                  : (v) => setState(() => _manualEndpoint = v),
            ),
            if (_manualEndpoint) ...[
              TextField(
                controller: _port,
                decoration: const InputDecoration(labelText: '面板监听端口'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _path,
                decoration: const InputDecoration(labelText: '面板访问路径'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _domain,
                decoration: const InputDecoration(labelText: '面板绑定域名（可选）'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('面板自身使用 HTTPS'),
                value: _https,
                onChanged: _busy ? null : (v) => setState(() => _https = v),
              ),
              const Text('连接当前实例网络内的回环地址，不改变监听设置。入口信息仅保留在本次会话。'),
            ],
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _login,
          icon: const Icon(Icons.login_rounded),
          label: Text(_busy ? '正在认证…' : '连接面板管理'),
        ),
      ],
    ),
  );

  Widget _navigation() => SizedBox(
    width: 220,
    child: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
          child: Text(
            '管理功能',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final group in _visibleGroups)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: NavigationItem(
              label: _groups[group] ?? group,
              icon: _groupIcon(group),
              selected: _group == group,
              onTap: _busy ? null : () => _selectGroup(group),
            ),
          ),
      ],
    ),
  );

  Map<String, dynamic> _resourceItem(Map<String, dynamic> row) =>
      _group == 'clients' && row['client'] is Map
      ? Map<String, dynamic>.from(row['client'] as Map)
      : row;

  Widget _resources() {
    final all = (_data is List ? _data as List : const [])
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    bool enabled(Map<String, dynamic> row) =>
        _resourceItem(row)[_mihomo ? 'enabled' : 'enable'] == true;
    final query = _resourceSearch.text.trim().toLowerCase();
    final rows = all.where((row) {
      final item = _resourceItem(row);
      final text = [
        'name',
        'username',
        'remark',
        'email',
        'protocol',
        'port',
        'id',
      ].map((key) => '${item[key] ?? ''}').join(' ').toLowerCase();
      return text.contains(query) &&
          (_resourceFilter == 'all' ||
              enabled(row) == (_resourceFilter == 'enabled'));
    }).toList();
    final addLabel = switch (_group) {
      'inbounds' => '新增入站',
      'clients' => '新增客户端',
      '3m-listeners' => '新增 Listener',
      _ => '新增用户',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _resourceSearch,
                decoration: InputDecoration(
                  labelText: '搜索名称、协议或端口',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => setState(_resourceSearch.clear),
                          icon: const Icon(Icons.close),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in {
                        'all': '全部',
                        'enabled': '已启用',
                        'disabled': '已停用',
                      }.entries)
                        ChoiceChip(
                          label: Text(filter.value),
                          selected: _resourceFilter == filter.key,
                          showCheckmark: false,
                          onSelected: (_) =>
                              setState(() => _resourceFilter = filter.key),
                        ),
                    ],
                  ),
                  Text(
                    '共 ${all.length} 项 · 已启用 ${all.where(enabled).length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  FilledButton.icon(
                    onPressed: _busy || _data == null
                        ? null
                        : () => _mihomo
                              ? _editThreeM()
                              : _group == 'inbounds'
                              ? _editInbound()
                              : _editClient(),
                    icon: const Icon(Icons.add, size: 20),
                    label: Text(addLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_data == null && !_busy) _card(const Text('列表尚未读取，请点击右上角刷新重试。')),
        if (_data is List && rows.isEmpty)
          _card(
            Column(
              children: [
                Icon(
                  all.isEmpty ? Icons.inbox_outlined : Icons.search_off_rounded,
                  size: 32,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(all.isEmpty ? '当前列表为空。' : '没有匹配的项目。'),
                if (all.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _resourceSearch.clear();
                      _resourceFilter = 'all';
                    }),
                    child: const Text('清除筛选'),
                  ),
              ],
            ),
            padding: 28,
          ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _mihomo ? _threeMRow(row) : _row(row),
          ),
      ],
    );
  }

  Widget _operations() {
    final ops = panelOperations
        .where(
          (op) =>
              _available?.contains(op['id']) == true &&
              op['group'] == _group &&
              '${managementLabel(op)} ${op['path']}'.toLowerCase().contains(
                _search.toLowerCase(),
              ),
        )
        .toList();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: TextField(
            key: ValueKey('operations-$_group'),
            decoration: const InputDecoration(
              labelText: '搜索操作',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) => setState(() => _search = v),
          ),
        ),
        if (ops.isEmpty)
          const Padding(padding: EdgeInsets.all(24), child: Text('没有匹配的操作。')),
        for (final op in ops)
          ListTile(
            title: Text(managementLabel(op)),
            subtitle: Text(
              _unavailable[op['id']] as String? ??
                  (op['write'] == true ? '修改 · 执行前确认' : '读取'),
            ),
            leading: Icon(
              op['write'] == true
                  ? Icons.edit_outlined
                  : Icons.visibility_outlined,
              size: 20,
            ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            enabled: !_busy && !_unavailable.containsKey(op['id']),
            onTap: _busy || _unavailable.containsKey(op['id'])
                ? null
                : () => _advanced(op),
          ),
      ],
    );
    return _card(
      _hasResources || _hasConfig
          ? ExpansionTile(
              key: ValueKey('advanced-$_group'),
              title: const Text('高级操作'),
              subtitle: const Text('批量处理与完整面板接口'),
              children: [content],
            )
          : content,
      padding: 4,
    );
  }

  Widget _serviceControls() => _card(
    ExpansionTile(
      title: const Text('实例服务'),
      subtitle: const Text('启动、停止或重启当前实例'),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final action in {
              'start': '启动',
              'stop': '停止',
              'restart': '重启',
            }.entries)
              OutlinedButton(
                onPressed: _busy ? null : () => _service(action.key),
                child: Text(action.value),
              ),
          ],
        ),
      ],
    ),
    padding: 4,
  );

  Widget _content(bool wide) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _available == null ? 560 : 1100),
      child: ListView(
        controller: _scroll,
        padding: EdgeInsets.all(wide ? 24 : 16),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: StateNotice(
                _error!,
                error: true,
                onDismiss: () => setState(() => _error = null),
              ),
            ),
          if (_notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: StateNotice(
                _notice!,
                onDismiss: () => setState(() => _notice = null),
              ),
            ),
          if (_available == null)
            _loginCard()
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                StatusBadge(
                  '${_mihomo ? '3m-ui · Mihomo' : '3x-ui · Xray'} $_version',
                  icon: Icons.memory_outlined,
                ),
                const StatusBadge(
                  '已认证',
                  active: true,
                  icon: Icons.check_circle_outline,
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (!wide) ...[
              DropdownButtonFormField<String>(
                key: ValueKey('group-$_group'),
                initialValue: _group,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '管理功能'),
                items: [
                  for (final group in _visibleGroups)
                    DropdownMenuItem(
                      value: group,
                      child: Text(
                        _groups[group] ?? group,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) _selectGroup(value);
                      },
              ),
              const SizedBox(height: 20),
            ] else ...[
              Text(
                _groups[_group] ?? _group,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              _groupHelp,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_panelUpdateRun != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _run(_readPanelUpdate),
                  icon: const Icon(Icons.refresh),
                  label: const Text('刷新本次面板升级进度'),
                ),
              ),
            if (_hasResources) _resources(),
            if (_hasConfig && _snapshot != null)
              _card(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _groupIcon(_group),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '配置已读取',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('打开编辑器查看完整配置。保存前会检查当前版本，避免覆盖其他会话的修改。'),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy ? null : _editSettings,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('查看与编辑完整配置'),
                    ),
                  ],
                ),
              ),
            if (_mihomo &&
                {'3m-listeners', '3m-users', '3m-config'}.contains(_group) &&
                _available!.contains(_id('POST', '/config/apply')))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _applyMihomo,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('应用并检查 Mihomo'),
                ),
              ),
            const SizedBox(height: 20),
            _operations(),
          ],
          const SizedBox(height: 20),
          _serviceControls(),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.instance['name']}',
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        if (_available != null)
          IconButton(
            tooltip: '重新认证',
            onPressed: _busy
                ? null
                : () => setState(() {
                    _auth.clear();
                    _available = null;
                    _data = null;
                    _snapshot = null;
                    _error = null;
                    _notice = null;
                  }),
            icon: const Icon(Icons.lock_reset),
          ),
        if (_available != null)
          IconButton(
            tooltip: '重新读取',
            onPressed: _busy ? null : () => _run(_load),
            icon: const Icon(Icons.refresh),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(3),
        child: SizedBox(
          height: 3,
          child: _busy ? const LinearProgressIndicator() : null,
        ),
      ),
    ),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (wide && _available != null) _navigation(),
              Expanded(child: _content(wide)),
            ],
          );
        },
      ),
    ),
  );

  Widget _itemTitle(String name, bool enabled) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Expanded(
          child: Text(
            name.isEmpty || name == 'null' ? '未命名' : name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 8),
        StatusBadge(enabled ? '启用' : '停用', active: enabled),
      ],
    ),
  );

  String _quota(Object? value) => value == 0 ? '不限量' : formatBytes(value);

  String _expiryLabel(Object? value) {
    if (value == 0 || value == null || '$value'.startsWith('0001-')) {
      return '不限期';
    }
    if (value is num && value < 0) {
      return '首次使用后 ${(-value / 86400000).toStringAsFixed(1)} 天';
    }
    final date = value is num
        ? DateTime.fromMillisecondsSinceEpoch(value.toInt())
        : DateTime.tryParse('$value')?.toLocal();
    if (date == null) return '$value';
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  Widget _row(Map<String, dynamic> row) {
    final inbound = _group == 'inbounds';
    final client = row['client'] is Map
        ? Map<String, dynamic>.from(row['client'] as Map)
        : row;
    final item = inbound ? row : client;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        title: _itemTitle(
          '${inbound ? item['remark'] : item['email']}',
          item['enable'] == true,
        ),
        subtitle: Text(
          inbound
              ? "${'${item['protocol']}'.toUpperCase()} · 端口 ${item['port']} · #${item['id']}"
              : '配额 ${_quota(item['totalGB'])} · 到期 ${_expiryLabel(item['expiryTime'])}\n↑ ${formatBytes(item['up'])} / ↓ ${formatBytes(item['down'])}',
        ),
        onTap: _busy
            ? null
            : () => inbound ? _editInbound(item) : _editClient(item),
        trailing: PopupMenuButton<String>(
          tooltip: '更多操作',
          enabled: !_busy,
          onSelected: (action) async {
            if (action == 'delete') {
              await _write(
                inbound ? '/inbounds/del/{id}' : '/clients/del/{email}',
                parameters: inbound
                    ? {'id': item['id']}
                    : {'email': item['email']},
                title: '删除 ${inbound ? item['remark'] : item['email']}',
              );
            } else if (action == 'toggle') {
              await _write(
                inbound
                    ? '/inbounds/setEnable/{id}'
                    : (item['enable'] == true
                          ? '/clients/bulkDisable'
                          : '/clients/bulkEnable'),
                parameters: inbound ? {'id': item['id']} : {},
                data: inbound
                    ? {'enable': item['enable'] != true}
                    : {
                        'emails': [item['email']],
                      },
              );
            } else if (action == 'links') {
              await _share(item);
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'toggle',
              child: Text(item['enable'] == true ? '停用' : '启用'),
            ),
            if (!inbound)
              const PopupMenuItem(value: 'links', child: Text('分享与订阅')),
            const PopupMenuItem(value: 'delete', child: Text('删除')),
          ],
        ),
      ),
    );
  }

  Future<void> _share(Map<String, dynamic> client) => _run(() async {
    final nodes = await _call(
      _id('GET', '/clients/links/{email}'),
      parameters: {'email': client['email']},
    );
    final subscription = '${client['subId'] ?? ''}';
    final subs = subscription.isEmpty
        ? null
        : await _call(
            _id('GET', '/clients/subLinks/{subId}'),
            parameters: {'subId': subscription},
          );
    if (!mounted) return;
    final groups = {'节点链接': nodes['result'], '订阅地址': subs?['result']};
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('分享 · ${client['email']}'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final group in groups.entries) ...[
                  Text(
                    group.key,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (group.value is! List || (group.value as List).isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('面板尚未提供。请检查客户端关联、Hosts 和订阅设置。'),
                    ),
                  if (group.value is List)
                    for (final link
                        in (group.value as List).whereType<String>()) ...[
                      const SizedBox(height: 12),
                      if (link.length <= 2000)
                        Center(
                          child: QrImageView(
                            data: link,
                            size: 170,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      SelectableText(link),
                      Wrap(
                        spacing: 12,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: link),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('已复制链接')),
                                );
                              }
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('复制链接'),
                          ),
                          TextButton.icon(
                            onPressed: () => saveNode(link),
                            icon: const Icon(Icons.download),
                            label: const Text('导出'),
                          ),
                        ],
                      ),
                    ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  });
}

Object? _decodeJson(Object? value) {
  if (value is! String) return value;
  try {
    return jsonDecode(value);
  } catch (_) {
    return value;
  }
}

Object? _defaults(Map schema) {
  if (schema.containsKey('default')) return schema['default'];
  if (schema['anyOf'] is List && (schema['anyOf'] as List).isNotEmpty) {
    return _defaults((schema['anyOf'] as List).first as Map);
  }
  return switch (schema['type']) {
    'array' => [],
    'boolean' => false,
    'integer' || 'number' => 0,
    'string' => '',
    _ => {
      for (final entry in (schema['properties'] as Map? ?? {}).entries)
        '${entry.key}': _defaults(entry.value as Map),
    },
  };
}
