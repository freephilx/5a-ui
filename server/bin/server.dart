import 'dart:io';

import 'package:five_a_server/app.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

Future<void> main() async {
  final env = Platform.environment;
  final root = env['WEB_ROOT'] ?? '../build/web';
  if (!File('$root/index.html').existsSync()) {
    stderr.writeln(
      'Flutter Web build missing. Run fvm dart run tool/dev.dart from the project root.',
    );
    exitCode = 1;
    return;
  }
  final api = ApiApp(env: env);
  final static = createStaticHandler(root, defaultDocument: 'index.html');
  Future<Response> handler(Request request) async {
    final connection =
        request.context['shelf.io.connection_info'] as HttpConnectionInfo?;
    if (request.url.path.startsWith('api/')) {
      return api.handle(
        request.change(
          context: {'clientIp': connection?.remoteAddress.address ?? 'unknown'},
        ),
      );
    }
    var response = await static(request);
    if (response.statusCode == 404 &&
        !request.url.path.split('/').last.contains('.')) {
      response = await static(request.change(path: request.url.path));
    }
    return response.change(
      headers: {...securityHeaders, 'Cache-Control': 'no-cache'},
    );
  }

  final server = await shelf_io.serve(
    handler,
    env['LOCAL_HOST'] ?? '127.0.0.1',
    int.parse(env['PORT'] ?? '5000'),
  );
  server.autoCompress = true;
  stdout.writeln('5a-ui: http://${server.address.address}:${server.port}');
  stdout.writeln(
    'Press Ctrl+C to stop the local service. Remote installation jobs continue.',
  );
  ProcessSignal.sigint.watch().listen((_) async {
    api.close();
    await server.close(force: true);
    exit(0);
  });
  if (!Platform.isWindows) {
    ProcessSignal.sigterm.watch().listen((_) async {
      api.close();
      await server.close(force: true);
      exit(0);
    });
  }
}
