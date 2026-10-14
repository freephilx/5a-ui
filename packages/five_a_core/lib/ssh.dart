// Native-only transport. The Flutter Web client imports the HTTP adapter instead.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'five_a_core.dart';
import 'src/private_key.dart';

const remoteCommand =
    'if [ "\$(id -u)" = 0 ]; then exec /bin/bash -s; elif sudo -n true 2>/dev/null; then exec sudo -n /bin/bash -s; else exit 77; fi';

class SshResult {
  const SshResult(this.stdout, this.fingerprint);
  final String stdout, fingerprint;
}

Future<List<SSHKeyPair>> _parseKeys(String pem, String? passphrase) =>
    Isolate.run(
      () =>
          SSHKeyPair.fromPem(normalizePrivateKey(pem, passphrase), passphrase),
    );

class SshRunner {
  void Function()? _cancel;
  void cancel() => _cancel?.call();

  Future<SshResult> run(
    ConnectionInput input,
    String script, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (_cancel != null) throw const AppException('BUSY', '请等待当前请求完成。');
    SSHSocket? socket;
    SSHClient? client;
    var stopped = false;
    var mismatch = false;
    var fingerprint = '';
    final cancelled = Completer<SshResult>();
    void checkActive() {
      if (stopped) throw const AppException('CANCELLED', '已暂停刷新，服务器上的安装会继续。');
    }

    _cancel = () {
      if (!cancelled.isCompleted) {
        cancelled.completeError(
          const AppException('CANCELLED', '已暂停刷新，服务器上的安装会继续。'),
        );
      }
    };
    Future<SshResult> execute() async {
      List<SSHKeyPair>? keys;
      if (input.authMethod == 'key') {
        try {
          keys = await _parseKeys(input.privateKey!, input.passphrase);
        } catch (_) {
          throw const AppException('INVALID_KEY', '无法读取 SSH 私钥，请检查格式和密钥口令。');
        }
      }
      checkActive();
      socket = await SSHSocket.connect(
        input.host,
        input.port,
        timeout: const Duration(seconds: 15),
      );
      if (stopped) {
        socket!.destroy();
        checkActive();
      }
      client = SSHClient(
        socket!,
        username: input.username,
        identities: keys,
        onPasswordRequest: input.authMethod == 'password'
            ? () => input.password
            : null,
        keepAliveInterval: const Duration(seconds: 5),
        onVerifyHostKey: (type, bytes) {
          fingerprint = utf8.decode(bytes);
          mismatch =
              input.hostFingerprint != null &&
              input.hostFingerprint != fingerprint;
          return !mismatch;
        },
      );
      // Transport errors are returned through authenticate/execute; never log them.
      unawaited(client!.done.catchError((Object _) {}));
      final session = await client!.execute(remoteCommand);
      checkActive();
      final output = BytesBuilder(copy: false);
      Future<void> readOutput() async {
        await for (final chunk in session.stdout) {
          if (output.length + chunk.length > 128 * 1024) {
            throw const AppException('REMOTE_OUTPUT', '服务器返回的数据过大。', 502);
          }
          output.add(chunk);
        }
      }

      final drained = Future.wait<void>([
        readOutput(),
        session.stderr.drain<void>(),
        session.done,
      ], eagerError: true);
      session.stdin.add(utf8.encode(script));
      unawaited(session.stdin.close().catchError((Object _) {}));
      await drained;
      if (session.exitCode == 77) {
        throw const AppException(
          'SUDO_REQUIRED',
          '此账号没有安装权限。请使用 root，或具有免密 sudo 权限的账号。',
          403,
        );
      }
      if (session.exitCode != 0) {
        throw const AppException(
          'REMOTE_COMMAND',
          '服务器操作失败，请确认系统支持 Bash，并使用 root 或具有免密 sudo 权限的账号。',
          502,
        );
      }
      return SshResult(utf8.decode(output.takeBytes()), fingerprint);
    }

    try {
      return await Future.any([execute(), cancelled.future]).timeout(timeout);
    } on AppException {
      rethrow;
    } on TimeoutException {
      throw const AppException(
        'SSH_TIMEOUT',
        '服务器响应超时。已启动的安装会继续，可重新读取状态。',
        504,
      );
    } catch (error) {
      if (mismatch) {
        throw const AppException(
          'HOST_KEY_CHANGED',
          'SSH 主机指纹与记录不一致，请核对服务器是否重装或更换。',
          409,
        );
      }
      if (error is SSHAuthFailError || error is SSHAuthAbortError) {
        throw const AppException('SSH_AUTH', 'SSH 登录失败，请检查用户名、密码或私钥。', 401);
      }
      throw const AppException(
        'SSH_CONNECTION',
        '无法建立 SSH 连接，请检查服务器 IP、SSH 端口、网络和安全组。',
        502,
      );
    } finally {
      stopped = true;
      client?.close();
      socket?.destroy();
      _cancel = null;
    }
  }
}

Future<bool> probePort(String host, int port) async {
  try {
    final socket = await Socket.connect(
      host,
      port,
      timeout: const Duration(seconds: 4),
    );
    socket.destroy();
    return true;
  } catch (_) {
    return false;
  }
}

typedef SshExecutor = Future<SshResult> Function(
  ConnectionInput input,
  String script,
);
typedef PortProbe = Future<bool> Function(String host, int port);

Future<ServerStatus> executeAction(
  ServerAction action,
  ConnectionInput input, {
  SshExecutor? ssh,
  PortProbe? probe,
}) async {
  final validated = validateInput(input.toJson());
  final result = await (ssh ?? SshRunner().run)(
    validated,
    action == ServerAction.install
        ? installScript(validated)
        : statusScript(validated.host),
  );
  var status = parseRemoteResult(result.stdout)
      .withFields({'hostFingerprint': result.fingerprint});
  if (status.node case final node?) {
    final link = Uri.parse(node['link'] as String)
        .replace(host: validated.host)
        .toString();
    status = status.withFields({
      'node': {...node, 'host': validated.host, 'link': link},
      'portReachable': await (probe ?? probePort)(
        validated.host,
        node['port'] as int,
      ),
    });
  }
  return status;
}

class NativeGateway implements ServerGateway {
  final _ssh = SshRunner();
  @override
  Future<String?> loadSiteKey() async => null;
  @override
  Future<ServerStatus> perform(ServerAction action, ConnectionInput input) =>
      executeAction(action, input, ssh: _ssh.run);
  @override
  void cancel() => _ssh.cancel();
  @override
  void dispose() => cancel();
}
