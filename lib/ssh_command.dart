import 'package:five_a_core/five_a_core.dart';

/// Extracts connection fields only; never launches a shell or an SSH process.
class SshConnectionCommand {
  const SshConnectionCommand({
    required this.host,
    required this.port,
    this.username,
    this.identityFile,
    this.password,
  });

  final String host;
  final int port;
  final String? username, identityFile, password;

  static SshConnectionCommand parse(String source) {
    if (source.length > 8192 || source.contains('\x00')) {
      throw const FormatException('SSH 命令过长或包含无效字符。');
    }
    final args = _split(source.trim());
    String? password;
    if (args.isNotEmpty && args.first == 'sshpass') {
      args.removeAt(0);
      if (args.isEmpty || !args.first.startsWith('-p')) {
        throw const FormatException('仅支持 sshpass -p 的密码格式，也可以在表单中单独填写密码。');
      }
      final option = args.removeAt(0);
      if (option == '-p') {
        if (args.isEmpty) throw const FormatException('sshpass -p 后缺少密码。');
        password = args.removeAt(0);
      } else {
        password = option.substring(2);
      }
      if (password.isEmpty) throw const FormatException('SSH 密码不能为空。');
    }
    if (args.isEmpty ||
        !RegExp(r'^(?:.*[/\\])?ssh(?:\.exe)?$').hasMatch(args.removeAt(0))) {
      throw const FormatException('请输入以 ssh 开头的连接命令。');
    }
    String? user, identity, destination;
    var port = 22;
    var options = true;
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (options && arg == '--') {
        options = false;
        continue;
      }
      if (options && arg.startsWith('-')) {
        if (arg.length < 2 || !{'p', 'i', 'l'}.contains(arg[1])) {
          throw const FormatException(
            '暂不支持此 SSH 选项，请只保留地址、-p 端口、-l 用户名和 -i 私钥路径。',
          );
        }
        final String value;
        if (arg.length > 2) {
          value = arg.substring(2);
        } else {
          if (++i >= args.length || args[i].startsWith('-')) {
            throw const FormatException('SSH 选项后缺少端口、用户名或私钥路径。');
          }
          value = args[i];
        }
        if (value.isEmpty) throw const FormatException('SSH 选项的值不能为空。');
        switch (arg[1]) {
          case 'p':
            final parsed = int.tryParse(value);
            if (parsed == null || parsed < 1 || parsed > 65535) {
              throw const FormatException('SSH 端口需要是 1–65535 之间的整数。');
            }
            port = parsed;
          case 'i':
            if (identity != null) {
              throw const FormatException('请只保留一个要使用的私钥路径。');
            }
            identity = value;
          case 'l':
            user = value;
        }
      } else {
        if (destination != null) {
          throw const FormatException('请只粘贴连接命令，不包含远端命令、管道或多台服务器。');
        }
        destination = arg;
      }
    }
    if (destination == null) throw const FormatException('SSH 命令中缺少服务器地址。');
    final at = destination.lastIndexOf('@');
    if (at >= 0) {
      user = destination.substring(0, at);
      destination = destination.substring(at + 1);
    }
    if (user != null &&
        !RegExp(
          r'^[a-z_][a-z0-9_-]{0,31}$',
          caseSensitive: false,
        ).hasMatch(user)) {
      throw const FormatException('请输入有效的服务器用户名，例如 root、ubuntu 或 debian。');
    }
    if (destination.startsWith('[') && destination.endsWith(']')) {
      destination = destination.substring(1, destination.length - 1);
    }
    if (identity != null && password != null) {
      throw const FormatException('请使用私钥或密码中的一种认证方式。');
    }
    return SshConnectionCommand(
      host: publicIP(destination),
      port: port,
      username: user,
      identityFile: identity,
      password: password,
    );
  }
}

List<String> _split(String source) {
  final result = <String>[];
  var token = StringBuffer();
  String? quote;
  var started = false;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (quote == "'") {
      if (char == quote) {
        quote = null;
      } else {
        token.write(char);
      }
      continue;
    }
    if (char == '\\' && i + 1 < source.length) {
      final next = source[i + 1];
      if ((quote == '"' ? '\\"\$\n' : '\\"\' \t\n').contains(next)) {
        if (next != '\n') token.write(next);
        i++;
        started = true;
        continue;
      }
    }
    if (quote == '"') {
      if (char == quote) {
        quote = null;
      } else if (char == '\$' || char == '`') {
        throw const FormatException('请使用具体参数，不支持 Shell 变量或命令替换。');
      } else {
        token.write(char);
      }
      continue;
    }
    if (char == "'" || char == '"') {
      quote = char;
      started = true;
    } else if (RegExp(r'\s').hasMatch(char)) {
      if (started) result.add(token.toString());
      token = StringBuffer();
      started = false;
    } else if (';&|<>()`\$'.contains(char)) {
      throw const FormatException('请只粘贴 SSH 连接命令，不包含 Shell 操作或变量。');
    } else {
      token.write(char);
      started = true;
    }
  }
  if (quote != null) throw const FormatException('SSH 命令中的引号没有闭合。');
  if (started) result.add(token.toString());
  return result;
}
