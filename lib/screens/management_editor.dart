import 'dart:convert';

import 'package:flutter/material.dart';

const _pretty = JsonEncoder.withIndent('  ');

Future<Object?> showManagementEditor(
  BuildContext context,
  String title,
  Object? data, {
  required String help,
  String? kind,
}) => showDialog<Object>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _JsonEditor(title: title, data: data, help: help, kind: kind),
);

class _JsonEditor extends StatefulWidget {
  const _JsonEditor({
    required this.title,
    required this.data,
    required this.help,
    this.kind,
  });
  final String title, help;
  final Object? data;
  final String? kind;
  @override
  State<_JsonEditor> createState() => _JsonEditorState();
}

class _JsonEditorState extends State<_JsonEditor> {
  late final _text = TextEditingController(text: _pretty.convert(widget.data));
  late bool _raw = widget.kind == null;
  late Map<String, dynamic> _value = widget.data is Map
      ? jsonDecode(jsonEncode(widget.data)) as Map<String, dynamic>
      : {};
  final _form = GlobalKey<FormState>();
  String? _error;

  Map<String, dynamic> get _record =>
      widget.kind == 'client' && _value['client'] is Map
      ? _value['client'] as Map<String, dynamic>
      : _value;

  Widget _field(
    String name,
    String label, {
    bool number = false,
    bool required = false,
    Map<String, dynamic>? target,
  }) {
    final record = target ?? _record;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        initialValue: '${record[name] ?? (number ? 0 : '')}',
        decoration: InputDecoration(labelText: label),
        keyboardType: number
            ? const TextInputType.numberWithOptions(signed: true)
            : TextInputType.text,
        autocorrect: false,
        validator: (v) {
          if (required && (v ?? '').trim().isEmpty) return '请填写此项。';
          if (number && int.tryParse(v ?? '') == null) return '请输入整数。';
          if (name == 'port' &&
              number &&
              (int.parse(v!) < 1 || int.parse(v) > 65535)) {
            return '端口必须为 1–65535。';
          }
          if ({'total', 'totalGB', 'limitIp'}.contains(name) &&
              int.parse(v!) < 0) {
            return '不能为负数。';
          }
          return null;
        },
        onSaved: (v) => record[name] = number ? int.parse(v!) : v!,
      ),
    );
  }

  List<Widget> _fields() => widget.kind?.startsWith('3m-') == true
      ? [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用'),
            value: _record['enabled'] == true,
            onChanged: (v) => setState(() => _record['enabled'] = v),
          ),
          if (widget.kind == '3m-listener') ...[
            _field('name', '名称', required: true),
            _field('port', '监听端口 / 范围', required: true),
            _field('protocol', '协议（在完整 JSON 中同步配置）', required: true),
            _field('bind_address', '监听地址'),
          ] else ...[
            _field('username', '用户名', required: true),
            _field('traffic_limit', '流量配额（字节，0 不限）', number: true),
            _field('expire_time', '到期时间（ISO 日期）', required: true),
            _field('remark', '备注'),
          ],
        ]
      : [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('启用'),
            value: _record['enable'] == true,
            onChanged: (v) => setState(() => _record['enable'] = v),
          ),
          if (widget.kind == 'inbound') ...[
            _field('remark', '备注'),
            _field('port', '监听端口', number: true, required: true),
            _field('listen', '监听地址（空表示所有地址）'),
            _field('protocol', '协议（修改时需在完整 JSON 中同步协议配置）', required: true),
            _field('total', '流量配额（字节，0 不限）', number: true),
          ] else ...[
            _field('email', '客户端标识', required: true),
            _field('totalGB', '流量配额（字节，0 不限）', number: true),
            if (_record.containsKey('id')) _field('id', 'UUID'),
            if (_record.containsKey('subId')) _field('subId', '订阅标识'),
            if (_value.containsKey('inboundIds'))
              TextFormField(
                initialValue: (_value['inboundIds'] as List).join(','),
                decoration: const InputDecoration(labelText: '关联入站 ID（逗号分隔）'),
                validator: (v) =>
                    (v ?? '')
                        .split(',')
                        .any(
                          (s) =>
                              int.tryParse(s.trim()) == null ||
                              int.parse(s.trim()) <= 0,
                        )
                    ? '请输入至少一个有效入站 ID。'
                    : null,
                onSaved: (v) => _value['inboundIds'] = v!
                    .split(',')
                    .map((s) => int.parse(s.trim()))
                    .toList(),
              ),
            const SizedBox(height: 14),
          ],
          _field('expiryTime', '到期时间（毫秒时间戳，0 不限，负数为使用时长）', number: true),
        ];

  void _switchMode(bool raw) {
    try {
      if (_raw) {
        final value = jsonDecode(_text.text);
        if (value is! Map<String, dynamic>) throw const FormatException();
        _value = value;
      } else {
        if (!_form.currentState!.validate()) return;
        _form.currentState!.save();
        _text.text = _pretty.convert(_value);
      }
      setState(() {
        _raw = raw;
        _error = null;
      });
    } catch (_) {
      setState(() => _error = '请输入有效的 JSON 对象。');
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    insetPadding: const EdgeInsets.all(16),
    title: Text(widget.title),
    content: SizedBox(
      width: 760,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('填写说明'),
              childrenPadding: const EdgeInsets.only(bottom: 16),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: SelectableText(widget.help),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (widget.kind != null) ...[
              SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, label: Text('常用字段')),
                  ButtonSegment(value: true, label: Text('完整 JSON')),
                ],
                selected: {_raw},
                onSelectionChanged: (value) => _switchMode(value.first),
              ),
              const SizedBox(height: 16),
            ],
            if (!_raw)
              Form(
                key: _form,
                child: Column(children: _fields()),
              ),
            if (_raw)
              TextField(
                controller: _text,
                minLines: 8,
                maxLines: 20,
                autocorrect: false,
                enableSuggestions: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                decoration: InputDecoration(
                  labelText: '完整 JSON 配置',
                  errorText: _error,
                  alignLabelWithHint: true,
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          try {
            if (!_raw) {
              if (!_form.currentState!.validate()) return;
              _form.currentState!.save();
              _text.text = _pretty.convert(_value);
            }
            final value = jsonDecode(_text.text);
            if (value is! Map && value is! List) throw const FormatException();
            if (widget.kind != '3m-listener' &&
                value is Map &&
                value.containsKey('port') &&
                (value['port'] is! int ||
                    value['port'] < 1 ||
                    value['port'] > 65535)) {
              setState(() => _error = '端口必须为 1–65535 的整数。');
              return;
            }
            Navigator.pop(context, value);
          } catch (_) {
            setState(() => _error = '请输入有效的 JSON 对象或数组。');
          }
        },
        child: const Text('检查并继续'),
      ),
    ],
  );
}
