import 'dart:io';

Future<void> run(List<String> args, {String? workingDirectory}) async {
  final process = await Process.start(
    'fvm',
    args,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  if (code != 0) exit(code);
}

Future<void> main(List<String> args) async {
  if (!File('.fvmrc').existsSync() || !Directory('server').existsSync()) {
    stderr.writeln('Run this command from the 5a-ui repository root.');
    exit(1);
  }
  await run(['dart', 'run', 'tool/generate.dart']);
  if (!args.contains('--skip-build')) {
    await run(['flutter', 'pub', 'get']);
    await run([
      'flutter',
      'build',
      'web',
      '--release',
      '--no-web-resources-cdn',
    ]);
  }
  await run(['dart', 'pub', 'get'], workingDirectory: 'server');
  await run(['dart', 'run', 'bin/server.dart'], workingDirectory: 'server');
}
