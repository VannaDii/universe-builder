import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/exception_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('exceptions preserve nullable version pins, decision links, exact validity and authored scope', () {
    final universe = UniverseId.generate(), context = RecordId.generate();
    RecordRef ref() =>
        RecordRef(universe: universe, record: RecordId.generate());
    for (final pin in [null, RecordVersionId.generate()]) {
      final record = ExceptionRecord(
        fictionalDeparture: true,
        rule: ref(),
        ruleVersion: pin,
        authorizingDecision: ref(),
        scope: Scope(
          applicability: const UniverseApplicability(),
          context: RecordRef(universe: universe, record: context),
          realm: ref(),
        ),
        validity: InstantValidity(
          ExactTime(CalendarId.generate(), '9007199254740997'),
        ),
        rationale: 'Scoped departure 記憶 😀',
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: context,
          operations: [
            AddExceptionOperation(clientRef: 'exception', record: record),
          ],
          rationale: 'Keep draft rationale.',
        ),
      );
      final form = UnfinishedExceptionForm.fromWire(
        exceptionFormFromDraft(draft, 0).toWire(),
      );
      expect(
        exceptionOperation(form).record.toWire().toText(),
        record.toWire().toText(),
      );
      final request = exceptionDraftRequest(
        draft: draft,
        form: form.copyWith(
          rationale: 'Reviewed scoped departure.',
          ruleVersionEnabled: false,
        ),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        index: 0,
      );
      final next =
          (request.content.operations.single as AddExceptionOperation).record;
      expect(next.ruleVersion, isNull);
      expect(next.rule, record.rule);
      expect(next.authorizingDecision, record.authorizingDecision);
      expect(next.rationale, 'Reviewed scoped departure.');
      expect(next.scope.toWire().toText(), record.scope.toWire().toText());
      expect(
        next.validity.toWire().toText(),
        record.validity.toWire().toText(),
      );
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => exceptionDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          index: 0,
        ),
        throwsFormatException,
      );
    }
  });
  test('unfinished exceptions recover without choosing a decision or manufacturing a version', () {
    final root = Directory('/tmp').createTempSync('ub-exception-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final form = UnfinishedExceptionForm(
      fictionalDeparture: true,
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      ruleVersion: 'unfinished pin 記憶 😀',
      rationale: 'Unfinished exception.',
    );
    var store = ExceptionFormRecoveryStore.open('${root.path}/forms.sqlite');
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = ExceptionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.ruleVersionEnabled, isFalse);
      expect(recovered.decision.record, isEmpty);
      expect(() => exceptionOperation(recovered), throwsFormatException);
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(
          scope,
          form.copyWith(ruleVersionEnabled: true),
          BigInt.zero,
        ),
        throwsA(isA<EditorRecoveryException>()),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
