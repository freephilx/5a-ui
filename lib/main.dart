import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:five_a_core/five_a_core.dart';

import 'controller.dart';
import 'services/gateway.dart';
import 'theme.dart';
import 'screens/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FiveAApp());
}

class FiveAApp extends StatefulWidget {
  const FiveAApp({super.key, this.gateway});
  final ServerGateway? gateway;
  @override
  State<FiveAApp> createState() => _FiveAAppState();
}

class _FiveAAppState extends State<FiveAApp> {
  late final controller = ServerController(widget.gateway ?? createGateway());
  ThemeMode mode = ThemeMode.system;
  @override
  void initState() {
    super.initState();
    controller.initialize();
  }

  @override
  void dispose() {
    controller.dispose();
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
      themeMode: mode,
      onThemeChanged: (value) => setState(() => mode = value),
    ),
  );
}
