import 'package:flutter/material.dart';

/// Uses FlClash's selectable-card and selection-badge pattern.
class AuthMethodSelector extends StatelessWidget {
  const AuthMethodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('认证方式', style: theme.textTheme.titleSmall),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final option in const [
              ('password', Icons.password_rounded, '密码登录', '输入服务器密码'),
              ('key', Icons.key_outlined, 'SSH 私钥', '导入或粘贴私钥'),
            ]) ...[
              if (option.$1 == 'key') const SizedBox(width: 12),
              Expanded(
                child: MergeSemantics(
                  child: Semantics(
                    checked: value == option.$1,
                    inMutuallyExclusiveGroup: true,
                    child: OutlinedButton(
                      onPressed: onChanged == null
                          ? null
                          : () => onChanged!(option.$1),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.all(12),
                        backgroundColor: value == option.$1
                            ? colors.primaryContainer
                            : colors.surfaceContainerLow,
                        foregroundColor: value == option.$1
                            ? colors.onPrimaryContainer
                            : colors.onSurfaceVariant,
                        side: BorderSide(
                          color: value == option.$1
                              ? colors.primary
                              : colors.outlineVariant,
                          width: 2,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(option.$2, size: 22),
                              ExcludeSemantics(
                                child: Icon(
                                  value == option.$1
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked,
                                  color: value == option.$1
                                      ? colors.primary
                                      : colors.outline,
                                  size: 22,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            option.$3,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(option.$4, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
