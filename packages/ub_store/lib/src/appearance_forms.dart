import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _fields =
    'generation,base_revision,client_ref,target_kind,target_entry,target_owner,label,physical_description,atmosphere,validity_kind,calendar,start,end,start_unbounded,end_unbounded,rationale,target_record,target_universe,expected_record_version,original,draft_version';
const _imageFields =
    'ordinal,asset_record,asset_universe,caption,purpose,preview,staged_ref,digest,media_type,byte_size,width,height,original_name';
const _linkFields = 'ordinal,entry_record,entry_universe,relationship,note';
const _schema = """
CREATE TABLE appearance_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL,
 target_kind TEXT NOT NULL, target_entry TEXT NOT NULL, target_owner TEXT NOT NULL,
 label TEXT NOT NULL, physical_description TEXT NOT NULL, atmosphere TEXT NOT NULL,
 validity_kind TEXT NOT NULL, calendar TEXT NOT NULL, start TEXT NOT NULL, end TEXT NOT NULL,
 start_unbounded INTEGER NOT NULL CHECK(start_unbounded IN (0,1)), end_unbounded INTEGER NOT NULL CHECK(end_unbounded IN (0,1)),
 rationale TEXT NOT NULL, target_record TEXT, target_universe TEXT, expected_record_version TEXT, original TEXT, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE appearance_image (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), asset_record TEXT NOT NULL, asset_universe TEXT NOT NULL,
 caption TEXT NOT NULL, purpose TEXT NOT NULL, preview TEXT NOT NULL,
 staged_ref TEXT, digest TEXT, media_type TEXT, byte_size TEXT, width INTEGER, height INTEGER, original_name TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES appearance_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE appearance_link (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 ordinal INTEGER NOT NULL CHECK(ordinal>=0), entry_record TEXT NOT NULL, entry_universe TEXT NOT NULL, relationship TEXT NOT NULL, note TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,ordinal),
 FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES appearance_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=1;
""";

/// Device-private named fields and ordered references. Only the retained original
/// is a canonical domain record; incomplete form state is never a JSON blob.
final class AppearanceFormRecoveryStore {
  AppearanceFormRecoveryStore._(this._db);
  final Database _db;
  static AppearanceFormRecoveryStore open(String path) {
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
      return AppearanceFormRecoveryStore._(db);
    } on EditorRecoveryException {
      db?.close();
      rethrow;
    } on Object {
      db?.close();
      throw const EditorRecoveryException(EditorRecoveryFailure.unavailable);
    }
  }

  static int _checkSchema(Database db) {
    final names = db
        .select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
        )
        .map((row) => row['name'])
        .toSet();
    if (names.isEmpty) return 0;
    final version = db.select('PRAGMA user_version').single.values.single;
    if (version != 1 ||
        names.length != 3 ||
        !names.containsAll([
          'appearance_form',
          'appearance_image',
          'appearance_link',
        ]) ||
        db
                .select('PRAGMA table_info(appearance_form)')
                .map((row) => row['name'])
                .join(',') !=
            '$_keys,$_fields' ||
        db
                .select('PRAGMA table_info(appearance_image)')
                .map((row) => row['name'])
                .join(',') !=
            '$_keys,$_imageFields' ||
        db
                .select('PRAGMA table_info(appearance_link)')
                .map((row) => row['name'])
                .join(',') !=
            '$_keys,$_linkFields') {
      throw const EditorRecoveryException(
        EditorRecoveryFailure.incompatibleSchema,
      );
    }
    return 1;
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
      throw const FormatException('Choose the appearance context.');
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

  SavedAppearanceForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT * FROM appearance_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final images = _db
        .select(
          'SELECT * FROM appearance_image WHERE $_where ORDER BY ordinal',
          binding,
        )
        .map(
          (child) => AppearanceImageInput(
            asset: ExpressionReferenceInput(
              record: child['asset_record'] as String,
              universe: child['asset_universe'] as String,
            ),
            caption: child['caption'] as String,
            purpose: child['purpose'] as String,
            preview: child['preview'] as String,
            stagedOperation: child['staged_ref'] == null
                ? null
                : AddImageAssetOperation(
                    clientRef: child['staged_ref'] as String,
                    record: ImageAssetRecord(
                      contentDigest: child['digest'] as String,
                      mediaType: child['media_type'] as String,
                      byteSize: BigInt.parse(child['byte_size'] as String),
                      width: child['width'] as int,
                      height: child['height'] as int,
                      originalName: child['original_name'] as String,
                    ),
                  ),
          ),
        );
    final links = _db
        .select(
          'SELECT * FROM appearance_link WHERE $_where ORDER BY ordinal',
          binding,
        )
        .map(
          (child) => AppearanceLinkInput(
            entry: ExpressionReferenceInput(
              record: child['entry_record'] as String,
              universe: child['entry_universe'] as String,
            ),
            relationship: child['relationship'] as String,
            note: child['note'] as String,
          ),
        );
    return SavedAppearanceForm(
      generation: BigInt.parse(row['generation'] as String),
      form: UnfinishedAppearanceForm(
        baseRevision: RevisionId.parse(row['base_revision'] as String),
        representedContext: scope.representedContext!,
        clientRef: row['client_ref'] as String,
        targetKind: row['target_kind'] as String,
        target: ExpressionReferenceInput(
          record: row['target_entry'] as String,
          universe: row['target_owner'] as String,
        ),
        label: row['label'] as String,
        physicalDescription: row['physical_description'] as String,
        atmosphere: row['atmosphere'] as String,
        images: images,
        links: links,
        validityKind: row['validity_kind'] as String,
        calendar: row['calendar'] as String,
        start: row['start'] as String,
        end: row['end'] as String,
        startUnbounded: row['start_unbounded'] == 1,
        endUnbounded: row['end_unbounded'] == 1,
        rationale: row['rationale'] as String,
        revisionTarget: row['target_record'] == null
            ? null
            : ExpressionReferenceInput(
                record: row['target_record'] as String,
                universe: row['target_universe'] as String,
              ),
        expectedRecordVersion: row['expected_record_version'] == null
            ? null
            : RecordVersionId.parse(row['expected_record_version'] as String),
        original: row['original'] == null
            ? null
            : AppearanceRecord.fromWire(
                CanonicalValue.parseWireJson(row['original'] as String),
              ),
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(row['draft_version'] as String),
      ),
    );
  }

  SavedAppearanceForm? load(EditorFormScope scope) {
    _db.execute('BEGIN');
    try {
      final form = _read(scope);
      _db.execute('COMMIT');
      return form;
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  SavedAppearanceForm save(
    EditorFormScope scope,
    UnfinishedAppearanceForm form,
    BigInt expectedGeneration,
  ) {
    final binding = _binding(scope);
    if (expectedGeneration < BigInt.zero ||
        expectedGeneration >= (BigInt.one << 64)) {
      throw const FormatException('Invalid expected editor generation');
    }
    if (form.representedContext != scope.representedContext ||
        scope.typeClientRef != null &&
            scope.typeClientRef != form.recoveryKey) {
      throw const FormatException(
        'Story appearance form scope does not match.',
      );
    }
    void exact(CanonicalValue value) {
      switch (value) {
        case CanonicalString(:final value):
          if (decodeExactUtf8(utf8.encode(value)) != value) {
            throw const EditorRecoveryException(
              EditorRecoveryFailure.invalidText,
            );
          }
        case CanonicalArray(:final items):
          for (final child in items) {
            exact(child);
          }
        case CanonicalObject(:final fields):
          for (final field in fields) {
            exact(field.value);
          }
        default:
          break;
      }
    }

    exact(form.toWire());
    _db.execute('BEGIN IMMEDIATE');
    try {
      final current = _read(scope), generation = currentGeneration(current);
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
      final next = generation + BigInt.one;
      final values = <Object?>[
        ...binding,
        next.toString(),
        form.baseRevision.value,
        form.clientRef,
        form.targetKind,
        form.target.record,
        form.target.universe,
        form.label,
        form.physicalDescription,
        form.atmosphere,
        form.validityKind,
        form.calendar,
        form.start,
        form.end,
        form.startUnbounded ? 1 : 0,
        form.endUnbounded ? 1 : 0,
        form.rationale,
        form.revisionTarget?.record,
        form.revisionTarget?.universe,
        form.expectedRecordVersion?.value,
        form.original?.toWire().toText(),
        form.draftVersion?.toString(),
      ];
      final columns = '$_keys,$_fields'.split(',');
      _db.execute(
        'INSERT INTO appearance_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((field) => '$field=excluded.$field').join(',')}',
        values,
      );
      _db.execute('DELETE FROM appearance_image WHERE $_where', binding);
      _db.execute('DELETE FROM appearance_link WHERE $_where', binding);
      for (var i = 0; i < form.images.length; i++) {
        final image = form.images[i],
            op = image.stagedOperation,
            asset = op?.record;
        final values = <Object?>[
          ...binding,
          i,
          image.asset.record,
          image.asset.universe,
          image.caption,
          image.purpose,
          image.preview,
          op?.clientRef,
          asset?.contentDigest,
          asset?.mediaType,
          asset?.byteSize.toString(),
          asset?.width,
          asset?.height,
          asset?.originalName,
        ];
        _db.execute(
          'INSERT INTO appearance_image VALUES(${List.filled(values.length, '?').join(',')})',
          values,
        );
      }
      for (var i = 0; i < form.links.length; i++) {
        final link = form.links[i];
        _db.execute(
          'INSERT INTO appearance_link VALUES(?,?,?,?,?,?,?,?,?,?,?)',
          [
            ...binding,
            i,
            link.entry.record,
            link.entry.universe,
            link.relationship,
            link.note,
          ],
        );
      }
      _db.execute('COMMIT');
      return SavedAppearanceForm(generation: next, form: form);
    } catch (_) {
      if (!_db.autocommit) _db.execute('ROLLBACK');
      rethrow;
    }
  }

  BigInt currentGeneration(SavedAppearanceForm? current) =>
      current?.generation ?? BigInt.zero;
  void close() => _db.close();
}
