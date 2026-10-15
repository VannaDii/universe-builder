import 'dart:io';

import 'package:ub_domain/ub_domain.dart';

import 'src/software_json.dart';

// Generates the existing closed software schema. Never opens an installation.
typedef Json = Map<String, dynamic>;
const _string = <String, dynamic>{'type': 'string'};
const _integer = <String, dynamic>{'type': 'integer', 'minimum': 0};
const _boolean = <String, dynamic>{'type': 'boolean'};
Json _object(Json fields) => {
  'type': 'object',
  'properties': fields,
  'required': fields.keys.toList(),
  'additionalProperties': false,
};
Json _ref(String name) => {r'$ref': '#/\$defs/$name'};
Json _array(String name) => {'type': 'array', 'items': _ref(name)};
Json _nullable(Json schema) => {
  'anyOf': [
    schema,
    {'type': 'null'},
  ],
};
Json _asObject(Object? value) => value as Json;
List<dynamic> _asList(Object? value) => value as List<dynamic>;

Json _contracts(Directory root, Directory source) {
  var definitions = <String, dynamic>{};
  void collect(dynamic value) {
    if (value is Json) {
      definitions.addAll(_asObject(value[r'$defs'] ?? <String, dynamic>{}));
      for (final child in value.values) {
        collect(child);
      }
    } else if (value is List<dynamic>) {
      for (final child in value) {
        collect(child);
      }
    }
  }

  final files =
      Directory('${root.path}/contracts')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    collect(readSoftwareJson(file));
  }
  final live = _asObject(
    readSoftwareJson(File('${source.path}/source-contracts.json')),
  );
  for (final entry in live.entries) {
    final schema = _asObject(entry.value);
    definitions.addAll(_asObject(schema[r'$defs'] ?? <String, dynamic>{}));
    definitions[entry.key] = <String, dynamic>{
      for (final f in schema.entries)
        if (f.key != r'$defs' && f.key != r'$schema') f.key: f.value,
    };
  }
  // Exact private envelope fields, retained from the existing normative model.
  definitions.addAll({
    'Footprint': _object({
      'worlds': _array('WorldId'),
      'shared': _boolean,
      'protected': _boolean,
    }),
    'Assignment': _object({
      'record_id': _ref('RecordId'),
      'expected': _nullable(_ref('RecordVersionId')),
      'next': _nullable(_ref('RecordVersion')),
    }),
    'CommitInput': _object({
      'universe': _ref('UniverseId'),
      'continuity': _ref('ContinuityId'),
      'expected_head': _ref('RevisionId'),
      'principal': _ref('PrincipalId'),
      'decision': _string,
      'reason': _string,
      'idempotency_key': _string,
      'changes': _array('Assignment'),
    }),
    'StoredContext': _object({
      'owner': _string,
      'scope': _string,
      'expires': _integer,
      'frame': _ref('Frame'),
    }),
    'StoredProposal': _object({
      'proposal': _ref('Proposal'),
      'owner': _string,
      'author_origin': _boolean,
      'changes': _array('Assignment'),
      'footprint': _ref('Footprint'),
    }),
    'ValidationCapture': _object({
      'selection': _ref('AssessmentSelection'),
      'assessment': _ref('AssessmentState'),
      'submitted_input': _ref('SubmittedInput'),
      'head': _ref('RevisionId'),
      'latest_proposal_key': _nullable(_string),
      'authority_digest': _string,
      'authority_sequence': _nullable({'type': 'integer'}),
    }),
    'Checked': _object({
      'proposal_digest': _string,
      'validation': _ref('Validation'),
      'admissible': _boolean,
      'report': _nullable(_ref('ValidationV3')),
      'capture': _nullable(_ref('ValidationCapture')),
    }),
    'OperationStatusInternal': _object({
      'validation': _nullable(_ref('Validation')),
      'failure': _nullable(_string),
      'operation_id': _ref('OperationId'),
      'kind': _ref('OperationKind'),
      'state': _ref('OperationState'),
      'proposal': _nullable(_ref('Proposal')),
      'receipt': _nullable(_ref('CommitReceipt')),
      'cancellation_requested': _boolean,
    }),
    'StoredOperation': _object({
      'owner': _string,
      'digest': _string,
      'status': _ref('OperationStatusInternal'),
      'input': _nullable(_ref('CommitInput')),
      'footprint': _ref('Footprint'),
      'validation_capture': _nullable(_ref('ValidationCapture')),
    }),
    'ApprovalEvidence': _object({
      'author': _string,
      'proposal': _ref('ProposalRef'),
      'validation_digest': _string,
      'evaluator': _string,
    }),
    'AssessmentReceipt': _object({
      'request_digest': _string,
      'selection': _ref('AssessmentSelection'),
      'envelope': _nullable(_ref('AssessmentEnvelope')),
    }),
    'Cursor': _object({'binding': _string, 'offset': _integer}),
    'Cancellation': _object({'owner': _string, 'cancelled': _boolean}),
    'ReservedRecord': _object({'proposal_id': _ref('ProposalId')}),
    'DraftContent': _object({
      'base_revision': _ref('RevisionId'),
      'represented_context': _ref('RecordId'),
      'operations': _array('DomainOperation'),
      'rationale': _string,
      'proposal': _nullable(_ref('ProposalRef')),
    }),
    'SavedDraft': _object({
      'version': _integer,
      'content': _ref('DraftContent'),
    }),
    'ImportOrigin': _object({
      'digest': _string,
      'source_universe': _ref('UniverseId'),
      'target_universe': _ref('UniverseId'),
      'complete': _boolean,
      'omitted_records': _integer,
    }),
    'ImportAdmission': _object({
      'preview_id': _ref('OperationId'),
      'digest': _string,
      'universe_id': _ref('UniverseId'),
      'name': _string,
      'complete': _boolean,
      'omitted_records': _integer,
      'imported': _boolean,
    }),
    'ImportPreview': _object({
      'id': _ref('OperationId'),
      'owner': _string,
      'source_digest': _string,
      'target': _ref('UniverseId'),
      'source': _ref('UniverseId'),
      'name': _string,
      'complete': _boolean,
      'omitted_records': _integer,
      'records': _integer,
      'includes_workflow': _boolean,
    }),
    'ArchiveManifest': _object({
      'format': _string,
      'universe': _ref('UniverseId'),
      'name': _string,
      'complete': _boolean,
      'omitted_records': _integer,
      'includes_history': _boolean,
      'includes_workflow': _boolean,
    }),
  });
  dynamic replaceModel(dynamic input) {
    if (input is List<dynamic>) return input.map(replaceModel).toList();
    if (input is! Json) return input;
    final schema = <String, dynamic>{
      for (final e in input.entries) e.key: replaceModel(e.value),
    };
    final fields = _asObject(schema['properties'] ?? <String, dynamic>{});
    final required = schema['required'] is List<dynamic>
        ? _asList(schema['required'])
        : <dynamic>[];
    bool has(List<String> keys) => keys.every(fields.containsKey);
    if (has(['namespace', 'key', 'labels', 'classificationExecutable'])) {
      fields.remove('parents');
      fields.addAll({
        'name': _string,
        'parent': _nullable(_ref('RecordId')),
        'parentResolution': {
          'type': 'string',
          'enum': ['root', 'resolved', 'ambiguous'],
        },
        'applicability': _ref('Applicability'),
      });
      schema['required'] = [
        ...required.where((k) => k != 'parents'),
        'name',
        'parent',
        'parentResolution',
        'applicability',
      ];
    }
    if (has(['names', 'types', 'worldAssociations', 'metadata'])) {
      fields.remove('types');
      fields.addAll({
        'classification': _nullable(_ref('RecordId')),
        'classificationResolution': {
          'type': 'string',
          'enum': ['unclassified', 'resolved', 'ambiguous'],
        },
      });
      schema['required'] = [
        ...required.where((k) => k != 'types'),
        'classification',
        'classificationResolution',
      ];
    }
    if (has(['proposition', 'polarity', 'scope', 'validity', 'basis'])) {
      fields['attributeMode'] = {
        'type': 'string',
        'enum': ['instance', 'shared', 'initial_value'],
      };
      schema['required'] = [...required, 'attributeMode'];
    }
    if (has([
      'commitPolicy',
      'targetPredicates',
      'expression',
      'applicability',
    ])) {
      fields['requiredEvidence'] = _nullable(_ref('RequiredEvidence'));
    }
    if (has(['occurrence', 'participants', 'effects', 'expansionVersion'])) {
      fields['basis'] = _nullable(_ref('EvidenceBasis'));
    }
    if (has(['rule', 'ruleVersion', 'authorizingDecision', 'rationale'])) {
      fields['fictionalDeparture'] = _boolean;
    }
    if (fields.containsKey('payload_schema_version')) {
      fields.remove('payload_schema_version');
      schema['required'] = required
          .where((k) => k != 'payload_schema_version')
          .toList();
    }
    return schema;
  }

  definitions['EvidenceReviewMethod'] = {
    'type': 'string',
    'enum': ['human_review', 'external_model_review'],
  };
  definitions['RequiredEvidence'] = _object({
    'sourceCategories': _array('VersionRef'),
    'reviewMethods': _array('EvidenceReviewMethod'),
  });
  _asList(_asObject(definitions['RequiredEvidence'])['required'])
      .remove('reviewMethods');
  definitions = _asObject(replaceModel(definitions));
  const aliases = {
    'ValidationV3': 'ValidationReport',
    'OperationStatusV3': 'OperationStatusReport',
    'SourceAssessmentV1': 'SourceAssessment',
    'SourceValidationBinding': 'SourceValidationBinding',
  };
  dynamic rename(dynamic value) {
    if (value is Json) {
      return <String, dynamic>{
        for (final e in value.entries) aliases[e.key] ?? e.key: rename(e.value),
      };
    }
    if (value is List<dynamic>) return value.map(rename).toList();
    if (value is String) {
      if (value.startsWith(r'#/$defs/')) {
        final name = value.split('/').last;
        return '#/\$defs/${aliases[name] ?? name}';
      }
      return value.replaceFirst(RegExp(r'_v[0-9]+$'), '');
    }
    return value;
  }

  definitions = _asObject(rename(definitions));
  for (final e in {
    'Checked': ['report', 'capture'],
    'StoredOperation': ['validation_capture'],
    'ValidationCapture': ['authority_sequence'],
    'DraftContent': ['proposal'],
    'Cancellation': ['owner'],
    'OperationStatusInternal': ['validation', 'failure'],
  }.entries) {
    final model = _asObject(definitions[e.key]);
    model['required'] = _asList(model['required'])
        .where((k) => !e.value.contains(k))
        .toList();
  }
  _asList(_asObject(definitions['EvidenceBasis'])['oneOf']).add(
    _object({
      'kind': {'type': 'string', 'const': 'instance_initialization'},
      'start': _ref('VersionRef'),
      'definition': _ref('VersionRef'),
      'source_revision': _ref('RevisionId'),
    }),
  );
  final operations = _asList(
    _asObject(definitions['DomainOperation'])['oneOf'],
  );
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'initialize_instance'},
      'client_ref': _string,
      'instance': _ref('RecordRef'),
      'start': _ref('RecordRef'),
      'definition': _ref('VersionRef'),
      'scope': _ref('Scope'),
      'validity': _ref('Validity'),
    }),
  );
  for (final (kind, replacement) in [
    ('revise_item_power', 'ItemPower'),
    ('revise_attitude', 'EpistemicAttitude'),
    ('revise_communication', 'Communication'),
  ]) {
    operations.add(
      _object({
        'kind': {'type': 'string', 'const': kind},
        'record': _ref('RecordRef'),
        'expected_version': _ref('RecordVersionId'),
        'replacement': _ref(replacement),
        'rationale': _string,
      }),
    );
  }
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'revise_interpretation'},
      'record': _ref('RecordRef'),
      'expected_version': _ref('RecordVersionId'),
      'interpretation': _nullable(_ref('RecordRef')),
      'rationale': _string,
    }),
  );
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'withdraw_event'},
      'record': _ref('RecordRef'),
      'expected_version': _ref('RecordVersionId'),
      'rationale': _string,
    }),
  );
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'revise_scene'},
      'record': _ref('RecordRef'),
      'expected_version': _ref('RecordVersionId'),
      'replacement': _ref('SceneRef'),
      'rationale': _string,
    }),
  );
  definitions['Secret'] = _object({
    'scope': _array('RecordRef'),
    'fictionalKnowers': _array('RecordRef'),
    'readerDisclosed': _boolean,
    'concealment': _nullable(_string),
    'validity': _ref('Validity'),
  });
  _asList(_asObject(definitions['Secret'])['required']).remove('concealment');
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'create_secret'},
      'client_ref': _string,
      'record': _ref('Secret'),
    }),
  );
  operations.add(
    _object({
      'kind': {'type': 'string', 'const': 'revise_secret'},
      'record': _ref('RecordRef'),
      'expected_version': _ref('RecordVersionId'),
      'replacement': _ref('Secret'),
    }),
  );
  return definitions;
}

String _ident(String name) => name
    .replaceAllMapped(
      RegExp('[A-Z]'),
      (m) => '${m.start == 0 ? '' : '_'}${m[0]}',
    )
    .toLowerCase()
    .replaceAll(RegExp('[^a-z0-9_]'), '_');
String _quote(String name) => '"${name.replaceAll('"', '""')}"';
String _literal(dynamic value) {
  if (value is bool) return value ? '1' : '0';
  if (value is CanonicalNumber) return value.digits;
  if (value is num) return value.toString();
  return "'${value.toString().replaceAll("'", "''")}'";
}

final class _Compiler {
  _Compiler(this.definitions);
  final Json definitions;
  final models = <String, Json>{};
  String model(Json input, String name) {
    var schema = input;
    while (schema.containsKey(r'$ref')) {
      name = (schema[r'$ref'] as String).split('/').last;
      schema = _asObject(definitions[name]);
    }
    if (models.containsKey(name)) return name;
    final d = models[name] = {'table': 'r_${_ident(name)}'};
    final alternatives = schema.containsKey('oneOf')
        ? schema['oneOf']
        : schema['anyOf'];
    final type = schema['type'];
    if (alternatives is List<dynamic> && alternatives.isNotEmpty) {
      d['kind'] = 'union';
      d['variants'] = [
        for (var i = 0; i < alternatives.length; i++)
          model(_asObject(alternatives[i]), '${name}_v$i'),
      ];
    } else if (type == 'object' && schema.containsKey('properties')) {
      d['kind'] = 'object';
      final fields = <String, dynamic>{};
      d['fields'] = fields;
      for (final e in _asObject(schema['properties']).entries) {
        fields[e.key] = {
          'model': model(_asObject(e.value), '${name}_${e.key}'),
          'required': _asList(schema['required'] ?? <dynamic>[])
              .contains(e.key),
        };
      }
    } else if (type == 'object') {
      final additional = schema['additionalProperties'];
      if (additional is! Json) {
        throw FormatException('Unbounded object forbidden: $name');
      }
      d['kind'] = 'map';
      d['item'] = model(additional, '${name}_item');
    } else if (type == 'array' && schema.containsKey('prefixItems')) {
      d['kind'] = 'tuple';
      final items = _asList(schema['prefixItems']);
      d['fields'] = <String, dynamic>{
        for (var i = 0; i < items.length; i++)
          '$i': {
            'model': model(_asObject(items[i]), '${name}_p$i'),
            'required': true,
          },
      };
    } else if (type == 'array') {
      if (!schema.containsKey('items')) {
        throw FormatException('Untyped array: $name');
      }
      d['kind'] = 'array';
      d['item'] = model(_asObject(schema['items']), '${name}_item');
    } else if ([
      'string',
      'integer',
      'number',
      'boolean',
      'null',
    ].contains(type)) {
      d['kind'] = type;
      for (final key in ['const', 'enum', 'pattern', 'minimum', 'maximum']) {
        if (schema.containsKey(key)) d[key] = schema[key];
      }
    } else if (type is List<dynamic>) {
      d['kind'] = 'union';
      d['variants'] = [
        for (var i = 0; i < type.length; i++)
          model({'type': type[i]}, '${name}_v$i'),
      ];
    } else {
      throw FormatException('Unsupported closed contract: $name');
    }
    return name;
  }

  bool scalar(String name) => [
    'string',
    'integer',
    'number',
    'boolean',
    'null',
  ].contains(models[name]!['kind']);
  String _storage(String name) => models[name]!['kind'] == 'boolean'
      ? 'INTEGER'
      : scalar(name)
      ? 'TEXT'
      : 'INTEGER';
  String _reference(String name) => scalar(name)
      ? ''
      : ' REFERENCES ${_quote(models[name]!['table'] as String)}(__row_id)';
  String ddl() {
    final statements = [
      '-- NORMATIVE UNRELEASED MODEL. One relational schema; not a production migration.',
      'PRAGMA foreign_keys=ON;',
    ];
    for (final entry in models.entries) {
      final name = entry.key, d = entry.value;
      if (scalar(name)) continue;
      final table = d['table'] as String;
      var cols = ['__row_id INTEGER PRIMARY KEY'];
      if (['object', 'tuple'].contains(d['kind'])) {
        for (final e in _asObject(d['fields']).entries) {
          final field = _asObject(e.value),
              fieldModel = field['model'] as String,
              m = models[fieldModel]!;
          final state = _quote('${e.key}__state'), col = _quote(e.key);
          final nullable =
              m['kind'] == 'null' ||
              m['kind'] == 'union' &&
                  _asList(m['variants'])
                      .any((dynamic v) => models[v]!['kind'] == 'null');
          final states = [if (field['required'] != true) 0, if (nullable) 1, 2];
          cols.add(
            '$state INTEGER NOT NULL CHECK($state IN (${states.join(',')}))',
          );
          cols.add('$col ${_storage(fieldModel)}${_reference(fieldModel)}');
          cols.add(
            'CHECK(($state=2 AND $col IS NOT NULL) OR ($state IN (0,1) AND $col IS NULL))',
          );
          if (m['kind'] == 'boolean') cols.add('CHECK($col IN (0,1))');
          if (m.containsKey('const')) {
            cols.add('CHECK($col=${_literal(m['const'])})');
          }
          if (m.containsKey('enum')) {
            cols.add(
              'CHECK($col IN (${_asList(m['enum']).map(_literal).join(',')}))',
            );
          }
        }
      } else if (d['kind'] == 'union') {
        final variants = _asList(d['variants']).cast<String>();
        cols.add(
          'variant INTEGER NOT NULL CHECK(variant BETWEEN 0 AND ${variants.length - 1})',
        );
        for (var i = 0; i < variants.length; i++) {
          cols.add('v$i ${_storage(variants[i])}${_reference(variants[i])}');
        }
        for (var i = 0; i < variants.length; i++) {
          cols.add('CHECK(variant=$i OR v$i IS NULL)');
          if (models[variants[i]]!['kind'] != 'null') {
            cols.add('CHECK(variant!=$i OR v$i IS NOT NULL)');
          }
        }
      }
      cols = [
        ...cols.where((s) => !s.startsWith('CHECK(')),
        ...cols.where((s) => s.startsWith('CHECK(')),
      ];
      statements.add(
        'CREATE TABLE ${_quote(table)} (\n  ${cols.join(',\n  ')}\n) STRICT;',
      );
      if (['array', 'map'].contains(d['kind'])) {
        final item = d['item'] as String;
        final key = d['kind'] == 'array'
            ? 'ordinal INTEGER NOT NULL CHECK(ordinal>=0)'
            : 'name TEXT NOT NULL';
        statements.add(
          'CREATE TABLE ${_quote('${table}_items')} (owner INTEGER NOT NULL REFERENCES ${_quote(table)}(__row_id), $key, item ${_storage(item)}${_reference(item)}, PRIMARY KEY(owner,${d['kind'] == 'array' ? 'ordinal' : 'name'})) STRICT;',
        );
      }
    }
    for (final entry in models.entries) {
      if (scalar(entry.key)) continue;
      final d = entry.value, table = d['table'] as String;
      for (final child in [
        table,
        if (['array', 'map'].contains(d['kind'])) '${table}_items',
      ]) {
        for (final action in ['UPDATE', 'DELETE']) {
          statements.add(
            "CREATE TRIGGER ${_quote('${child}_no_${action.toLowerCase()}')} BEFORE $action ON ${_quote(child)} BEGIN SELECT RAISE(ABORT,'immutable typed body'); END;",
          );
        }
      }
    }
    return '${statements.join('\n\n')}\n';
  }
}

const _roots = [
  'Payload',
  'DomainOperation',
  'RecordVersion',
  'StoredContext',
  'StoredProposal',
  'Checked',
  'StoredOperation',
  'ApprovalEvidence',
  'AssessmentEnvelope',
  'AssessmentSelection',
  'AssessmentReceipt',
  'Cursor',
  'Cancellation',
  'ReservedRecord',
  'SavedDraft',
  'ImportOrigin',
  'ImportAdmission',
  'ImportPreview',
  'ArchiveManifest',
  'SourceValidationBinding',
];
void main(List<String> arguments) {
  if (arguments.isNotEmpty &&
      (arguments.length != 1 || arguments.single != '--check')) {
    throw const FormatException(
      'Usage: dart run tool/build_schema.dart [--check]',
    );
  }
  final check = arguments.contains('--check');
  final root = File.fromUri(Platform.script).parent.parent;
  final source = Directory('${root.path}/docs/decisions/relational-storage');
  final compiler = _Compiler(_contracts(root, source));
  compiler.definitions['SourceValidationBinding'] = _object({
    'kind': _ref('ValidationBindingKind'),
    'proposal': _ref('ProposalRef'),
    'base_frame': _ref('Frame'),
    'selection': _ref('AssessmentSelection'),
    'submitted_input': _ref('SubmittedInput'),
    'assessment_state': _ref('AssessmentState'),
    'execution_result_digest': _string,
    'evaluator_version': _string,
  });
  for (final name in _roots) {
    compiler.model(_ref(name), name);
  }
  final lines = [
    '# Exact field mapping',
    '',
    'Generated from current domain schemas and checked-in public contracts. The replacement model is normative before release. Private envelopes are explicitly specified in `tool/build_schema.dart`; DraftContent.operations uses typed operations. Superseded editor formats are one-time input concerns (see compatibility.md). `__state`: 0 absent, 1 explicit null, 2 value. Collections use child rows; an empty collection still has a header. Numeric wire tokens use decimal TEXT, never SQLite REAL.',
    '',
    '| Contract | Table / scalar domain | Fields or links |',
    '|---|---|---|',
  ];
  for (final entry in compiler.models.entries) {
    final d = entry.value;
    var description = _asObject(d['fields'] ?? <String, dynamic>{}).entries
        .map((f) => '${f.key} → ${_asObject(f.value)['model']}')
        .join(', ');
    if (description.isEmpty) {
      description = _asList(d['variants'] ?? <dynamic>[]).join(', ');
    }
    if (description.isEmpty) description = (d['item'] ?? d['kind']) as String;
    lines.add(
      '| `${entry.key}` | `${d['table']}`${compiler.scalar(entry.key) ? ' (scalar column)' : ''} | $description |',
    );
  }
  for (final entry in {
    'typed.sql': compiler.ddl(),
    'catalog.json':
        '${prettySoftwareJson({'roots': _roots, 'models': compiler.models})}\n',
    'field-mapping.md': '${lines.join('\n')}\n',
  }.entries) {
    final file = File('${source.path}/${entry.key}');
    if (check) {
      if (file.readAsStringSync() != entry.value) {
        throw StateError(
          'Stale ${entry.key}: run dart run tool/build_schema.dart',
        );
      }
    } else {
      file.writeAsStringSync(entry.value);
    }
  }
  stdout.writeln(
    '${compiler.models.length} closed models; ${compiler.models.keys.where((n) => !compiler.scalar(n)).length} typed tables plus collection children',
  );
}
