import 'dart:convert';

import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/cfnew_gateway.dart';
import '../services/export.dart';
import '../widgets/challenge.dart';
import '../widgets/status_panel.dart';
import '../widgets/ui.dart';

class CfnewPanel extends StatefulWidget {
  const CfnewPanel({
    super.key,
    required this.configLoaded,
    this.active = true,
    this.siteKey,
    this.gateway,
  });
  final bool configLoaded;
  final bool active;
  final String? siteKey;
  final CfnewGateway? gateway;
  @override
  State<CfnewPanel> createState() => _CfnewPanelState();
}

class _CfnewPanelState extends State<CfnewPanel> {
  final account = TextEditingController(), token = TextEditingController();
  late final uuid = TextEditingController(text: newCfnewUuid());
  late final name = TextEditingController(
    text: 'cfnew-${uuid.text.substring(0, 8)}',
  );
  late final gateway = widget.gateway ?? createCfnewGateway();
  bool busy = false, pause = false, showToken = false;
  String? error, progress, namespaceId, proof;
  String challengeToken = '';
  int challenge = 0;
  Map<String, dynamic>? result;

  @override
  void dispose() {
    for (final c in [account, token, uuid, name]) {
      c.dispose();
    }
    gateway.dispose();
    super.dispose();
  }

  Map<String, dynamic> input(String step) => {
    'accountId': account.text.trim().toLowerCase(),
    'apiToken': token.text.trim(),
    'workerName': name.text.trim(),
    'uuid': uuid.text.trim().toLowerCase(),
    'step': step,
    if (namespaceId != null) 'namespaceId': namespaceId,
    if (proof != null) 'proofToken': proof,
    if (challengeToken.isNotEmpty) 'turnstileToken': challengeToken,
  };
  void reset(String _) => setState(() {
    namespaceId = null;
    proof = null;
    result = null;
    error = null;
    progress = null;
  });
  Future<void> deploy({bool verifyOnly = false}) async {
    if (busy) return;
    try {
      CfnewInput.parse(input(verifyOnly ? 'verify' : 'prepare'));
    } on AppException catch (e) {
      setState(() => error = e.message);
      return;
    }
    setState(() {
      busy = true;
      pause = false;
      error = null;
    });
    try {
      for (final step in verifyOnly ? ['verify'] : cfnewSteps) {
        if (!mounted || pause) break;
        setState(
          () => progress = switch (step) {
            'prepare' => '正在检查账号与准备配置存储…',
            'upload' => '正在下载并校验 cfnew、上传 Worker…',
            'activate' => '正在启用访问并回读部署结果…',
            _ => '正在验证 cfnew 管理接口…',
          },
        );
        final response = await gateway.perform(CfnewInput.parse(input(step)));
        if (!mounted) return;
        if (response['step'] != step || response['namespaceId'] is! String) {
          throw const AppException('CF_RESPONSE', '部署响应不完整，请使用原参数重试。');
        }
        namespaceId = response['namespaceId'] as String;
        proof = response['proofToken'] as String? ?? proof;
        if (response['phase'] == 'deployed') result = response;
        setState(() {});
      }
      if (mounted) {
        setState(
          () => progress = pause
              ? '后续步骤已暂停，点击继续部署可恢复。'
              : result?['runtimeVerified'] == true
              ? '部署完成，管理接口与 KV 绑定已验证。'
              : '部署已提交；边缘访问验证尚未通过，可稍后重新验证。',
        );
      }
    } on AppException catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          progress = '部署已暂停，修正后可使用原参数重试。';
          if (e.code.startsWith('CAPTCHA')) proof = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          error = '部署结果未能确认，请保持原账号、名称和 UUID 重试。';
          progress = '部署已暂停。';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          challengeToken = '';
          challenge++;
        });
      }
    }
  }

  Future<void> copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制')));
      }
    } catch (_) {
      if (mounted) setState(() => error = '复制失败，请长按文字手动复制。');
    }
  }

  Future<void> export() async {
    try {
      await saveData(
        Uint8List.fromList(
          utf8.encode(
            const JsonEncoder.withIndent('  ').convert({
              'product': 'cfnew',
              'version': cfnewRelease['version'],
              'accountId': account.text.trim(),
              'workerName': name.text.trim(),
              'uuid': uuid.text.trim(),
              'namespaceId': namespaceId,
              for (final key in [
                'managementUrl',
                'subscriptionUrl',
                'clashUrl',
                'dashboardUrl',
              ])
                if (result?[key] != null) key: result![key],
            }),
          ),
        ),
        '5a-ui-cfnew.json',
      );
    } catch (_) {
      if (mounted) setState(() => error = '导出失败，请复制 UUID 和部署地址。');
    }
  }

  Widget field(
    TextEditingController c,
    String label, {
    bool secret = false,
    bool identity = false,
    Widget? suffix,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextField(
      controller: c,
      enabled: !busy,
      obscureText: secret,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: identity ? reset : (_) => setState(() {}),
      decoration: InputDecoration(labelText: label, suffixIcon: suffix),
    ),
  );
  Widget link(String label, String key) => Padding(
    padding: const EdgeInsets.only(top: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            IconButton(
              tooltip: '复制$label',
              onPressed: () => copy(result![key] as String),
              icon: const Icon(Icons.copy_outlined, size: 18),
            ),
          ],
        ),
        SelectableText(result![key] as String),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 640),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'cfnew · Cloudflare',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('无需 VPS。创建 Worker 与配置存储，自动生成节点、管理页面和订阅地址。'),
                const SizedBox(height: 24),
                field(account, 'Cloudflare 账号 ID', identity: true),
                field(
                  token,
                  'Cloudflare API Token',
                  secret: !showToken,
                  suffix: IconButton(
                    tooltip: showToken ? '隐藏 Token' : '显示 Token',
                    onPressed: busy
                        ? null
                        : () => setState(() => showToken = !showToken),
                    icon: Icon(
                      showToken
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
                field(name, 'Worker 名称', identity: true),
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: const Text('访问凭据与部署说明'),
                  children: [
                    field(
                      uuid,
                      '访问 UUID（已自动生成）',
                      identity: true,
                      suffix: IconButton(
                        tooltip: '复制 UUID',
                        onPressed: () => copy(uuid.text),
                        icon: const Icon(Icons.copy_outlined),
                      ),
                    ),
                    const Text(
                      'Token 需要指定账号的 Workers Scripts 和 Workers KV Storage 编辑权限。账号需先在 Cloudflare 控制台启用 workers.dev。\n\nUUID 同时保护管理页面与订阅，请妥善保存。相同账号、名称和 UUID 可继续未完成的部署；已有其他 Worker 不会被覆盖。',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      kIsWeb
                          ? 'API Token 仅保留在本次会话；部署时交由本站后端调用 Cloudflare。请使用可信的 5a-ui 部署。'
                          : 'API Token 仅保留在本次会话，由应用直接调用 Cloudflare。',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '使用上游 v3.1，默认 VLESS + TLS 原生节点。优选地址、其他协议和家宽链式可在 cfnew 管理页面自行配置。使用 Cloudflare 账号现有额度，未开通或升级付费套餐。',
                    ),
                    const SizedBox(height: 12),
                    const SelectableText(
                      'https://github.com/byJoey/cfnew/tree/v3.1',
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
                if (widget.active &&
                    widget.siteKey != null &&
                    proof == null) ...[
                  VerificationChallenge(
                    key: ValueKey(challenge),
                    siteKey: widget.siteKey!,
                    onToken: (value) => setState(() => challengeToken = value),
                    onError: (value) => setState(() => error = value),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => setState(() => challenge++),
                    child: const Text('重新验证'),
                  ),
                ],
                const SizedBox(height: 16),
                if (error != null) ...[
                  StateNotice(error!, error: true),
                  const SizedBox(height: 12),
                ],
                if (progress != null) ...[
                  Text(progress!),
                  const SizedBox(height: 12),
                ],
                if (busy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                FilledButton.icon(
                  onPressed:
                      busy ||
                          !widget.configLoaded ||
                          (widget.siteKey != null &&
                              proof == null &&
                              challengeToken.isEmpty)
                      ? null
                      : () => deploy(),
                  icon: const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    busy
                        ? '正在部署…'
                        : namespaceId == null
                        ? '一键部署 cfnew'
                        : '继续 / 重新检查部署',
                  ),
                ),
                if (busy)
                  TextButton(
                    onPressed: () => setState(() => pause = true),
                    child: const Text('暂停后续步骤'),
                  ),
                if (namespaceId != null)
                  TextButton.icon(
                    onPressed: busy ? null : export,
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('导出部署信息（包含 UUID）'),
                  ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() {
                          token.clear();
                          proof = null;
                          showToken = false;
                        }),
                  child: const Text('清除 API Token'),
                ),
              ],
            ),
          ),
          if (result != null) ...[
            const SizedBox(height: 20),
            SectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result!['runtimeVerified'] == true
                        ? 'cfnew 已就绪'
                        : 'cfnew 已部署，访问待验证',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('管理与订阅链接含访问凭据。配置与协议管理请进入 cfnew 原生面板。'),
                  link('管理地址', 'managementUrl'),
                  link('通用订阅', 'subscriptionUrl'),
                  link('Clash / Mihomo 订阅', 'clashUrl'),
                  link('Cloudflare 控制台', 'dashboardUrl'),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: busy || token.text.isEmpty
                        ? null
                        : () => deploy(verifyOnly: true),
                    icon: const Icon(Icons.refresh),
                    label: const Text('重新验证访问'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    ),
  );
}
