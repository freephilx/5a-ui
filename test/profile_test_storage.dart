import 'package:five_a_ui/services/profile_storage.dart';

class TestProfileStorage implements ProfileStorage {
  String? value;
  bool failRead = false,
      failWrite = false,
      ignoreWrite = false,
      failDelete = false;
  int writes = 0;
  Future<void>? beforeRead;
  @override
  Future<String?> read() async {
    await beforeRead;
    if (failRead) throw StateError('storage unavailable');
    return value;
  }

  @override
  Future<void> write(String text) async {
    writes++;
    if (failWrite) throw StateError('storage unavailable');
    if (!ignoreWrite) value = text;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('storage unavailable');
    value = null;
  }
}
