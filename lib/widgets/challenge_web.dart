import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

@JS('turnstile')
external TurnstileApi? get _api;

extension type TurnstileApi(JSObject _) implements JSObject {
  external String render(web.HTMLElement element, JSObject options);
  external void remove(String id);
}

Future<void>? _loading;
Future<void> _load() async {
  if (_api != null) return;
  if (_loading != null) return _loading!;
  final script = web.HTMLScriptElement()
    ..src =
        'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit'
    ..async = true;
  final completer = Completer<void>();
  script.onload = ((web.Event _) {
    if (!completer.isCompleted) completer.complete();
  }).toJS;
  script.onerror = ((web.Event _) {
    if (!completer.isCompleted) {
      completer.completeError(StateError('Challenge failed'));
    }
  }).toJS;
  web.document.head!.append(script);
  _loading = completer.future.timeout(const Duration(seconds: 20));
  try {
    await _loading;
  } catch (_) {
    _loading = null;
    script.remove();
    rethrow;
  }
}

class VerificationChallenge extends StatefulWidget {
  const VerificationChallenge({
    super.key,
    required this.siteKey,
    required this.onToken,
    required this.onError,
  });
  final String siteKey;
  final ValueChanged<String> onToken, onError;
  @override
  State<VerificationChallenge> createState() => _ChallengeState();
}

class _ChallengeState extends State<VerificationChallenge> {
  String? _id;
  Future<void> _created(Object element) async {
    try {
      await _load();
      final div = element as web.HTMLDivElement;
      for (var i = 0; i < 300 && mounted && !div.isConnected; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
      if (!mounted) return;
      _id = _api!.render(
        div,
        {
              'sitekey': widget.siteKey,
              'theme': 'auto',
              'size': 'flexible',
              'callback': ((JSString value) {
                if (mounted) widget.onToken(value.toDart);
              }).toJS,
              'expired-callback': (() {
                if (mounted) widget.onToken('');
              }).toJS,
              'error-callback': (() {
                if (mounted) widget.onError('人机验证加载失败，请重试。');
              }).toJS,
            }.jsify()
            as JSObject,
      );
    } catch (_) {
      if (mounted) widget.onError('人机验证加载失败，请检查网络后重试。');
    }
  }

  @override
  void dispose() {
    if (_id != null) _api?.remove(_id!);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 75,
    child: HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: _created,
    ),
  );
}
