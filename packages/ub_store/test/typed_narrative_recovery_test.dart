@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending narrative input',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
const reason = '\ufeffMemoir 記憶 😀\r\n\u0000';
void legacy(
  String path,
  String table,
  List<(EditorFormScope, BigInt, String)> entries,
) {
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE $table(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, generation, text) in entries) {
      db.execute('INSERT INTO $table VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        generation.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
}

dynamic input(String kind, EditorFormScope s, {bool editing = true}) {
  final base = RevisionId.generate(),
      expected = editing ? RecordVersionId.generate() : null;
  final target = editing
      ? const ExpressionReferenceInput(
          record: '',
          universe: '\ufeffPartial universe',
        )
      : null;
  switch (kind) {
    case 'saga':
      return UnfinishedSagaForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
        title: '\ufeffSaga title',
        rationale: reason,
        membershipTarget: target,
        expectedRecordVersion: expected,
        draftVersion: editing ? maxU64 : null,
        labels: const [
          PropertyLabelInput(language: '\ufeffen', text: '\ufeffName'),
          PropertyLabelInput(language: '', text: ''),
          PropertyLabelInput(
            language: '\ufeffen',
            text: 'Repeated unfinished label',
          ),
        ],
        memberships: const [
          SagaMembershipInput(
            work: ExpressionReferenceInput(
              record: '\ufeffPending work',
              universe: '',
            ),
            role: '\ufeffOpening',
            orderEnabled: false,
            order: '9007199254740993',
          ),
          SagaMembershipInput(
            work: ExpressionReferenceInput(
              record: '\ufeffPending work',
              universe: '',
            ),
            role: 'Repeated work',
            orderEnabled: true,
            order: 'not finished',
          ),
          SagaMembershipInput(),
        ],
      );
    case 'work_version':
      return UnfinishedWorkVersionForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
        work: const ExpressionReferenceInput(
          record: '\ufeffPending work',
          universe: '\ufeffPending universe',
        ),
        versionLabel: '\ufeffEdition',
        bindingKind: 'still choosing',
        continuity: '\ufeffPending continuity',
        revision: 'Pending revision',
        bindingTarget: target,
        expectedRecordVersion: expected,
        rationale: reason,
        draftVersion: editing ? maxU64 : null,
        segments: const [
          WorkSegmentInput(
            segment: '\ufeffOpening',
            continuity: '\ufeffc',
            revision: 'r',
          ),
          WorkSegmentInput(),
          WorkSegmentInput(
            segment: '\ufeffOpening',
            continuity: '\ufeffc',
            revision: 'r',
          ),
        ],
      );
    case 'passage':
      return UnfinishedPassageForm(
        baseRevision: base,
        representedContext: s.representedContext!,
        clientRef: s.typeClientRef!,
        passageId: '\ufeffPending passage',
        edition: const ExpressionReferenceInput(
          record: '\ufeffPending edition',
          universe: 'Pending universe',
        ),
        editionVersion: '\ufeffPartial pin',
        anchorEnabled: false,
        anchor: const ExpressionReferenceInput(
          record: '\ufeffRetained disabled selection',
          universe: '',
        ),
        rationale: reason,
        draftVersion: editing ? maxU64 : null,
      );
    default:
      throw StateError('Unknown test form');
  }
}

dynamic cleared(String kind, dynamic value) => switch (kind) {
  'saga' => (value as UnfinishedSagaForm).copyWith(
    title: '\ufeffNew title',
    labels: [],
    memberships: [],
  ),
  'work_version' => (value as UnfinishedWorkVersionForm).copyWith(
    bindingKind: 'bound',
    segments: [],
  ),
  'passage' => (value as UnfinishedPassageForm).copyWith(anchorEnabled: true),
  _ => throw StateError('Unknown test form'),
};
void main() {
  for (final kind in ['saga', 'work_version', 'passage']) {
    dynamic open(String path) => switch (kind) {
      'saga' => SagaFormRecoveryStore.open(path),
      'work_version' => WorkVersionFormRecoveryStore.open(path),
      'passage' => PassageFormRecoveryStore.open(path),
      _ => throw StateError('Unknown test form'),
    };
    final table = '${kind}_form';
    test(
      '$kind fresh typed recovery retains incomplete text and selections across restart',
      () {
        final root = Directory('/tmp').createTempSync('ub-narrative-fields-');
        final path = '${root.path}/forms.sqlite', selected = scope();
        final dynamic form = input(kind, selected);
        dynamic store = open(path);
        try {
          store.save(selected, form, BigInt.zero);
          store.close();
          store = open(path);
          expect(
            store.load(selected).form.toWire().toText(),
            form.toWire().toText(),
          );
          expect(
            store.save(selected, form, BigInt.zero).generation,
            BigInt.one,
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(
              db.select('PRAGMA table_info($table)').map((r) => r['name']),
              isNot(contains('form_input')),
            );
            expect(
              db
                  .select(
                    'SELECT CAST(rationale AS BLOB) AS reason FROM $table',
                  )
                  .single['reason'],
              utf8.encode(reason),
            );
            if (kind == 'saga') {
              expect(
                db
                    .select(
                      'SELECT order_enabled,order_input FROM saga_membership ORDER BY ordinal',
                    )
                    .map((r) => [r['order_enabled'], r['order_input']]),
                [
                  [0, '9007199254740993'],
                  [1, 'not finished'],
                  [0, ''],
                ],
              );
            }
            if (kind == 'work_version') {
              expect(
                db
                    .select(
                      'SELECT CAST(segment AS BLOB) AS segment FROM work_version_segment ORDER BY ordinal',
                    )
                    .map((r) => r['segment']),
                ['\ufeffOpening', '', '\ufeffOpening'].map(utf8.encode),
              );
            }
          } finally {
            db.close();
          }
        } finally {
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind conversion preserves separate profiles, optional states, generations and competing edits',
      () {
        final root = Directory('/tmp')
            .createTempSync('ub-narrative-conversion-');
        final path = '${root.path}/forms.sqlite',
            selected = scope(),
            otherScope = scope();
        final dynamic form = input(kind, selected),
            other = input(kind, otherScope, editing: false);
        legacy(path, table, [
          (selected, BigInt.from(11), form.toWire().toText()),
          (otherScope, maxU64, other.toWire().toText()),
        ]);
        dynamic store = open(path);
        final dynamic competing = open(path);
        try {
          expect(
            store.load(selected).form.toWire().toText(),
            form.toWire().toText(),
          );
          expect(
            store.load(otherScope).form.toWire().toText(),
            other.toWire().toText(),
          );
          final dynamic changed = cleared(kind, form);
          expect(
            store.save(selected, changed, BigInt.from(11)).generation,
            BigInt.from(12),
          );
          expect(
            store.save(selected, changed, BigInt.from(11)).generation,
            BigInt.from(12),
          );
          expect(
            () => competing.save(selected, form, BigInt.from(11)),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.conflict,
              ),
            ),
          );
          expect(
            () => store.save(otherScope, other, maxU64),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.generationExhausted,
              ),
            ),
          );
          store.close();
          store = open(path);
          expect(
            store.load(selected).form.toWire().toText(),
            changed.toWire().toText(),
          );
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA user_version').single.values.single, 2);
            for (final child in switch (kind) {
              'saga' => ['saga_label', 'saga_membership'],
              'work_version' => ['work_version_segment'],
              _ => <String>[],
            }) {
              expect(
                db.select('SELECT count(*) AS n FROM $child WHERE profile=?', [
                  selected.profile.value,
                ]).single['n'],
                0,
              );
            }
          } finally {
            db.close();
          }
        } finally {
          competing.close();
          store.close();
          root.deleteSync(recursive: true);
        }
      },
    );
    test(
      '$kind failed conversion retains every legacy row without partial named fields',
      () {
        final root = Directory('/tmp').createTempSync('ub-narrative-rollback-');
        final path = '${root.path}/forms.sqlite',
            selected = scope(),
            otherScope = scope();
        final text = input(kind, selected).toWire().toText() as String;
        legacy(path, table, [
          (selected, BigInt.one, text),
          (otherScope, BigInt.two, '{unfinished'),
        ]);
        try {
          expect(() => open(path), throwsA(isA<EditorRecoveryException>()));
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA user_version').single.values.single, 1);
            expect(
              db
                  .select('SELECT form_input FROM $table ORDER BY generation')
                  .map((r) => r['form_input']),
              [text, '{unfinished'],
            );
            expect(
              db
                  .select("SELECT name FROM sqlite_master WHERE type='table'")
                  .map((r) => r['name']),
              [table],
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
}
