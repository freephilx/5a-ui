import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:five_a_core/five_a_core.dart';

import 'controller.dart';
import 'services/gateway.dart';
import 'theme.dart';
import 'screens/home.dart';
import 'saved_servers.dart';
import 'services/profile_storage.dart';
import 'services/key_file.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FiveAApp());
}

class FiveAApp extends StatefulWidget {
  const FiveAApp({
    super.key,
    this.gateway,
    this.profileStorage,
    this.privateKeyReader,
  });
  final ServerGateway? gateway;
  final ProfileStorage? profileStorage;
  final PrivateKeyReader? privateKeyReader;
  @override
  State<FiveAApp> createState() => _FiveAAppState();
}

class _FiveAAppState extends State<FiveAApp> {
  static const _windowChannel = MethodChannel('app.fivea/window');
  late final controller = ServerController(widget.gateway ?? createGateway());
  late final savedServers = SavedServers(
    widget.profileStorage ?? SecureProfileStorage(),
  );
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    _updateWindowAppearance();
    controller.initialize();
  }

  Future<void> _updateWindowAppearance() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS) return;
    try {
      await _windowChannel.invokeMethod<void>('setAppearance', mode.name);
    } on MissingPluginException {
      // Widget tests do not create a native window.
    }
  }

  @override
  void dispose() {
    controller.dispose();
    savedServers.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '5a-ui',
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh', 'CN'),
    supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: mode,
    home: HomeScreen(
      controller: controller,
      savedServers: savedServers,
      themeMode: mode,
      privateKeyReader: widget.privateKeyReader,
      onThemeChanged: (value) {
        setState(() => mode = value);
        _updateWindowAppearance();
      },
    ),
  );
}
