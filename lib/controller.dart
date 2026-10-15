import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:five_a_core/five_a_core.dart';

class ServerController extends ChangeNotifier {
  ServerController(
    this.gateway, {
    this.pollInterval = const Duration(seconds: 6),
  });
  final ServerGateway gateway;
  final Duration pollInterval;
  ServerStatus? status;
  ConnectionInput? _connection;
  String? error, siteKey;
  String token = '';
  bool configLoaded = false, busy = false, polling = false, paused = false;
  int challenge = 0, _epoch = 0;
  Timer? _timer;
  DateTime? _until;
  bool _disposed = false;
  bool _deploymentAvailable = false;
  ServerAction? _activeAction;
  bool get deploymentAvailable => _deploymentAvailable;
  bool get canDeploy => deploymentAvailable && canRequest;
  bool get startingDeployment => busy && _activeAction == ServerAction.install;
  bool get canRequest =>
      configLoaded &&
      !busy &&
      !polling &&
      (siteKey == null || token.isNotEmpty || _connection?.proofToken != null);
  bool get canRefresh => _connection != null && canRequest;
  String? get connectedUsername => _connection?.username;
  String? get connectedHost => _connection?.host;
  String? fingerprintFor(ConnectionInput input) =>
      _connection?.host == input.host &&
          _connection?.port == input.port &&
          _connection?.username == input.username
      ? _connection?.hostFingerprint
      : null;

  Future<void> initialize() async {
    error = null;
    try {
      final key = await gateway.loadSiteKey();
      if (_disposed) return;
      siteKey = key;
      configLoaded = true;
    } catch (_) {
      if (_disposed) return;
      error = '服务配置加载失败，请检查网络后重试。';
    }
    notifyListeners();
  }

  void setToken(String value) {
    token = value;
    notifyListeners();
  }

  void showError(String message) {
    error = message;
    notifyListeners();
  }

  Future<void> start(ServerAction action, ConnectionInput input) async {
    if (busy || polling || !configLoaded) return;
    error = null;
    try {
      final same =
          _connection?.host == input.host &&
          _connection?.port == input.port &&
          _connection?.username == input.username;
      if (action == ServerAction.install && (!same || !canDeploy)) {
        throw const AppException(
          'INSPECTION_REQUIRED',
          '请先连接并读取服务器，确认没有已有面板或存在未完成的部署后再继续。',
        );
      }
      _connection = validateInput({
        ...input.toJson(),
        if (same &&
            input.hostFingerprint == null &&
            _connection?.hostFingerprint != null)
          'hostFingerprint': _connection!.hostFingerprint,
        if (same && _connection?.proofToken != null)
          'proofToken': _connection!.proofToken,
        if (token.isNotEmpty) 'turnstileToken': token,
      });
    } on AppException catch (exception) {
      error = exception.message;
      notifyListeners();
      return;
    }
    paused = false;
    _deploymentAvailable = false;
    _until = DateTime.now().add(const Duration(minutes: 30));
    await _request(action, ++_epoch);
  }

  Future<void> refresh() async {
    if (_connection != null) await start(ServerAction.status, _connection!);
  }

  Future<Map<String, dynamic>> manage(Map<String, dynamic> request) async {
    if (_connection == null || !canRequest) {
      throw const AppException('NOT_CONNECTED', '请先连接服务器，并等待当前操作完成。');
    }
    final epoch = _epoch;
    final input = validateInput({
      ..._connection!.toJson(),
      'management': request,
    });
    busy = true;
    notifyListeners();
    try {
      final response = await gateway.perform(ServerAction.manage, input);
      if (_disposed || epoch != _epoch) {
        throw const AppException('CANCELLED', '连接已更换或操作已取消，请重新读取确认结果。');
      }
      _connection = _connection!.withTrust(
        fingerprint: response.fingerprint,
        proof: response.proofToken,
      );
      final result = response.data['management'];
      if (result is! Map<String, dynamic>) {
        throw const AppException('PANEL_RESPONSE', '管理响应格式不正确，请重新读取确认结果。');
      }
      return result;
    } finally {
      if (!_disposed && epoch == _epoch) {
        busy = false;
        notifyListeners();
      }
    }
  }

  Future<void> _request(ServerAction action, int epoch) async {
    _activeAction = action;
    busy = true;
    notifyListeners();
    try {
      final next = await gateway.perform(action, _connection!);
      if (_disposed || epoch != _epoch) return;
      status = next;
      _deploymentAvailable =
          (next.phase == 'not-installed' || next.phase == 'failed') &&
          next.instances.isEmpty &&
          next.data['installed'] != true;
      _connection = _connection!.withTrust(
        resolvedUsername: _connection!.username.isEmpty
            ? next.sshUsername
            : null,
        fingerprint: next.fingerprint,
        proof: next.proofToken,
      );
      token = '';
      if (siteKey != null && _connection!.proofToken == null) challenge++;
      if (next.isInstalling && DateTime.now().isBefore(_until!)) {
        polling = true;
        _timer = Timer(
          pollInterval,
          () => _request(ServerAction.status, epoch),
        );
      } else {
        polling = false;
        paused = next.isInstalling;
      }
    } catch (exception) {
      if (_disposed || epoch != _epoch) return;
      polling = false;
      _deploymentAvailable = false;
      paused = status?.isInstalling ?? false;
      error = exception is AppException
          ? exception.message
          : '网络连接中断或响应超时。已启动的安装会继续，请重新读取状态。';
      if (siteKey != null &&
          (exception is AppException && exception.code.startsWith('CAPTCHA_') ||
              _connection?.proofToken == null)) {
        token = '';
        challenge++;
        _connection = validateInput(
          {..._connection!.toJson()}
            ..remove('proofToken')
            ..remove('turnstileToken'),
        );
      }
    } finally {
      if (!_disposed && epoch == _epoch) {
        _activeAction = null;
        busy = false;
        notifyListeners();
      }
    }
  }

  void pause() {
    _epoch++;
    _timer?.cancel();
    gateway.cancel();
    _activeAction = null;
    busy = false;
    polling = false;
    paused = true;
    _deploymentAvailable = false;
    notifyListeners();
  }

  void clear() {
    pause();
    _connection = null;
    status = null;
    error = null;
    token = '';
    paused = false;
    challenge++;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    gateway.dispose();
    super.dispose();
  }
}
