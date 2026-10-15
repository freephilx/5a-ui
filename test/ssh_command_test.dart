import 'package:five_a_core/five_a_core.dart';
import 'package:five_a_ui/ssh_command.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('imports key paths, ports and users without resolving files', () {
    final parsed = SshConnectionCommand.parse(
      'ssh -i ~/.ssh/synthetic -p 2222 ubuntu@8.8.8.8',
    );
    expect(parsed.host, '8.8.8.8');
    expect(parsed.username, 'ubuntu');
    expect(parsed.port, 2222);
    expect(parsed.identityFile, '~/.ssh/synthetic');
    expect(parsed.password, isNull);
    expect(SshConnectionCommand.parse('ssh 8.8.8.8').username, isNull);
  });

  test('supports quoted paths, escaped spaces, attached options and IPv6', () {
    final parsed = SshConnectionCommand.parse(
      'ssh -i "/tmp/key with spaces" -l ubuntu -p2222 8.8.8.8',
    );
    expect(parsed.identityFile, '/tmp/key with spaces');
    expect(parsed.port, 2222);
    expect(parsed.username, 'ubuntu');
    expect(
      SshConnectionCommand.parse(r'ssh ubuntu@8.8.8.8 -i/tmp/key\ with\ spaces')
          .identityFile,
      '/tmp/key with spaces',
    );
    final ipv6 = SshConnectionCommand.parse(
      '/usr/bin/ssh -lubuntu -p2222 -- [2001:4860:4860::8888]',
    );
    expect(ipv6.host, '2001:4860:4860::8888');
    expect(ipv6.username, 'ubuntu');
    expect(ipv6.port, 2222);
    expect(
      SshConnectionCommand.parse(
        r'ssh.exe -i "C:\Users\tester\key.pem" ubuntu@8.8.8.8',
      ).identityFile,
      r'C:\Users\tester\key.pem',
    );
  });

  test('password commands keep literal secrets and default to port 22', () {
    final plain = SshConnectionCommand.parse('ssh ubuntu@8.8.8.8');
    expect(plain.port, 22);
    expect(plain.identityFile, isNull);
    expect(plain.password, isNull);
    final password = SshConnectionCommand.parse(
      r'''sshpass -p 'synthetic $secret;`text`' ssh -p 2222 ubuntu@8.8.8.8''',
    );
    expect(password.password, r'synthetic $secret;`text`');
    expect(password.port, 2222);
    expect(
      SshConnectionCommand.parse('sshpass -psynthetic ssh ubuntu@8.8.8.8')
          .password,
      'synthetic',
    );
  });

  test(
    'rejects unsupported or ambiguous commands with errors free of secrets',
    () {
      final invalid = [
        '',
        'scp ubuntu@8.8.8.8',
        'ssh',
        'ssh -p',
        'ssh -p nope ubuntu@8.8.8.8',
        'ssh -p 0 ubuntu@8.8.8.8',
        'ssh -p 65536 ubuntu@8.8.8.8',
        'ssh -i a -i b ubuntu@8.8.8.8',
        'ssh -J jump ubuntu@8.8.8.8',
        'ssh ubuntu@8.8.8.8 uptime',
        'ssh ubuntu@8.8.8.8; echo secret',
        r'ssh -i $(command) ubuntu@8.8.8.8',
        r'ssh -i "$KEY" ubuntu@8.8.8.8',
        'ssh -i "unclosed ubuntu@8.8.8.8',
        'ssh invalid!@8.8.8.8',
        'ssh ubuntu@127.0.0.1',
        'ssh ubuntu@my-alias',
        'sshpass -p synthetic-secret ssh -i key ubuntu@8.8.8.8',
        'sshpass -p synthetic-secret ssh -Z ubuntu@8.8.8.8',
        "sshpass -p '' ssh ubuntu@8.8.8.8",
        'sshpass -e ssh ubuntu@8.8.8.8',
      ];
      for (final command in invalid) {
        expect(
          () => SshConnectionCommand.parse(command),
          throwsA(anyOf(isA<FormatException>(), isA<AppException>())),
          reason: 'Invalid command index ${invalid.indexOf(command)}',
        );
      }
      try {
        SshConnectionCommand.parse(
          'sshpass -p synthetic-secret ssh -Z ubuntu@8.8.8.8',
        );
      } on FormatException catch (e) {
        expect(e.message, isNot(contains('synthetic-secret')));
      }
    },
  );
}
