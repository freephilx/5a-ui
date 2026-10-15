import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:five_a_core/five_a_core.dart';

import '../controller.dart';
import 'cfnew.dart';
import '../saved_servers.dart';
import '../widgets/save_server_dialog.dart';
import '../widgets/auth_method_selector.dart';
import '../widgets/challenge.dart';
import '../widgets/status_panel.dart';
import '../widgets/ui.dart';
import '../widgets/sidebar.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.savedServers,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final ServerController controller;
  final SavedServers savedServers;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeChanged;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final host = TextEditingController(),
      username = TextEditingController(text: 'root');
  final port = TextEditingController(text: '22'),
      nodePort = TextEditingController(text: '443');
  final password = TextEditingController(),
      privateKey = TextEditingController(),
      passphrase = TextEditingController();
  final target = TextEditingController(), fingerprint = TextEditingController();
  final hostFocus = FocusNode();
  int page = 0;
  String panelType = '3x-ui';
  String auth = 'password';
  bool showPassword = false, sidebarCollapsed = false;
  final _resultKey = GlobalKey();
  final _errorKey = GlobalKey();
  final _cfnewKey = GlobalKey();
  String? keyName;
  String? selectedProfileId;
  int _formRevision = 0;
  SavedServers get savedServers => widget.savedServers;
  ServerController get controller => widget.controller;
  bool get working => controller.busy || controller.polling;
  static const destinations = [
    (Icons.dashboard_outlined, '概览'),
    (Icons.dns_outlined, '服务器'),
    (Icons.cloud_outlined, 'Cloudflare'),
    (Icons.tune_rounded, '设置'),
  ];

  @override
  void initState() {
    super.initState();
    for (final field in [
      host,
      username,
      port,
      password,
      privateKey,
      passphrase,
      fingerprint,
    ]) {
      field.addListener(_draftChanged);
    }
    _restoreSaved();
  }

  void _draftChanged() => _formRevision++;

  Future<void> _restoreSaved() async {
    final revision = _formRevision;
    final loaded = await savedServers.initialize();
    if (!mounted || !loaded || revision != _formRevision || page != 0) return;
    final saved = savedServers.selected;
    if (saved != null) _loadProfile(saved);
  }

  void _loadProfile(SavedServer profile) {
    controller.clear();
    final input = profile.connection;
    host.text = input.host;
    username.text = input.username;
    port.text = '${input.port}';
    password.text = input.password ?? '';
    privateKey.text = input.privateKey ?? '';
    passphrase.text = input.passphrase ?? '';
    fingerprint.text = input.hostFingerprint ?? '';
    nodePort.text = '443';
    target.clear();
    setState(() {
      auth = input.authMethod;
      panelType = '3x-ui';
      keyName = null;
      showPassword = false;
      selectedProfileId = profile.id;
      page = 1;
    });
  }

  Future<void> _selectProfile(SavedServer profile) async {
    if (await savedServers.select(profile.id) && mounted) _loadProfile(profile);
  }

  void _newServer() {
    _clear();
    host.clear();
    username.text = 'root';
    port.text = '22';
    nodePort.text = '443';
    target.clear();
    setState(() {
      selectedProfileId = null;
      auth = 'password';
      panelType = '3x-ui';
      page = 1;
    });
    hostFocus.requestFocus();
  }

  Future<void> _saveProfile() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final input = _input(ServerAction.status);
    final existing = savedServers.servers
        .where((s) => s.matches(input))
        .firstOrNull;
    final saved = await showDialog<SavedServer>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SaveServerDialog(
        servers: savedServers,
        input: input.withTrust(
          fingerprint:
              input.hostFingerprint ?? controller.fingerprintFor(input),
        ),
        existing: existing,
      ),
    );
    if (!mounted || saved == null) return;
    setState(() => selectedProfileId = saved.id);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('服务器已保存，下次打开自动填入')));
  }

  Future<void> _removeSaved(SavedServer? profile) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(profile == null ? '删除全部本机记录？' : '删除本机记录？'),
        content: const Text('删除保存的连接信息和登录凭据，服务器上的面板与节点不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (remove != true || !mounted) return;
    if (await savedServers.remove(profile?.id) &&
        mounted &&
        (profile == null || selectedProfileId == profile.id)) {
      _clear();
    }
  }

  @override
  void dispose() {
    for (final input in [
      host,
      username,
      port,
      nodePort,
      password,
      privateKey,
      passphrase,
      target,
      fingerprint,
    ]) {
      input.dispose();
    }
    hostFocus.dispose();
    super.dispose();
  }

  void _connect() {
    setState(() {
      page = 1;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) hostFocus.requestFocus();
    });
  }

  void _clear() {
    password.clear();
    privateKey.clear();
    passphrase.clear();
    fingerprint.clear();
    setState(() {
      keyName = null;
      showPassword = false;
      selectedProfileId = null;
    });
    controller.clear();
  }

  void _identityChanged(String _) {
    controller.clear();
    fingerprint.clear();
    setState(() => selectedProfileId = null);
  }

  Future<void> _perform(ServerAction action) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final input = _input(action);
    await controller.start(action, input);
    if (!mounted) return;
    final id = selectedProfileId;
    final trustedFingerprint = controller.status?.fingerprint;
    if (controller.error == null && id != null && trustedFingerprint != null) {
      await savedServers.rememberFingerprint(id, input, trustedFingerprint);
    }
    if (!mounted || page != 1) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = controller.error == null
          ? _resultKey.currentContext
          : _errorKey.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 240),
          alignment: 0.1,
        );
      }
    });
  }

  ConnectionInput _input(ServerAction action) => ConnectionInput(
    host: host.text.trim(),
    username: username.text.trim(),
    port: int.tryParse(port.text) ?? -1,
    nodePort: action == ServerAction.install
        ? int.tryParse(nodePort.text) ?? -1
        : 443,
    panelType: action == ServerAction.install ? panelType : '3x-ui',
    authMethod: auth,
    password: auth == 'password' ? password.text : null,
    privateKey: auth == 'key' ? privateKey.text : null,
    passphrase: auth == 'key' ? passphrase.text : null,
    realityServerName:
        action != ServerAction.install || target.text.trim().isEmpty
        ? null
        : target.text.trim(),
    hostFingerprint: fingerprint.text.trim().isEmpty
        ? null
        : fingerprint.text.trim(),
  );

  Future<void> _pickKey() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
        dialogTitle: '选择 SSH 私钥',
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (file.size > 64 * 1024 || file.bytes == null) {
        controller.showError('私钥文件最大支持 64 KB，请重新选择。');
        return;
      }
      privateKey.text = utf8.decode(file.bytes!);
      setState(() => keyName = file.name);
    } catch (_) {
      if (mounted) controller.showError('无法读取私钥文件，请重新选择或直接粘贴。');
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([controller, savedServers]),
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 840;
      final nativeMac =
          !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
      final theme = Theme.of(context);
      final body = ColoredBox(
        color: theme.scaffoldBackgroundColor,
        child: SafeArea(
          minimum: EdgeInsets.only(top: nativeMac && !wide ? 32 : 0),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(wide ? 32 : 20, 20, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            destinations[page].$2,
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            switch (page) {
                              0 => controller.connectedHost ?? '连接、部署与管理',
                              1 => '通过 SSH 接入你的服务器',
                              2 => 'cfnew 一键部署',
                              _ => '外观与会话偏好',
                            },
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: theme.brightness == Brightness.dark
                          ? '切换浅色主题'
                          : '切换深色主题',
                      onPressed: () => widget.onThemeChanged(
                        theme.brightness == Brightness.dark
                            ? ThemeMode.light
                            : ThemeMode.dark,
                      ),
                      icon: Icon(
                        theme.brightness == Brightness.dark
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: ValueKey(page),
                  padding: EdgeInsets.fromLTRB(
                    wide ? 32 : 16,
                    12,
                    wide ? 32 : 16,
                    32,
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1180),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (savedServers.error != null) ...[
                            StateNotice(savedServers.error!, error: true),
                            TextButton(
                              onPressed: savedServers.busy
                                  ? null
                                  : () => savedServers.initialize(),
                              child: const Text('重新读取本机记录'),
                            ),
                            const SizedBox(height: 16),
                          ],
                          if (controller.error != null) ...[
                            _errorBanner(),
                            const SizedBox(height: 16),
                          ],
                          if (!controller.configLoaded)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: controller.error == null
                                  ? const LinearProgressIndicator()
                                  : OutlinedButton.icon(
                                      onPressed: controller.initialize,
                                      icon: const Icon(Icons.refresh),
                                      label: const Text('重新加载服务配置'),
                                    ),
                            ),
                          switch (page) {
                            0 => _overview(),
                            1 => _serverPage(),
                            2 => const SizedBox.shrink(),
                            _ => _settings(),
                          },
                          Offstage(
                            offstage: page != 2,
                            child: CfnewPanel(
                              key: _cfnewKey,
                              active: page == 2,
                              configLoaded: controller.configLoaded,
                              siteKey: controller.siteKey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      return Scaffold(
        backgroundColor: nativeMac ? Colors.transparent : null,
        body: Row(
          children: [
            if (wide)
              AppSidebar(
                labels: [for (final item in destinations) item.$2],
                selectedIndex: page,
                expanded: !sidebarCollapsed,
                onSelected: (value) => setState(() => page = value),
                onToggle: () =>
                    setState(() => sidebarCollapsed = !sidebarCollapsed),
              ),
            Expanded(child: body),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: NavigationBar(
                      selectedIndex: page,
                      onDestinationSelected: (value) =>
                          setState(() => page = value),
                      height: 68,
                      destinations: [
                        for (final item in destinations)
                          NavigationDestination(
                            icon: Icon(item.$1),
                            label: item.$2,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
      );
    },
  );

  Widget _errorBanner() =>
      StateNotice(controller.error!, key: _errorKey, error: true);

  Widget _overview() {
    final data = controller.status?.data;
    final memory = data?['memory'] as Map?;
    final traffic = data?['traffic'] as Map?;
    final cpu = data?['cpu'] as num?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (data != null)
          LayoutBuilder(
            builder: (context, constraints) {
              final count = constraints.maxWidth >= 760
                  ? 4
                  : constraints.maxWidth >= 320
                  ? 2
                  : 1;
              final width = (constraints.maxWidth - (count - 1) * 16) / count;
              final cards = [
                MetricCard(
                  icon: Icons.power_settings_new_rounded,
                  label: '服务状态',
                  value: controller.status == null
                      ? '未连接'
                      : controller.status!.running
                      ? '运行中'
                      : controller.status!.isInstalling
                      ? '部署中'
                      : '未运行',
                  caption: controller.connectedHost ?? '连接服务器后查看',
                ),
                MetricCard(
                  icon: Icons.memory_rounded,
                  label: 'CPU 使用率',
                  value: cpu == null ? '—' : '${cpu.toStringAsFixed(1)}%',
                  caption: '服务器实时负载',
                ),
                MetricCard(
                  icon: Icons.storage_rounded,
                  label: '内存用量',
                  value: formatBytes(memory?['current']),
                  caption: memory == null
                      ? '读取状态后查看'
                      : '共 ${formatBytes(memory['total'])}',
                ),
                MetricCard(
                  icon: Icons.swap_vert_rounded,
                  label: '累计流量',
                  value: traffic == null
                      ? '—'
                      : formatBytes(
                          (traffic['up'] as num) + (traffic['down'] as num),
                        ),
                  caption: traffic == null
                      ? '上传与下载'
                      : '↑ ${formatBytes(traffic['up'])}  ↓ ${formatBytes(traffic['down'])}',
                ),
              ];
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  for (final card in cards) SizedBox(width: width, child: card),
                ],
              );
            },
          ),
        if (data != null) const SizedBox(height: 20),
        _statusResult(),
        const SizedBox(height: 16),
        SectionCard(
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('部署 cfnew'),
            subtitle: const Text('Cloudflare Workers · 无需 VPS'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => setState(() => page = 2),
          ),
        ),
      ],
    );
  }

  Widget _serverPage() => LayoutBuilder(
    builder: (context, constraints) {
      final hasResult = controller.status != null || working;
      if (!hasResult) {
        return Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: _connectionForm(),
          ),
        );
      }
      final result = _statusResult();
      if (constraints.maxWidth < 820) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_connectionForm(), const SizedBox(height: 16), result],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 410, child: _connectionForm()),
          const SizedBox(width: 20),
          Expanded(child: result),
        ],
      );
    },
  );

  Widget _statusResult() => Column(
    key: _resultKey,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      StatusPanel(controller: controller, onConnect: _connect),
      if (controller.deploymentAvailable) ...[
        const SizedBox(height: 16),
        _deploymentForm(),
      ],
    ],
  );

  Widget _deploymentForm() {
    final theme = Theme.of(context);
    final retry = controller.status?.phase == 'failed';
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(retry ? '继续部署' : '部署面板', style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            retry
                ? '上次部署未完成，请选择原面板类型重试。'
                : '已连接，未发现已有面板。选择面板后，将自动创建 VLESS + REALITY 节点。',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: panelType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '部署面板类型'),
            items: const [
              DropdownMenuItem(value: '3x-ui', child: Text('3x-ui · Xray（默认）')),
              DropdownMenuItem(value: '3m-ui', child: Text('3m-ui · Mihomo')),
            ],
            onChanged: working
                ? null
                : (value) => setState(() => panelType = value!),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('部署设置'),
            children: [
              const SizedBox(height: 4),
              _field(nodePort, '节点端口', keyboard: TextInputType.number),
              const SizedBox(height: 16),
              _field(target, 'REALITY 目标（可选）', hint: '留空自动选择'),
              const SizedBox(height: 16),
            ],
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: controller.canDeploy
                ? () => _perform(ServerAction.install)
                : null,
            icon: const Icon(Icons.rocket_launch_outlined, size: 19),
            label: Text(retry ? '重试部署' : '一键部署'),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController value,
    String label, {
    String? hint,
    bool secret = false,
    TextInputType? keyboard,
    ValueChanged<String>? onChanged,
    FocusNode? focus,
    int lines = 1,
  }) => TextField(
    controller: value,
    enabled: !working && !savedServers.busy,
    focusNode: focus,
    obscureText: secret,
    minLines: lines,
    maxLines: secret ? 1 : lines,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      alignLabelWithHint: lines > 1,
    ),
  );

  Widget _credentials() => Column(
    key: ValueKey(auth),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (auth == 'password')
        TextField(
          controller: password,
          enabled: !working && !savedServers.busy,
          obscureText: !showPassword,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'SSH 密码',
            suffixIcon: IconButton(
              tooltip: showPassword ? '隐藏密码' : '显示密码',
              icon: Icon(
                showPassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: working
                  ? null
                  : () => setState(() => showPassword = !showPassword),
            ),
          ),
        )
      else ...[
        FilledButton.tonalIcon(
          onPressed: working ? null : _pickKey,
          icon: const Icon(Icons.upload_file_rounded),
          label: Text(keyName ?? '选择私钥文件', overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(height: 12),
        _field(
          privateKey,
          '或粘贴 SSH 私钥',
          hint: '-----BEGIN OPENSSH PRIVATE KEY-----',
          lines: 4,
        ),
        const SizedBox(height: 12),
        _field(passphrase, '密钥口令（如有）', secret: true),
      ],
    ],
  );

  Widget _connectionForm() {
    final theme = Theme.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('连接服务器', style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            '连接后自动识别 3x-ui / 3m-ui；未安装时可一键部署。',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          if (savedServers.servers.isNotEmpty) ...[
            DropdownButtonFormField<String>(
              key: ValueKey(selectedProfileId),
              initialValue:
                  savedServers.servers.any((s) => s.id == selectedProfileId)
                  ? selectedProfileId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: '已保存的服务器'),
              items: [
                for (final server in savedServers.servers)
                  DropdownMenuItem(
                    value: server.id,
                    child: Text(server.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: working || savedServers.busy
                  ? null
                  : (id) => _selectProfile(
                      savedServers.servers.firstWhere((s) => s.id == id),
                    ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: working || savedServers.busy ? null : _newServer,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增服务器'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _field(
            host,
            '公网 IP',
            hint: 'IPv4 或 IPv6 地址',
            focus: hostFocus,
            onChanged: _identityChanged,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: _field(username, '用户名', onChanged: _identityChanged),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _field(
                  port,
                  'SSH 端口',
                  keyboard: TextInputType.number,
                  onChanged: _identityChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          AuthMethodSelector(
            value: auth,
            onChanged: working
                ? null
                : (value) {
                    if (auth == value) return;
                    setState(() {
                      auth = value;
                      showPassword = false;
                    });
                  },
          ),
          const SizedBox(height: 20),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _credentials(),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('高级设置'),
            children: [
              const SizedBox(height: 4),
              _field(fingerprint, '已知 SSH 主机指纹（可选）', hint: 'SHA256:…'),
              const SizedBox(height: 12),
              Text(
                '首次连接会记录主机指纹。也可以填写从服务器控制台核对的指纹。',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
            ],
          ),
          if (controller.siteKey != null) ...[
            const SizedBox(height: 12),
            VerificationChallenge(
              key: ValueKey(controller.challenge),
              siteKey: controller.siteKey!,
              onToken: controller.setToken,
              onError: controller.showError,
            ),
            TextButton(
              onPressed: () {
                controller.setToken('');
                setState(() => controller.challenge++);
              },
              child: const Text('重新验证'),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: controller.canRequest && !savedServers.busy
                ? () => _perform(ServerAction.status)
                : null,
            icon: const Icon(Icons.login_rounded, size: 19),
            label: Text(working ? '正在读取…' : '连接并读取'),
          ),
          if (working)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: TextButton.icon(
                onPressed: controller.pause,
                icon: const Icon(Icons.pause_rounded),
                label: const Text('暂停刷新'),
              ),
            ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: working || savedServers.busy || !savedServers.loaded
                ? null
                : _saveProfile,
            icon: const Icon(Icons.bookmark_add_outlined, size: 18),
            label: const Text('保存服务器'),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.lock_reset_rounded, size: 18),
            label: const Text('清除登录凭据'),
          ),
        ],
      ),
    );
  }

  Widget _settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('外观', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 20),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  icon: Icon(Icons.brightness_auto_outlined),
                  label: Text('系统'),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  icon: Icon(Icons.light_mode_outlined),
                  label: Text('浅色'),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  icon: Icon(Icons.dark_mode_outlined),
                  label: Text('深色'),
                ),
              ],
              selected: {widget.themeMode},
              onSelectionChanged: (value) => widget.onThemeChanged(value.first),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (savedServers.servers.isNotEmpty) ...[
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('已保存的服务器', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              for (final server in savedServers.servers)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(server.name),
                  subtitle: Text(
                    '${server.connection.username}@${server.connection.host}:${server.connection.port}\n${server.includesCredentials ? '包含登录凭据' : '仅服务器信息'}',
                  ),
                  onTap: working || savedServers.busy
                      ? null
                      : () => _selectProfile(server),
                  trailing: IconButton(
                    tooltip: '删除 ${server.name}',
                    onPressed: working || savedServers.busy
                        ? null
                        : () => _removeSaved(server),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ),
              TextButton(
                onPressed: working || savedServers.busy
                    ? null
                    : () => _removeSaved(null),
                child: const Text('删除全部本机记录'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
      ],
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('隐私与连接', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              '只有点击“保存服务器”后，连接信息才会保存；是否包含密码、私钥和口令由你选择。下次打开会恢复最后选择的服务器，点击连接后读取最新状态。\n\n使用 Web 版时，浏览器保存的内容可由本站点读取，连接时后端也会处理 SSH 凭据，请选择可信的部署实例。\n\n清除本次会话凭据不会删除已保存的服务器；删除本机记录请使用上方列表。服务器上的节点和后台安装均不受影响。',
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.lock_reset_rounded),
              label: const Text('清除本次会话凭据'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('5a-ui', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            const Text('3x-ui / 3m-ui 部署与管理\nFlutter 跨平台客户端 · MIT License'),
            const SizedBox(height: 12),
            const SelectableText('https://github.com/freephilx/5a-ui'),
          ],
        ),
      ),
    ],
  );
}
