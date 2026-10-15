import 'dart:convert';
import 'dart:io';

import 'package:five_a_core/five_a_core.dart';

Future<void> main() async {
  final raw = jsonDecode(await stdin.transform(utf8.decoder).join()) as List;
  stdout.write(
    jsonEncode(
      raw.map((r) {
        try {
          final input = CfnewInput.parse(r);
          return {
            'input': input.toJson(),
            'owner': input.owner,
            'metadata': cfnewMetadata(input, 'b' * 32),
          };
        } on AppException catch (e) {
          return {'error': e.code};
        }
      }).toList(),
    ),
  );
}
