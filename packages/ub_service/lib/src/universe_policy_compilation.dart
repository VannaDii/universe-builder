import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/ub_store.dart';

import 'universe_evidence_policy.dart';

/// Creates fresh template records privately during proposal preparation. Exact
/// source-category versions are bound here, before the ordinary review flow.
List<Assignment> compileUniversePolicy({
  required UniverseId universe,
  required List<RecordVersion> base,
  required DefineUniversePolicyOperation operation,
}) {
  InvalidArgumentError invalid(String message) =>
      InvalidArgumentError(field: 'operations', message: message);
  RecordId id;
  try {
    id = RecordId.parse(operation.clientRef);
  } on FormatException {
    throw invalid('Policy client_ref must reserve a rec_ ID');
  }
  if (operation.key.trim().isEmpty) {
    throw invalid('Give the policy a name');
  }
  if (!operation.realWorld && operation.sourceCategoryMembers.isNotEmpty) {
    throw invalid('Source selections apply only to a Real World clone');
  }
  final sources = operation.sourceCategoryMembers.toSet();
  if (sources.length != operation.sourceCategoryMembers.length) {
    throw invalid('Choose each qualifying source version once');
  }
  for (final source in sources) {
    if (!base.any(
      (row) =>
          row.identity.recordId == source && row.payload is SourceVersionRecord,
    )) {
      throw invalid('Choose an existing source version from this universe');
    }
  }
  if (base.any((row) => row.identity.recordId == id)) {
    throw invalid('Policy identity already exists');
  }
  final key = '$universePolicyDefinitionPrefix${operation.key}';
  if (base.any(
    (row) =>
        row.payload is DomainPackRecord &&
        (row.payload as DomainPackRecord).key == key,
  )) {
    throw invalid('A policy with this name already exists');
  }
  final previous = base.any(isUniversePolicyRecord)
      ? UniversePolicySelection.fromRecords(universe, base)
      : null;
  if (!operation.activate && previous == null) {
    throw invalid('The first defined policy must be selected as the root');
  }
  if ((operation.activate &&
          previous?.selection.recordVersionId !=
              operation.expectedRootVersion) ||
      (!operation.activate && operation.expectedRootVersion != null)) {
    throw invalid('Root policy version changed; reopen the current root');
  }
  final generated = initialUniversePolicyRecords(
    universe,
    operation.realWorld,
    definitionId: id,
    definitionKey: key,
    evidenceNamespace: 'policy_${id.value.substring(4)}',
    sourceCategoryMembers: operation.sourceCategoryMembers,
  );
  final defined = UniversePolicySelection.fromRecords(universe, generated);
  final rows = [
    for (final row in generated)
      if (row != defined.selection) row,
  ];
  final changes = <Assignment>[];
  StoredVersion stored(RecordVersion row) => StoredVersion(
    versionId: row.recordVersionId,
    identity: row.identity,
    payload: row.payload.toWire(),
    digest: row.payloadDigest,
  );
  for (final row in rows) {
    changes.add(Assignment(recordId: row.identity.recordId, next: stored(row)));
  }
  if (operation.activate) {
    final root = previous?.selection ?? defined.selection;
    final selectionVersion = RecordVersionId.generate();
    final selection = RecordVersion.build(
      recordVersionId: selectionVersion,
      identity: root.identity,
      payload: DomainPackRecord(
        key: universePolicySelectionKey,
        version: selectionVersion.value,
        dependencies: {key: '1'},
        capabilities: [],
        records: [id],
      ),
    );
    changes.add(
      Assignment(
        recordId: root.identity.recordId,
        expected: previous?.selection.recordVersionId,
        next: stored(selection),
      ),
    );
  }
  return changes;
}

/// Editing the selected definition also updates its root's exact dependency in
/// the same compiled proposal. An explicit root change retains caller intent.
void synchronizeUniversePolicySelection({
  required UniverseId universe,
  required List<RecordVersion> base,
  required List<Assignment> changes,
}) {
  if (!changes.any((change) {
        final payload = change.next?.payload;
        if (payload == null) {
          return false;
        }
        final record = RecordPayload.fromWire(payload);
        return record is DomainPackRecord &&
            record.key.startsWith(universePolicyDefinitionPrefix);
      }) ||
      !base.any(isUniversePolicyRecord)) {
    return;
  }
  final selected = UniversePolicySelection.fromRecords(universe, base);
  if (changes.any(
    (change) => change.recordId == selected.selection.identity.recordId,
  )) {
    return;
  }
  final edit = changes
      .where(
        (change) => change.recordId == selected.definition.identity.recordId,
      )
      .singleOrNull;
  if (edit?.next == null) {
    return;
  }
  final definition = RecordPayload.fromWire(edit!.next!.payload);
  if (definition is! DomainPackRecord) {
    return;
  }
  final version = RecordVersionId.generate();
  final root = RecordVersion.build(
    recordVersionId: version,
    identity: selected.selection.identity,
    payload: DomainPackRecord(
      key: universePolicySelectionKey,
      version: version.value,
      dependencies: {definition.key: definition.version},
      capabilities: [],
      records: [selected.definition.identity.recordId],
    ),
  );
  changes.add(
    Assignment(
      recordId: root.identity.recordId,
      expected: selected.selection.recordVersionId,
      next: StoredVersion(
        versionId: version,
        identity: root.identity,
        payload: root.payload.toWire(),
        digest: root.payloadDigest,
      ),
    ),
  );
}
