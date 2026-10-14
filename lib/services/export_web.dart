import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<bool> saveNode(String link) async {
  final blob = web.Blob(
    ['$link\n'.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = '5a-ui-vless.txt';
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(seconds: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
