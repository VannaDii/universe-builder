@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_issue_decision_recovery.dart';
import 'package:ub_client/browser_exception_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

EditorFormScope scopeFor(RecordId context, String clientRef) => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: context,
  typeClientRef: clientRef,
);

Future<void> deleteDatabase(String name) async {
  final done = Completer<void>();
  final request = web.window.indexedDB.deleteDatabase(name);
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('Test cleanup failed'),
  )).toJS;
  await done.future;
}

void main() {
  test(
    'issue decisions recover ordered findings and enforce principal binding',
    () async {
      final name = 'ub-issue-test-${OperationId.generate().value}';
      var store = await BrowserIssueDecisionFormRecoveryStore.open(
        databaseName: name,
      );
      final context = RecordId.generate();
      final scope = scopeFor(context, 'issue');
      final principal = PrincipalId.parse(
        scope.profile.value.replaceFirst('prf_', 'prn_'),
      );
      final input = UnfinishedIssueDecisionForm(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        clientRef: 'issue',
        principal: principal,
        mode: 'unfinished mode',
        fingerprints: ['finding A', '', 'finding A', 'finding B'],
        scope: 'Scene 記憶 😀\r\n',
        rationale: '',
        draftVersion: BigInt.parse('9007199254740993123'),
        original: IssueDecisionRecord(
          fingerprints: [
            FindingFingerprint('original A'),
            FindingFingerprint('original B'),
          ],
          mode: IssueDecisionMode.defer,
          scope: 'previous scope',
          rationale: 'previous reason',
          principal: principal,
        ),
      );
      try {
        await store.save(scope, input, BigInt.zero);
        store.close();
        store = await BrowserIssueDecisionFormRecoveryStore.open(
          databaseName: name,
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          input.toWire().toText(),
        );
        expect(
          (await store.save(scope, input, BigInt.zero)).generation,
          BigInt.one,
        );
        final reversed = input.copyWith(
          fingerprints: input.fingerprints.reversed.toList(),
        );
        await expectLater(
          store.save(scope, reversed, BigInt.zero),
          throwsA(
            isA<EditorRecoveryException>().having(
              (e) => e.failure,
              'failure',
              EditorRecoveryFailure.conflict,
            ),
          ),
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          input.toWire().toText(),
        );
        await store.save(scope, reversed, BigInt.one);
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          reversed.toWire().toText(),
        );
        final cleared = input.copyWith(
          fingerprints: [],
          mode: '',
          scope: '',
          rationale: 'new reason',
        );
        await store.save(scope, cleared, BigInt.two);
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          cleared.toWire().toText(),
        );
        await expectLater(
          store.save(
            scope,
            cleared.copyWith(rationale: '\uD800'),
            BigInt.from(3),
          ),
          throwsFormatException,
        );
        final other = scopeFor(context, 'issue');
        expect(await store.load(other), isNull);
        await expectLater(
          store.save(other, input, BigInt.zero),
          throwsFormatException,
        );
        final mismatched = UnfinishedIssueDecisionForm(
          baseRevision: input.baseRevision,
          representedContext: context,
          clientRef: 'other',
          principal: principal,
        );
        await expectLater(
          store.save(scope, mismatched, BigInt.from(3)),
          throwsFormatException,
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          cleared.toWire().toText(),
        );
      } finally {
        store.close();
        await deleteDatabase(name);
      }
    },
  );

  test(
    'exceptions recover pinned rules, decisions and inactive unfinished input',
    () async {
      final name = 'ub-exception-test-${OperationId.generate().value}';
      var store = await BrowserExceptionFormRecoveryStore.open(
        databaseName: name,
      );
      final context = RecordId.generate(), calendar = CalendarId.generate();
      final scope = scopeFor(context, 'exception');
      final input = UnfinishedExceptionForm(
        baseRevision: RevisionId.generate(),
        representedContext: context,
        clientRef: 'exception',
        rule: ExpressionReferenceInput(
          record: 'unfinished rule',
          universe: scope.universe.value,
        ),
        ruleVersionEnabled: true,
        ruleVersion: 'unfinished version-',
        decision: ExpressionReferenceInput(record: 'unfinished decision'),
        scope: ScopeInput(
          contextRecord: context.value,
          applicability: 'worlds',
          worlds: ['a', '', 'a', 'b'],
          hasRealm: true,
          realmRecord: 'unfinished realm',
        ),
        validity: TemporalValidityInput(
          calendar: calendar.value,
          start: TemporalBoundInput(value: '9007199254740993123'),
          end: TemporalBoundInput(value: 'unfinished-'),
        ),
        rationale: 'Reason 記憶 😀\r\n',
        draftVersion: BigInt.parse('18446744073709551615'),
        original: ExceptionRecord(
          rule: RecordRef(
            universe: scope.universe,
            record: RecordId.generate(),
          ),
          ruleVersion: RecordVersionId.generate(),
          authorizingDecision: RecordRef(record: RecordId.generate()),
          scope: Scope(
            context: RecordRef(record: context),
            applicability: UniverseApplicability(),
          ),
          validity: InstantValidity(ExactTime(calendar, '9007199254740993123')),
          rationale: 'previous reason',
        ),
      );
      try {
        await store.save(scope, input, BigInt.zero);
        store.close();
        store = await BrowserExceptionFormRecoveryStore.open(
          databaseName: name,
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          input.toWire().toText(),
        );
        expect(
          (await store.save(scope, input, BigInt.zero)).generation,
          BigInt.one,
        );
        final disabled = input.copyWith(
          ruleVersionEnabled: false,
          scope: ScopeInput(worlds: ['b', 'a', '', 'a']),
          rationale: '',
        );
        await expectLater(
          store.save(scope, disabled, BigInt.zero),
          throwsA(
            isA<EditorRecoveryException>().having(
              (e) => e.failure,
              'failure',
              EditorRecoveryFailure.conflict,
            ),
          ),
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          input.toWire().toText(),
        );
        await store.save(scope, disabled, BigInt.one);
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          disabled.toWire().toText(),
        );
        final cleared = input.copyWith(
          ruleVersionEnabled: false,
          ruleVersion: '',
          rule: ExpressionReferenceInput(),
          decision: ExpressionReferenceInput(),
          scope: ScopeInput(),
          validity: TemporalValidityInput(),
        );
        await store.save(scope, cleared, BigInt.two);
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          cleared.toWire().toText(),
        );
        await expectLater(
          store.save(
            scope,
            cleared.copyWith(ruleVersion: '\uD800'),
            BigInt.from(3),
          ),
          throwsFormatException,
        );
        final other = scopeFor(context, 'exception');
        expect(await store.load(other), isNull);
        final mismatch = UnfinishedExceptionForm(
          baseRevision: input.baseRevision,
          representedContext: RecordId.generate(),
          clientRef: 'exception',
        );
        await expectLater(
          store.save(scope, mismatch, BigInt.zero),
          throwsFormatException,
        );
        expect(
          (await store.load(scope))!.form.toWire().toText(),
          cleared.toWire().toText(),
        );
      } finally {
        store.close();
        await deleteDatabase(name);
      }
    },
  );
}
