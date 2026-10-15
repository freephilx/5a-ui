import 'dart:convert';
import 'dart:math';

import 'package:five_a_core/five_a_core.dart';
import 'package:flutter/foundation.dart';

import 'services/profile_storage.dart';

class SavedServer {
  const SavedServer._(
    this.id,
    this.name,
    this.connection,
    this.includesCredentials,
    this.autoLogin,
  );
  final String id, name;
  final ConnectionInput connection;
  final bool includesCredentials;
  final bool autoLogin;

  bool matches(ConnectionInput other) =>
      connection.host == other.host &&
      connection.port == other.port &&
      connection.username == other.username;

  factory SavedServer.create({
    required String id,
    required String name,
    required ConnectionInput input,
    required bool includeCredentials,
    bool autoLogin = false,
  }) {
    final title = name.trim().isEmpty ? input.host.trim() : name.trim();
    if (title.length > 80 || title.contains(RegExp(r'[\x00-\x1f]'))) {
      throw const AppException('PROFILE_NAME', '服务器名称最多 80 字，不能包含控制字符。');
    }
    if (!{'password', 'key'}.contains(input.authMethod)) {
      throw const AppException('PROFILE_AUTH', '请选择密码或 SSH 私钥。');
    }
    // Validate metadata without requiring a credential when the user saves only
    // the server. This placeholder is never stored or sent to a gateway.
    final checked = validateInput({
      'host': input.host,
      'port': input.port,
      'username': input.username,
      'authMethod': includeCredentials ? input.authMethod : 'password',
      'password': includeCredentials ? input.password : 'metadata-validation',
      if (includeCredentials && input.authMethod == 'key') ...{
        'privateKey': input.privateKey,
        if (input.passphrase != null) 'passphrase': input.passphrase,
      },
      if (input.hostFingerprint != null)
        'hostFingerprint': input.hostFingerprint,
    });
    return SavedServer._(
      id,
      title,
      ConnectionInput(
        host: checked.host,
        port: checked.port,
        username: checked.username,
        authMethod: input.authMethod,
        hostFingerprint: checked.hostFingerprint,
        password: includeCredentials && input.authMethod == 'password'
            ? checked.password
            : null,
        privateKey: includeCredentials && input.authMethod == 'key'
            ? checked.privateKey
            : null,
        passphrase: includeCredentials && input.authMethod == 'key'
            ? checked.passphrase
            : null,
      ),
      includeCredentials,
      autoLogin && includeCredentials,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'includesCredentials': includesCredentials,
    'autoLogin': autoLogin,
    'host': connection.host,
    'port': connection.port,
    'username': connection.username,
    'authMethod': connection.authMethod,
    if (connection.hostFingerprint != null)
      'hostFingerprint': connection.hostFingerprint,
    if (includesCredentials && connection.authMethod == 'password')
      'password': connection.password,
    if (includesCredentials && connection.authMethod == 'key') ...{
      'privateKey': connection.privateKey,
      if (connection.passphrase != null) 'passphrase': connection.passphrase,
    },
  };

  factory SavedServer.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    if (!RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(id)) {
      throw const FormatException('Invalid saved server ID');
    }
    return SavedServer.create(
      id: id,
      name: json['name'] as String,
      includeCredentials: json['includesCredentials'] as bool,
      // Existing profiles keep their original manual-connect behavior.
      autoLogin: json['autoLogin'] as bool? ?? false,
      input: ConnectionInput(
        host: json['host'] as String,
        port: json['port'] as int,
        username: json['username'] as String,
        authMethod: json['authMethod'] as String,
        hostFingerprint: json['hostFingerprint'] as String?,
        password: json['password'] as String?,
        privateKey: json['privateKey'] as String?,
        passphrase: json['passphrase'] as String?,
      ),
    );
  }
}

class _Catalog {
  const _Catalog(this.servers, this.selectedId);
  final List<SavedServer> servers;
  final String? selectedId;

  String encode() => jsonEncode({
    'version': 1,
    'selectedId': selectedId,
    'servers': servers.map((server) => server.toJson()).toList(),
  });

  static _Catalog decode(String? raw) {
    if (raw == null) return const _Catalog([], null);
    if (raw.length > 4 * 1024 * 1024) {
      throw const FormatException('Storage too large');
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    if (json['version'] != 1) {
      throw const FormatException('Unsupported storage version');
    }
    final records = json['servers'] as List;
    if (records.length > 50) throw const FormatException('Too many records');
    final servers = records
        .map((item) => SavedServer.fromJson(item as Map<String, dynamic>))
        .toList();
    if (servers.map((s) => s.id).toSet().length != servers.length) {
      throw const FormatException('Duplicate saved server ID');
    }
    final selected = json['selectedId'] as String?;
    return _Catalog(
      servers,
      servers.any((s) => s.id == selected) ? selected : servers.firstOrNull?.id,
    );
  }
}

class SavedServers extends ChangeNotifier {
  SavedServers(this.storage);
  final ProfileStorage storage;
  _Catalog _catalog = const _Catalog([], null);
  Future<void> _tail = Future.value();
  int _pending = 0;
  bool loaded = false, _disposed = false;
  String? error;
  List<SavedServer> get servers => List.unmodifiable(_catalog.servers);
  SavedServer? get selected =>
      servers.where((s) => s.id == _catalog.selectedId).firstOrNull;
  bool get busy => _pending > 0;

  Future<bool> _run(Future<_Catalog> Function() operation, String message) {
    _pending++;
    if (!_disposed) notifyListeners();
    final result = _tail.then((_) async {
      try {
        final next = await operation();
        _catalog = next;
        error = null;
        loaded = true;
        return true;
      } catch (_) {
        // Plugin errors may contain platform details; never echo saved content.
        error = message;
        return false;
      } finally {
        _pending--;
        if (!_disposed) notifyListeners();
      }
    });
    _tail = result.then((_) {});
    return result;
  }

  Future<bool> initialize() => _run(
    () async => _Catalog.decode(await storage.read()),
    '无法读取已保存的服务器，请解锁系统安全存储后重试。Web 版需要 HTTPS 或 localhost，且浏览器允许本地存储。',
  );

  Future<_Catalog> _persist(_Catalog next) async {
    if (next.servers.isEmpty) {
      await storage.delete();
      if (await storage.read() != null) {
        throw const FormatException('Delete not confirmed');
      }
    } else {
      final encoded = next.encode();
      await storage.write(encoded);
      if (await storage.read() != encoded) {
        throw const FormatException('Save not confirmed');
      }
    }
    return next;
  }

  Future<SavedServer?> save({
    required ConnectionInput input,
    required String name,
    required bool includeCredentials,
    bool autoLogin = false,
    String? previousId,
  }) async {
    // Validate before entering the storage operation so actionable field errors
    // reach the caller without being confused with a storage failure.
    final candidate = SavedServer.create(
      id: 'new',
      name: name,
      input: input,
      includeCredentials: includeCredentials,
      autoLogin: autoLogin,
    );
    SavedServer? saved;
    final ok = await _run(() async {
      if (!loaded) throw const FormatException('Storage has not loaded');
      final current = _Catalog.decode(await storage.read());
      final existing = current.servers
          .where(
            (s) => previousId == null
                ? s.matches(candidate.connection)
                : s.id == previousId &&
                      s.connection.host == candidate.connection.host &&
                      s.connection.port == candidate.connection.port &&
                      (s.connection.username.isEmpty ||
                          s.connection.username ==
                              candidate.connection.username),
          )
          .firstOrNull;
      if (previousId != null && existing == null) {
        throw const FormatException('Saved server changed or was removed');
      }
      if (existing == null && current.servers.length >= 50) {
        throw const FormatException('Too many records');
      }
      final id =
          existing?.id ??
          base64UrlEncode(
            List.generate(18, (_) => Random.secure().nextInt(256)),
          );
      saved = SavedServer._(
        id,
        candidate.name,
        candidate.connection.withTrust(
          fingerprint:
              candidate.connection.hostFingerprint ??
              existing?.connection.hostFingerprint,
        ),
        candidate.includesCredentials,
        candidate.autoLogin,
      );
      final next = [...current.servers.where((s) => s.id != id), saved!];
      return _persist(_Catalog(next, id));
    }, '保存未能确认，请重试。安全存储不可用时不会改用明文保存；最多可保存 50 台服务器。');
    return ok ? saved : null;
  }

  Future<bool> disableAutoLogin(String id) => _run(() async {
    final current = _Catalog.decode(await storage.read());
    final next = [
      for (final server in current.servers)
        if (server.id == id)
          SavedServer.create(
            id: server.id,
            name: server.name,
            input: server.connection,
            includeCredentials: false,
          )
        else
          server,
    ];
    return _persist(_Catalog(next, current.selectedId));
  }, '关闭自动登录未能确认，保存的登录凭据可能仍然存在，请重试。');

  Future<bool> select(String id) => _run(() async {
    final current = _Catalog.decode(await storage.read());
    if (!current.servers.any((s) => s.id == id)) {
      throw const FormatException('Server no longer saved');
    }
    return _persist(_Catalog(current.servers, id));
  }, '无法记住所选服务器，请重试。');

  Future<bool> remove(String? id) => _run(() async {
    final current = _Catalog.decode(await storage.read());
    final next = id == null
        ? <SavedServer>[]
        : current.servers.where((s) => s.id != id).toList();
    return _persist(
      _Catalog(
        next,
        next.any((s) => s.id == current.selectedId)
            ? current.selectedId
            : next.firstOrNull?.id,
      ),
    );
  }, '删除未能确认，请重试；本机保存记录可能仍然存在。');

  Future<bool> rememberFingerprint(
    String id,
    ConnectionInput input,
    String fingerprint, {
    String? resolvedUsername,
  }) => _run(() async {
    final current = _Catalog.decode(await storage.read());
    final saved = current.servers
        .where((s) => s.id == id && s.matches(input))
        .firstOrNull;
    // A deleted record is never resurrected, and a known host key is never
    // silently replaced. This operation never changes credential preferences.
    if (saved == null ||
        (saved.connection.hostFingerprint != null &&
            saved.connection.hostFingerprint != fingerprint)) {
      return current;
    }
    final resolved = saved.connection.username.isEmpty
        ? resolvedUsername
        : null;
    if (saved.connection.hostFingerprint == fingerprint &&
        (resolved == null || resolved.isEmpty)) {
      return current;
    }
    final next = SavedServer.create(
      id: id,
      name: saved.name,
      input: saved.connection.withTrust(
        fingerprint: fingerprint,
        resolvedUsername: resolved,
      ),
      includeCredentials: saved.includesCredentials,
      autoLogin: saved.autoLogin,
    );
    return _persist(
      _Catalog([
        for (final s in current.servers)
          if (s.id == id) next else s,
      ], current.selectedId),
    );
  }, '已连接，但登录用户名和 SSH 主机指纹未能保存，请重试。');

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
