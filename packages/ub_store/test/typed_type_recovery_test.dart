@TestOn('vm')
library;

import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/src/ownership.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope({bool edit = true}) => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: edit ? '\ufeffPending type' : null,
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef ?? '',
];
UnfinishedTypeForm input(EditorFormScope s, {bool empty = false}) {
  final world = WorldId.generate();
  return UnfinishedTypeForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: s.typeClientRef ?? '\ufeffCreation',
    namespace: '\ufeffAuthored',
    key: '\ufeffKey',
    name: empty ? '' : '\ufeffName\r\n\u0000😀',
    parentChoice: 'unfinished parent',
    applicabilityChoice: 'undecided',
    rationale: '\ufeffReason',
    classificationExecutable: empty ? null : true,
    worlds: empty ? [] : [world, world],
    draftVersion: empty ? null : maxU64,
    revisionTarget: empty
        ? null
        : RecordRef(record: RecordId.generate(), universe: s.universe),
    expectedRecordVersion: empty ? null : RecordVersionId.generate(),
    parentResolution: empty ? '' : 'unfinished resolution',
    labels: empty
        ? []
        : const [
            PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
            PropertyLabelInput(),
            PropertyLabelInput(language: '\ufeffen', text: 'Repeated'),
          ],
    original: empty
        ? null
        : EntityTypeRecord(
            namespace: '\ufeffOriginal',
            key: '\ufeffType',
            name: '',
            labels: {'\ufeffen': '\ufeffOriginal', '': '', 'ja': '記憶😀'},
            parent: RecordId.generate(),
            parentResolution: ParentResolution.resolved,
            applicability: WorldsApplicability([world, world]),
            classificationExecutable: false,
          ),
  );
}

void legacy(
  String path,
  int version,
  List<(EditorFormScope, UnfinishedTypeForm, String)> entries, {
  bool broken = false,
}) {
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  final keys = version == 1
      ? 'instance,profile,universe,continuity,context'
      : 'instance,profile,universe,continuity,context,editor_key';
  try {
    db.execute(
      'CREATE TABLE type_form(${keys.split(',').map((k) => '$k TEXT NOT NULL').join(',')},generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,namespace TEXT NOT NULL,key TEXT NOT NULL,name TEXT NOT NULL,parent_choice TEXT NOT NULL,applicability_choice TEXT NOT NULL,rationale TEXT NOT NULL,classification_executable INTEGER${version >= 2 ? ',draft_version TEXT' : ''}${version >= 3 ? ',revision_input TEXT' : ''},PRIMARY KEY($keys)) STRICT; CREATE TABLE type_form_world(${keys.split(',').map((k) => '$k TEXT NOT NULL').join(',')},ordinal INTEGER NOT NULL,world TEXT NOT NULL,PRIMARY KEY($keys,ordinal)) STRICT; PRAGMA user_version=$version',
    );
    for (final (s, f, g) in entries) {
      final values = <Object?>[
        ...(version == 1 ? binding(s).sublist(0, 5) : binding(s)),
        g,
        f.baseRevision.value,
        f.clientRef,
        f.namespace,
        f.key,
        f.name,
        f.parentChoice,
        f.applicabilityChoice,
        f.rationale,
        f.classificationExecutable == null
            ? null
            : f.classificationExecutable!
            ? 1
            : 0,
        if (version >= 2) f.draftVersion?.toString(),
        if (version >= 3)
          broken && s == entries.last.$1
              ? '{unfinished'
              : f.revisionTarget == null
              ? null
              : f.revisionFields.toText(),
      ];
      db.execute(
        'INSERT INTO type_form VALUES(${List.filled(values.length, '?').join(',')})',
        values,
      );
      for (var i = 0; i < f.worlds.length; i++) {
        final v = [
          ...(version == 1 ? binding(s).sublist(0, 5) : binding(s)),
          i,
          f.worlds[i].value,
        ];
        db.execute(
          'INSERT INTO type_form_world VALUES(${List.filled(v.length, '?').join(',')})',
          v,
        );
      }
    }
  } finally {
    db.close();
  }
}

void main() {
  test('typed type recovery retains exact revision metadata, labels, worlds and original definition through restart and replacement', () {
    final root = Directory('/tmp').createTempSync('ub-typed-type-'),
        s = scope();
    final path = '${root.path}/forms.sqlite', form = input(s);
    var store = TypeFormRecoveryStore.open(path);
    try {
      store.save(s, form, BigInt.zero);
      store.close();
      store = TypeFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(s, form, BigInt.zero).generation, BigInt.one);
      store.save(s, form, BigInt.one);
      final empty = input(s, empty: true);
      store.save(s, empty, BigInt.two);
      store.close();
      store = TypeFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), empty.toWire().toText());
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(type_form)').map((r) => r['name']),
          isNot(contains('revision_input')),
        );
        for (final r in db.select(
          "SELECT name FROM sqlite_master WHERE type='table' AND name!='type_form'",
        )) {
          expect(
            db.select('SELECT count(*) AS n FROM "${r['name']}"').single['n'],
            0,
            reason: r['name'] as String,
          );
        }
        expect(db.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('type v3 conversion preserves separate recovery slots, original revisions, generations and competing saves', () {
    final root = Directory('/tmp').createTempSync('ub-type-v3-conversion-'),
        s = scope(),
        second = scope();
    final path = '${root.path}/forms.sqlite',
        form = input(s),
        other = input(second);
    legacy(path, 3, [(s, form, '19'), (second, other, maxU64.toString())]);
    final store = TypeFormRecoveryStore.open(path),
        competing = TypeFormRecoveryStore.open(path);
    try {
      expect(store.load(s)!.form.toWire().toText(), form.toWire().toText());
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = input(s, empty: true);
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        store.save(s, changed, BigInt.from(19)).generation,
        BigInt.from(20),
      );
      expect(
        () => competing.save(s, form, BigInt.from(19)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(second, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  for (final version in [1, 2, 3]) {
    test(
      'type v$version conversion rolls back all typed rows on malformed saved generation',
      () {
        final root = Directory('/tmp')
                .createTempSync('ub-type-v$version-rollback-'),
            s = scope(edit: version != 1),
            second = scope(edit: version != 1);
        final path = '${root.path}/forms.sqlite', form = input(s);
        legacy(path, version, [
          (s, form, '1'),
          (second, input(second), (maxU64 + BigInt.one).toString()),
        ]);
        try {
          expect(
            () => TypeFormRecoveryStore.open(path),
            throwsA(isA<EditorRecoveryException>()),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db.select('PRAGMA user_version').single.values.single,
              version,
            );
            expect(
              db
                  .select('SELECT generation FROM type_form')
                  .map((r) => r['generation']),
              ['1', (maxU64 + BigInt.one).toString()],
            );
            expect(
              db.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name LIKE 'r_%'",
              ),
              isEmpty,
            );
            expect(
              db
                  .select('SELECT count(*) AS n FROM type_form_world')
                  .single['n'],
              4,
            );
          } finally {
            db.close();
          }
        } finally {
          root.deleteSync(recursive: true);
        }
      },
    );
  }
  test(
    'malformed type revision input retains its complete v3 recovery file',
    () {
      final root = Directory('/tmp')
              .createTempSync('ub-type-revision-rollback-'),
          s = scope(),
          second = scope();
      final path = '${root.path}/forms.sqlite', form = input(s);
      legacy(path, 3, [
        (s, form, '1'),
        (second, input(second), '2'),
      ], broken: true);
      try {
        expect(
          () => TypeFormRecoveryStore.open(path),
          throwsA(isA<EditorRecoveryException>()),
        );
        final db = sqlite3.open(path, mode: OpenMode.readOnly);
        try {
          expect(db.select('PRAGMA user_version').single.values.single, 3);
          expect(
            db
                .select(
                  'SELECT revision_input FROM type_form ORDER BY generation',
                )
                .map((r) => r['revision_input']),
            [form.revisionFields.toText(), '{unfinished'],
          );
          expect(
            db
                .select("SELECT name FROM sqlite_master WHERE type='table'")
                .map((r) => r['name']),
            ['type_form', 'type_form_world'],
          );
        } finally {
          db.close();
        }
      } finally {
        root.deleteSync(recursive: true);
      }
    },
  );
}
