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
    'generation,base_revision,client_ref,sender_record,sender_universe,channel_enabled,channel_input,distorted,sent_root,received_enabled,received_root,target_record,target_universe,expected_record_version,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('communication');
final _domainStorage = RecoveryDomainSchema([_originalModel]);
final _schema =
    """
CREATE TABLE communication_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,sender_record TEXT NOT NULL,sender_universe TEXT NOT NULL,channel_enabled INTEGER NOT NULL CHECK(channel_enabled IN (0,1)),channel_input TEXT NOT NULL,distorted INTEGER CHECK(distorted IN (0,1)),sent_root INTEGER NOT NULL REFERENCES communication_temporal(id),received_enabled INTEGER NOT NULL CHECK(received_enabled IN (0,1)),received_root INTEGER NOT NULL REFERENCES communication_temporal(id),target_record TEXT,target_universe TEXT,expected_record_version TEXT,rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,
 CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE communication_reference (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('intended','actual','content')),ordinal INTEGER NOT NULL CHECK(ordinal>=0),record_input TEXT NOT NULL,universe_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES communication_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('communication')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'channel_enabled',
            'distorted',
            'ordinal',
            'original',
            'received_enabled',
            'received_root',
            'sent_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named communication fields, separate from canon.
final class CommunicationFormRecoveryStore {
  CommunicationFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'communication');

  static CommunicationFormRecoveryStore open(String path) {
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
          db.execute(
            'ALTER TABLE communication_form RENAME TO legacy_communication_form',
          );
          db.execute(_schema);
          final store = CommunicationFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_communication_form',
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
            final form = UnfinishedCommunicationForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedCommunicationForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_communication_form');
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
      return CommunicationFormRecoveryStore._(db);
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
        columns('communication_form') == _legacyColumns;
    final expected = {
      'communication_form': '$_keys,$_fields',
      'communication_reference':
          '$_keys,list_kind,ordinal,record_input,universe_input',
      ...RecoveryValueInputs.columns('communication'),
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
      throw const FormatException('Choose the communication context.');
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

  ExpressionReferenceInput _ref(Row r, String prefix) =>
      ExpressionReferenceInput(
        record: _text(r, '${prefix}_record'),
        universe: _text(r, '${prefix}_universe'),
      );
  List<ExpressionReferenceInput> _references(
    List<String> binding,
    String kind,
  ) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection('record_input,universe_input')} FROM communication_reference WHERE $_where AND list_kind=? ORDER BY ordinal',
      [...binding, kind],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete communication reference order');
      }
    }
    return rows
        .map(
          (r) => ExpressionReferenceInput(
            record: _text(r, 'record_input'),
            universe: _text(r, 'universe_input'),
          ),
        )
        .toList();
  }

  SavedCommunicationForm? _read(EditorFormScope scope) {
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM communication_form WHERE $_where',
      _binding(scope),
    );
    if (rows.isEmpty) return null;
    final r = rows.single, binding = _binding(scope);
    return SavedCommunicationForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedCommunicationForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        sender: _ref(r, 'sender'),
        channelEnabled: r['channel_enabled'] == 1,
        channel: _text(r, 'channel_input'),
        distorted: r['distorted'] == null ? null : r['distorted'] == 1,
        sentAt: _inputs.readTemporal(r['sent_root'] as int, 0),
        receivedEnabled: r['received_enabled'] == 1,
        receivedAt: _inputs.readTemporal(r['received_root'] as int, 0),
        correctionTarget: r['target_record'] == null ? null : _ref(r, 'target'),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        intendedRecipients: _references(binding, 'intended'),
        actualRecipients: _references(binding, 'actual'),
        content: _references(binding, 'content'),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : CommunicationRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedCommunicationForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT original,sent_root,received_root FROM communication_form WHERE $_where',
      binding,
    );
    final sentRoot = _inputs.writeTemporal(f.sentAt, 0),
        receivedRoot = _inputs.writeTemporal(f.receivedAt, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO communication_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.sender.record,
        f.sender.universe,
        f.channelEnabled ? 1 : 0,
        f.channel,
        f.distorted == null
            ? null
            : f.distorted!
            ? 1
            : 0,
        sentRoot,
        f.receivedEnabled ? 1 : 0,
        receivedRoot,
        f.correctionTarget?.record,
        f.correctionTarget?.universe,
        f.expectedRecordVersion?.value,
        f.rationale,
        original,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute('DELETE FROM communication_reference WHERE $_where', binding);
    for (final list in {
      'intended': f.intendedRecipients,
      'actual': f.actualRecipients,
      'content': f.content,
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final r = list.value[i];
        _db.execute(
          'INSERT INTO communication_reference VALUES(?,?,?,?,?,?,?,?,?,?)',
          [...binding, list.key, i, r.record, r.universe],
        );
      }
    }
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['sent_root'] as int);
      _inputs.deleteTemporal(old.single['received_root'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedCommunicationForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Communication form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedCommunicationForm? load(EditorFormScope scope) {
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

  SavedCommunicationForm save(
    EditorFormScope scope,
    UnfinishedCommunicationForm form,
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
      final saved = SavedCommunicationForm(
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
