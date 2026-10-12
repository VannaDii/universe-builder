import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';
import 'package:ub_store/ub_store.dart';

import 'rule_checks.dart';

/// Protects transitive references and every affected exact period. Changes must
/// include both proposed versions and removed/replaced historical versions.
/// This check does not grant publication or author authority.
CheckedRule evaluateCandidateBoundary({
  required RecordVersion target,
  required List<RecordVersion> changes,
  required List<RecordVersion> records,
  required List<RecordVersion> historical,
  required Frame frame,
  required bool author,
}) {
  final boundary = target.payload;
  if (boundary is! BoundaryRecord) {
    throw ArgumentError.value(target, 'target', 'Expected a creative boundary');
  }
  final timing = [...historical, ...records];
  final byId = {for (final r in timing) r.identity.recordId: r};
  var evidence = Evidence.supported([]), complete = true, accepted = true;
  var work = 100000;
  CheckedRule result() =>
      CheckedRule(evidence: evidence, complete: complete, accepted: accepted);
  bool charge() {
    if (work == 0) {
      complete = false;
      accepted = false;
      return false;
    }
    work--;
    return true;
  }

  void unresolved() {
    complete = false;
    accepted = false;
  }

  for (final changed in changes) {
    if (changed.payload is BoundaryRecord ||
        changed.payload is ExceptionRecord ||
        changed.payload is IssueDecisionRecord) {
      continue;
    }
    final pending = [changed], visited = <RecordId>{};
    var touches = false;
    while (pending.isNotEmpty) {
      final r = pending.removeLast();
      if (!visited.add(r.identity.recordId)) continue;
      if (!charge()) return result();
      touches |= switch (boundary.area) {
        RecordBoundaryArea(:final record) =>
          r.identity.recordId == record.record,
        CategoryBoundaryArea(:final entityType) =>
          r.payload is EntityRecord &&
              (r.payload as EntityRecord).classification == entityType,
        PredicateBoundaryArea(:final predicate, :final subject) =>
          switch (r.payload) {
            PropositionRecord(subject: final s, predicate: final p)
                when subject == null || subject == s =>
              switch (byId[p.record]?.payload) {
                PropertyRecord(:final namespace, :final key) ||
                RelationRecord(
                  :final namespace,
                  :final key,
                ) => '$namespace:$key' == predicate,
                _ => false,
              },
            _ => false,
          },
      };
      final deps = recordDependencies(
        StoredVersion(
          versionId: r.recordVersionId,
          identity: r.identity,
          payload: r.payload.toWire(),
          digest: r.payloadDigest,
        ),
      );
      // Rust's dependency set visits IDs in reverse lexical order on this stack.
      final sorted = deps.toList()..sort((a, b) => a.value.compareTo(b.value));
      for (final id in sorted) {
        final dep = byId[id];
        if (dep != null) pending.add(dep);
      }
    }
    if (!touches) continue;
    final scopes = <(Scope?, Validity)>[];
    switch (changed.payload) {
      case AssertionRecord(:final scope, :final validity) ||
          CompletenessRecord(:final scope, :final validity):
        scopes.add((scope, validity));
      case EventRecord(:final effects) when effects.isNotEmpty:
        scopes.addAll(effects.map((e) => (e.scope, e.validity)));
      case PropositionRecord():
        for (final r in records) {
          final a = r.payload;
          if (a is AssertionRecord &&
              a.proposition.record == changed.identity.recordId) {
            scopes.add((a.scope, a.validity));
          }
        }
        if (scopes.isEmpty) scopes.add((null, const UnspecifiedValidity()));
      default:
        scopes.add((null, const UnspecifiedValidity()));
    }
    for (final (scope, validity) in scopes) {
      if (scope != null) {
        if (scope.context != boundary.scope.context) continue;
        if (scope.realm != null &&
            boundary.scope.realm != null &&
            scope.realm != boundary.scope.realm) {
          continue;
        }
        if (scope.realm == null && boundary.scope.realm != null) {
          unresolved();
          continue;
        }
        final a = scope.applicability, b = boundary.scope.applicability;
        if (a is WorldsApplicability &&
            b is WorldsApplicability &&
            !a.worldIds.any(b.worldIds.contains)) {
          continue;
        }
        if (a is! UniverseApplicability && a is! WorldsApplicability) {
          unresolved();
          continue;
        }
      }
      final applicability = boundary.scope.applicability;
      if (applicability is! UniverseApplicability &&
          applicability is! WorldsApplicability) {
        unresolved();
        continue;
      }
      if (validity is! UnspecifiedValidity &&
          boundary.validity is! UnspecifiedValidity) {
        final overlap = temporalOverlaps(validity, boundary.validity);
        if (overlap == false) continue;
        if (overlap == null) {
          unresolved();
          continue;
        }
      }
      final period = boundary.validity is UnspecifiedValidity
          ? validity
          : boundary.validity;
      final base = Frame(
        universe: frame.universe,
        continuity: frame.continuity,
        revision: frame.revision,
        context: boundary.scope.context,
        time: const TimelessFrameTime(),
        perspective: frame.perspective,
        readerScene: frame.readerScene,
        personalSequence: frame.personalSequence,
      );
      final frames = exactEvidenceFrames(period, timing, base);
      if (frames == null) {
        unresolved();
        continue;
      }
      final worlds = switch (scope?.applicability) {
        WorldsApplicability(:final worldIds) => worldIds,
        _ => switch (applicability) {
          WorldsApplicability(:final worldIds) => worldIds,
          _ => <WorldId>[],
        },
      };
      for (final cell in frames) {
        if (!charge()) return result();
        if (validity is! UnspecifiedValidity &&
            cell.time is! TimelessFrameTime) {
          final applies = eventApplies(validity, cell.time, records);
          if (applies == false) continue;
          if (applies == null) {
            unresolved();
            continue;
          }
        }
        final worldCells = worlds.isEmpty
            ? <List<RecordId>>[[]]
            : worlds
                  .where(
                    (w) =>
                        applicability is! WorldsApplicability ||
                        applicability.worldIds.contains(w),
                  )
                  .map(
                    (w) => [
                      RecordId.parse(
                        'rec_${w.value.substring(WorldId.prefix.length)}',
                      ),
                    ],
                  )
                  .toList();
        for (final world in worldCells) {
          var cellEvidence = Evidence.supported([]), cellComplete = true;
          switch (boundary.mode) {
            case BoundaryMode.fixed ||
                BoundaryMode.prohibited ||
                BoundaryMode.intentionallyUnresolved:
              cellEvidence = Evidence.refuted([target.recordVersionId]);
            case BoundaryMode.authorReserved when !author:
              cellEvidence = Evidence.refuted([target.recordVersionId]);
            case BoundaryMode.openWithConstraints:
              if (boundary.scope.realm != null) cellComplete = false;
              for (final expr in boundary.constraints) {
                final (e, c) = evaluateExpression(
                  expr,
                  EvaluationContext(
                    frame: cell,
                    baseSnapshot: records,
                    worldScope: world,
                  ),
                );
                cellEvidence = cellEvidence.all(e);
                cellComplete &= c;
              }
            default:
              break;
          }
          final waived = records.any((r) {
            final e = r.payload;
            return e is ExceptionRecord &&
                exceptionAt(e, target, cell, world, records);
          });
          accepted &=
              cellComplete &&
              (cellEvidence.outcome == EvidenceOutcome.supported || waived);
          complete &= cellComplete;
          evidence = evidence.all(cellEvidence);
        }
      }
    }
  }
  return result();
}
