import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:five_a_core/five_a_core.dart';

import '../controller.dart';
import '../widgets/challenge.dart';
import '../widgets/status_panel.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    required this.themeMode,
    required this.onThemeChanged,
  });
  final ServerController controller;
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
  String auth = 'password';
  bool showPassword = false;
  String? keyName;
  ServerController get controller => widget.controller;
  bool get working => controller.busy || controller.polling;
  static const destinations = [
    (Icons.dashboard_outlined, '概览'),
    (Icons.dns_outlined, '服务器'),
    (Icons.tune_rounded, '设置'),
  ];

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
    setState(() => page = 1);
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
    });
    controller.clear();
  }

  void _identityChanged(String _) {
    controller.clear();
    fingerprint.clear();
  }

  void _perform(ServerAction action) {
    FocusManager.instance.primaryFocus?.unfocus();
    controller.start(
      action,
      ConnectionInput(
        host: host.text.trim(),
        username: username.text.trim(),
        port: int.tryParse(port.text) ?? -1,
        nodePort: int.tryParse(nodePort.text) ?? -1,
        authMethod: auth,
        password: password.text,
        privateKey: privateKey.text,
        passphrase: passphrase.text,
        realityServerName: target.text.trim().isEmpty
            ? null
            : target.text.trim(),
        hostFingerprint: fingerprint.text.trim().isEmpty
            ? null
            : fingerprint.text.trim(),
      ),
    );
  }

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
    listenable: controller,
    builder: (context, _) {
      final wide = MediaQuery.sizeOf(context).width >= 840;
      final theme = Theme.of(context);
      final body = SafeArea(
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
                          style: theme.textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          switch (page) {
                            0 => '你的服务器，一目了然。',
                            1 => '从连接到部署，都在这里。',
                            _ => '让 5a-ui 更适合你。',
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
                          _ => _settings(),
                        },
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
      return Scaffold(
        body: Row(
          children: [
            if (wide) _sidebar(),
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

  Widget _sidebar() {
    final theme = Theme.of(context);
    return Container(
      width: 216,
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 20,
                  horizontal: 8,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        Icons.hub_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text('5a-ui', style: theme.textTheme.titleLarge),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              for (var i = 0; i < destinations.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      selected: page == i,
                      selectedTileColor: theme.colorScheme.secondaryContainer,
                      selectedColor: theme.colorScheme.onSecondaryContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      leading: Icon(destinations[i].$1),
                      title: Text(destinations[i].$2),
                      onTap: () => setState(() => page = i),
                    ),
                  ),
                ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 10),
                    Text('掌握自己的连接', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 5),
                    Text(
                      '凭据仅保留在本次会话',
                      style: theme.textTheme.bodySmall!.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _errorBanner() {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: colors.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              controller.error!,
              style: TextStyle(color: colors.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overview() {
    final data = controller.status?.data;
    final memory = data?['memory'] as Map?;
    final traffic = data?['traffic'] as Map?;
    final cpu = data?['cpu'] as num?;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        const SizedBox(height: 20),
        StatusPanel(controller: controller, onConnect: _connect),
        const SizedBox(height: 20),
        _requirements(),
      ],
    );
  }

  Widget _serverPage() => LayoutBuilder(
    builder: (context, constraints) {
      final form = _connectionForm();
      final status = StatusPanel(
        controller: controller,
        onConnect: () => hostFocus.requestFocus(),
      );
      if (constraints.maxWidth < 880) {
        return Column(children: [form, const SizedBox(height: 20), status]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 410, child: form),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [status, const SizedBox(height: 20), _requirements()],
            ),
          ),
        ],
      );
    },
  );

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
    enabled: !working,
    focusNode: focus,
    obscureText: secret,
    minLines: lines,
    maxLines: secret ? 1 : lines,
    keyboardType: keyboard,
    autocorrect: false,
    enableSuggestions: false,
    onChanged: onChanged,
    decoration: InputDecoration(labelText: label, hintText: hint),
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
            '使用 SSH 密码或私钥，无需注册。',
            style: theme.textTheme.bodyMedium!.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
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
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'password',
                icon: Icon(Icons.password_rounded),
                label: Text('密码'),
              ),
              ButtonSegment(
                value: 'key',
                icon: Icon(Icons.key_rounded),
                label: Text('私钥'),
              ),
            ],
            selected: {auth},
            onSelectionChanged: working
                ? null
                : (value) {
                    setState(() {
                      auth = value.first;
                      password.clear();
                      privateKey.clear();
                      passphrase.clear();
                      keyName = null;
                    });
                  },
          ),
          const SizedBox(height: 20),
          if (auth == 'password')
            TextField(
              controller: password,
              enabled: !working,
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
                  onPressed: () => setState(() => showPassword = !showPassword),
                ),
              ),
            )
          else ...[
            OutlinedButton.icon(
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
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('高级设置'),
            children: [
              const SizedBox(height: 4),
              _field(nodePort, '节点端口', keyboard: TextInputType.number),
              const SizedBox(height: 16),
              _field(target, 'REALITY 目标（可选）', hint: '留空自动选择'),
              const SizedBox(height: 16),
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
            onPressed: controller.canRequest
                ? () => _perform(
                    controller.status?.data['installed'] == true
                        ? ServerAction.status
                        : ServerAction.install,
                  )
                : null,
            icon: const Icon(Icons.rocket_launch_outlined, size: 19),
            label: Text(
              controller.status?.data['installed'] == true ? '读取已有服务' : '一键部署',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: controller.canRequest
                ? () => _perform(ServerAction.status)
                : null,
            icon: const Icon(Icons.sync_rounded, size: 19),
            label: const Text('读取状态'),
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
          TextButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.lock_reset_rounded, size: 18),
            label: const Text('清除登录凭据'),
          ),
        ],
      ),
    );
  }

  Widget _requirements() => SectionCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.info_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text('开始之前', style: Theme.of(context).textTheme.titleMedium),
          ],
        ),
        const SizedBox(height: 16),
        const Text(
          '接入已有服务：Linux + Python 3\n新部署：Debian 11+ 或 Ubuntu 20.04+\nroot 或具有免密 sudo 权限的账号\n安全组放行 SSH 与节点端口',
        ),
        const SizedBox(height: 12),
        Text(
          '已有 3x-ui 会直接接入，可查看实例、入站和客户端；保留原配置，无需重新部署。',
          style: Theme.of(context).textTheme.bodySmall!
              .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    ),
  );

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
      SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('隐私与连接', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
              'SSH 密码、私钥和口令只保存在本次会话内存中。关闭应用后，需要重新输入。\n\n使用 Web 版时，提供服务的后端会处理你的 SSH 凭据，请选择可信的部署实例。\n\n清除凭据不会删除服务器上的节点，也不会中断正在执行的安装。',
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
            const Text('3x-ui 一键部署与状态管理\nFlutter 跨平台客户端 · MIT License'),
            const SizedBox(height: 12),
            const SelectableText('https://github.com/freephilx/5a-ui'),
          ],
        ),
      ),
    ],
  );
}
