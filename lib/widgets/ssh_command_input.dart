import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/material.dart';

import '../ssh_command.dart';

class SshCommandInput extends StatefulWidget {
  const SshCommandInput({
    super.key,
    required this.controller,
    required this.onImported,
    required this.enabled,
  });

  final TextEditingController controller;
  final ValueChanged<SshConnectionCommand> onImported;
  final bool enabled;

  @override
  State<SshCommandInput> createState() => _SshCommandInputState();
}

class _SshCommandInputState extends State<SshCommandInput> {
  String? error;
  bool showExamples = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() => setState(() => error = null);

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _import() {
    if (!widget.enabled || widget.controller.text.trim().isEmpty) return;
    try {
      widget.onImported(SshConnectionCommand.parse(widget.controller.text));
    } on FormatException catch (e) {
      setState(() => error = e.message);
    } on AppException catch (e) {
      setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secondary = TextStyle(
      fontSize: 14,
      height: 20 / 14,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          child: TextField(
            controller: widget.controller,
            enabled: widget.enabled,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 15),
            obscureText: widget.controller.text.trimLeft().startsWith(
              'sshpass',
            ),
            onSubmitted: (_) => _import(),
            decoration: InputDecoration(
              labelText: 'SSH 命令',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 20,
              ),
              hintText: '粘贴 SSH 连接命令',
              hintStyle: Theme.of(context).textTheme.bodyMedium!.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              errorText: error,
              errorMaxLines: 4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('自动填入地址、端口和私钥路径；密码可在下一步填写。', style: secondary),
        const SizedBox(height: 8),
        Semantics(
          expanded: showExamples,
          child: TextButton(
            onPressed: () => setState(() => showExamples = !showExamples),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 40),
              foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('命令示例', style: secondary),
                Icon(showExamples ? Icons.expand_less : Icons.expand_more),
              ],
            ),
          ),
        ),
        if (showExamples) ...[
          Text('密码登录', style: secondary),
          const SizedBox(height: 4),
          const Text(
            'ssh -p 22 ubuntu@公网IP',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 18 / 13,
            ),
          ),
          const SizedBox(height: 12),
          Text('私钥登录', style: secondary),
          const SizedBox(height: 4),
          const Text(
            'ssh -i ~/.ssh/id_ed25519 -p 22 ubuntu@公网IP',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 18 / 13,
            ),
          ),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 32),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            return Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: constraints.maxWidth >= 560 * scale
                    ? 200
                    : double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      widget.enabled && widget.controller.text.trim().isNotEmpty
                      ? _import
                      : null,
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 19),
                  label: const Text('解析并填入'),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
