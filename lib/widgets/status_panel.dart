import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../controller.dart';
import '../services/export.dart';
import '../screens/management.dart';
import 'ui.dart';

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child, this.padding = 20});
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
              Expanded(child: Text('服务与节点', style: text.titleMedium)),
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
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainer,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Icon(
                        Icons.dns_outlined,
                        size: 32,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('从一台服务器开始', style: text.titleLarge),
                    const SizedBox(height: 10),
                    Text(
                      '连接后自动识别已有 3x-ui / 3m-ui。\n未安装面板时，可继续一键部署。',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium!.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: onConnect,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('连接服务器，一键自建'),
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
                        : busy
                        ? controller.startingDeployment ||
                                  status?.isInstalling == true
                              ? '正在部署面板'
                              : '正在读取服务器'
                        : status?.instances.isNotEmpty == true
                        ? '已连接面板'
                        : status?.isReady == true
                        ? status!.running
                              ? '节点运行中'
                              : '节点未运行'
                        : status?.phase == 'not-installed'
                        ? '未发现面板'
                        : status?.phase == 'failed'
                        ? '上次部署未完成'
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
            if (status?.isInstalling == true ||
                controller.startingDeployment) ...[
              const SizedBox(height: 24),
              _Stages(
                phase: status?.isInstalling == true ? status!.phase : 'queued',
              ),
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
            if (status != null && status.instances.isNotEmpty) ...[
              const SizedBox(height: 20),
              _Instances(
                key: ValueKey(controller.connectedHost),
                instances: status.instances,
                truncated: status.data['truncated'] == true,
                onCopy: (link) => _copy(context, link),
                onSave: (link) => _save(context, link),
                onManage: (instance) => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => ManagementScreen(
                      controller: controller,
                      instance: instance,
                    ),
                  ),
                ),
              ),
            ],
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

class _Instances extends StatefulWidget {
  const _Instances({
    super.key,
    required this.instances,
    required this.truncated,
    required this.onCopy,
    required this.onSave,
    required this.onManage,
  });
  final List<Map<String, dynamic>> instances;
  final bool truncated;
  final Future<void> Function(String) onCopy, onSave;
  final void Function(Map<String, dynamic>) onManage;
  @override
  State<_Instances> createState() => _InstancesState();
}

class _InstancesState extends State<_Instances> {
  String? selected;

  String _traffic(Map value) {
    final traffic = value['traffic'] as Map?;
    return '↑ ${formatBytes(traffic?['up'])}  ↓ ${formatBytes(traffic?['down'])}';
  }

  String _expiry(Object? value) {
    if (value is! int || value == 0) return '不限时';
    if (value < 0) return '首次使用后开始计时';
    try {
      return DateTime.fromMillisecondsSinceEpoch(value)
          .toLocal()
          .toString()
          .split('.')
          .first;
    } catch (_) {
      return '—';
    }
  }

  Future<void> _showNode(Map<String, dynamic> node, String protocol) async {
    final link = node['link'] as String;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 640),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                node['name'] as String,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text('$protocol · ${node['message'] ?? ''}'),
              const SizedBox(height: 16),
              Center(
                child: QrImageView(
                  data: link,
                  size: 190,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => widget.onCopy(link),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('复制节点链接'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => widget.onSave(link),
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('导出节点'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _Detail('服务器', '${node['host']}:${node['port']}'),
              if ((node['serverName'] as String?)?.isNotEmpty == true)
                _Detail('SNI', node['serverName'] as String),
              _Detail('流量', _traffic(node)),
              _Detail(
                '流量限额',
                node['total'] == 0 ? '不限量' : formatBytes(node['total']),
              ),
              _Detail('到期时间', _expiry(node['expiryTime'])),
              const SizedBox(height: 12),
              SelectableText(
                link,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              const Text('链接和二维码是节点访问凭据，请妥善保存。'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current =
        widget.instances.where((item) => item['id'] == selected).firstOrNull ??
        widget.instances.first;
    final inbounds = (current['inbounds'] as List).cast<Map<String, dynamic>>();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.instances.length > 1) ...[
          DropdownButtonFormField<String>(
            key: ValueKey(current['id']),
            initialValue: current['id'] as String,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '面板实例'),
            items: [
              for (final item in widget.instances)
                DropdownMenuItem(
                  value: item['id'] as String,
                  child: Text(
                    item['name'] as String,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => selected = value),
          ),
          const SizedBox(height: 16),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            StatusBadge(
              current['name'] as String,
              icon: current['kind'] == 'docker'
                  ? Icons.inventory_2_outlined
                  : Icons.dns_outlined,
            ),
            StatusBadge(
              current['running'] == true
                  ? '服务运行中'
                  : current['running'] == false
                  ? '服务已停止'
                  : '运行状态未知',
              active: current['running'] as bool?,
            ),
            if (current['panelVersion'] is String)
              StatusBadge(
                "${current['panelType'] ?? '3x-ui'} ${current['panelVersion']}",
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          current['message'] as String? ?? '',
          style: TextStyle(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () => widget.onManage(current),
          icon: const Icon(Icons.tune),
          label: const Text('管理此实例'),
        ),
        if (widget.truncated || current['truncated'] == true) ...[
          const SizedBox(height: 8),
          Text(
            '数据较多，本次仅显示部分记录；完整列表请在原面板查看。',
            style: TextStyle(color: colors.error),
          ),
        ],
        for (final inbound in inbounds)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colors.surfaceContainerLow,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ExpansionTile(
                key: ValueKey('${current['id']}:${inbound['id']}'),
                initiallyExpanded: inbounds.length == 1,
                shape: const Border(),
                collapsedShape: const Border(),
                title: Text(
                  inbound['name'] as String,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${(inbound['protocol'] as String).toUpperCase()} · ${inbound['port']} · ${inbound['enabled'] == true ? '已启用' : '已停用'}\n${_traffic(inbound)}',
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (inbound['message'] is String)
                    Text(inbound['message'] as String),
                  if ((inbound['clients'] as List).isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('此入站暂无可列出的客户端。'),
                    ),
                  for (final node
                      in (inbound['clients'] as List)
                          .cast<Map<String, dynamic>>())
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        node['name'] as String,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${node['message'] ?? ''} · ${_traffic(node)}${node['link'] == null ? '\n${node['linkMessage'] ?? '此配置暂无可导出的链接'}' : ''}',
                      ),
                      leading: Icon(
                        node['available'] == true
                            ? Icons.person_outline
                            : Icons.person_off_outlined,
                        color: node['available'] == true
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                      trailing: node['link'] != null
                          ? const Icon(Icons.qr_code_rounded)
                          : null,
                      onTap: node['link'] is String
                          ? () => _showNode(
                              node,
                              (inbound['protocol'] as String).toUpperCase(),
                            )
                          : null,
                    ),
                ],
              ),
            ),
          ),
      ],
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
      ('installing', '安装面板'),
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
          const SizedBox(height: 16),
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
