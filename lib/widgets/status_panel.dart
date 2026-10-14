import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controller.dart';
import '../services/export.dart';

String formatBytes(Object? raw) {
  if (raw is! num || !raw.isFinite) return '—';
  var value = raw.toDouble();
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = 24});
  final Widget child;
  final double padding;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(padding: EdgeInsets.all(padding), child: child),
  );
}

class StatusPanel extends StatelessWidget {
  const StatusPanel({
    super.key,
    required this.controller,
    required this.onConnect,
  });
  final ServerController controller;
  final VoidCallback onConnect;

  Future<void> _copy(BuildContext context, String link) async {
    try {
      await Clipboard.setData(ClipboardData(text: link));
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('节点链接已复制')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('复制失败，请在连接详情中手动复制。')));
      }
    }
  }

  Future<void> _save(BuildContext context, String link) async {
    try {
      final saved = await saveNode(link);
      if (saved && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('节点链接已导出')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('导出失败，请复制节点链接。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final busy = controller.busy || controller.polling;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.hub_outlined, color: colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text('节点状态', style: text.titleMedium)),
              if (busy)
                IconButton(
                  onPressed: controller.pause,
                  tooltip: '暂停刷新',
                  icon: const Icon(Icons.pause_circle_outline),
                )
              else
                IconButton(
                  onPressed: controller.canRefresh ? controller.refresh : null,
                  tooltip: '刷新状态',
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (status == null && !busy) ...[
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.dns_outlined,
                        size: 44,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('从一台服务器开始', style: text.titleLarge),
                    const SizedBox(height: 10),
                    Text(
                      '连接你的服务器，一键部署 3x-ui。\n已有节点也可以直接读取状态。',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('连接服务器'),
                    ),
                  ],
                ),
              ),
            ),
          ] else ...[
            Row(
              children: [
                if (busy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                else
                  Icon(
                    status?.running == true
                        ? Icons.check_circle_rounded
                        : status?.phase == 'failed'
                        ? Icons.error_outline
                        : Icons.info_outline,
                    color: status?.phase == 'failed'
                        ? colors.error
                        : colors.primary,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    controller.paused
                        ? '已暂停刷新'
                        : status?.isReady == true
                        ? status!.running
                              ? '节点运行中'
                              : '节点未运行'
                        : busy
                        ? '正在连接与部署'
                        : '服务器状态',
                    style: text.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              status?.message ?? '正在连接服务器，请稍候…',
              style: text.bodyMedium!.copyWith(color: colors.onSurfaceVariant),
            ),
            if (status?.isInstalling == true || busy && status == null) ...[
              const SizedBox(height: 24),
              _Stages(phase: status?.phase ?? 'queued'),
              const SizedBox(height: 16),
              Text(
                '安装在服务器上后台运行，离开页面或暂停刷新不会中断安装。',
                style: text.bodySmall!.copyWith(color: colors.onSurfaceVariant),
              ),
            ],
            if (controller.paused)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: OutlinedButton.icon(
                  onPressed: controller.canRefresh ? controller.refresh : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('继续读取状态'),
                ),
              ),
            if (status?.link case final link?) ...[
              const SizedBox(height: 28),
              Wrap(
                spacing: 24,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Semantics(
                    label: 'VLESS 节点连接二维码',
                    image: true,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: QrImageView(
                        data: link,
                        size: 160,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.all(12),
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VLESS + REALITY',
                        style: text.labelLarge!.copyWith(color: colors.primary),
                      ),
                      const SizedBox(height: 14),
                      FilledButton.icon(
                        onPressed: () => _copy(context, link),
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('复制节点链接'),
                      ),
                      const SizedBox(height: 6),
                      TextButton.icon(
                        onPressed: () => _save(context, link),
                        icon: const Icon(Icons.download_rounded, size: 18),
                        label: const Text('导出节点'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (status!.data['portReachable'] == false)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '节点端口暂不可达。${status.data['firewall'] ?? '请检查云平台安全组是否放行节点 TCP 端口。'}',
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('连接详情'),
                children: [
                  SelectableText(link, style: text.bodySmall),
                  const SizedBox(height: 16),
                  _Detail(
                    '服务器',
                    '${status.node!['host']}:${status.node!['port']}',
                  ),
                  _Detail('REALITY 目标', status.node!['serverName'] as String),
                  _Detail(
                    '3x-ui',
                    status.data['panelVersion'] as String? ?? '—',
                  ),
                  _Detail('Xray', status.data['xrayVersion'] as String? ?? '—'),
                  const SizedBox(height: 8),
                  Text('链接和二维码是节点访问凭据，请妥善保存。', style: text.bodySmall),
                  const SizedBox(height: 12),
                ],
              ),
            ],
            if (status?.fingerprint case final fingerprint?) ...[
              const SizedBox(height: 20),
              Text(
                'SSH 主机指纹',
                style: text.labelMedium!.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                fingerprint,
                style: text.bodySmall!.copyWith(fontFamily: 'monospace'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _Stages extends StatelessWidget {
  const _Stages({required this.phase});
  final String phase;
  @override
  Widget build(BuildContext context) {
    const stages = [
      ('preparing', '检查服务器'),
      ('installing', '安装 3x-ui'),
      ('configuring', '配置节点'),
      ('checking', '验证连接'),
    ];
    final current = stages.indexWhere((stage) => stage.$1 == phase);
    final colors = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (var i = 0; i < stages.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Icon(
                  i < current
                      ? Icons.check_circle
                      : i == current
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color: i <= current ? colors.primary : colors.outline,
                ),
                const SizedBox(width: 12),
                Text(
                  stages[i].$2,
                  style: TextStyle(
                    color: i <= current
                        ? colors.onSurface
                        : colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Text(label),
        const SizedBox(width: 24),
        Expanded(child: SelectableText(value, textAlign: TextAlign.right)),
      ],
    ),
  );
}

class MetricCard extends StatelessWidget {
  const MetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.caption,
  });
  final IconData icon;
  final String label, value, caption;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(label, style: theme.textTheme.labelLarge)),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            value,
            style: theme.textTheme.headlineMedium!.copyWith(
              fontFeatures: [const FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            caption,
            style: theme.textTheme.bodySmall!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
