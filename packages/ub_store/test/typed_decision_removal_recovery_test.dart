@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

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
  test('decision and removal forms retain ordered findings and exact inputs after restart', () {
    final root = Directory.systemTemp.createTempSync('ub-decisions-');
    final selected = scope();
    final path = '${root.path}/decision.sqlite';
    var decisions = IssueDecisionFormRecoveryStore.open(path);
    final form = decision(selected);
    try {
      decisions.save(selected, form, BigInt.zero);
      decisions.close();
      decisions = IssueDecisionFormRecoveryStore.open(path);
      expect(
        decisions.load(selected)!.form.toWire().toText(),
        form.toWire().toText(),
      );
      expect(
        () => decisions.save(selected, form, BigInt.two),
        throwsA(isA<EditorRecoveryException>()),
      );
      final removed = removal(selected);
      var removals = RecordRemovalFormRecoveryStore.open(
        '${root.path}/removal.sqlite',
      );
      try {
        removals.save(selected, removed, BigInt.zero);
        removals.close();
        removals = RecordRemovalFormRecoveryStore.open(
          '${root.path}/removal.sqlite',
        );
        expect(
          removals.load(selected)!.form.toWire().toText(),
          removed.toWire().toText(),
        );
      } finally {
        removals.close();
      }
    } finally {
      decisions.close();
      root.deleteSync(recursive: true);
    }
  });
}
