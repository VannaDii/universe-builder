import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';
import 'catalog.dart';
import 'relational.dart';
import 'recovery_domain_rows.dart';
import 'recovery_value_inputs.dart';
import 'recovery_expression_inputs.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _fields =
    'generation,base_revision,client_ref,namespace,rule_key,rule_kind,commit_policy,rationale,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,expression_root,executable,temporal,original,target_record,target_universe,expected_record_version,draft_version';
const _knowledgeFields =
    'policy_enabled,boundary_enabled,mode,policy_context_record,policy_context_universe,holder_record,holder_universe,proposition_record,proposition_universe,boundary_context_record,boundary_context_universe';
const _constraintFields =
    'cardinality_enabled,chronology_enabled,relation_record,relation_universe,grouping_input,grouping_role,counted_role,maximum_input,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,channel,forward_only,minimum_enabled,maximum_enabled,minimum_delay,maximum_delay';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('rule');
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'Expr',
  'Operand',
]);
final _schema =
    """
CREATE TABLE rule_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,namespace TEXT NOT NULL,rule_key TEXT NOT NULL,rule_kind TEXT NOT NULL,commit_policy TEXT NOT NULL,rationale TEXT NOT NULL,
 scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,
 expression_root INTEGER NOT NULL REFERENCES rule_expression(id),executable INTEGER CHECK(executable IN (0,1)),temporal INTEGER NOT NULL REFERENCES rule_temporal(id),original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),target_record TEXT,target_universe TEXT,expected_record_version TEXT,draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE rule_label (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),language TEXT NOT NULL,label_text TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE rule_list (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,list_kind TEXT NOT NULL CHECK(list_kind IN ('world','subject','predicate','capability','constraint_world','review_method')),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_text TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE rule_knowledge (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,policy_enabled INTEGER NOT NULL CHECK(policy_enabled IN (0,1)),boundary_enabled INTEGER NOT NULL CHECK(boundary_enabled IN (0,1)),mode TEXT NOT NULL,policy_context_record TEXT NOT NULL,policy_context_universe TEXT NOT NULL,holder_record TEXT NOT NULL,holder_universe TEXT NOT NULL,proposition_record TEXT NOT NULL,proposition_universe TEXT NOT NULL,boundary_context_record TEXT NOT NULL,boundary_context_universe TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE rule_constraint (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,cardinality_enabled INTEGER NOT NULL CHECK(cardinality_enabled IN (0,1)),chronology_enabled INTEGER NOT NULL CHECK(chronology_enabled IN (0,1)),relation_record TEXT NOT NULL,relation_universe TEXT NOT NULL,grouping_input TEXT NOT NULL,grouping_role TEXT NOT NULL,counted_role TEXT NOT NULL,maximum_input TEXT NOT NULL,scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,temporal INTEGER REFERENCES rule_temporal(id) NOT NULL,channel TEXT NOT NULL,forward_only INTEGER CHECK(forward_only IN (0,1)),minimum_enabled INTEGER NOT NULL CHECK(minimum_enabled IN (0,1)),maximum_enabled INTEGER NOT NULL CHECK(maximum_enabled IN (0,1)),minimum_delay TEXT NOT NULL,maximum_delay TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE rule_evidence (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,enabled INTEGER NOT NULL CHECK(enabled IN (0,1)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE rule_evidence_category (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),universe_input TEXT NOT NULL,record_input TEXT NOT NULL,version_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES rule_evidence(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('rule')}
${RecoveryExpressionInputs.schema('rule')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'boundary_enabled',
            'cardinality_enabled',
            'chronology_enabled',
            'enabled',
            'executable',
            'expression_root',
            'forward_only',
            'maximum_enabled',
            'minimum_enabled',
            'ordinal',
            'original',
            'policy_enabled',
            'scope_has_realm',
            'temporal',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named rule fields, separate from canon.
final class RuleFormRecoveryStore {
  RuleFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'rule');
  late final _expressions = RecoveryExpressionInputs(
    _db,
    'rule',
    _domainStorage,
  );

  static RuleFormRecoveryStore open(String path) {
    Database? db;
    try {
      final directory = privateDirectory(File(path).absolute.parent.path);
      final actual = '$directory/${File(path).uri.pathSegments.last}';
      protectedFile(actual, create: true);
      for (final suffix in ['-wal', '-shm']) {
        if (FileSystemEntity.typeSync('$actual$suffix', followLinks: false) !=
            FileSystemEntityType.notFound) {
          protectedFile('$actual$suffix');
        }
      }
      db = sqlite3.open(actual, mode: OpenMode.readWrite);
      if (sqlite3.version.versionNumber < 3051003) {
        throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
      }
      _checkSchema(db);
      db.execute(
        'PRAGMA foreign_keys=ON; PRAGMA busy_timeout=1000; PRAGMA synchronous=FULL',
      );
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('BEGIN IMMEDIATE');
      try {
        final version = _checkSchema(db);
        if (version == 0) {
          db.execute(_schema);
        }
        db.execute('COMMIT');
      } catch (_) {
        if (!db.autocommit) db.execute('ROLLBACK');
        rethrow;
      }
      for (final suffix in ['-wal', '-shm']) {
        if (File('$actual$suffix').existsSync()) {
          protectedFile('$actual$suffix');
        }
      }
      return RuleFormRecoveryStore._(db);
    } on EditorRecoveryException {
      db?.close();
      rethrow;
    } on Object {
      db?.close();
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  static int _checkSchema(Database db) {
    final tables = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    if (tables.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    String columns(String table) =>
        db.select('PRAGMA table_info($table)').map((r) => r['name']).join(',');
    final expected = {
      'rule_form': '$_keys,$_fields',
      'rule_label': '$_keys,ordinal,language,label_text',
      'rule_list': '$_keys,list_kind,ordinal,input_text',
      'rule_knowledge': '$_keys,$_knowledgeFields',
      'rule_constraint': '$_keys,$_constraintFields',
      'rule_evidence': '$_keys,enabled',
      'rule_evidence_category':
          '$_keys,ordinal,universe_input,record_input,version_input',
      ...RecoveryValueInputs.columns('rule'),
      ...RecoveryExpressionInputs.columns('rule'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _domainStorage.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domainStorage.matches(db);
    if (!current) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return version as int;
  }

  List<String> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null ||
        scope.attributeClientRef != null) {
      throw const FormatException('Choose the rule context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      scope.typeClientRef ?? '',
    ];
  }

  List<Row> _rows(
    String table,
    String columns,
    List<String> binding, {
    String? kind,
    bool ordered = false,
  }) {
    final rows = _db.select(
      'SELECT ${ordered ? 'ordinal,' : ''}${_textProjection(columns)} FROM rule_$table WHERE $_where${kind == null ? '' : ' AND list_kind=?'}${ordered ? ' ORDER BY ordinal' : ''}',
      [...binding, ?kind],
    );
    if (ordered) {
      for (var i = 0; i < rows.length; i++) {
        if (rows[i]['ordinal'] != i) {
          throw const FormatException('Incomplete rule input order');
        }
      }
    }
    return rows;
  }

  List<String> _list(List<String> binding, String kind) => _rows(
    'list',
    'input_text',
    binding,
    kind: kind,
    ordered: true,
  ).map((r) => _text(r, 'input_text')).toList();
  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  ScopeInput _scope(Row r, List<String> binding, String worlds) => ScopeInput(
    applicability: _text(r, 'scope_applicability'),
    contextRecord: _text(r, 'scope_context_record'),
    contextUniverse: _text(r, 'scope_context_universe'),
    hasRealm: r['scope_has_realm'] == 1,
    realmRecord: _text(r, 'scope_realm_record'),
    realmUniverse: _text(r, 'scope_realm_universe'),
    worlds: _list(binding, worlds),
  );
  SavedRuleForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _rows('form', _fields, _binding(scope));
    if (rows.isEmpty) return null;
    final r = rows.single,
        knowledge = _rows('knowledge', _knowledgeFields, binding),
        constraints = _rows('constraint', _constraintFields, binding),
        evidence = _rows('evidence', 'enabled', binding);
    final k = knowledge.isEmpty ? null : knowledge.single,
        c = constraints.isEmpty ? null : constraints.single;
    return SavedRuleForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedRuleForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        namespace: _text(r, 'namespace'),
        key: _text(r, 'rule_key'),
        kind: _text(r, 'rule_kind'),
        commitPolicy: _text(r, 'commit_policy'),
        rationale: _text(r, 'rationale'),
        scope: _scope(r, binding, 'world'),
        labels: _rows('label', 'language,label_text', binding, ordered: true)
            .map(
              (l) => PropertyLabelInput(
                language: _text(l, 'language'),
                text: _text(l, 'label_text'),
              ),
            ),
        subjectTypes: _list(binding, 'subject'),
        targetPredicates: _list(binding, 'predicate'),
        capabilities: _list(binding, 'capability'),
        expression: _expressions.read(r['expression_root'] as int),
        executable: r['executable'] == null ? null : r['executable'] == 1,
        validity: _inputs.readTemporal(r['temporal'] as int, 0),
        original: r['original'] == null
            ? null
            : RuleRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        revisionTarget: r['target_record'] == null ? null : _ref(r, 'target'),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
        knowledge: k == null
            ? null
            : RuleKnowledgeInput(
                policyEnabled: k['policy_enabled'] == 1,
                boundaryEnabled: k['boundary_enabled'] == 1,
                mode: _text(k, 'mode'),
                policyContext: _ref(k, 'policy_context'),
                holder: _ref(k, 'holder'),
                proposition: _ref(k, 'proposition'),
                boundaryContext: _ref(k, 'boundary_context'),
              ),
        constraints: c == null
            ? null
            : RuleConstraintInput(
                cardinalityEnabled: c['cardinality_enabled'] == 1,
                chronologyEnabled: c['chronology_enabled'] == 1,
                relation: _ref(c, 'relation'),
                grouping: _text(c, 'grouping_input'),
                groupingRole: _text(c, 'grouping_role'),
                countedRole: _text(c, 'counted_role'),
                maximum: _text(c, 'maximum_input'),
                scope: _scope(c, binding, 'constraint_world'),
                validity: _inputs.readTemporal(c['temporal'] as int, 0),
                channel: _text(c, 'channel'),
                forwardOnly: c['forward_only'] == null
                    ? null
                    : c['forward_only'] == 1,
                minimumEnabled: c['minimum_enabled'] == 1,
                maximumEnabled: c['maximum_enabled'] == 1,
                minimumDelay: _text(c, 'minimum_delay'),
                maximumDelay: _text(c, 'maximum_delay'),
              ),
        evidence: evidence.isEmpty
            ? null
            : RuleEvidenceInput(
                enabled: evidence.single['enabled'] == 1,
                categories:
                    _rows(
                      'evidence_category',
                      'universe_input,record_input,version_input',
                      binding,
                      ordered: true,
                    ).map(
                      (v) => RuleEvidenceCategoryInput(
                        universe: _text(v, 'universe_input'),
                        record: _text(v, 'record_input'),
                        version: _text(v, 'version_input'),
                      ),
                    ),
                reviewMethods: _list(binding, 'review_method'),
              ),
      ),
    );
  }

  void _insert(String table, List<Object?> values) => _db.execute(
    'INSERT INTO rule_$table VALUES(${List.filled(values.length, '?').join(',')})',
    values,
  );
  void _write(EditorFormScope scope, SavedRuleForm saved) {
    final binding = _binding(scope), f = saved.form, s = f.scope;
    final old = _db.select(
          'SELECT original,temporal,expression_root FROM rule_form WHERE $_where',
          binding,
        ),
        oldConstraint = _db.select(
          'SELECT temporal FROM rule_constraint WHERE $_where',
          binding,
        );
    final temporal = _inputs.writeTemporal(f.validity, 0),
        expression = _expressions.write(f.expression),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO rule_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.namespace,
        f.key,
        f.kind,
        f.commitPolicy,
        f.rationale,
        s.applicability,
        s.contextRecord,
        s.contextUniverse,
        s.hasRealm ? 1 : 0,
        s.realmRecord,
        s.realmUniverse,
        expression,
        f.executable == null
            ? null
            : f.executable!
            ? 1
            : 0,
        temporal,
        original,
        f.revisionTarget?.record,
        f.revisionTarget?.universe,
        f.expectedRecordVersion?.value,
        f.draftVersion?.toString(),
      ],
    );
    for (final table in [
      'evidence_category',
      'evidence',
      'knowledge',
      'constraint',
      'list',
      'label',
    ]) {
      _db.execute('DELETE FROM rule_$table WHERE $_where', binding);
    }
    for (var i = 0; i < f.labels.length; i++) {
      final l = f.labels[i];
      _insert('label', [...binding, i, l.language, l.text]);
    }
    final k = f.knowledge, c = f.constraints, e = f.evidence;
    if (k != null) {
      _insert('knowledge', [
        ...binding,
        k.policyEnabled ? 1 : 0,
        k.boundaryEnabled ? 1 : 0,
        k.mode,
        k.policyContext.record,
        k.policyContext.universe,
        k.holder.record,
        k.holder.universe,
        k.proposition.record,
        k.proposition.universe,
        k.boundaryContext.record,
        k.boundaryContext.universe,
      ]);
    }
    if (c != null) {
      final time = _inputs.writeTemporal(c.validity, 0), s = c.scope;
      _insert('constraint', [
        ...binding,
        c.cardinalityEnabled ? 1 : 0,
        c.chronologyEnabled ? 1 : 0,
        c.relation.record,
        c.relation.universe,
        c.grouping,
        c.groupingRole,
        c.countedRole,
        c.maximum,
        s.applicability,
        s.contextRecord,
        s.contextUniverse,
        s.hasRealm ? 1 : 0,
        s.realmRecord,
        s.realmUniverse,
        time,
        c.channel,
        c.forwardOnly == null
            ? null
            : c.forwardOnly!
            ? 1
            : 0,
        c.minimumEnabled ? 1 : 0,
        c.maximumEnabled ? 1 : 0,
        c.minimumDelay,
        c.maximumDelay,
      ]);
    }
    if (e != null) {
      _insert('evidence', [...binding, e.enabled ? 1 : 0]);
      for (var i = 0; i < e.categories.length; i++) {
        final category = e.categories[i];
        _insert('evidence_category', [
          ...binding,
          i,
          category.universe,
          category.record,
          category.version,
        ]);
      }
    }
    final lists = {
      'world': s.worlds,
      'subject': f.subjectTypes,
      'predicate': f.targetPredicates,
      'capability': f.capabilities,
      'constraint_world': c?.scope.worlds ?? <String>[],
      'review_method': e?.reviewMethods ?? <String>[],
    };
    for (final list in lists.entries) {
      for (var i = 0; i < list.value.length; i++) {
        _insert('list', [...binding, list.key, i, list.value[i]]);
      }
    }
    for (final c in oldConstraint) {
      _inputs.deleteTemporal(c['temporal'] as int);
    }
    if (old.isNotEmpty) {
      final r = old.single;
      _expressions.delete(r['expression_root'] as int);
      _inputs.deleteTemporal(r['temporal'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, r['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedRuleForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Rule form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedRuleForm? load(EditorFormScope scope) {
    _db.execute('BEGIN');
    try {
      final result = _read(scope);
      _db.execute('COMMIT');
      return result;
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  SavedRuleForm save(
    EditorFormScope scope,
    UnfinishedRuleForm form,
    BigInt expectedGeneration,
  ) {
    _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= BigInt.one << 64) {
      throw const FormatException('Invalid expected editor generation');
    }
    _validate(scope, form);
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _read(scope);
      final generation = current?.generation ?? BigInt.zero;
      if (generation != expectedGeneration) {
        if (generation == expectedGeneration + BigInt.one &&
            current!.form.toWire().toText() == form.toWire().toText()) {
          _db.execute('COMMIT');
          return current;
        }
        throw const EditorRecoveryException(EditorRecoveryFailure.conflict);
      }
      if (generation == (BigInt.one << 64) - BigInt.one) {
        throw const EditorRecoveryException(
          EditorRecoveryFailure.generationExhausted,
        );
      }
      final saved = SavedRuleForm(
        generation: generation + BigInt.one,
        form: form,
      );
      _write(scope, saved);
      _db.execute('COMMIT');
      return saved;
    } on EditorRecoveryException {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    } on Object {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  void close() => _db.close();
}
