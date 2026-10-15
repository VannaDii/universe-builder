import 'dart:io';

import 'src/distribution.dart' as distribution;

Future<void> main(List<String> arguments) async {
  const usage = '''Usage:
  dart run apps/ub_cli/tool/distribution.dart archive --bundle PATH --output PATH --tag vVERSION [--allow-dirty]
  dart run apps/ub_cli/tool/distribution.dart formula --assets PATH --version VERSION (--repository OWNER/REPO | --local) --output PATH
Creates preview packaging only; does not publish a release.''';
  if (arguments.length == 1 && {'--help', '-h'}.contains(arguments.single)) {
    stdout.writeln(usage);
    return;
  }
  try {
    if (arguments.isEmpty ||
        !{'archive', 'formula'}.contains(arguments.first)) {
      throw const FormatException('Expected archive or formula');
    }
    final command = arguments.first;
    final flags = command == 'archive' ? {'--allow-dirty'} : {'--local'};
    final allowed = command == 'archive'
        ? {'--bundle', '--output', '--tag'}
        : {'--assets', '--version', '--repository', '--output'};
    final options = <String, String>{};
    final selected = <String>{};
    for (var i = 1; i < arguments.length; i++) {
      final key = arguments[i];
      if (!selected.add(key)) throw FormatException('Duplicate option: $key');
      if (flags.contains(key)) continue;
      if (!allowed.contains(key) ||
          i + 1 >= arguments.length ||
          arguments[i + 1].startsWith('--')) {
        throw FormatException('Invalid or missing option: $key');
      }
      options[key] = arguments[++i];
    }
    String required(String key) =>
        options[key] ?? (throw FormatException('Missing $key'));
    if (command == 'archive') {
      final result = await distribution.archive(
        Directory(required('--bundle')),
        Directory(required('--output')),
        required('--tag'),
        allowDirty: selected.contains('--allow-dirty'),
      );
      stdout.writeln(result.path);
    } else {
      final local = selected.contains('--local');
      if (local == options.containsKey('--repository')) {
        throw const FormatException('Choose --repository or --local');
      }
      final root = File.fromUri(Platform.script)
          .absolute
          .parent
          .parent
          .parent
          .parent;
      final content = await distribution.formula(
        Directory(required('--assets')),
        required('--version'),
        File('${root.path}/packaging/multiverse-mcp.rb.in'),
        repository: options['--repository'],
        local: local,
      );
      final output = File(required('--output'));
      await output.parent.create(recursive: true);
      await output.writeAsString(content);
      stdout.writeln(output.path);
    }
  } on Object catch (error) {
    stderr.writeln('$error\n$usage');
    exitCode = 1;
  }
}
