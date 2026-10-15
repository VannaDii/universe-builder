@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart' show protectedFile;

const keys = 'instance,profile,universe,continuity,context,editor_key';
final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
  typeClientRef: '\ufeffPending decision',
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef!,
];
void legacy(
  String path,
  String table,
  List<(EditorFormScope, BigInt, String)> rows,
) {
  protectedFile(path, createNew: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE $table (instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY($keys)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, generation, input) in rows) {
      db.execute('INSERT INTO $table VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        generation.toString(),
        input,
      ]);
    }
  } finally {
    db.close();
  }
}

UnfinishedIssueDecisionForm decision(EditorFormScope s) =>
    UnfinishedIssueDecisionForm(
      baseRevision: RevisionId.generate(),
      representedContext: s.representedContext!,
      clientRef: s.typeClientRef!,
      principal: PrincipalId.parse(
        s.profile.value.replaceFirst('prf_', 'prn_'),
      ),
      mode: 'still choosing',
      fingerprints: ['\ufeffExact finding', '', 'duplicate', 'duplicate'],
      scope: '\ufeffUnfinished scope',
      rationale: '\ufeffWhy 記憶 😀\r\n\u0000',
      draftVersion: maxU64,
      original: IssueDecisionRecord(
        fingerprints: const [
          FindingFingerprint('B'),
          FindingFingerprint('A'),
          FindingFingerprint('B'),
        ],
        mode: IssueDecisionMode.defer,
        scope: '\ufeffOriginal scope',
        rationale: '\ufeffOriginal reason\r\n',
        principal: PrincipalId.generate(),
      ),
    );
UnfinishedRecordRemovalForm removal(EditorFormScope s) =>
    UnfinishedRecordRemovalForm(
      baseRevision: RevisionId.generate(),
      representedContext: s.representedContext!,
      clientRef: s.typeClientRef!,
      target: const ExpressionReferenceInput(
        record: '\ufeffUnfinished target',
        universe: '\ufeffUnfinished universe',
      ),
      expectedRecordVersion: RecordVersionId.generate(),
      rationale: '\ufeffReason 記憶 😀\r\n\u0000',
      draftVersion: maxU64,
    );

void main() {
  for (final table in ['assertion_retraction_form', 'event_withdrawal_form']) {
    dynamic open(String path) => table == 'assertion_retraction_form'
        ? AssertionRetractionFormRecoveryStore.open(path)
        : EventWithdrawalFormRecoveryStore.open(path);
    test(
      '$table preserves unfinished fields and generations through conversion, retry and restart',
      () {
        final root = Directory('/tmp').createTempSync('ub-typed-withdrawal-');
        final path = '${root.path}/forms.sqlite', selected = scope();
        final wire = removal(selected).toWire();
        final dynamic input = table == 'assertion_retraction_form'
            ? UnfinishedAssertionRetractionForm.fromWire(wire)
            : UnfinishedEventWithdrawalForm.fromWire(wire);
        legacy(path, table, [(selected, BigInt.from(7), wire.toText())]);
        dynamic store = open(path);
        try {
          expect(store.load(selected).form.toWire().toText(), wire.toText());
          final dynamic changed = input.copyWith(
            rationale: '\ufeffNew reason\r\n記憶',
          );
          expect(
            store.save(selected, changed, BigInt.from(7)).generation,
            BigInt.from(8),
          );
          expect(
            store.save(selected, changed, BigInt.from(7)).generation,
            BigInt.from(8),
          );
          expect(
            () => store.save(selected, input, BigInt.from(7)),
            throwsA(
              isA<EditorRecoveryException>().having(
                (e) => e.failure,
                'failure',
                EditorRecoveryFailure.conflict,
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
            expect(
              db.select('PRAGMA table_info($table)').map((r) => r['name']),
              isNot(contains('form_input')),
            );
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
      '$table leaves malformed legacy input intact on failed conversion',
      () {
        final root = Directory('/tmp')
            .createTempSync('ub-withdrawal-rollback-');
        final path = '${root.path}/forms.sqlite', selected = scope();
        legacy(path, table, [(selected, BigInt.two, '{unfinished')]);
        try {
          expect(() => open(path), throwsA(isA<EditorRecoveryException>()));
          final db = sqlite3.open(path, mode: OpenMode.readOnly);
          try {
            expect(db.select('PRAGMA user_version').single.values.single, 1);
            expect(
              db.select('SELECT form_input FROM $table').single['form_input'],
              '{unfinished',
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

  test('legacy decisions become named fields and ordered findings without changing input or save generations', () {
    final root = Directory('/tmp').createTempSync('ub-typed-decision-');
    final path = '${root.path}/forms.sqlite', first = scope(), second = scope();
    final input = decision(first),
        other = decision(second),
        generation = maxU64 - BigInt.one;
    legacy(path, 'issue_decision_form', [
      (first, generation, input.toWire().toText()),
      (second, BigInt.two, other.toWire().toText()),
    ]);
    var store = IssueDecisionFormRecoveryStore.open(path);
    try {
      expect(
        store.load(first)!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(store.load(first)!.generation, generation);
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = input.copyWith(
        fingerprints: ['last', '', '\ufefffirst'],
        rationale: '\ufeffChanged reason',
      );
      expect(store.save(first, changed, generation).generation, maxU64);
      expect(store.save(first, changed, generation).generation, maxU64);
      expect(
        () => store.save(first, input, generation),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(first, input, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
      store.close();
      store = IssueDecisionFormRecoveryStore.open(path);
      expect(
        store.load(first)!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        expect(
          db
              .select('PRAGMA table_info(issue_decision_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        final typed = db.select(
          'SELECT mode,CAST(rationale AS BLOB) AS reason,original_mode FROM issue_decision_form WHERE profile=?',
          [first.profile.value],
        ).single;
        expect(typed['mode'], changed.mode);
        expect(typed['reason'], utf8.encode(changed.rationale));
        expect(typed['original_mode'], 'defer');
        expect(
          db
              .select(
                "SELECT CAST(fingerprint_input AS BLOB) AS input FROM issue_decision_fingerprint WHERE profile=? AND list_kind='input' ORDER BY ordinal",
                [first.profile.value],
              )
              .map((r) => r['input']),
          changed.fingerprints.map(utf8.encode),
        );
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('a malformed legacy decision rolls back the entire conversion and retains every original row', () {
    final root = Directory('/tmp').createTempSync('ub-decision-rollback-');
    final path = '${root.path}/forms.sqlite', first = scope(), second = scope();
    final text = decision(first).toWire().toText();
    legacy(path, 'issue_decision_form', [
      (first, BigInt.one, text),
      (second, BigInt.two, '{unfinished'),
    ]);
    try {
      expect(
        () => IssueDecisionFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select(
                'SELECT form_input FROM issue_decision_form ORDER BY generation',
              )
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['issue_decision_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });

  test('legacy removal fields retain exact references and competing saves after conversion and restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-removal-');
    final path = '${root.path}/forms.sqlite', first = scope(), second = scope();
    final input = removal(first), other = removal(second);
    legacy(path, 'record_removal_form', [
      (first, BigInt.from(42), input.toWire().toText()),
      (second, BigInt.one, other.toWire().toText()),
    ]);
    var store = RecordRemovalFormRecoveryStore.open(path);
    final competing = RecordRemovalFormRecoveryStore.open(path);
    try {
      expect(
        store.load(first)!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final changed = input.copyWith(rationale: '\ufeffUpdated reason\r\n');
      expect(
        store.save(first, changed, BigInt.from(42)).generation,
        BigInt.from(43),
      );
      expect(
        store.save(first, changed, BigInt.from(42)).generation,
        BigInt.from(43),
      );
      expect(
        () => competing.save(first, input, BigInt.from(42)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(
          first,
          input.copyWith(rationale: '\ud800'),
          BigInt.from(43),
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      store.close();
      store = RecordRemovalFormRecoveryStore.open(path);
      expect(
        store.load(first)!.form.toWire().toText(),
        changed.toWire().toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        expect(
          db
              .select('PRAGMA table_info(record_removal_form)')
              .map((r) => r['name']),
          isNot(contains('form_input')),
        );
        final row = db.select(
          'SELECT CAST(target_record AS BLOB) AS target,expected_record_version FROM record_removal_form WHERE profile=?',
          [first.profile.value],
        ).single;
        expect(row['target'], utf8.encode(input.target.record));
        expect(
          row['expected_record_version'],
          input.expectedRecordVersion.value,
        );
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('a mismatched legacy removal scope is retained without a partial conversion', () {
    final root = Directory('/tmp').createTempSync('ub-removal-rollback-');
    final path = '${root.path}/forms.sqlite',
        first = scope(),
        unrelated = scope();
    final text = removal(unrelated).toWire().toText();
    legacy(path, 'record_removal_form', [(first, BigInt.one, text)]);
    try {
      expect(
        () => RecordRemovalFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select('SELECT form_input FROM record_removal_form')
              .single['form_input'],
          text,
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
