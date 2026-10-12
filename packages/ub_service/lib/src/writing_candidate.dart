import 'package:ub_domain/ub_domain.dart';

import 'operation_compilation.dart';

/// Assemble a transient writer candidate through the canonical compiler.
/// Versions allocated here are previews, not persisted canon or approvals.
List<RecordVersion> compileWritingCandidate({
  required UniverseId universe,
  required RevisionId revision,
  required List<RecordVersion> base,
  required List<DomainOperation> operations,
}) {
  final changes = compileOperations(
    universe: universe,
    revision: revision,
    base: base,
    operations: operations,
  );
  final rows = {for (final row in base) row.identity.recordId: row};
  for (final change in changes) {
    final next = change.next;
    if (next == null) {
      rows.remove(change.recordId);
    } else {
      rows[change.recordId] = RecordVersion.fromWire(next.toCanonical());
    }
  }
  final sorted = rows.keys.toList()..sort((a, b) => a.value.compareTo(b.value));
  return List.unmodifiable([for (final id in sorted) rows[id]!]);
}
