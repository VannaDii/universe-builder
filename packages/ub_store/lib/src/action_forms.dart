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

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,namespace,action_key,rationale,original,target_record,target_universe,expected_record_version,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,slots_present,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel(
  RecordKind.actionDefinition.wireName,
);
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'AttributeRequirement',
  'EffectSlot',
]);
final _schema =
    """
CREATE TABLE action_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,namespace TEXT NOT NULL,action_key TEXT NOT NULL,rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),target_record TEXT,target_universe TEXT,expected_record_version TEXT,
 scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,temporal INTEGER NOT NULL REFERENCES action_temporal(id),slots_present INTEGER NOT NULL CHECK(slots_present IN (0,1)),draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE action_label (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),language TEXT NOT NULL,label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES action_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE action_world (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES action_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE action_requirement (
 id INTEGER PRIMARY KEY,role_input TEXT NOT NULL,predicate_record TEXT NOT NULL,predicate_universe TEXT NOT NULL,value_root INTEGER NOT NULL REFERENCES action_qualifier(id),original INTEGER REFERENCES "${BodyCatalog.instance.model('AttributeRequirement').table}"(__row_id)
) STRICT;
CREATE TABLE action_requirement_item (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),requirement_root INTEGER NOT NULL REFERENCES action_requirement(id),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES action_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE action_slot (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0),target_record TEXT NOT NULL,target_universe TEXT NOT NULL,condition_root INTEGER NOT NULL REFERENCES action_requirement(id),value_root INTEGER NOT NULL REFERENCES action_qualifier(id),original INTEGER REFERENCES "${BodyCatalog.instance.model('EffectSlot').table}"(__row_id),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES action_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE action_slot_field (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 slot_ordinal INTEGER NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT NOT NULL,input_value TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,slot_ordinal,ordinal),UNIQUE(instance,profile,universe,continuity,context,editor_key,slot_ordinal,input_key),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,slot_ordinal) REFERENCES action_slot(instance,profile,universe,continuity,context,editor_key,ordinal)
) STRICT;
${RecoveryValueInputs.schema('action')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'original',
            'scope_has_realm',
            'temporal',
            'slots_present',
            'value_root',
            'condition_root',
            'requirement_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named action fields, separate from canon.
final class ActionFormRecoveryStore {
  ActionFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'action');

  static ActionFormRecoveryStore open(String path) {
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
        } else if (version == 1) {
          db.execute('ALTER TABLE action_form RENAME TO legacy_action_form');
          db.execute(_schema);
          final store = ActionFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_action_form',
          )) {
            final scope = EditorFormScope(
              instance: OperationId.parse(_text(row, 'instance')),
              profile: ProfileId.parse(_text(row, 'profile')),
              universe: UniverseId.parse(_text(row, 'universe')),
              continuity: ContinuityId.parse(_text(row, 'continuity')),
              representedContext: RecordId.parse(_text(row, 'context')),
              typeClientRef: _text(row, 'editor_key').isEmpty
                  ? null
                  : _text(row, 'editor_key'),
            );
            final form = UnfinishedActionForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedActionForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_action_form');
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
      return ActionFormRecoveryStore._(db);
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
    final legacy =
        version == 1 &&
        tables.length == 1 &&
        columns('action_form') == _legacyColumns;
    final expected = {
      'action_form': '$_keys,$_fields',
      'action_label': '$_keys,ordinal,language,label_text',
      'action_world': '$_keys,ordinal,world_input',
      'action_requirement': 'id,role_input,predicate_record,predicate_universe,value_root,original',
      'action_requirement_item': '$_keys,ordinal,requirement_root',
      'action_slot':
          '$_keys,ordinal,target_record,target_universe,condition_root,value_root,original',
      'action_slot_field': '$_keys,slot_ordinal,ordinal,input_key,input_value',
      ...RecoveryValueInputs.columns('action'),
    };
    final current =
        version == 2 &&
        tables.length == expected.length + _domainStorage.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domainStorage.matches(db);
    if (!legacy && !current) {
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
      throw const FormatException('Choose the action context.');
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

  List<Row> _ordered(
    String table,
    String columns,
    List<String> binding, {
    int? slot,
  }) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM action_$table WHERE $_where${slot == null ? '' : ' AND slot_ordinal=?'} ORDER BY ordinal',
      [...binding, ?slot],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete action input order');
      }
    }
    return rows;
  }

  ActionRequirementInput _readRequirement(int id) {
    final r = _db.select(
      'SELECT ${_textProjection('role_input,predicate_record,predicate_universe,value_root,original')} FROM action_requirement WHERE id=?',
      [id],
    ).single;
    return ActionRequirementInput(
      role: _text(r, 'role_input'),
      predicate: ExpressionReferenceInput(
        record: _text(r, 'predicate_record'),
        universe: _text(r, 'predicate_universe'),
      ),
      value: _inputs.readQualifier(r['value_root'] as int, 0),
      original: r['original'] == null
          ? null
          : AttributeRequirement.fromWire(
              RelationalCodec(_db).get('AttributeRequirement', r['original']),
            ),
    );
  }

  SavedActionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope), codec = RelationalCodec(_db);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM action_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedActionForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedActionForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        namespace: _text(r, 'namespace'),
        key: _text(r, 'action_key'),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : ActionDefinitionRecord.fromWire(
                codec.get(_originalModel, r['original']),
              ),
        revisionTarget: r['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(r, 'target_record'),
                universe: _text(r, 'target_universe'),
              ),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        labels: _ordered('label', 'language,label_text', binding).map(
          (l) => PropertyLabelInput(
            language: _text(l, 'language'),
            text: _text(l, 'label_text'),
          ),
        ),
        requirements: _ordered(
          'requirement_item',
          'requirement_root',
          binding,
        ).map((q) => _readRequirement(q['requirement_root'] as int)),
        slots: r['slots_present'] == 0
            ? null
            : _ordered(
                'slot',
                'target_record,target_universe,condition_root,value_root,original',
                binding,
              ).map(
                (s) => ActionSlotInput(
                  target: ExpressionReferenceInput(
                    record: _text(s, 'target_record'),
                    universe: _text(s, 'target_universe'),
                  ),
                  condition: _readRequirement(s['condition_root'] as int),
                  value: _inputs.readQualifier(s['value_root'] as int, 0),
                  original: s['original'] == null
                      ? null
                      : EffectSlot.fromWire(
                          codec.get('EffectSlot', s['original']),
                        ),
                  fields: {
                    for (final f in _ordered(
                      'slot_field',
                      'input_key,input_value',
                      binding,
                      slot: s['ordinal'] as int,
                    ))
                      _text(f, 'input_key'): _text(f, 'input_value'),
                  },
                ),
              ),
        scope: ScopeInput(
          applicability: _text(r, 'scope_applicability'),
          contextRecord: _text(r, 'scope_context_record'),
          contextUniverse: _text(r, 'scope_context_universe'),
          hasRealm: r['scope_has_realm'] == 1,
          realmRecord: _text(r, 'scope_realm_record'),
          realmUniverse: _text(r, 'scope_realm_universe'),
          worlds: _ordered(
            'world',
            'world_input',
            binding,
          ).map((w) => _text(w, 'world_input')).toList(),
        ),
        validity: _inputs.readTemporal(r['temporal'] as int, 0),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  int _writeRequirement(ActionRequirementInput r) {
    final value = _inputs.writeQualifier(r.value, 0),
        original = r.original == null
            ? null
            : RelationalCodec(_db)
                  .put('AttributeRequirement', r.original!.toWire());
    _db.execute(
      'INSERT INTO action_requirement(role_input,predicate_record,predicate_universe,value_root,original) VALUES(?,?,?,?,?)',
      [r.role, r.predicate.record, r.predicate.universe, value, original],
    );
    return _db.lastInsertRowId;
  }

  void _deleteRequirement(int id) {
    final r = _db.select(
      'SELECT value_root,original FROM action_requirement WHERE id=?',
      [id],
    ).single;
    _db.execute('DELETE FROM action_requirement WHERE id=?', [id]);
    _inputs.deleteQualifier(r['value_root'] as int);
    _domainStorage.deleteOwned(_db, 'AttributeRequirement', r['original']);
  }

  void _write(EditorFormScope scope, SavedActionForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        s = f.scope,
        codec = RelationalCodec(_db);
    final old = _db.select(
          'SELECT original,temporal FROM action_form WHERE $_where',
          binding,
        ),
        oldSlots = _db.select(
          'SELECT original,condition_root,value_root FROM action_slot WHERE $_where',
          binding,
        ),
        oldRequirements = _db.select(
          'SELECT requirement_root FROM action_requirement_item WHERE $_where',
          binding,
        );
    final temporal = _inputs.writeTemporal(f.validity, 0),
        original = f.original == null
            ? null
            : codec.put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO action_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.namespace,
        f.key,
        f.rationale,
        original,
        f.revisionTarget?.record,
        f.revisionTarget?.universe,
        f.expectedRecordVersion?.value,
        s.applicability,
        s.contextRecord,
        s.contextUniverse,
        s.hasRealm ? 1 : 0,
        s.realmRecord,
        s.realmUniverse,
        temporal,
        f.slots == null ? 0 : 1,
        f.draftVersion?.toString(),
      ],
    );
    for (final table in [
      'slot_field',
      'slot',
      'requirement_item',
      'label',
      'world',
    ]) {
      _db.execute('DELETE FROM action_$table WHERE $_where', binding);
    }
    for (var i = 0; i < f.labels.length; i++) {
      final l = f.labels[i];
      _db.execute('INSERT INTO action_label VALUES(?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        l.language,
        l.text,
      ]);
    }
    for (var i = 0; i < s.worlds.length; i++) {
      _db.execute('INSERT INTO action_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        s.worlds[i],
      ]);
    }
    for (var i = 0; i < f.requirements.length; i++) {
      final root = _writeRequirement(f.requirements[i]);
      _db.execute(
        'INSERT INTO action_requirement_item VALUES(?,?,?,?,?,?,?,?)',
        [...binding, i, root],
      );
    }
    final slots = f.slots ?? <ActionSlotInput>[];
    for (var i = 0; i < slots.length; i++) {
      final slot = slots[i],
          condition = _writeRequirement(slots[i].condition),
          value = _inputs.writeQualifier(slots[i].value, 0),
          original = slot.original == null
              ? null
              : codec.put('EffectSlot', slot.original!.toWire());
      _db.execute('INSERT INTO action_slot VALUES(?,?,?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        slot.target.record,
        slot.target.universe,
        condition,
        value,
        original,
      ]);
      var j = 0;
      for (final field in slot.fields.entries) {
        _db.execute(
          'INSERT INTO action_slot_field VALUES(?,?,?,?,?,?,?,?,?,?)',
          [...binding, i, j++, field.key, field.value],
        );
      }
    }
    for (final r in oldRequirements) {
      _deleteRequirement(r['requirement_root'] as int);
    }
    for (final slot in oldSlots) {
      _deleteRequirement(slot['condition_root'] as int);
      _inputs.deleteQualifier(slot['value_root'] as int);
      _domainStorage.deleteOwned(_db, 'EffectSlot', slot['original']);
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['temporal'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedActionForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Action form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedActionForm? load(EditorFormScope scope) {
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

  SavedActionForm save(
    EditorFormScope scope,
    UnfinishedActionForm form,
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
      final saved = SavedActionForm(
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
