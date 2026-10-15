import 'package:flutter/material.dart';

/// Uses FlClash's selectable-card and selection-badge pattern.
class ConnectionMethodSelector extends StatelessWidget {
  const ConnectionMethodSelector({
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
    const options = [
      ('password', Icons.password_rounded, '密码登录', '输入服务器密码'),
      ('key', Icons.key_outlined, 'SSH 私钥', '路径、文件或粘贴'),
      ('command', Icons.terminal_rounded, 'SSH 命令', '粘贴命令并填入'),
    ];
    Widget choice((String, IconData, String, String) option, bool compact) {
      final selected = value == option.$1;
      final secondary = onChanged == null
          ? colors.onSurface.withValues(alpha: 0.38)
          : colors.onSurfaceVariant;
      final icon = Icon(option.$2, size: 22, color: secondary);
      final mark = ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: selected
              ? DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: onChanged == null ? secondary : colors.primary,
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: colors.onPrimary,
                  ),
                )
              : null,
        ),
      );
      final title = Text(
        option.$3,
        style: const TextStyle(
          fontSize: 16,
          height: 21 / 16,
          fontWeight: FontWeight.w500,
        ),
      );
      final subtitle = Text(
        option.$4,
        style: TextStyle(
          fontSize: 13,
          height: 18 / 13,
          fontWeight: FontWeight.w400,
          color: secondary,
        ),
      );
      return MergeSemantics(
        child: Semantics(
          checked: selected,
          inMutuallyExclusiveGroup: true,
          child: OutlinedButton(
            onPressed: onChanged == null ? null : () => onChanged!(option.$1),
            style:
                OutlinedButton.styleFrom(
                  padding: EdgeInsets.all(compact ? 16 : 20),
                  minimumSize: Size(0, compact ? 72 : 88),
                  visualDensity: VisualDensity.standard,
                  backgroundColor: theme.brightness == Brightness.dark
                      ? colors.surfaceContainerHigh
                      : colors.surfaceContainer,
                  foregroundColor: colors.onSurface,
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? BorderSide(color: colors.primary, width: 2)
                        : BorderSide.none,
                  ),
                ),
            child: compact
                ? Row(
                    children: [
                      icon,
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            title,
                            const SizedBox(height: 4),
                            subtitle,
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      mark,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          icon,
                          const SizedBox(width: 10),
                          Expanded(child: title),
                          const SizedBox(width: 12),
                          mark,
                        ],
                      ),
                      const SizedBox(height: 8),
                      subtitle,
                    ],
                  ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '输入方式',
          style: TextStyle(
            fontSize: 14,
            height: 20 / 14,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
            if (constraints.maxWidth < 600 * scale) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in options) ...[
                    if (option != options.first) const SizedBox(height: 12),
                    choice(option, true),
                  ],
                ],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final option in options) ...[
                    if (option != options.first) const SizedBox(width: 16),
                    Expanded(child: choice(option, false)),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
