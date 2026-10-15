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
    'generation,base_revision,client_ref,holder_record,holder_universe,proposition_record,proposition_universe,attitude_input,certainty_enabled,certainty_input,validity_root,basis_kind,basis_note,basis_anchor_record,basis_anchor_universe,basis_verified,acquisition_enabled,truth_record,truth_universe,acquisition_root,world_enabled,world_record,world_universe,acquisition_basis,communication_record,communication_universe,interpretation_enabled,interpretation_record,interpretation_universe,target_record,target_universe,expected_record_version,rationale,original,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel(
  RecordKind.epistemicAttitude.wireName,
);
final _domainStorage = RecoveryDomainSchema([_originalModel]);
final _schema =
    """
CREATE TABLE attitude_form (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,holder_record TEXT NOT NULL,holder_universe TEXT NOT NULL,proposition_record TEXT NOT NULL,proposition_universe TEXT NOT NULL,attitude_input TEXT NOT NULL,certainty_enabled INTEGER NOT NULL CHECK(certainty_enabled IN (0,1)),certainty_input TEXT NOT NULL,validity_root INTEGER NOT NULL REFERENCES attitude_temporal(id),basis_kind TEXT NOT NULL,basis_note TEXT NOT NULL,basis_anchor_record TEXT NOT NULL,basis_anchor_universe TEXT NOT NULL,basis_verified INTEGER NOT NULL CHECK(basis_verified IN (0,1)),acquisition_enabled INTEGER NOT NULL CHECK(acquisition_enabled IN (0,1)),truth_record TEXT NOT NULL,truth_universe TEXT NOT NULL,acquisition_root INTEGER NOT NULL REFERENCES attitude_temporal(id),world_enabled INTEGER NOT NULL CHECK(world_enabled IN (0,1)),world_record TEXT NOT NULL,world_universe TEXT NOT NULL,acquisition_basis TEXT NOT NULL,communication_record TEXT NOT NULL,communication_universe TEXT NOT NULL,interpretation_enabled INTEGER NOT NULL CHECK(interpretation_enabled IN (0,1)),interpretation_record TEXT NOT NULL,interpretation_universe TEXT NOT NULL,target_record TEXT,target_universe TEXT,expected_record_version TEXT,rationale TEXT NOT NULL,original INTEGER REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id),draft_version TEXT,CHECK((target_record IS NULL AND target_universe IS NULL) OR (target_record IS NOT NULL AND target_universe IS NOT NULL)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('attitude')}
${_domainStorage.statements.join('\n')}
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'acquisition_enabled',
            'acquisition_root',
            'basis_verified',
            'certainty_enabled',
            'expression_root',
            'interpretation_enabled',
            'ordinal',
            'original',
            'validity_root',
            'world_enabled',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named attitude fields, separate from canon.
final class AttitudeFormRecoveryStore {
  AttitudeFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'attitude');

  static AttitudeFormRecoveryStore open(String path) {
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
            'ALTER TABLE attitude_form RENAME TO legacy_attitude_form',
          );
          db.execute(_schema);
          final store = AttitudeFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_attitude_form',
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
            final form = UnfinishedAttitudeForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedAttitudeForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_attitude_form');
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
      return AttitudeFormRecoveryStore._(db);
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
        columns('attitude_form') == _legacyColumns;
    final expected = {
      'attitude_form': '$_keys,$_fields',
      ...RecoveryValueInputs.columns('attitude'),
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
      throw const FormatException('Choose the attitude context.');
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
  SavedAttitudeForm? _read(EditorFormScope scope) {
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM attitude_form WHERE $_where',
      _binding(scope),
    );
    if (rows.isEmpty) return null;
    final r = rows.single;
    return SavedAttitudeForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedAttitudeForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: _text(r, 'client_ref'),
        holder: _ref(r, 'holder'),
        proposition: _ref(r, 'proposition'),
        attitude: _text(r, 'attitude_input'),
        certaintyEnabled: r['certainty_enabled'] == 1,
        certainty: _text(r, 'certainty_input'),
        validity: _inputs.readTemporal(r['validity_root'] as int, 0),
        basis: EvidenceBasisInput(
          kind: _text(r, 'basis_kind'),
          note: _text(r, 'basis_note'),
          anchorRecord: _text(r, 'basis_anchor_record'),
          anchorUniverse: _text(r, 'basis_anchor_universe'),
          verified: r['basis_verified'] == 1,
        ),
        acquisition: KnowledgeAcquisitionInput(
          enabled: r['acquisition_enabled'] == 1,
          truthContext: _ref(r, 'truth'),
          time: _inputs.readTemporal(r['acquisition_root'] as int, 0),
          worldEnabled: r['world_enabled'] == 1,
          world: _ref(r, 'world'),
          basis: _text(r, 'acquisition_basis'),
          communication: _ref(r, 'communication'),
          interpretationEnabled: r['interpretation_enabled'] == 1,
          interpretation: _ref(r, 'interpretation'),
        ),
        correctionTarget: r['target_record'] == null ? null : _ref(r, 'target'),
        expectedRecordVersion: r['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(_text(r, 'expected_record_version')),
        rationale: _text(r, 'rationale'),
        original: r['original'] == null
            ? null
            : EpistemicAttitudeRecord.fromWire(
                RelationalCodec(_db).get(_originalModel, r['original']),
              ),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedAttitudeForm saved) {
    final binding = _binding(scope), f = saved.form;
    final old = _db.select(
      'SELECT original,validity_root,acquisition_root FROM attitude_form WHERE $_where',
      binding,
    );
    final validityRoot = _inputs.writeTemporal(f.validity, 0),
        acquisitionRoot = _inputs.writeTemporal(f.acquisition.time, 0),
        original = f.original == null
            ? null
            : RelationalCodec(_db).put(_originalModel, f.original!.toWire());
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO attitude_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.holder.record,
        f.holder.universe,
        f.proposition.record,
        f.proposition.universe,
        f.attitude,
        f.certaintyEnabled ? 1 : 0,
        f.certainty,
        validityRoot,
        f.basis.kind,
        f.basis.note,
        f.basis.anchorRecord,
        f.basis.anchorUniverse,
        f.basis.verified ? 1 : 0,
        f.acquisition.enabled ? 1 : 0,
        f.acquisition.truthContext.record,
        f.acquisition.truthContext.universe,
        acquisitionRoot,
        f.acquisition.worldEnabled ? 1 : 0,
        f.acquisition.world.record,
        f.acquisition.world.universe,
        f.acquisition.basis,
        f.acquisition.communication.record,
        f.acquisition.communication.universe,
        f.acquisition.interpretationEnabled ? 1 : 0,
        f.acquisition.interpretation.record,
        f.acquisition.interpretation.universe,
        f.correctionTarget?.record,
        f.correctionTarget?.universe,
        f.expectedRecordVersion?.value,
        f.rationale,
        original,
        f.draftVersion?.toString(),
      ],
    );
    if (old.isNotEmpty) {
      _inputs.deleteTemporal(old.single['validity_root'] as int);
      _inputs.deleteTemporal(old.single['acquisition_root'] as int);
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
    }
  }

  void _validate(EditorFormScope scope, UnfinishedAttitudeForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException('Attitude form context does not match.');
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedAttitudeForm? load(EditorFormScope scope) {
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

  SavedAttitudeForm save(
    EditorFormScope scope,
    UnfinishedAttitudeForm form,
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
      final saved = SavedAttitudeForm(
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
