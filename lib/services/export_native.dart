import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<bool> saveNode(String link) async {
  final bytes = Uint8List.fromList(utf8.encode('$link\n'));
  final path = await FilePicker.platform.saveFile(
    dialogTitle: '导出节点',
    fileName: '5a-ui-vless.txt',
    bytes: bytes,
  );
  if (path == null) return false;
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return true;
}
