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
  bool get canRequest =>
      configLoaded &&
      !busy &&
      !polling &&
      (siteKey == null || token.isNotEmpty || _connection?.proofToken != null);
  bool get canRefresh => _connection != null && canRequest;
  String? get connectedHost => _connection?.host;

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
    _until = DateTime.now().add(const Duration(minutes: 30));
    await _request(action, ++_epoch);
  }

  Future<void> refresh() async {
    if (_connection != null) await start(ServerAction.status, _connection!);
  }

  Future<void> _request(ServerAction action, int epoch) async {
    busy = true;
    notifyListeners();
    try {
      final next = await gateway.perform(action, _connection!);
      if (_disposed || epoch != _epoch) return;
      status = next;
      _connection = _connection!.withTrust(
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
        busy = false;
        notifyListeners();
      }
    }
  }

  void pause() {
    _epoch++;
    _timer?.cancel();
    gateway.cancel();
    busy = false;
    polling = false;
    paused = true;
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
