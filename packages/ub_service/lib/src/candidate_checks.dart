import 'dart:collection';

import 'package:ub_contracts/ub_contracts.dart' show InvalidArgumentError;
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

typedef CandidateConflict = (RecordId, List<RecordVersionId>);
typedef CandidateConflicts = (List<CandidateConflict>, List<String>);
typedef _Key = (RecordId, RecordId, RecordId, int);
typedef _Witness = (RecordVersion, AssertionRecord, PropositionRecord);

Applicability _intersection(Applicability a, Applicability b) {
  if (a is WorldsApplicability && a.worldIds.isEmpty ||
      b is WorldsApplicability && b.worldIds.isEmpty) {
    return WorldsApplicability([]);
  }
  if (a is UniverseApplicability) return b;
  if (b is UniverseApplicability) return a;
  if (a is WorldsApplicability && b is WorldsApplicability) {
    return WorldsApplicability(a.worldIds.where(b.worldIds.contains).toList());
  }
  return const UnspecifiedApplicability();
}

/// Full candidate comparisons; passing these does not confer publication rights.
CandidateConflicts scalarConflicts(List<RecordVersion> records) {
  final map = {for (final r in records) r.identity.recordId: r.payload};
  final groups = <_Key, List<_Witness>>{};
  for (final r in records) {
    final a = r.payload;
    if (a is! AssertionRecord || a.polarity != Polarity.support) continue;
    final p = map[a.proposition.record];
    if (p is! PropositionRecord) continue;
    final property = map[p.predicate.record];
    if (property is! PropertyRecord ||
        property.multiplicity != Multiplicity.single && !property.exclusive) {
      continue;
    }
    final key = (
      p.subject.record,
      p.predicate.record,
      a.scope.context.record,
      a.attributeMode == AttributeMode.initialValue ? 1 : 0,
    );
    (groups[key] ??= []).add((r, a, p));
  }
  final originals = Map<_Key, List<_Witness>>.from(groups);
  // Copy witness lists before adding descendants to existing groups.
  for (final key in originals.keys.toList()) {
    originals[key] = List.of(originals[key]!);
  }
  for (final r in records) {
    if (r.payload is! EntityRecord && r.payload is! EntityTypeRecord) continue;
    final chain = definitionAncestry(r.identity.recordId, records);
    if (!chain.complete) continue;
    for (final entry in originals.entries) {
      final (owner, predicate, context, mode) = entry.key;
      if (owner == r.identity.recordId || !chain.types.contains(owner)) {
        continue;
      }
      for (final witness in entry.value) {
        if (witness.$2.attributeMode == AttributeMode.shared) {
          (groups[(r.identity.recordId, predicate, context, mode)] ??= []).add(
            witness,
          );
        }
      }
    }
  }
  final keys = groups.keys.toList()
    ..sort((a, b) {
      for (final pair in [(a.$1, b.$1), (a.$2, b.$2), (a.$3, b.$3)]) {
        final c = pair.$1.value.compareTo(pair.$2.value);
        if (c != 0) return c;
      }
      return a.$4.compareTo(b.$4);
    });
  final conflicts = <CandidateConflict>[], gaps = SplayTreeSet<String>();
  var remaining = 1000000;
  Applicability scope(AssertionRecord a, PropositionRecord p) {
    final definition = map[p.subject.record];
    return a.attributeMode == AttributeMode.shared &&
            definition is EntityTypeRecord
        ? _intersection(a.scope.applicability, definition.applicability)
        : a.scope.applicability;
  }

  for (final key in keys) {
    final facts = groups[key]!;
    for (var i = 0; i < facts.length; i++) {
      final (left, a, p) = facts[i];
      for (final (right, b, q) in facts.skip(i + 1)) {
        if (remaining == 0 || conflicts.length >= 1000) {
          gaps.add('scalar-work-budget-exhausted');
          return (conflicts, gaps.toList());
        }
        remaining--;
        if (a.scope.realm != b.scope.realm) continue;
        if (p.value == q.value ||
            p.value != null &&
                q.value != null &&
                compareValues(p.value!, Comparator.eq, q.value!) == true) {
          continue;
        }
        final x = scope(a, p), y = scope(b, q);
        if (x is WorldsApplicability && x.worldIds.isEmpty ||
            y is WorldsApplicability && y.worldIds.isEmpty) {
          continue;
        }
        if (x is WorldsApplicability &&
            y is WorldsApplicability &&
            x.worldIds.every((w) => !y.worldIds.contains(w))) {
          continue;
        }
        final overlap = temporalOverlaps(a.validity, b.validity);
        if (a.precision != Precision.exact ||
            b.precision != Precision.exact ||
            overlap == null ||
            x is UnspecifiedApplicability ||
            x is ConditionalApplicability ||
            y is UnspecifiedApplicability ||
            y is ConditionalApplicability) {
          gaps.add('scalar-scope-or-time:${key.$2.value}');
          continue;
        }
        if (overlap == false) continue;
        conflicts.add((key.$2, [left.recordVersionId, right.recordVersionId]));
      }
    }
  }
  return (conflicts, gaps.toList());
}

/// Rechecks unchanged assertions when candidate type/world definitions change.
List<String> validateDefinitionApplicability(List<RecordVersion> records) {
  final map = {for (final r in records) r.identity.recordId: r.payload};
  final gaps = SplayTreeSet<String>();
  for (final r in records) {
    final a = r.payload;
    if (a is! AssertionRecord) continue;
    final p = map[a.proposition.record];
    if (p is! PropositionRecord) continue;
    final checks = <(RecordId, List<RecordId>)>[];
    switch (map[p.predicate.record]) {
      case PropertyRecord d:
        checks.add((p.subject.record, d.subjectTypes));
      case RelationRecord d:
        for (final role in p.roles) {
          for (final def in d.roles) {
            if (def.name == role.role) {
              checks.add((role.participant.record, def.participantTypes));
              break;
            }
          }
        }
      default:
        break;
    }
    if (map[p.subject.record] is EntityTypeRecord) {
      checks.add((p.subject.record, [p.subject.record]));
    }
    for (final (subject, targets) in checks) {
      switch (coversDefinitionScope(
        subject,
        targets,
        records,
        a.scope.applicability,
      )) {
        case true:
          break;
        case false:
          throw InvalidArgumentError(
            field: 'candidate',
            message: "assertion is outside its definition's type/world applicability",
          );
        case null:
          gaps.add(
            'definition-applicability:${r.identity.recordId.value}:${subject.value}',
          );
      }
    }
  }
  return gaps.toList();
}

/// Only objective complete collections constrain additions in their exact scope.
CandidateConflicts completenessConflicts(List<RecordVersion> records) {
  final byId = {for (final r in records) r.identity.recordId: r};
  final members = <(RecordRef, String), List<_Witness>>{};
  for (final record in records) {
    final a = record.payload;
    if (a is! AssertionRecord ||
        a.polarity != Polarity.support ||
        a.precision != Precision.exact) {
      continue;
    }
    final p = byId[a.proposition.record]?.payload;
    if (p is! PropositionRecord) continue;
    final keys = [p.predicate.record.value];
    switch (byId[p.predicate.record]?.payload) {
      case PropertyRecord d:
        keys.add('${d.namespace}:${d.key}');
      case RelationRecord d:
        keys.add('${d.namespace}:${d.key}');
      default:
        break;
    }
    for (final key in keys) {
      (members[(p.subject, key)] ??= []).add((record, a, p));
    }
  }
  final findings = <CandidateConflict>[], gaps = <String>[];
  var budget = 1000000;
  for (final declaration in records) {
    final c = declaration.payload;
    if (c is! CompletenessRecord || c.completeness is! ObjectiveCompleteness) {
      continue;
    }
    final listed = c.members.toSet();
    for (final (record, a, p)
        in members[(c.subject, c.predicate)] ?? <_Witness>[]) {
      if (budget == 0) {
        gaps.add('completeness work budget exhausted');
        return (findings, gaps);
      }
      budget--;
      if (a.scope != c.scope) continue;
      final value = p.value;
      if (value is! ReferenceValue ||
          value.kind != ValueReferenceKind.entity ||
          listed.contains(value.record)) {
        continue;
      }
      switch (temporalOverlaps(a.validity, c.validity)) {
        case true:
          findings.add((
            declaration.identity.recordId,
            [declaration.recordVersionId, record.recordVersionId],
          ));
        case false:
          break;
        case null:
          gaps.add(
            'completeness:${declaration.identity.recordId.value}: unresolved temporal overlap',
          );
      }
    }
  }
  return (findings, gaps);
}
