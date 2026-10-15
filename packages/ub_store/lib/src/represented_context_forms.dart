import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'ownership.dart';

const _keys = 'instance,profile,universe,continuity,context,editor_key';
const _legacyColumns = '$_keys,generation,form_input';
const _fields =
    'generation,base_revision,client_ref,context_kind,authored_label,reference_record,reference_universe,parent_enabled,parent_record,parent_universe,chronology_enabled,calendar_input,system_input,offset_input,tick_label_input,ticks_enabled,ticks_input,first_interaction_input,current_input,rationale,draft_version';
const _originalFields =
    'own_universe,context_kind,authored_label,reference_record,reference_universe,parent_record,parent_universe,calendar,clock_kind,offset_seconds,tick_label,ticks_per_month,first_interaction,current_coordinate';
const _where =
    'instance=? AND profile=? AND universe=? AND continuity=? AND context=? AND editor_key=?';
const _schema = """
CREATE TABLE represented_context_form (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 generation TEXT NOT NULL, base_revision TEXT NOT NULL, client_ref TEXT NOT NULL, context_kind TEXT NOT NULL, authored_label TEXT NOT NULL,
 reference_record TEXT NOT NULL, reference_universe TEXT NOT NULL, parent_enabled INTEGER NOT NULL CHECK(parent_enabled IN (0,1)), parent_record TEXT NOT NULL, parent_universe TEXT NOT NULL,
 chronology_enabled INTEGER NOT NULL CHECK(chronology_enabled IN (0,1)), calendar_input TEXT NOT NULL, system_input TEXT NOT NULL, offset_input TEXT NOT NULL, tick_label_input TEXT NOT NULL,
 ticks_enabled INTEGER NOT NULL CHECK(ticks_enabled IN (0,1)), ticks_input TEXT NOT NULL, first_interaction_input TEXT NOT NULL, current_input TEXT NOT NULL, rationale TEXT NOT NULL, draft_version TEXT,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE TABLE represented_context_label (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 list_kind TEXT NOT NULL CHECK(list_kind IN ('input','original')), ordinal INTEGER NOT NULL CHECK(ordinal>=0), language TEXT NOT NULL, label_text TEXT NOT NULL,
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key,list_kind,ordinal), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES represented_context_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
CREATE UNIQUE INDEX represented_context_original_language ON represented_context_label(instance,profile,universe,continuity,context,editor_key,language) WHERE list_kind='original';
CREATE TABLE represented_context_original (
 instance TEXT NOT NULL, profile TEXT NOT NULL, universe TEXT NOT NULL, continuity TEXT NOT NULL, context TEXT NOT NULL, editor_key TEXT NOT NULL,
 own_universe TEXT NOT NULL, context_kind TEXT NOT NULL CHECK(context_kind IN ('objective','character','source','narrator','authored')), authored_label TEXT, reference_record TEXT, reference_universe TEXT, parent_record TEXT, parent_universe TEXT,
 calendar TEXT, clock_kind TEXT CHECK(clock_kind IN ('gregorian','fictional')), offset_seconds INTEGER CHECK(offset_seconds BETWEEN -2147483648 AND 2147483647), tick_label TEXT, ticks_per_month INTEGER CHECK(ticks_per_month BETWEEN 0 AND 4294967295), first_interaction TEXT, current_coordinate TEXT,
 CHECK((context_kind='authored' AND authored_label IS NOT NULL AND reference_record IS NULL AND reference_universe IS NULL) OR (context_kind='objective' AND authored_label IS NULL AND reference_record IS NULL AND reference_universe IS NULL) OR (context_kind IN ('character','source','narrator') AND authored_label IS NULL AND reference_record IS NOT NULL)),
 CHECK(parent_record IS NOT NULL OR parent_universe IS NULL),
 CHECK((calendar IS NULL AND clock_kind IS NULL AND offset_seconds IS NULL AND tick_label IS NULL AND ticks_per_month IS NULL AND first_interaction IS NULL AND current_coordinate IS NULL) OR
       (calendar IS NOT NULL AND first_interaction IS NOT NULL AND current_coordinate IS NOT NULL AND ((clock_kind='gregorian' AND offset_seconds IS NOT NULL AND tick_label IS NULL AND ticks_per_month IS NULL) OR (clock_kind='fictional' AND offset_seconds IS NULL AND tick_label IS NOT NULL)))),
 PRIMARY KEY(instance,profile,universe,continuity,context,editor_key), FOREIGN KEY(instance,profile,universe,continuity,context,editor_key) REFERENCES represented_context_form(instance,profile,universe,continuity,context,editor_key)
) STRICT;
PRAGMA user_version=2;
""";
String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'ordinal',
            'parent_enabled',
            'chronology_enabled',
            'ticks_enabled',
            'offset_seconds',
            'ticks_per_month',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);

/// Device-private named represented_context fields, separate from canon.
final class RepresentedContextFormRecoveryStore {
  RepresentedContextFormRecoveryStore._(this._db);
  final Database _db;

  static RepresentedContextFormRecoveryStore open(String path) {
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
            'ALTER TABLE represented_context_form RENAME TO legacy_represented_context_form',
          );
          db.execute(_schema);
          final store = RepresentedContextFormRecoveryStore._(db);
          for (final row in db.select(
            'SELECT ${_textProjection(_legacyColumns)} FROM legacy_represented_context_form',
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
            final form = UnfinishedRepresentedContextForm.fromWire(
              CanonicalValue.parseWireJson(_text(row, 'form_input')),
            );
            store._validate(scope, form);
            store._write(
              scope,
              SavedRepresentedContextForm(
                generation: BigInt.parse(_text(row, 'generation')),
                form: form,
              ),
            );
          }
          db.execute('DROP TABLE legacy_represented_context_form');
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
      return RepresentedContextFormRecoveryStore._(db);
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
        columns('represented_context_form') == _legacyColumns;
    final current =
        version == 2 &&
        tables.length == 3 &&
        columns('represented_context_form') == '$_keys,$_fields' &&
        columns('represented_context_label') ==
            '$_keys,list_kind,ordinal,language,label_text' &&
        columns('represented_context_original') == '$_keys,$_originalFields';
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
      throw const FormatException('Choose the represented context.');
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

  List<PropertyLabelInput> _labels(List<String> binding, String kind) {
    final rows = _db.select(
      'SELECT ordinal,${_textProjection('language,label_text')} FROM represented_context_label WHERE $_where AND list_kind=? ORDER BY ordinal',
      [...binding, kind],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete context label order');
      }
    }
    return rows
        .map(
          (r) => PropertyLabelInput(
            language: _text(r, 'language'),
            text: _text(r, 'label_text'),
          ),
        )
        .toList();
  }

  SavedRepresentedContextForm? _read(EditorFormScope scope) {
    final binding = _binding(scope);
    final rows = _db.select(
      'SELECT ${_textProjection(_fields)} FROM represented_context_form WHERE $_where',
      binding,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;
    final originals = _db.select(
      'SELECT ${_textProjection(_originalFields)} FROM represented_context_original WHERE $_where',
      binding,
    );
    RepresentedContextRecord? original;
    if (originals.isNotEmpty) {
      final o = originals.single;
      RecordRef ref(String prefix) => RecordRef(
        record: RecordId.parse(_text(o, '${prefix}_record')),
        universe: o['${prefix}_universe'] == null
            ? null
            : UniverseId.parse(_text(o, '${prefix}_universe')),
      );
      original = RepresentedContextRecord(
        universe: UniverseId.parse(_text(o, 'own_universe')),
        kind: switch (_text(o, 'context_kind')) {
          'objective' => const ObjectiveContext(),
          'authored' => AuthoredContext(_text(o, 'authored_label')),
          'character' => CharacterContext(ref('reference')),
          'source' => SourceContext(ref('reference')),
          'narrator' => NarratorContext(ref('reference')),
          _ => throw const FormatException('Unknown original context kind'),
        },
        parent: o['parent_record'] == null ? null : ref('parent'),
        chronology: o['calendar'] == null
            ? null
            : Chronology(
                calendar: CalendarId.parse(_text(o, 'calendar')),
                system: switch (_text(o, 'clock_kind')) {
                  'gregorian' => GregorianClock(o['offset_seconds'] as int),
                  'fictional' => FictionalClock(
                    _text(o, 'tick_label'),
                    o['ticks_per_month'] as int?,
                  ),
                  _ => throw const FormatException(
                    'Unknown original clock kind',
                  ),
                },
                firstInteraction: _text(o, 'first_interaction'),
                current: _text(o, 'current_coordinate'),
              ),
        labels: {
          for (final l in _labels(binding, 'original')) l.language: l.text,
        },
      );
    }
    return SavedRepresentedContextForm(
      generation: BigInt.parse(_text(row, 'generation')),
      form: UnfinishedRepresentedContextForm(
        baseRevision: RevisionId.parse(_text(row, 'base_revision')),
        representedContext: scope.representedContext!,
        universe: scope.universe,
        clientRef: _text(row, 'client_ref'),
        kind: _text(row, 'context_kind'),
        authoredLabel: _text(row, 'authored_label'),
        reference: ExpressionReferenceInput(
          record: _text(row, 'reference_record'),
          universe: _text(row, 'reference_universe'),
        ),
        parentEnabled: row['parent_enabled'] == 1,
        parent: ExpressionReferenceInput(
          record: _text(row, 'parent_record'),
          universe: _text(row, 'parent_universe'),
        ),
        chronology: ChronologyInput(
          enabled: row['chronology_enabled'] == 1,
          calendar: _text(row, 'calendar_input'),
          system: _text(row, 'system_input'),
          offsetSeconds: _text(row, 'offset_input'),
          tickLabel: _text(row, 'tick_label_input'),
          ticksPerMonthEnabled: row['ticks_enabled'] == 1,
          ticksPerMonth: _text(row, 'ticks_input'),
          firstInteraction: _text(row, 'first_interaction_input'),
          current: _text(row, 'current_input'),
        ),
        labels: _labels(binding, 'input'),
        rationale: _text(row, 'rationale'),
        original: original,
        draftVersion: row['draft_version'] == null
            ? null
            : BigInt.parse(_text(row, 'draft_version')),
      ),
    );
  }

  void _write(EditorFormScope scope, SavedRepresentedContextForm saved) {
    final binding = _binding(scope), f = saved.form, c = f.chronology;
    final columns = '$_keys,$_fields'.split(',');
    _db.execute(
      'INSERT INTO represented_context_form(${columns.join(',')}) VALUES(${List.filled(columns.length, '?').join(',')}) ON CONFLICT($_keys) DO UPDATE SET ${_fields.split(',').map((c) => '$c=excluded.$c').join(',')}',
      [
        ...binding,
        saved.generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.kind,
        f.authoredLabel,
        f.reference.record,
        f.reference.universe,
        f.parentEnabled ? 1 : 0,
        f.parent.record,
        f.parent.universe,
        c.enabled ? 1 : 0,
        c.calendar,
        c.system,
        c.offsetSeconds,
        c.tickLabel,
        c.ticksPerMonthEnabled ? 1 : 0,
        c.ticksPerMonth,
        c.firstInteraction,
        c.current,
        f.rationale,
        f.draftVersion?.toString(),
      ],
    );
    _db.execute(
      'DELETE FROM represented_context_original WHERE $_where',
      binding,
    );
    _db.execute('DELETE FROM represented_context_label WHERE $_where', binding);
    final o = f.original;
    if (o != null) {
      final (kind, label, ref) = switch (o.kind) {
        ObjectiveContext() => ('objective', null, null),
        AuthoredContext(:final label) => ('authored', label, null),
        CharacterContext(:final holder) => ('character', null, holder),
        SourceContext(:final source) => ('source', null, source),
        NarratorContext(:final narrator) => ('narrator', null, narrator),
      };
      final (clock, offset, tick, ticks) = switch (o.chronology?.system) {
        GregorianClock(:final offsetSeconds) => (
          'gregorian',
          offsetSeconds,
          null,
          null,
        ),
        FictionalClock(:final tickLabel, :final ticksPerMonth) => (
          'fictional',
          null,
          tickLabel,
          ticksPerMonth,
        ),
        null => (null, null, null, null),
      };
      final originalColumns = '$_keys,$_originalFields'.split(',');
      _db.execute(
        'INSERT INTO represented_context_original VALUES(${List.filled(originalColumns.length, '?').join(',')})',
        [
          ...binding,
          o.universe.value,
          kind,
          label,
          ref?.record.value,
          ref?.universe?.value,
          o.parent?.record.value,
          o.parent?.universe?.value,
          o.chronology?.calendar.value,
          clock,
          offset,
          tick,
          ticks,
          o.chronology?.firstInteraction,
          o.chronology?.current,
        ],
      );
    }
    for (final list in {
      'input': f.labels,
      'original':
          o?.labels.entries
              .map((e) => PropertyLabelInput(language: e.key, text: e.value))
              .toList() ??
          <PropertyLabelInput>[],
    }.entries) {
      for (var i = 0; i < list.value.length; i++) {
        final label = list.value[i];
        _db.execute(
          'INSERT INTO represented_context_label VALUES(?,?,?,?,?,?,?,?,?,?)',
          [...binding, list.key, i, label.language, label.text],
        );
      }
    }
  }

  void _validate(EditorFormScope scope, UnfinishedRepresentedContextForm form) {
    if (scope.universe != form.universe ||
        scope.representedContext != form.representedContext ||
        scope.typeClientRef != null && scope.typeClientRef != form.clientRef) {
      throw const FormatException(
        'RepresentedContext form context does not match.',
      );
    }
    for (final text in form.exactTexts) {
      if (decodeExactUtf8(utf8.encode(text)) != text) {
        throw const EditorRecoveryException(EditorRecoveryFailure.invalidText);
      }
    }
    form.toWire();
  }

  SavedRepresentedContextForm? load(EditorFormScope scope) {
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

  SavedRepresentedContextForm save(
    EditorFormScope scope,
    UnfinishedRepresentedContextForm form,
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
      final saved = SavedRepresentedContextForm(
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
