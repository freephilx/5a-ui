import 'package:five_a_core/five_a_core.dart';

Future<String?> privateKeyInitialDirectory(String path) async => null;

Future<String> readPrivateKeyFile(String path) async {
  throw const AppException('KEY_PATH_WEB', '浏览器不能读取本机文件路径，请使用“选择私钥文件”导入对应私钥。');
}
