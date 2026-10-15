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
const _v1Columns = '$_keys,generation,base_revision,draft_version,value_input';
const _v2Columns = '$_v1Columns,evidence_input';
const _v3Columns = '$_v2Columns,creation_input';
const _v4Columns = '$_v3Columns,roles_input';
const _fields =
    'generation,base_revision,draft_version,value_root,roles_present,creation_operation,creation_property_record,creation_property_universe,creation_subject_record,creation_subject_version,creation_subject_universe,creation_relationship';
const _evidenceFields =
    'attribute_mode,polarity,precision,persistence,validity,temporal,basis_kind,basis_note,basis_anchor_record,basis_anchor_universe,basis_verified,scope_applicability,scope_context_record,scope_context_universe,scope_has_realm,scope_realm_record,scope_realm_universe,alternatives_present';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
final _domains = RecoveryDomainSchema(['Validity']);
final _schema =
    """
CREATE TABLE attribute_form (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,base_revision TEXT NOT NULL,draft_version TEXT NOT NULL,
 value_root INTEGER NOT NULL REFERENCES attribute_qualifier(id),roles_present INTEGER NOT NULL CHECK(roles_present IN (0,1)),creation_operation TEXT,creation_property_record TEXT,creation_property_universe TEXT,creation_subject_record TEXT,creation_subject_version TEXT,creation_subject_universe TEXT,creation_relationship INTEGER CHECK(creation_relationship IN (0,1)),
 CHECK((creation_operation IS NULL AND creation_property_record IS NULL AND creation_property_universe IS NULL AND creation_subject_record IS NULL AND creation_subject_version IS NULL AND creation_subject_universe IS NULL AND creation_relationship IS NULL) OR (creation_operation IS NOT NULL AND creation_property_record IS NOT NULL AND creation_property_universe IS NOT NULL AND creation_subject_record IS NOT NULL AND creation_subject_version IS NOT NULL AND creation_relationship IS NOT NULL)),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE attribute_evidence (
 instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,
 attribute_mode TEXT,polarity TEXT,precision TEXT,persistence TEXT,validity INTEGER REFERENCES "${BodyCatalog.instance.model('Validity').table}"(__row_id),temporal INTEGER REFERENCES attribute_temporal(id),basis_kind TEXT,basis_note TEXT,basis_anchor_record TEXT,basis_anchor_universe TEXT,basis_verified INTEGER CHECK(basis_verified IN (0,1)),scope_applicability TEXT,scope_context_record TEXT,scope_context_universe TEXT,scope_has_realm INTEGER CHECK(scope_has_realm IN (0,1)),scope_realm_record TEXT,scope_realm_universe TEXT,alternatives_present INTEGER NOT NULL CHECK(alternatives_present IN (0,1)),
 CHECK((basis_kind IS NULL AND basis_note IS NULL AND basis_anchor_record IS NULL AND basis_anchor_universe IS NULL AND basis_verified IS NULL) OR (basis_kind IS NOT NULL AND basis_note IS NOT NULL AND basis_anchor_record IS NOT NULL AND basis_anchor_universe IS NOT NULL AND basis_verified IS NOT NULL)),
 CHECK((scope_applicability IS NULL AND scope_context_record IS NULL AND scope_context_universe IS NULL AND scope_has_realm IS NULL AND scope_realm_record IS NULL AND scope_realm_universe IS NULL) OR (scope_applicability IS NOT NULL AND scope_context_record IS NOT NULL AND scope_context_universe IS NOT NULL AND scope_has_realm IS NOT NULL AND scope_realm_record IS NOT NULL AND scope_realm_universe IS NOT NULL)),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES attribute_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE attribute_world (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES attribute_evidence(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE attribute_alternative (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_root INTEGER NOT NULL REFERENCES attribute_qualifier(id),PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES attribute_evidence(instance,profile,universe,continuity,context,editor_key)) STRICT;
CREATE TABLE attribute_role (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,ordinal INTEGER NOT NULL CHECK(ordinal>=0),role_input TEXT NOT NULL,record_input TEXT NOT NULL,universe_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES attribute_form(instance,profile,universe,continuity,context,editor_key)) STRICT;
${RecoveryValueInputs.schema('attribute')}
${_domains.statements.join('\n')}
PRAGMA user_version=5;
""";
String _projection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'value_root',
            'input_root',
            'roles_present',
            'creation_relationship',
            'validity',
            'temporal',
            'basis_verified',
            'scope_has_realm',
            'alternatives_present',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private incomplete attribute value input, separate from canon.
final class AttributeFormRecoveryStore {
  AttributeFormRecoveryStore._(this._db);
  final Database _db;
  late final _inputs = RecoveryValueInputs(_db, 'attribute');

  static AttributeFormRecoveryStore open(String path) {
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
        } else if (version < 5) {
          if (version == 1) {
            db.execute(
              'ALTER TABLE attribute_form ADD COLUMN evidence_input TEXT',
            );
          }
          if (version < 3) {
            db.execute(
              'ALTER TABLE attribute_form ADD COLUMN creation_input TEXT',
            );
          }
          if (version < 4) {
            db.execute(
              'ALTER TABLE attribute_form ADD COLUMN roles_input TEXT',
            );
          }
          db.execute(
            'ALTER TABLE attribute_form RENAME TO legacy_attribute_form',
          );
          db.execute(_schema);
          final store = AttributeFormRecoveryStore._(db);
          for (final r in db.select(
            'SELECT ${_projection(_v4Columns)} FROM legacy_attribute_form',
          )) {
            final scope = EditorFormScope(
              instance: OperationId.parse(_text(r, 'instance')),
              profile: ProfileId.parse(_text(r, 'profile')),
              universe: UniverseId.parse(_text(r, 'universe')),
              continuity: ContinuityId.parse(_text(r, 'continuity')),
              representedContext: RecordId.parse(_text(r, 'context')),
              attributeClientRef: _text(r, 'editor_key'),
            );
            final form = UnfinishedAttributeForm(
              baseRevision: RevisionId.parse(_text(r, 'base_revision')),
              representedContext: scope.representedContext!,
              clientRef: scope.attributeClientRef!,
              draftVersion: BigInt.parse(_text(r, 'draft_version')),
              value: QualifierInput.fromWire(
                CanonicalValue.parseWireJson(_text(r, 'value_input')),
              ),
              evidenceInput: r['evidence_input'] == null
                  ? null
                  : AttributeEvidenceInput.fromWire(
                      CanonicalValue.parseWireJson(_text(r, 'evidence_input')),
                    ),
              creationInput: r['creation_input'] == null
                  ? null
                  : AttributeCreationInput.fromWire(
                      CanonicalValue.parseWireJson(_text(r, 'creation_input')),
                    ),
              roles: r['roles_input'] == null
                  ? null
                  : (CanonicalValue.parseWireJson(_text(r, 'roles_input'))
                            as CanonicalArray)
                        .items
                        .map(PropositionRoleInput.fromWire),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedAttributeForm(
                generation: BigInt.parse(_text(r, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_attribute_form');
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
      return AttributeFormRecoveryStore._(db);
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
    final legacyColumns = switch (version) {
      1 => _v1Columns,
      2 => _v2Columns,
      3 => _v3Columns,
      4 => _v4Columns,
      _ => null,
    };
    final legacy =
        legacyColumns != null &&
        tables.length == 1 &&
        columns('attribute_form') == legacyColumns;
    final expected = {
      'attribute_form': '$_keys,$_fields',
      'attribute_evidence': '$_keys,$_evidenceFields',
      'attribute_world': '$_keys,ordinal,world_input',
      'attribute_alternative': '$_keys,ordinal,input_root',
      'attribute_role': '$_keys,ordinal,role_input,record_input,universe_input',
      ...RecoveryValueInputs.columns('attribute'),
    };
    final current =
        version == 5 &&
        tables.length == expected.length + _domains.statements.length &&
        expected.entries.every((e) => columns(e.key) == e.value) &&
        _domains.matches(db);
    if (!legacy && !current) {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return version as int;
  }

  List<String> _binding(EditorFormScope scope) {
    if (scope.representedContext == null ||
        scope.attributeClientRef == null ||
        scope.attributeClientRef!.isEmpty ||
        scope.worldClientRef != null ||
        scope.worldRecord != null ||
        scope.typeClientRef != null ||
        scope.entityClientRef != null ||
        scope.entityNameRecord != null ||
        scope.entityClassificationRecord != null ||
        scope.entityOperationIndex != null) {
      throw const FormatException('Choose the attribute edit context.');
    }
    return [
      scope.instance.value,
      scope.profile.value,
      scope.universe.value,
      scope.continuity.value,
      scope.representedContext!.value,
      scope.attributeClientRef!,
    ];
  }

  List<Row> _ordered(String table, String columns, List<String> binding) {
    final rows = _db.select(
      'SELECT ordinal,${_projection(columns)} FROM attribute_$table WHERE $_where ORDER BY ordinal',
      binding,
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete attribute input order');
      }
    }
    return rows;
  }

  AttributeEvidenceInput _readEvidence(Row r, List<String> binding) {
    final codec = RelationalCodec(_db);
    CanonicalString scalar(String key) => CanonicalString(_text(r, key));
    return AttributeEvidenceInput(
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
                .map((a) => _inputs.readQualifier(a['input_root'] as int, 0))
                .toList(),
    );
  }

  SavedAttributeForm? _read(EditorFormScope scope) {
    final binding = _binding(scope),
        rows = _db.select(
          'SELECT ${_projection(_fields)} FROM attribute_form WHERE $_where',
          _binding(scope),
        );
    if (rows.isEmpty) return null;
    final r = rows.single;
    final evidence = _db.select(
      'SELECT ${_projection(_evidenceFields)} FROM attribute_evidence WHERE $_where',
      binding,
    );
    return SavedAttributeForm(
      generation: BigInt.parse(_text(r, 'generation')),
      form: UnfinishedAttributeForm(
        baseRevision: RevisionId.parse(_text(r, 'base_revision')),
        representedContext: scope.representedContext!,
        clientRef: scope.attributeClientRef!,
        draftVersion: BigInt.parse(_text(r, 'draft_version')),
        value: _inputs.readQualifier(r['value_root'] as int, 0),
        evidenceInput: evidence.isEmpty
            ? null
            : _readEvidence(evidence.single, binding),
        roles: r['roles_present'] == 0
            ? null
            : _ordered(
                'role',
                'role_input,record_input,universe_input',
                binding,
              ).map(
                (role) => PropositionRoleInput(
                  role: _text(role, 'role_input'),
                  record: _text(role, 'record_input'),
                  universe: _text(role, 'universe_input'),
                ),
              ),
        creationInput: r['creation_operation'] == null
            ? null
            : AttributeCreationInput(
                operationRef: _text(r, 'creation_operation'),
                propertyRecord: _text(r, 'creation_property_record'),
                propertyUniverse: _text(r, 'creation_property_universe'),
                relationship: r['creation_relationship'] == 1,
                subject: VersionRef(
                  record: RecordId.parse(_text(r, 'creation_subject_record')),
                  version: RecordVersionId.parse(
                    _text(r, 'creation_subject_version'),
                  ),
                  universe: r['creation_subject_universe'] == null
                      ? null
                      : UniverseId.parse(_text(r, 'creation_subject_universe')),
                ),
              ),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedAttributeForm saved) {
    final binding = _binding(scope),
        f = saved.form,
        e = f.evidenceInput,
        c = f.creationInput,
        codec = RelationalCodec(_db);
    final old = _db.select(
          'SELECT value_root FROM attribute_form WHERE $_where',
          binding,
        ),
        oldEvidence = _db.select(
          'SELECT validity,temporal FROM attribute_evidence WHERE $_where',
          binding,
        ),
        oldAlternatives = _db.select(
          'SELECT input_root FROM attribute_alternative WHERE $_where',
          binding,
        );
    final value = _inputs.writeQualifier(f.value, 0),
        columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO attribute_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.draftVersion.toString(),
        value,
        f.roles == null ? 0 : 1,
        c?.operationRef,
        c?.propertyRecord,
        c?.propertyUniverse,
        c?.subject.record.value,
        c?.subject.version.value,
        c?.subject.universe?.value,
        c == null
            ? null
            : c.relationship
            ? 1
            : 0,
      ],
    );
    for (final table in ['world', 'alternative', 'role', 'evidence']) {
      _db.execute('DELETE FROM attribute_$table WHERE $_where', binding);
    }
    if (e != null) {
      final b = e.basis,
          s = e.scope,
          validity = e.validity == null
              ? null
              : codec.put('Validity', e.validity!.toWire()),
          temporal = e.temporalValidity == null
              ? null
              : _inputs.writeTemporal(e.temporalValidity!, 0);
      _db.execute(
        'INSERT INTO attribute_evidence VALUES(${List.filled(6 + _evidenceFields.split(',').length, '?').join(',')})',
        [
          ...binding,
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
        ],
      );
      final worlds = s?.worlds ?? <String>[];
      for (var i = 0; i < worlds.length; i++) {
        _db.execute('INSERT INTO attribute_world VALUES(?,?,?,?,?,?,?,?)', [
          ...binding,
          i,
          worlds[i],
        ]);
      }
      final alternatives = e.alternatives ?? <QualifierInput>[];
      for (var i = 0; i < alternatives.length; i++) {
        final root = _inputs.writeQualifier(alternatives[i], 0);
        _db.execute(
          'INSERT INTO attribute_alternative VALUES(?,?,?,?,?,?,?,?)',
          [...binding, i, root],
        );
      }
    }
    final roles = f.roles ?? <PropositionRoleInput>[];
    for (var i = 0; i < roles.length; i++) {
      final r = roles[i];
      _db.execute('INSERT INTO attribute_role VALUES(?,?,?,?,?,?,?,?,?,?)', [
        ...binding,
        i,
        r.role,
        r.record,
        r.universe,
      ]);
    }
    for (final a in oldAlternatives) {
      _inputs.deleteQualifier(a['input_root'] as int);
    }
    for (final e in oldEvidence) {
      _domains.deleteOwned(_db, 'Validity', e['validity']);
      if (e['temporal'] case final int t) _inputs.deleteTemporal(t);
    }
    if (old.isNotEmpty) {
      _inputs.deleteQualifier(old.single['value_root'] as int);
    }
  }

  SavedAttributeForm? load(EditorFormScope scope) {
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

  void _validate(EditorFormScope scope, UnfinishedAttributeForm form) {
    if (scope.representedContext != form.representedContext ||
        scope.attributeClientRef != form.clientRef) {
      throw const FormatException('Attribute form context does not match.');
    }
    for (final text in [
      form.clientRef,
      ...form.value.exactTexts,
      if (form.roles != null)
        for (final role in form.roles!) ...role.exactTexts,
      if (form.creationInput case final creation?) ...[
        creation.operationRef,
        creation.propertyRecord,
        creation.propertyUniverse,
      ],
      if (form.evidenceInput != null) ...form.evidenceInput!.exactTexts,
    ]) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedAttributeForm save(
    EditorFormScope scope,
    UnfinishedAttributeForm form,
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
      final saved = SavedAttributeForm(
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
