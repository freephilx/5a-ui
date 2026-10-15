import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/material.dart';

class SshUsernameInput extends StatelessWidget {
  const SshUsernameInput({
    super.key,
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    enabled: enabled,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: '用户名',
      hintText: '自动',
      floatingLabelBehavior: FloatingLabelBehavior.always,
      suffixIcon: PopupMenuButton<String>(
        enabled: enabled,
        tooltip: '选择登录用户名',
        icon: const Icon(Icons.expand_more_rounded),
        initialValue: controller.text.trim(),
        onSelected: (value) {
          controller.text = value;
          onChanged(value);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: '', child: Text('自动')),
          for (final username in defaultSshUsernames)
            PopupMenuItem(value: username, child: Text(username)),
        ],
      ),
    ),
  );
}
