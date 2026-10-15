import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:five_a_core/five_a_core.dart';

import '../saved_servers.dart';

class SaveServerDialog extends StatefulWidget {
  const SaveServerDialog({
    super.key,
    required this.servers,
    required this.input,
    this.existing,
  });
  final SavedServers servers;
  final ConnectionInput input;
  final SavedServer? existing;
  @override
  State<SaveServerDialog> createState() => _SaveServerDialogState();
}

class _SaveServerDialogState extends State<SaveServerDialog> {
  late final name = TextEditingController(
    text: widget.existing?.name ?? widget.input.host,
  );
  late bool credentials = widget.existing?.includesCredentials ?? false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saved = await widget.servers.save(
        input: widget.input,
        name: name.text,
        includeCredentials: credentials,
      );
      if (!mounted) return;
      if (saved != null) {
        Navigator.of(context).pop(saved);
        return;
      }
      setState(() => error = widget.servers.error);
    } on AppException catch (e) {
      if (mounted) setState(() => error = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(widget.existing == null ? '保存服务器' : '更新保存的服务器'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 80,
                decoration: const InputDecoration(labelText: '名称'),
              ),
              const SizedBox(height: 8),
              const Text('保存地址、SSH 端口、用户名、认证方式及已核验的主机指纹。下次打开自动填入，连接后读取最新状态。'),
              const SizedBox(height: 16),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('同时保存登录凭据'),
                subtitle: Text(
                  widget.input.authMethod == 'key'
                      ? '包含当前 SSH 私钥及密钥口令'
                      : '包含当前 SSH 密码',
                ),
                value: credentials,
                onChanged: busy
                    ? null
                    : (value) => setState(() => credentials = value),
              ),
              const SizedBox(height: 8),
              Text(
                kIsWeb
                    ? '保存在当前浏览器的本站点加密存储中，本站点仍可读取。仅在可信的个人设备上保存凭据。'
                    : '使用本机安全存储，不同步到其他设备。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (error != null) ...[
                const SizedBox(height: 12),
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? '正在保存…' : '保存'),
        ),
      ],
    ),
  );
}
