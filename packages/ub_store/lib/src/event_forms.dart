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
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,label,occurrence,description,action_record,action_universe,temporal,rationale,original,target_record,target_universe,expected_record_version,region_record,region_universe,sequence_input,occurrence_id,effects_present,preconditions_present,draft_version';
const _effectFields =
    'slot_input,proposition_record,proposition_universe,polarity_input,order_input,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,original';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('event');
final _domainStorage = RecoveryDomainSchema([
  _originalModel,
  'EntityEffect',
  'Expr',
  'Operand',
]);
final _schema =
    """
CREATE TABLE event_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,label TEXT NOT NULL,occurrence TEXT NOT NULL,description TEXT NOT NULL,action_record TEXT NOT NULL,action_universe TEXT NOT NULL,
 temporal INTEGER NOT NULL REFERENCES event_temporal(id),rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),target_record TEXT,target_universe TEXT,expected_record_version TEXT,
 region_record TEXT NOT NULL,region_universe TEXT NOT NULL,sequence_input TEXT NOT NULL,occurrence_id TEXT NOT NULL,effects_present INTEGER NOT NULL CHECK(effects_present IN (0,1)),preconditions_present INTEGER NOT NULL CHECK(preconditions_present IN (0,1)),draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE event_participant(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),record_input TEXT NOT NULL,universe_input TEXT NOT NULL,role_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES event_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE event_world(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES event_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE event_precondition(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),expression_root INTEGER NOT NULL REFERENCES event_expression(id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES event_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE event_effect(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),slot_input TEXT NOT NULL,proposition_record TEXT NOT NULL,proposition_universe TEXT NOT NULL,polarity_input TEXT NOT NULL,order_input TEXT NOT NULL,scope_applicability TEXT NOT NULL,scope_context_record TEXT NOT NULL,scope_context_universe TEXT NOT NULL,scope_has_realm INTEGER NOT NULL CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT NOT NULL,scope_realm_universe TEXT NOT NULL,temporal INTEGER NOT NULL REFERENCES event_temporal(id),original INTEGER REFERENCES "${BodyCatalog.instance.model('EntityEffect').table}"(__row_id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES event_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE event_effect_world (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 effect_ordinal INTEGER NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,effect_ordinal,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,effect_ordinal) REFERENCES event_effect(instance,profile,universe,continuity,context,editor_key,ordinal)
) STRICT;
${RecoveryValueInputs.schema('event')}
${RecoveryExpressionInputs.schema('event')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'temporal',
            'original',
            'effects_present',
            'preconditions_present',
            'scope_has_realm',
            'expression_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named event fields, separate from canon.
final class EventFormRecoveryStore {
  EventFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'event');
  late final _expressions = RecoveryExpressionInputs(
    _db,
    'event',
    _domainStorage,
  );

  static EventFormRecoveryStore open(String path) {
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
          db.execute('ALTER TABLE event_form RENAME TO legacy_event_form');
          db.execute(_schema);
          final store = EventFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_event_form',
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
            final form = UnfinishedEventForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedEventForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_event_form');
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
      return EventFormRecoveryStore._(db);
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
        columns('event_form') == _legacyColumns;
    final expected = {
      'event_form': '$_keys,$_fields',
      'event_participant':
          '$_keys,ordinal,record_input,universe_input,role_input',
      'event_world': '$_keys,ordinal,world_input',
      'event_precondition': '$_keys,ordinal,expression_root',
      'event_effect':
          '$_keys,ordinal,slot_input,proposition_record,proposition_universe,polarity_input,order_input,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,temporal,original',
      'event_effect_world': '$_keys,effect_ordinal,ordinal,world_input',
      ...RecoveryValueInputs.columns('event'),
      ...RecoveryExpressionInputs.columns('event'),
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
      throw const FormatException('Choose the event context.');
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
    int? effect,
  }) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM event_$table WHERE $_where${effect == null ? '' : ' AND effect_ordinal=?'} ORDER BY ordinal',
      [...binding, ?effect],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete event input order');
      }
    }
    return rows;
  }

  SavedEventForm? _read(EditorFormScope scope) {
    final binding = _binding(scope), codec = RelationalCodec(_db);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM event_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedEventForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedEventForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        label: _text(r, 'label'),
        occurrence: _text(r, 'occurrence'),
        description: _text(r, 'description'),
        actionRecord: _text(r, 'action_record'),
        actionUniverse: _text(r, 'action_universe'),
        time: _inputs.readTemporal(r['temporal'] as int, 0),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : RecordPayload.fromWire(codec.get(_originalModel, r['original']))
                  as EventRecord,
        revisionTarget: r['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: _text(r, 'target_record'),
                universe: _text(r, 'target_universe'),
              ),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        worlds: _ordered(
          'world',
          'world_input',
          binding,
        ).map((w) => _text(w, 'world_input')),
        regionRecord: _text(r, 'region_record'),
        regionUniverse: _text(r, 'region_universe'),
        sequence: _text(r, 'sequence_input'),
        occurrenceId: _text(r, 'occurrence_id'),
        participants:
            _ordered(
              'participant',
              'record_input,universe_input,role_input',
              binding,
            ).map(
              (p) => EventParticipantInput(
                record: _text(p, 'record_input'),
                universe: _text(p, 'universe_input'),
                role: _text(p, 'role_input'),
              ),
            ),
        preconditions: r['preconditions_present'] == 0
            ? null
            : _ordered(
                'precondition',
                'expression_root',
                binding,
              ).map((p) => _expressions.read(p['expression_root'] as int)),
        effects: r['effects_present'] == 0
            ? null
            : _ordered('effect', _effectFields, binding).map(
                (e) => EventEffectInput(
                  slot: _text(e, 'slot_input'),
                  propositionRecord: _text(e, 'proposition_record'),
                  propositionUniverse: _text(e, 'proposition_universe'),
                  polarity: _text(e, 'polarity_input'),
                  order: _text(e, 'order_input'),
                  scope: ScopeInput(
                    applicability: _text(e, 'scope_applicability'),
                    contextRecord: _text(e, 'scope_context_record'),
                    contextUniverse: _text(e, 'scope_context_universe'),
                    hasRealm: e['scope_has_realm'] == 1,
                    realmRecord: _text(e, 'scope_realm_record'),
                    realmUniverse: _text(e, 'scope_realm_universe'),
                    worlds: _ordered(
                      'effect_world',
                      'world_input',
                      binding,
                      effect: e['ordinal'] as int,
                    ).map((w) => _text(w, 'world_input')).toList(),
                  ),
                  validity: _inputs.readTemporal(e['temporal'] as int, 0),
                  original: e['original'] == null
                      ? null
                      : EntityEffect.fromWire(
                          codec.get('EntityEffect', e['original']),
                        ),
                ),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedEventForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        codec = RelationalCodec(_db);
    final old = _db.select(
          'SELECT original,temporal FROM event_form WHERE $_where',
          binding,
        ),
        oldEffects = _db.select(
          'SELECT original,temporal FROM event_effect WHERE $_where',
          binding,
        ),
        oldConditions = _db.select(
          'SELECT expression_root FROM event_precondition WHERE $_where',
          binding,
        );
    final temporal = _inputs.writeTemporal(f.time, 0),
        original = f.original == null
            ? null
            : codec.put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO event_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.label,
        f.occurrence,
        f.description,
        f.actionRecord,
        f.actionUniverse,
        temporal,
        f.rationale,
        original,
        f.revisionTarget?.record,
        f.revisionTarget?.universe,
        f.expectedRecordVersion?.value,
        f.regionRecord,
        f.regionUniverse,
        f.sequence,
        f.occurrenceId,
        f.effects == null ? 0 : 1,
        f.preconditions == null ? 0 : 1,
        f.draftVersion?.toString(),
      ],
    );
    for (final table in [
      'effect_world',
      'effect',
      'precondition',
      'participant',
      'world',
    ]) {
      _db.execute('DELETE FROM event_$table WHERE $_where', binding);
    }
    for (var i = 0; i < f.participants.length; i++) {
      final p = f.participants[i];
      _db.execute('INSERT INTO event_participant VALUES(?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        p.record,
        p.universe,
        p.role,
      ]);
    }
    for (var i = 0; i < f.worlds.length; i++) {
      _db.execute('INSERT INTO event_world VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        f.worlds[i],
      ]);
    }
    final conditions = f.preconditions ?? <ExpressionInput>[];
    for (var i = 0; i < conditions.length; i++) {
      final root = _expressions.write(conditions[i]);
      _db.execute('INSERT INTO event_precondition VALUES(?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        root,
      ]);
    }
    final effects = f.effects ?? <EventEffectInput>[];
    for (var i = 0; i < effects.length; i++) {
      final e = effects[i],
          s = e.scope,
          time = _inputs.writeTemporal(effects[i].validity, 0),
          original = e.original == null
              ? null
              : codec.put('EntityEffect', e.original!.toWire());
      _db.execute(
        'INSERT INTO event_effect VALUES(${List.filled(7 + _effectFields.split(',').length, '?').join(',')})',
        [
          ...binding,
          i,
          e.slot,
          e.propositionRecord,
          e.propositionUniverse,
          e.polarity,
          e.order,
          s.applicability,
          s.contextRecord,
          s.contextUniverse,
          s.hasRealm ? 1 : 0,
          s.realmRecord,
          s.realmUniverse,
          time,
          original,
        ],
      );
      for (var j = 0; j < s.worlds.length; j++) {
        _db.execute(
          'INSERT INTO event_effect_world VALUES(?,?,?,?,?,?,?,?,?)',
          [...binding, i, j, s.worlds[j]],
        );
      }
    }
    for (final c in oldConditions) {
      _expressions.delete(c['expression_root'] as int);
    }
    for (final e in oldEffects) {
      _inputs.deleteTemporal(e['temporal'] as int);
      _domainStorage.deleteOwned(_db, 'EntityEffect', e['original']);
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['temporal'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedEventForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Event form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedEventForm? load(EditorFormScope scope) {
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

  SavedEventForm save(
    EditorFormScope scope,
    UnfinishedEventForm form,
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
      final saved = SavedEventForm(
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
