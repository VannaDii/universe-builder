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
const _fields =
    'generation,base_revision,client_ref,target_record,target_universe,expected_record_version,original,proposition_record,proposition_universe,attribute_mode,polarity,precision,persistence,validity,temporal,basis_kind,basis_note,basis_anchor_record,basis_anchor_universe,basis_verified,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,alternatives_present,rationale,draft_version';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _originalModel = recoveryPayloadModel('assertion');
final _domainStorage = RecoveryDomainSchema([_originalModel, 'Validity']);
final _schema =
    """
CREATE TABLE assertion_correction_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, target_record TEXT NOT NULL, target_universe TEXT NOT NULL, expected_record_version TEXT NOT NULL,
 original INTEGER NOT NULL REFERENCES "${BodyCatalog.instance.model(_originalModel).table}"(__row_id), proposition_record TEXT NOT NULL, proposition_universe TEXT NOT NULL,
 attribute_mode TEXT, polarity TEXT, precision TEXT, persistence TEXT, validity INTEGER REFERENCES "${BodyCatalog.instance.model('Validity').table}"(__row_id), temporal INTEGER REFERENCES correction_temporal(id),
 basis_kind TEXT, basis_note TEXT, basis_anchor_record TEXT, basis_anchor_universe TEXT, basis_verified INTEGER CHECK(basis_verified IN (0,1)),
 scope_applicability TEXT, scope_context_record TEXT, scope_context_universe TEXT, scope_has_realm INTEGER CHECK(scope_has_realm IN (0,1)), scope_realm_record TEXT, scope_realm_universe TEXT,
 alternatives_present INTEGER NOT NULL CHECK(alternatives_present IN (0,1)), rationale TEXT NOT NULL, draft_version TEXT,
 CHECK((basis_kind IS NULL AND basis_note IS NULL AND basis_anchor_record IS NULL AND basis_anchor_universe IS NULL AND basis_verified IS NULL) OR (basis_kind IS NOT NULL AND basis_note IS NOT NULL AND basis_anchor_record IS NOT NULL AND basis_anchor_universe IS NOT NULL AND basis_verified IS NOT NULL)),
 CHECK((scope_applicability IS NULL AND scope_context_record IS NULL AND scope_context_universe IS NULL AND scope_has_realm IS NULL AND scope_realm_record IS NULL AND scope_realm_universe IS NULL) OR (scope_applicability IS NOT NULL AND scope_context_record IS NOT NULL AND scope_context_universe IS NOT NULL AND scope_has_realm IS NOT NULL AND scope_realm_record IS NOT NULL AND scope_realm_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE assertion_correction_world (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), world_input TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES assertion_correction_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE assertion_correction_alternative (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), input_root INTEGER NOT NULL REFERENCES correction_qualifier(id),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES assertion_correction_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
${RecoveryValueInputs.schema('correction')}
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
            'validity',
            'temporal',
            'basis_verified',
            'scope_has_realm',
            'alternatives_present',
            'input_root',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named assertion_correction fields, separate from canon.
final class AssertionCorrectionFormRecoveryStore {
  AssertionCorrectionFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'correction');

  static AssertionCorrectionFormRecoveryStore open(String path) {
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
      return AssertionCorrectionFormRecoveryStore._(db);
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
      'assertion_correction_form': '$_keys,$_fields',
      'assertion_correction_world': '$_keys,ordinal,world_input',
      'assertion_correction_alternative': '$_keys,ordinal,input_root',
      ...RecoveryValueInputs.columns('correction'),
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
      throw const FormatException('Choose the assertion correction context.');
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

  List<Row> _ordered(String table, String columns, List<String> binding) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection(columns)} FROM assertion_correction_$table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete correction input order');
      }
    }
    return rows;
  }

  SavedAssertionCorrectionForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM assertion_correction_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final r = rows.single, codec = RelationalCodec(_db);
    CanonicalString scalar(String key) => CanonicalString(_text(r, key));
    return SavedAssertionCorrectionForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedAssertionCorrectionForm(
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
        original: AssertionRecord.fromWire(
          codec.get(_originalModel, r['original']),
        ),
        proposition: ExpressionReferenceInput(
          record: _text(r, 'proposition_record'),
          universe: _text(r, 'proposition_universe'),
        ),
        evidence: AttributeEvidenceInput(
          attributeMode: r['attribute_mode'] == null
              ? null
              : AttributeMode.fromWire(scalar('attribute_mode')),
          polarity: r['polarity'] == null
              ? null
              : Polarity.fromWire(scalar('polarity')),
          precision: r['precision'] == null
              ? null
              : Precision.fromWire(scalar('precision')),
          persistence: r['persistence'] == null
              ? null
              : PersistenceSemantics.fromWire(scalar('persistence')),
          validity: r['validity'] == null
              ? null
              : Validity.fromWire(codec.get('Validity', r['validity'])),
          temporalValidity: r['temporal'] == null
              ? null
              : _inputs.readTemporal(r['temporal'] as int, 0),
          basis: r['basis_kind'] == null
              ? null
              : EvidenceBasisInput(
                  kind: _text(r, 'basis_kind'),
                  note: _text(r, 'basis_note'),
                  anchorRecord: _text(r, 'basis_anchor_record'),
                  anchorUniverse: _text(r, 'basis_anchor_universe'),
                  verified: r['basis_verified'] == 1,
                ),
          scope: r['scope_applicability'] == null
              ? null
              : ScopeInput(
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
          alternatives: r['alternatives_present'] == 0
              ? null
              : _ordered('alternative', 'input_root', binding)
                    .map(
                      (a) => _inputs.readQualifier(a['input_root'] as int, 0),
                    )
                    .toList(),
        ),
        rationale: _text(r, 'rationale'),
        draftVersion: r['draft_version'] == null
            ? null
            : BigInt.parse(_text(r, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedAssertionCorrectionForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        e = f.evidence,
        b = e.basis,
        s = e.scope,
        codec = RelationalCodec(_db);
    final old = _db.select(
      'SELECT original,validity,temporal FROM assertion_correction_form WHERE $_where',
      binding,
    );
    final oldAlternatives = _db.select(
      'SELECT input_root FROM assertion_correction_alternative WHERE $_where',
      binding,
    );
    final original = codec.put(_originalModel, f.original.toWire()),
        validity = e.validity == null
            ? null
            : codec.put('Validity', e.validity!.toWire()),
        temporal = e.temporalValidity == null
            ? null
            : _inputs.writeTemporal(e.temporalValidity!, 0);
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO assertion_correction_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.target.record,
        f.target.universe,
        f.expectedRecordVersion.value,
        original,
        f.proposition.record,
        f.proposition.universe,
        e.attributeMode?.wireName,
        e.polarity?.wireName,
        e.precision?.wireName,
        e.persistence?.wireName,
        validity,
        temporal,
        b?.kind,
        b?.note,
        b?.anchorRecord,
        b?.anchorUniverse,
        b == null
            ? null
            : b.verified
            ? 1
            : 0,
        s?.applicability,
        s?.contextRecord,
        s?.contextUniverse,
        s == null
            ? null
            : s.hasRealm
            ? 1
            : 0,
        s?.realmRecord,
        s?.realmUniverse,
        e.alternatives == null ? 0 : 1,
        f.rationale,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute(
      'DELETE FROM assertion_correction_world WHERE $_where',
      binding,
    );
    _db.execute(
      'DELETE FROM assertion_correction_alternative WHERE $_where',
      binding,
    );
    final worlds = s?.worlds ?? <String>[];
    for (var i = 0; i < worlds.length; i++) {
      _db.execute(
        'INSERT INTO assertion_correction_world VALUES(?,?,?,?,?,?,?,?)',
        [...binding, i, worlds[i]],
      );
    }
    final alternatives = e.alternatives ?? <QualifierInput>[];
    for (var i = 0; i < alternatives.length; i++) {
      final root = _inputs.writeQualifier(alternatives[i], 0);
      _db.execute(
        'INSERT INTO assertion_correction_alternative VALUES(?,?,?,?,?,?,?,?)',
        [...binding, i, root],
      );
    }
    for (final a in oldAlternatives) {
      _inputs.deleteQualifier(a['input_root'] as int);
    }
    if (old.isNotEmpty) {
      _domainStorage.deleteOwned(_db, _originalModel, old.single['original']);
      _domainStorage.deleteOwned(_db, 'Validity', old.single['validity']);
      if (old.single['temporal'] case final int t) _inputs.deleteTemporal(t);
    }
  }

  void _validate(
    EditorFormScope scope,
    UnfinishedAssertionCorrectionForm form,
  ) {
    if (scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException(
        'Assertion correction form context does not match.',
      );
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedAssertionCorrectionForm? load(EditorFormScope scope) {
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

  SavedAssertionCorrectionForm save(
    EditorFormScope scope,
    UnfinishedAssertionCorrectionForm form,
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
      final saved = SavedAssertionCorrectionForm(
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
