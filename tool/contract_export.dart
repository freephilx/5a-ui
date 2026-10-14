import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';

Future<void> main() async {
  final values = jsonDecode(await stdin.transform(utf8.decoder).join()) as List;
  stdout.write(
    jsonEncode([
      for (final value in values)
        {
          'install': installScript(validateInput(value)),
          'status': statusScript(validateInput(value).host),
        },
    ]),
  );
}
