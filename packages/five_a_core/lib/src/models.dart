class AppException implements Exception {
  const AppException(this.code, this.message, [this.statusCode = 400]);
  final String code;
  final String message;
  final int statusCode;
  @override
  String toString() => message;
}

enum ServerAction { install, status }

class ConnectionInput {
  const ConnectionInput({
    required this.host,
    this.username = 'root',
    this.port = 22,
    this.authMethod = 'password',
    this.password,
    this.privateKey,
    this.passphrase,
    this.hostFingerprint,
    this.nodePort = 443,
    this.realityServerName,
    this.turnstileToken,
    this.proofToken,
  });
  final String host, username, authMethod;
  final int port, nodePort;
  final String? password,
      privateKey,
      passphrase,
      hostFingerprint,
      realityServerName,
      turnstileToken,
      proofToken;

  Map<String, Object?> toJson() => {
    'host': host,
    'username': username,
    'port': port,
    'authMethod': authMethod,
    'nodePort': nodePort,
    if (authMethod == 'password') 'password': password,
    if (authMethod == 'key') ...{
      'privateKey': privateKey,
      if (passphrase != null) 'passphrase': passphrase,
    },
    if (hostFingerprint != null) 'hostFingerprint': hostFingerprint,
    if (realityServerName != null) 'realityServerName': realityServerName,
    if (turnstileToken != null) 'turnstileToken': turnstileToken,
    if (proofToken != null) 'proofToken': proofToken,
  };

  ConnectionInput withTrust({String? fingerprint, String? proof}) =>
      ConnectionInput(
        host: host,
        username: username,
        port: port,
        authMethod: authMethod,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
        nodePort: nodePort,
        realityServerName: realityServerName,
        hostFingerprint: fingerprint ?? hostFingerprint,
        proofToken: proof ?? proofToken,
      );
}

const phases = {
  'not-installed',
  'existing',
  'queued',
  'preparing',
  'installing',
  'configuring',
  'checking',
  'ready',
  'failed',
};
const activePhases = {
  'queued',
  'preparing',
  'installing',
  'configuring',
  'checking',
};

class ServerStatus {
  ServerStatus(Map<String, dynamic> data) : data = Map.unmodifiable(data);
  final Map<String, dynamic> data;
  String get phase => data['phase'] as String;
  String get message => data['message'] as String;
  bool get isInstalling => activePhases.contains(phase);
  bool get isReady => phase == 'ready';
  bool get running => data['running'] == true;
  String? get fingerprint => data['hostFingerprint'] as String?;
  String? get proofToken => data['proofToken'] as String?;
  Map<String, dynamic>? get node => data['node'] as Map<String, dynamic>?;
  String? get link => node?['link'] as String?;
  ServerStatus withFields(Map<String, dynamic> fields) =>
      ServerStatus({...data, ...fields});
  Map<String, dynamic> toJson() => data;
}

abstract class ServerGateway {
  Future<String?> loadSiteKey();
  Future<ServerStatus> perform(ServerAction action, ConnectionInput input);
  void cancel();
  void dispose();
}
