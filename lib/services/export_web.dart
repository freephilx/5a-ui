import 'dart:js_interop';
import 'dart:convert';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<bool> saveNode(String link) async {
  return saveData(
    Uint8List.fromList(utf8.encode('$link\n')),
    '5a-ui-vless.txt',
  );
}

Future<bool> saveData(Uint8List bytes, String filename) async {
  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/octet-stream'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Future<void>.delayed(
    const Duration(seconds: 1),
    () => web.URL.revokeObjectURL(url),
  );
  return true;
}
