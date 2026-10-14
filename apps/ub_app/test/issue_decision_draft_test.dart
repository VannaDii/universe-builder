import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/issue_decision_draft.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

void main() {
  test('decisions preserve opaque ordered identities, scope and authorship through edits', () {
    final principal = PrincipalId.generate();
    for (final mode in IssueDecisionMode.values) {
      final record = IssueDecisionRecord(
        fingerprints: [
          const FindingFingerprint('exact 記憶 😀'),
          const FindingFingerprint('exact 記憶 😀'),
          const FindingFingerprint('different'),
        ],
        mode: mode,
        scope: 'authored:scope 記憶 😀',
        rationale: 'The author’s rationale.',
        principal: principal,
      );
      final draft = SavedDraft(
        version: BigInt.from(6),
        content: DraftContent(
          baseRevision: RevisionId.generate(),
          representedContext: RecordId.generate(),
          operations: [
            RecordIssueDecisionOperation(clientRef: 'decision', record: record),
          ],
          rationale: 'Retain draft rationale.',
        ),
      );
      final form = UnfinishedIssueDecisionForm.fromWire(
        issueDecisionFormFromDraft(draft, 0).toWire(),
      );
      expect(
        issueDecisionOperation(
          form,
          principal: principal,
        ).record.toWire().toText(),
        record.toWire().toText(),
      );
      final request = issueDecisionDraftRequest(
        draft: draft,
        form: form.copyWith(
          mode: 'defer',
          fingerprints: form.fingerprints.reversed.toList(),
          rationale: 'Defer while researching.',
        ),
        universe: const Selector('Universe'),
        continuity: ContinuityId.generate(),
        principal: principal,
        index: 0,
      );
      final next =
          (request.content.operations.single as RecordIssueDecisionOperation)
              .record;
      expect(next.mode, IssueDecisionMode.defer);
      expect(
        next.fingerprints.map((f) => f.value),
        record.fingerprints.reversed.map((f) => f.value),
      );
      expect(next.scope, record.scope);
      expect(next.principal, principal);
      expect(next.rationale, 'Defer while researching.');
      expect(request.content.rationale, draft.content.rationale);
      expect(
        () => issueDecisionOperation(form, principal: PrincipalId.generate()),
        throwsFormatException,
      );
      expect(
        () => issueDecisionDraftRequest(
          draft: SavedDraft(version: BigInt.from(7), content: draft.content),
          form: form,
          universe: const Selector('Universe'),
          continuity: ContinuityId.generate(),
          principal: principal,
          index: 0,
        ),
        throwsFormatException,
      );
    }
  });
  test('unfinished decisions recover without assuming acceptance and cannot cross author profiles', () {
    final root = Directory('/tmp').createTempSync('ub-issue-decision-form-');
    final scope = EditorFormScope(
      instance: OperationId.generate(),
      profile: ProfileId.generate(),
      universe: UniverseId.generate(),
      continuity: ContinuityId.generate(),
      representedContext: RecordId.generate(),
    );
    final principal = PrincipalId.parse(
      scope.profile.value.replaceFirst('prf_', 'prn_'),
    );
    final form = UnfinishedIssueDecisionForm(
      baseRevision: RevisionId.generate(),
      representedContext: scope.representedContext!,
      clientRef: RecordId.generate().value,
      principal: principal,
      fingerprints: ['incomplete 記憶 😀', ''],
      rationale: 'Unfinished rationale.',
    );
    var store = IssueDecisionFormRecoveryStore.open(
      '${root.path}/forms.sqlite',
    );
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      store = IssueDecisionFormRecoveryStore.open('${root.path}/forms.sqlite');
      final recovered = store.load(scope)!.form;
      expect(recovered.toWire().toText(), form.toWire().toText());
      expect(recovered.mode, isEmpty);
      expect(
        () => issueDecisionOperation(recovered, principal: principal),
        throwsFormatException,
      );
      expect(store.save(scope, form, BigInt.zero).generation, BigInt.one);
      expect(
        () => store.save(scope, form.copyWith(mode: 'accept'), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      expect(
        () => store.save(
          EditorFormScope(
            instance: scope.instance,
            profile: ProfileId.generate(),
            universe: scope.universe,
            continuity: scope.continuity,
            representedContext: scope.representedContext,
          ),
          form,
          BigInt.zero,
        ),
        throwsFormatException,
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
