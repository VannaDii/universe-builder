@TestOn('vm')
library;

import 'dart:io';
import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('initialization fields recover across restart with pinned sources and ordered partial scope', () {
    final root = Directory.systemTemp.createTempSync('ub-initialization-form-');
    final path = '${root.path}/form.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    var store = InitializationFormRecoveryStore.open(path);
    final form = UnfinishedInitializationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'pending initialization',
      instance: const ExpressionReferenceInput(record: 'unfinished instance'),
      start: const ExpressionReferenceInput(record: 'unfinished event'),
      definition: VersionRef(
        universe: scope.universe,
        record: RecordId.generate(),
        version: RecordVersionId.generate(),
      ),
      scope: ScopeInput(
        applicability: 'worlds',
        worlds: ['\ufeffSecond 記憶', 'First', 'First'],
        contextRecord: scope.representedContext!.value,
        contextUniverse: scope.universe.value,
        hasRealm: true,
        realmRecord: 'unfinished realm',
      ),
      endKind: 'exact',
      endCoordinate: 'not finished yet',
      rationale: '\ufeffAccount\r\n記憶 😀',
      draftVersion: BigInt.parse('18446744073709551615'),
    );
    try {
      final saved = store.save(scope, form, BigInt.zero);
      expect(saved.generation, BigInt.one);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      store.close();
      store = InitializationFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      final updated = form.copyWith(
        clearDefinition: true,
        endKind: 'unbounded',
      );
      expect(store.save(scope, updated, BigInt.one).generation, BigInt.two);
      expect(store.load(scope)!.form.definition, isNull);
      expect(
        store.load(
          EditorFormScope(
            instance: scope.instance,
            profile: ProfileId.generate(),
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: scope.representedContext,
          ),
        ),
        isNull,
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        final names = db
            .select('PRAGMA table_info(initialization_form)')
            .map((r) => r['name']);
        expect(
          names,
          containsAll([
            'instance_record',
            'definition_version',
            'end_coordinate',
          ]),
        );
        expect(names, isNot(contains('form_input')));
        expect(
          db
              .select(
                'SELECT CAST(world_input AS BLOB) AS world_bytes FROM initialization_world ORDER BY ordinal',
              )
              .map((r) => r['world_bytes']),
          ['\ufeffSecond 記憶', 'First', 'First'].map(utf8.encode),
        );
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });

  test('competing saves and malformed text retain the existing initialization input', () {
    final root = Directory.systemTemp.createTempSync(
      'ub-initialization-conflict-',
    );
    final path = '${root.path}/form.sqlite';
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedInitializationForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: 'one',
    );
    final first = InitializationFormRecoveryStore.open(path);
    final second = InitializationFormRecoveryStore.open(path);
    try {
      first.save(scope, form, BigInt.zero);
      expect(
        () => second.save(
          scope,
          form.copyWith(rationale: 'other window'),
          BigInt.zero,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => first.save(scope, form.copyWith(rationale: '\ud800'), BigInt.one),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(first.load(scope)!.generation, BigInt.one);
      expect(first.load(scope)!.form.rationale, isEmpty);
    } finally {
      second.close();
      first.close();
      root.deleteSync(recursive: true);
    }
  });
}
