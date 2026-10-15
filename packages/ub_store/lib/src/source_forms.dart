import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,label,source_text,rationale,anchor_record,anchor_version,anchor_universe,draft_version';
const _operationFields =
    'ordinal,record_kind,client_ref,label,external_id,origin_author,origin_note,source_record,source_universe,content_digest,media_type,byte_size,import_actor,import_time,encoding,representation,decoding_length,pin_record,pin_version,pin_universe,locator_kind,range_start,range_end,excerpt_digest,excerpt,context_record,context_universe';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE source_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 label TEXT NOT NULL, source_text TEXT NOT NULL, rationale TEXT NOT NULL,
 anchor_record TEXT, anchor_version TEXT, anchor_universe TEXT, draft_version TEXT,
 CHECK((anchor_record IS NULL AND anchor_version IS NULL AND anchor_universe IS NULL) OR (anchor_record IS NOT NULL AND anchor_version IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE source_operation (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), record_kind TEXT NOT NULL CHECK(record_kind IN ('source','source_version','anchor')),
 client_ref TEXT NOT NULL, label TEXT, external_id TEXT, origin_author TEXT, origin_note TEXT,
 source_record TEXT, source_universe TEXT, content_digest TEXT, media_type TEXT, byte_size TEXT,
 import_actor TEXT, import_time TEXT, encoding TEXT, representation TEXT, decoding_length TEXT,
 pin_record TEXT, pin_version TEXT, pin_universe TEXT, locator_kind TEXT CHECK(locator_kind IN ('byte_range','structural_path')),
 range_start TEXT, range_end TEXT, excerpt_digest TEXT, excerpt TEXT, context_record TEXT, context_universe TEXT,
 CHECK((record_kind='source' AND label IS NOT NULL AND source_record IS NULL AND source_universe IS NULL AND content_digest IS NULL AND media_type IS NULL AND byte_size IS NULL AND import_actor IS NULL AND import_time IS NULL AND encoding IS NULL AND representation IS NULL AND decoding_length IS NULL AND pin_record IS NULL AND pin_version IS NULL AND pin_universe IS NULL AND locator_kind IS NULL AND range_start IS NULL AND range_end IS NULL AND excerpt_digest IS NULL AND excerpt IS NULL AND context_record IS NULL AND context_universe IS NULL)
 OR (record_kind='source_version' AND source_record IS NOT NULL AND content_digest IS NOT NULL AND media_type IS NOT NULL AND byte_size IS NOT NULL AND import_actor IS NOT NULL AND import_time IS NOT NULL AND encoding IS NOT NULL AND representation IS NOT NULL AND decoding_length IS NOT NULL AND label IS NULL AND external_id IS NULL AND pin_record IS NULL AND pin_version IS NULL AND pin_universe IS NULL AND locator_kind IS NULL AND range_start IS NULL AND range_end IS NULL AND excerpt_digest IS NULL AND excerpt IS NULL AND context_record IS NULL AND context_universe IS NULL)
 OR (record_kind='anchor' AND pin_record IS NOT NULL AND pin_version IS NOT NULL AND locator_kind IS NOT NULL AND excerpt_digest IS NOT NULL AND excerpt IS NOT NULL AND label IS NULL AND external_id IS NULL AND origin_author IS NULL AND origin_note IS NULL AND source_record IS NULL AND source_universe IS NULL AND content_digest IS NULL AND media_type IS NULL AND byte_size IS NULL AND import_actor IS NULL AND import_time IS NULL AND encoding IS NULL AND representation IS NULL AND decoding_length IS NULL AND (context_record IS NOT NULL OR context_universe IS NULL) AND ((locator_kind='byte_range' AND range_start IS NOT NULL AND range_end IS NOT NULL) OR (locator_kind='structural_path' AND range_start IS NULL AND range_end IS NULL)))),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key)
 REFERENCES source_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE source_operation_item (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL,
 continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 operation_ordinal INTEGER NOT NULL, list_kind TEXT NOT NULL CHECK(list_kind IN ('version','path')),
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), item TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,operation_ordinal,list_kind,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key,operation_ordinal)
 REFERENCES source_operation(instance,profile,universe,continuity,context,editor_key,ordinal)
) STRICT;
PRAGMA user_version=2;
""";
String _projection(String columns) => columns
    .split(',')
    .map((c) => c == 'ordinal' ? c : 'CAST($c AS BLOB) AS $c')
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);
String? _optionalText(Row row, String column) =>
    row[column] == null ? null : _text(row, column);

/// Named private source input and typed staged source/anchor records.
final class SourceFormRecoveryStore {
  SourceFormRecoveryStore._(this._db);
  final Database _db;

  static SourceFormRecoveryStore open(String path) {
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
          db.execute('ALTER TABLE source_form RENAME TO legacy_source_form');
          db.execute(_schema);
          final store = SourceFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_projection(_legacyColumns)} FROM legacy_source_form',
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
            final form = UnfinishedSourceForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedSourceForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_source_form');
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
      return SourceFormRecoveryStore._(db);
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
        columns('source_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 3 &&
        columns('source_form') == '$_keys,$_fields' &&
        columns('source_operation') == '$_keys,$_operationFields' &&
        columns('source_operation_item') ==
            '$_keys,operation_ordinal,list_kind,ordinal,item';
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
      throw const FormatException('Choose the source import context.');
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

  SavedSourceForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_projection('$_keys,$_fields')} FROM source_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final staged = <DomainOperation>[];
    for (final operation in _db.select(
      'SELECT ${_projection(_operationFields)} FROM source_operation WHERE $_where ORDER BY ordinal',
      binding,
    )) {
      if (operation['ordinal'] != staged.length) {
        throw const FormatException('Source operation order is incomplete.');
      }
      staged.add(_readOperation(binding, operation));
    }
    return SavedSourceForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedSourceForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(row, 'client_ref'),
        label: _text(row, 'label'),
        text: _text(row, 'source_text'),
        rationale: _text(row, 'rationale'),
        staged: staged,
        anchorSource: row['anchor_record'] == null
            ? null
            : VersionRef(
                record: RecordId.parse(_text(row, 'anchor_record')),
                version: RecordVersionId.parse(_text(row, 'anchor_version')),
                universe: row['anchor_universe'] == null
                    ? null
                    : UniverseId.parse(_text(row, 'anchor_universe')),
              ),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
      ),
    );
  }

  DomainOperation _readOperation(List<String> binding, Row row) {
    final clientRef = _text(row, 'client_ref');
    List<String> items(String kind) {
      final rows = _db.select(
        'SELECT ordinal,CAST(item AS BLOB) AS item FROM source_operation_item WHERE $_where AND operation_ordinal=? AND list_kind=? ORDER BY ordinal',
        [...binding, row['ordinal'], kind],
      );
      for (var i = 0; i < rows.length; i++) {
        if (rows[i]['ordinal'] != i) {
          throw const FormatException('Source item order is incomplete.');
        }
      }
      return rows.map((r) => _text(r, 'item')).toList();
    }

    OriginMetadata origin() => OriginMetadata(
      externallyAssertedAuthor: _optionalText(row, 'origin_author'),
      originNote: _optionalText(row, 'origin_note'),
    );
    final kind = RecordKind.parse(_text(row, 'record_kind'));
    final RecordPayload payload;
    switch (kind) {
      case RecordKind.source:
        payload = SourceRecord(
          label: _text(row, 'label'),
          externalId: _optionalText(row, 'external_id'),
          origin: origin(),
          versions: items('version').map(RecordId.parse),
        );
      case RecordKind.sourceVersion:
        payload = SourceVersionRecord(
          source: RecordRef(
            record: RecordId.parse(_text(row, 'source_record')),
            universe: row['source_universe'] == null
                ? null
                : UniverseId.parse(_text(row, 'source_universe')),
          ),
          contentDigest: _text(row, 'content_digest'),
          mediaType: _text(row, 'media_type'),
          byteSize: BigInt.parse(_text(row, 'byte_size')),
          importActor: PrincipalId.parse(_text(row, 'import_actor')),
          importTime: _text(row, 'import_time'),
          decoding: DecodingDescriptor(
            encoding: _text(row, 'encoding'),
            representation: _text(row, 'representation'),
            byteLength: BigInt.parse(_text(row, 'decoding_length')),
          ),
          origin: origin(),
        );
      case RecordKind.anchor:
        final AnchorLocator locator = switch (_text(row, 'locator_kind')) {
          'byte_range' => ByteRangeLocator(
            BigInt.parse(_text(row, 'range_start')),
            BigInt.parse(_text(row, 'range_end')),
          ),
          'structural_path' => StructuralPathLocator(items('path')),
          _ => throw const FormatException('Unknown source anchor locator.'),
        };
        return AddSourceAnchorOperation(
          clientRef: clientRef,
          record: AnchorRecord(
            sourceVersion: VersionRef(
              record: RecordId.parse(_text(row, 'pin_record')),
              version: RecordVersionId.parse(_text(row, 'pin_version')),
              universe: row['pin_universe'] == null
                  ? null
                  : UniverseId.parse(_text(row, 'pin_universe')),
            ),
            locator: locator,
            excerptDigest: _text(row, 'excerpt_digest'),
            excerpt: _text(row, 'excerpt'),
            context: row['context_record'] == null
                ? null
                : RecordRef(
                    record: RecordId.parse(_text(row, 'context_record')),
                    universe: row['context_universe'] == null
                        ? null
                        : UniverseId.parse(_text(row, 'context_universe')),
                  ),
          ),
        );
      default:
        throw const FormatException('Unknown staged source record.');
    }
    return RecordNarrativeReferenceOperation(
      clientRef: clientRef,
      record: kind,
      payload: payload,
    );
  }

  void _write(EditorFormScope scope, SavedSourceForm saved) {
    final binding = _binding(scope), form = saved.form;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO source_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.label,
        form.text,
        form.rationale,
        form.anchorSource?.record.value,
        form.anchorSource?.version.value,
        form.anchorSource?.universe?.value,
        form.draftVersion?.toString(),
      ],
    );
    _db.execute('DELETE FROM source_operation_item WHERE $_where', binding);
    _db.execute('DELETE FROM source_operation WHERE $_where', binding);
    for (var i = 0; i < form.staged.length; i++) {
      _writeOperation(binding, i, form.staged[i]);
    }
  }

  void _writeOperation(
    List<String> binding,
    int ordinal,
    DomainOperation operation,
  ) {
    final RecordPayload payload;
    final String clientRef;
    switch (operation) {
      case AddSourceAnchorOperation(:final record, clientRef: final ref):
        payload = record;
        clientRef = ref;
      case RecordNarrativeReferenceOperation(
            :final record,
            payload: final body,
            clientRef: final ref,
          )
          when (body is SourceRecord || body is SourceVersionRecord) &&
              record == body.recordKind:
        payload = body;
        clientRef = ref;
      default:
        throw const FormatException(
          'Expected a staged source, source version or anchor.',
        );
    }
    final row = <String, Object?>{
      'ordinal': ordinal,
      'record_kind': payload.recordKind.wireName,
      'client_ref': clientRef,
    };
    void origin(OriginMetadata value) {
      row['origin_author'] = value.externallyAssertedAuthor;
      row['origin_note'] = value.originNote;
    }

    String? listKind;
    List<String> items = [];
    switch (payload) {
      case SourceRecord():
        row.addAll({'label': payload.label, 'external_id': payload.externalId});
        origin(payload.origin);
        listKind = 'version';
        items = payload.versions.map((id) => id.value).toList();
      case SourceVersionRecord():
        row.addAll({
          'source_record': payload.source.record.value,
          'source_universe': payload.source.universe?.value,
          'content_digest': payload.contentDigest,
          'media_type': payload.mediaType,
          'byte_size': payload.byteSize.toString(),
          'import_actor': payload.importActor.value,
          'import_time': payload.importTime,
          'encoding': payload.decoding.encoding,
          'representation': payload.decoding.representation,
          'decoding_length': payload.decoding.byteLength.toString(),
        });
        origin(payload.origin);
      case AnchorRecord():
        row.addAll({
          'pin_record': payload.sourceVersion.record.value,
          'pin_version': payload.sourceVersion.version.value,
          'pin_universe': payload.sourceVersion.universe?.value,
          'excerpt_digest': payload.excerptDigest,
          'excerpt': payload.excerpt,
          'context_record': payload.context?.record.value,
          'context_universe': payload.context?.universe?.value,
        });
        switch (payload.locator) {
          case ByteRangeLocator(:final start, :final end):
            row.addAll({
              'locator_kind': 'byte_range',
              'range_start': start.toString(),
              'range_end': end.toString(),
            });
          case StructuralPathLocator(:final path):
            row['locator_kind'] = 'structural_path';
            listKind = 'path';
            items = path;
        }
      default:
        throw const FormatException('Expected a source or anchor payload.');
    }
    final columns = '$_keys,$_operationFields'.split(',');
    _db.execute(
      'INSERT INTO source_operation(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')})',
      [...binding, ..._operationFields.split(',').map((c) => row[c])],
    );
    for (var i = 0; i < items.length; i++) {
      _db.execute(
        'INSERT INTO source_operation_item VALUES(?,?,?,?,?,?,?,?,?,?)',
        [...binding, ordinal, listKind!, i, items[i]],
      );
    }
  }

  void _validate(EditorFormScope scope, UnfinishedSourceForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null &&
            scope.typeClientRef !=
                (form.draftVersion == null
                    ? (form.anchorSource?.version.value ?? form.clientRef)
                    : form.clientRef)) {
      throw const FormatException('Source import form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
  }

  SavedSourceForm? load(EditorFormScope scope) {
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

  SavedSourceForm save(
    EditorFormScope scope,
    UnfinishedSourceForm form,
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
      final saved = SavedSourceForm(
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
