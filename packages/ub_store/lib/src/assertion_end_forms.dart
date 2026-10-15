import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,target_record,target_universe,expected_record_version,calendar,coordinate,basis_kind,basis_note,basis_anchor_record,basis_anchor_universe,basis_verified,original_kind,original_note,original_reference_record,original_reference_universe,original_verified,original_slot,original_evaluator,original_source_revision,rationale,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE assertion_end_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, target_record TEXT NOT NULL, target_universe TEXT NOT NULL, expected_record_version TEXT NOT NULL,
 calendar TEXT NOT NULL, coordinate TEXT NOT NULL, basis_kind TEXT NOT NULL, basis_note TEXT NOT NULL, basis_anchor_record TEXT NOT NULL, basis_anchor_universe TEXT NOT NULL, basis_verified INTEGER NOT NULL CHECK(basis_verified IN (0,1)),
 original_kind TEXT NOT NULL CHECK(original_kind IN ('author_decision','source_anchor','event_effect','instance_initialization','imported_claim','derivation')),
 original_note TEXT, original_reference_record TEXT, original_reference_universe TEXT, original_verified INTEGER CHECK(original_verified IN (0,1)), original_slot TEXT, original_evaluator TEXT, original_source_revision TEXT, rationale TEXT NOT NULL, draft_version TEXT,
 CHECK(original_reference_record IS NOT NULL OR original_reference_universe IS NULL),
 CHECK((original_kind='author_decision' AND original_note IS NOT NULL) OR (original_kind!='author_decision' AND original_note IS NULL)),
 CHECK((original_kind='source_anchor' AND original_reference_record IS NOT NULL AND original_verified IS NOT NULL AND original_slot IS NULL) OR (original_kind='event_effect' AND original_reference_record IS NOT NULL AND original_verified IS NULL AND original_slot IS NOT NULL) OR (original_kind NOT IN ('source_anchor','event_effect') AND original_reference_record IS NULL AND original_verified IS NULL AND original_slot IS NULL)),
 CHECK(original_kind='derivation' OR original_evaluator IS NULL),
 CHECK((original_kind='instance_initialization' AND original_source_revision IS NOT NULL) OR (original_kind!='instance_initialization' AND original_source_revision IS NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE assertion_end_basis_version (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('start','definition','chain')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), reference_universe TEXT, reference_record TEXT NOT NULL, reference_version TEXT NOT NULL,
 CHECK(list_kind='chain' OR ordinal=0),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES assertion_end_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) => {'ordinal', 'basis_verified', 'original_verified'}.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named assertion_end fields, separate from canon.
final class AssertionEndFormRecoveryStore {
  AssertionEndFormRecoveryStore._(this._db);
  final Database _db;

  static AssertionEndFormRecoveryStore open(String path) {
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
            'ALTER TABLE assertion_end_form RENAME TO legacy_assertion_end_form',
          );
          db.execute(_schema);
          final store = AssertionEndFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_assertion_end_form',
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
            final form = UnfinishedAssertionEndForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedAssertionEndForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_assertion_end_form');
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
      return AssertionEndFormRecoveryStore._(db);
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
        columns('assertion_end_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 2 &&
        columns('assertion_end_form') == '$_keys,$_fields' &&
        columns('assertion_end_basis_version') ==
            '$_keys,list_kind,ordinal,reference_universe,reference_record,reference_version';
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
      throw const FormatException('Choose the assertion end context.');
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

  SavedAssertionEndForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM assertion_end_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    List<VersionRef> versions(String kind) {
      final rows = _db.select(
        'SELECT ordinal,${_textProjection('reference_universe,reference_record,reference_version')} FROM assertion_end_basis_version WHERE $_where AND list_kind=? ORDER BY ordinal',
        [...binding, kind],
      );
      for (var i = 0; i < rows.length; i++) {
        if (rows[i]['ordinal'] != i) {
          throw const FormatException('Incomplete basis version order');
        }
      }
      return rows
          .map(
            (v) => VersionRef(
              universe: v['reference_universe'] == null
                  ? null
                  : UniverseId.parse(_text(v, 'reference_universe')),
              record: RecordId.parse(_text(v, 'reference_record')),
              version: RecordVersionId.parse(_text(v, 'reference_version')),
            ),
          )
          .toList();
    }

    RecordRef ref() => RecordRef(
      record: RecordId.parse(_text(r, 'original_reference_record')),
      universe: r['original_reference_universe'] == null
          ? null
          : UniverseId.parse(_text(r, 'original_reference_universe')),
    );
    final original = switch (_text(r, 'original_kind')) {
      'author_decision' => AuthorDecisionBasis(_text(r, 'original_note')),
      'source_anchor' => SourceAnchorBasis(ref(), r['original_verified'] == 1),
      'event_effect' => EventEffectBasis(ref(), _text(r, 'original_slot')),
      'instance_initialization' => InstanceInitializationBasis(
        versions('start').single,
        versions('definition').single,
        RevisionId.parse(_text(r, 'original_source_revision')),
      ),
      'imported_claim' => const ImportedClaimBasis(),
      'derivation' => DerivationBasis(
        versions('chain'),
        r['original_evaluator'] == null ? null : _text(r, 'original_evaluator'),
      ),
      _ => throw const FormatException('Unknown original evidence basis'),
    };
    return SavedAssertionEndForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedAssertionEndForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        target: ExpressionReferenceInput(
          record: _text(r, 'target_record'),
          universe: _text(r, 'target_universe'),
        ),
        expectedRecordVersion: RecordVersionId.parse(
          _text(r, 'expected_record_version'),
        ),
        calendar: CalendarId.parse(_text(r, 'calendar')),
        coordinate: _text(r, 'coordinate'),
        originalBasis: original,
        basis: EvidenceBasisInput(
          kind: _text(r, 'basis_kind'),
          note: _text(r, 'basis_note'),
          anchorRecord: _text(r, 'basis_anchor_record'),
          anchorUniverse: _text(r, 'basis_anchor_universe'),
          verified: r['basis_verified'] == 1,
        ),
        rationale: _text(r, 'rationale'),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedAssertionEndForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        b = f.basis,
        o = f.originalBasis;
    final (kind, note, ref, verified, slot, evaluator, revision) = switch (o) {
      AuthorDecisionBasis(:final note) => (
        'author_decision',
        note,
        null,
        null,
        null,
        null,
        null,
      ),
      SourceAnchorBasis(:final anchor, :final verified) => (
        'source_anchor',
        null,
        anchor,
        verified ? 1 : 0,
        null,
        null,
        null,
      ),
      EventEffectBasis(:final event, :final slot) => (
        'event_effect',
        null,
        event,
        null,
        slot,
        null,
        null,
      ),
      InstanceInitializationBasis(:final sourceRevision) => (
        'instance_initialization',
        null,
        null,
        null,
        null,
        null,
        sourceRevision.value,
      ),
      ImportedClaimBasis() => (
        'imported_claim',
        null,
        null,
        null,
        null,
        null,
        null,
      ),
      DerivationBasis(:final evaluator) => (
        'derivation',
        null,
        null,
        null,
        null,
        evaluator,
        null,
      ),
    };
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO assertion_end_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.target.record,
        f.target.universe,
        f.expectedRecordVersion.value,
        f.calendar.value,
        f.coordinate,
        b.kind,
        b.note,
        b.anchorRecord,
        b.anchorUniverse,
        b.verified ? 1 : 0,
        kind,
        note,
        ref?.record.value,
        ref?.universe?.value,
        verified,
        slot,
        evaluator,
        revision,
        f.rationale,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute(
      'DELETE FROM assertion_end_basis_version WHERE $_where',
      binding,
    );
    final lists = switch (o) {
      InstanceInitializationBasis(:final start, :final definition) => {
        'start': [start],
        'definition': [definition],
      },
      DerivationBasis(:final chain) => {'chain': chain},
      _ => <String, List<VersionRef>>{},
    };
    for (final list in lists.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final v = list.value[i];
        _db.execute(
          'INSERT INTO assertion_end_basis_version VALUES(?,?,?,?,?,?,?,?,?,?,?)',
          [
            ...binding,
            list.key,
            i,
            v.universe?.value,
            v.record.value,
            v.version.value,
          ],
        );
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedAssertionEndForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Assertion end form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedAssertionEndForm? load(EditorFormScope scope) {
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

  SavedAssertionEndForm save(
    EditorFormScope scope,
    UnfinishedAssertionEndForm form,
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
      final saved = SavedAssertionEndForm(
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
