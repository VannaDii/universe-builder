import 'dart:io';

import 'src/software_json.dart';

/// Bundle maintained JSON Schema references into self-contained MCP contracts.
void main(List<String> arguments) {
  if (arguments.isNotEmpty &&
      (arguments.length != 1 || arguments.single != '--check')) {
    throw const FormatException(
      'Usage: dart run tool/build_contracts.dart [--check]',
    );
  }
  final root = File.fromUri(Platform.script).parent.parent;
  final source = '${root.path}/contracts/source';
  final catalog = readSoftwareJson(
    File('$source/models.schema.json'),
  ) as Map<String, dynamic>;
  final definitions = catalog[r'$defs'] as Map<String, dynamic>;
  Map<String, dynamic> bundle(Map<String, dynamic> schema) => {
    for (final entry in schema.entries)
      entry.key: entry.key != r'$defs'
          ? entry.value
          : <String, dynamic>{
              for (final name in (entry.value as Map<String, dynamic>).keys)
                name: _model(
                  name,
                  (entry.value as Map<String, dynamic>)[name],
                  definitions,
                ),
            },
  };
  final tools = readSoftwareJson(File('$source/tools.json')) as List<dynamic>;
  final assessments = readSoftwareJson(
    File('$source/assessments.json'),
  ) as Map<String, dynamic>;
  final outputs = {
    'tools.json': <dynamic>[
      for (final tool in tools.cast<Map<String, dynamic>>())
        <String, dynamic>{
          for (final entry in tool.entries)
            entry.key: {'input_schema', 'output_schema'}.contains(entry.key)
                ? bundle(entry.value as Map<String, dynamic>)
                : entry.value,
        },
    ],
    'source-assessments.json': <String, dynamic>{
      for (final entry in assessments.entries)
        entry.key: bundle(entry.value as Map<String, dynamic>),
    },
  };
  for (final entry in outputs.entries) {
    final output = File('${root.path}/contracts/${entry.key}');
    final text = '${prettySoftwareJson(entry.value)}\n';
    if (arguments.contains('--check')) {
      if (!output.existsSync() || output.readAsStringSync() != text) {
        throw StateError(
          'Stale ${entry.key}: run dart run tool/build_contracts.dart',
        );
      }
    } else {
      output.writeAsStringSync(text);
    }
  }
}

dynamic _model(String name, dynamic binding, Map<String, dynamic> definitions) {
  if (binding is! Map<String, dynamic> ||
      binding.length != 1 ||
      binding[r'$ref'] != 'models.schema.json#/\$defs/$name' ||
      !definitions.containsKey(name)) {
    throw FormatException('Expected shared schema definition: $name');
  }
  return definitions[name];
}
