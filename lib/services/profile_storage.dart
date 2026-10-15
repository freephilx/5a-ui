import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ProfileStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureProfileStorage implements ProfileStorage {
  static const _key = 'five_a.saved_servers.v1';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      resetOnError: false,
      storageNamespace: 'five_a_saved_servers',
    ),
    iOptions: IOSOptions(
      accountName: 'app.fivea.saved-servers',
      accessibility: KeychainAccessibility.unlocked_this_device,
    ),
    mOptions: MacOsOptions(
      accountName: 'app.fivea.saved-servers',
      // The login Keychain also supports locally built, ad-hoc signed apps.
      usesDataProtectionKeychain: false,
    ),
    webOptions: WebOptions(
      dbName: 'FiveASavedServers',
      publicKey: 'FiveASavedServersKey',
    ),
  );

  @override
  Future<String?> read() => _storage.read(key: _key);
  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
  @override
  Future<void> delete() => _storage.delete(key: _key);
}
