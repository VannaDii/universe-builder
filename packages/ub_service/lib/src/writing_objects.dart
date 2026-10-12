import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_rules/ub_rules.dart';

import 'writing_binding.dart';
import 'writing_definitions.dart';

final _nonWhitespace = RegExp(
  r'[^\u0009-\u000d\u0020\u0085\u00a0\u1680\u2000-\u200a\u2028\u2029\u202f\u205f\u3000]',
);

/// Compile ordinary facts and definition attributes against admitted pinned
/// rows. Earlier declaration stages supply their exact bindings and candidate
/// unit/world rows. The caller owns admission and proposal persistence.
({
  List<DomainOperation> operations,
  List<String> additions,
  List<String> unchanged,
  List<String> excluded,
  List<String> clarifications,
  List<String> unknowns,
})
compileWritingObjects({
  required Frame frame,
  required List<RecordVersion> rows,
  required List<RecordVersion> propertyRows,
  required List<RecordVersion> worldRows,
  required List<ObjectChange> changes,
  required List<DefinitionChange> definitions,
  Map<String, RecordId> introducedDefinitions = const {},
  Set<String> ambiguousDefinitions = const {},
  Map<String, (RecordId, PropertyRecord)> declaredProperties = const {},
  Set<WorldId>? worldScope,
}) {
  final operations = <DomainOperation>[];
  final additions = <String>[],
      unchanged = <String>[],
      excluded = <String>[],
      clarifications = <String>[],
      unknowns = <String>[];
  final names = <String, RecordId>{}, ambiguous = <String>{};
  final properties = Map.of(declaredProperties);
  final newProperties = <RecordId, PropertyRecord>{};
  final emitted = <RecordId>{}, assertions = <String>{};
  for (final object in changes.where(
    (o) =>
        o.introduce &&
        (o.facts.isEmpty || o.facts.any((f) => f.statement == 'objective')),
  )) {
    if (names.containsKey(object.name)) {
      ambiguous.add(object.name);
      clarifications.add(
        "Are the repeated introductions of '${object.name}' the same object or separate identities?",
      );
    } else {
      names[object.name] = RecordId.generate();
    }
  }
  RecordId? resolve(String name) {
    if (ambiguous.contains(name)) return null;
    final ids = <RecordId>{
      for (final row in rows)
        if (row.payload case EntityRecord(:final labels, :final names))
          if (labels.values.contains(name) ||
              names.any(
                (n) =>
                    n.text == name &&
                    temporalApplies(n.validity, frame.time) != false,
              ))
            row.identity.recordId,
      if (names[name] != null) names[name]!,
    };
    return ids.length == 1 ? ids.single : null;
  }

  RecordId? definition(String name) => resolveWritingDefinition(
    rows,
    name,
    introduced: introducedDefinitions,
    ambiguous: ambiguousDefinitions,
  );
  RecordRef ref(RecordId id) => RecordRef(universe: frame.universe, record: id);
  final objects = <(ObjectChange, bool, bool)>[
    for (final object in changes) (object, false, false),
    for (final d in definitions)
      (ObjectChange(name: d.name, facts: d.sharedAttributes), true, false),
    for (final d in definitions)
      (ObjectChange(name: d.name, facts: d.initialValues), true, true),
  ];
  for (final (object, shared, initial) in objects) {
    if (!_nonWhitespace.hasMatch(object.name)) {
      throw const InvalidArgumentError(
        field: 'changes.name',
        message: 'nonempty object name required',
      );
    }
    for (final fact in object.facts) {
      if (!const {
        'objective',
        'dialogue',
        'belief',
        'plan',
        'hypothetical',
        'metaphor',
      }.contains(fact.statement)) {
        throw const InvalidArgumentError(
          field: 'statement',
          message: 'unknown statement mode',
        );
      }
      if (fact.statement != 'objective') {
        excluded.add(
          '${object.name} ${fact.property}: ${fact.statement} claim, not an objective fact',
        );
      }
    }
    if (object.facts.isNotEmpty &&
        object.facts.every((f) => f.statement != 'objective')) {
      if (object.introduce) {
        clarifications.add(
          "Does the objective narration separately establish '${object.name}' as a real new object?",
        );
      }
      continue;
    }
    if (ambiguous.contains(object.name)) continue;
    final classification = object.classification == null
        ? null
        : definition(object.classification!);
    if (object.classification != null && classification == null) {
      clarifications.add(
        "Which exact classification definition is '${object.classification}'?",
      );
      continue;
    }
    final RecordId subject;
    if (shared) {
      final id = definition(object.name);
      if (id == null) continue;
      subject = id;
    } else if (object.introduce) {
      subject =
          names[object.name] ??
          (throw const InvalidArgumentError(
            field: 'introduce',
            message: 'ambiguous new identity',
          ));
      operations.add(
        IntroduceInstanceOperation(
          clientRef: subject.value,
          name: ContextualName(
            text: object.name,
            validity: const UnspecifiedValidity(),
          ),
          classification: classification,
          worldAssociations: [],
        ),
      );
      additions.add('New object: ${object.name}');
    } else {
      final id = resolve(object.name);
      if (id == null) {
        clarifications.add(
          "Which existing object is '${object.name}', or is this a new independent object?",
        );
        continue;
      }
      subject = id;
    }
    if (!shared && !object.introduce && classification != null) {
      final current = rows
          .where((r) => r.identity.recordId == subject)
          .firstOrNull;
      if (current == null) {
        throw const NotFoundOrNotAccessibleError(message: 'resource');
      }
      if (current.payload
          case EntityRecord(
            classification: final existing,
            classificationResolution: ClassificationResolution.resolved,
          )
          when existing == classification) {
        unchanged.add('${object.name}: classification');
      } else {
        operations.add(
          RefineClassificationOperation(
            record: ref(subject),
            expectedVersion: current.recordVersionId,
            entityType: classification,
          ),
        );
        additions.add('Refined classification: ${object.name}');
      }
    }
    for (final fact in object.facts.where((f) => f.statement == 'objective')) {
      if (!_nonWhitespace.hasMatch(fact.property)) {
        throw const InvalidArgumentError(
          field: 'property',
          message: 'nonempty property name required',
        );
      }
      final DomainValue value;
      final ValueShape shape;
      if (fact.value case FactObjectValue(:final object)) {
        final id = resolve(object);
        if (id == null) {
          clarifications.add("Which object does '$object' refer to?");
          continue;
        }
        value = ReferenceValue(ValueReferenceKind.entity, ref(id));
        shape = EntityRefShape([]);
      } else {
        try {
          value = bindWritingValue(
            frame.universe,
            propertyRows,
            frame,
            fact.value,
          );
        } on FormatException catch (error) {
          clarifications.add(error.message.toString());
          continue;
        }
        shape = switch (value) {
          TextValue() => const SimpleValueShape(SimpleShapeKind.text),
          BooleanValue() => const SimpleValueShape(SimpleShapeKind.boolean),
          IntegerValue() => const SimpleValueShape(SimpleShapeKind.integer),
          DecimalValue() => const SimpleValueShape(SimpleShapeKind.decimal),
          QuantityValue(:final unit) => QuantityShape(unit),
          _ => throw StateError('Unexpected writer fact value'),
        };
      }
      var property = properties[fact.property];
      if (property == null) {
        final found = <(RecordId, PropertyRecord)>[
          for (final row in rows)
            if (row.payload case final PropertyRecord p)
              if (p.key == fact.property ||
                  p.labels.values.contains(fact.property))
                (row.identity.recordId, p),
        ];
        if (found.length > 1) {
          clarifications.add(
            "Which authored property named '${fact.property}' applies?",
          );
          continue;
        }
        if (found.isEmpty) {
          final id = RecordId.generate();
          final p = PropertyRecord(
            namespace: 'authoring',
            key: fact.property,
            labels: {},
            value: shape,
            multiplicity: Multiplicity.multiple,
            persistence: PersistenceSemantics.unspecified,
            exclusive: false,
            symmetric: false,
            transitive: false,
          );
          newProperties[id] = p;
          property = (id, p);
        } else {
          property = found.single;
        }
        properties[fact.property] = property;
      }
      final (propertyId, p) = property;
      if (p.value != shape &&
          !(p.value is EntityRefShape && shape is EntityRefShape)) {
        clarifications.add(
          "The value for '${object.name} ${fact.property}' does not match the existing property definition; clarify its intended value/unit/type.",
        );
        continue;
      }
      final Applicability applicability;
      try {
        applicability = bindWritingApplicability(
          worldRows,
          fact.scope,
          worldScope: worldScope,
        );
      } on ProtocolError {
        clarifications.add(
          "Which accessible authored world is '${fact.scope}'?",
        );
        continue;
      } on FormatException {
        clarifications.add(
          "Which accessible authored world is '${fact.scope}'?",
        );
        continue;
      }
      final when = fact.atTick != null ? 'scene' : fact.when;
      if (when != 'scene' && fact.lifetime is! FactUnspecifiedLifetime) {
        clarifications.add(
          'What authored scene time starts this explicit fact lifetime?',
        );
        continue;
      }
      final FrameTime factTime;
      try {
        factTime = when == 'scene' && fact.atTick != null
            ? AtFrameTime(bindWritingTime(frame, rows, fact.atTick))
            : frame.time;
      } on FormatException catch (error) {
        clarifications.add(error.message.toString());
        continue;
      }
      final Validity validity;
      if (when == 'unspecified') {
        validity = const UnspecifiedValidity();
      } else if (when == 'scene') {
        if (factTime case AtFrameTime(:final time)) {
          if (fact.lifetime is FactUnspecifiedLifetime &&
              p.persistence != PersistenceSemantics.persistentUntilChanged) {
            validity = InstantValidity(time);
          } else if (time case ExactTime(:final calendar, :final value)) {
            validity = CalendarIntervalValidity(
              calendar,
              ExactBound(value),
              fact.lifetime is FactUntilLifetime
                  ? ExactBound((fact.lifetime as FactUntilLifetime).endTick)
                  : const UnboundedBound(),
            );
          } else {
            clarifications.add(
              'What exact calendar time/lifetime applies to this fact?',
            );
            continue;
          }
        } else {
          clarifications.add('What story time do these scene facts hold at?');
          continue;
        }
      } else {
        throw const InvalidArgumentError(
          field: 'when',
          message: 'expected scene or unspecified',
        );
      }
      final scope = Scope(context: frame.context, applicability: applicability);
      final polarity = fact.negated ? Polarity.refutation : Polarity.support;
      final mode = initial
          ? AttributeMode.initialValue
          : shared
          ? AttributeMode.shared
          : AttributeMode.instance;
      final already = rows.any((row) {
        if (row.payload case final PropositionRecord proposition) {
          return proposition.subject.record == subject &&
              proposition.predicate.record == propertyId &&
              proposition.value == value &&
              proposition.context == frame.context &&
              rows.any((a) {
                if (a.payload case final AssertionRecord assertion) {
                  return assertion.proposition.record ==
                          row.identity.recordId &&
                      assertion.attributeMode == mode &&
                      assertion.polarity == polarity &&
                      assertion.precision == Precision.exact &&
                      assertion.alternatives.isEmpty &&
                      assertion.scope == scope &&
                      (assertion.validity == validity ||
                          factTime is AtFrameTime &&
                              temporalApplies(assertion.validity, factTime) ==
                                  true);
                }
                return false;
              });
        }
        return false;
      });
      final binding = CanonicalArray([
        CanonicalString(subject.value),
        CanonicalString(propertyId.value),
        value.toWire(),
        scope.toWire(),
        validity.toWire(),
        CanonicalString(polarity.name),
        CanonicalBool(initial),
        CanonicalBool(shared),
      ]).toText();
      if (already || !assertions.add(binding)) {
        unchanged.add('${object.name}: ${fact.property}');
        continue;
      }
      if (fact.scope == 'unspecified') {
        unknowns.add(
          'The world/universe applicability of the new facts remains unspecified.',
        );
      }
      if (when == 'unspecified') {
        unknowns.add(
          'The story-time validity of the new facts remains unspecified.',
        );
      }
      if (newProperties.containsKey(propertyId) && emitted.add(propertyId)) {
        operations.add(
          DefinePropertyOperation(clientRef: propertyId.value, record: p),
        );
      }
      final propositionId = RecordId.generate();
      if (shared && newProperties.containsKey(propertyId)) {
        operations.add(
          AddNamedAttributeOperation(
            clientRef: propositionId.value,
            subject: ref(subject),
            namespace: p.namespace,
            key: p.key,
            valueShape: p.value,
            subjectTypes: p.subjectTypes,
            multiplicity: p.multiplicity,
            value: value,
            evidence: AttributeEvidence(
              attributeMode: mode,
              polarity: polarity,
              scope: scope,
              validity: validity,
              persistence: p.persistence,
              precision: Precision.exact,
              basis: const ImportedClaimBasis(),
            ),
          ),
        );
      } else {
        operations.add(
          AssertPropositionOperation(
            clientRef: propositionId.value,
            proposition: PropositionRecord(
              subject: ref(subject),
              predicate: ref(propertyId),
              value: value,
              context: frame.context,
              quantification: Quantification.particular,
            ),
            assertion: AssertionRecord(
              attributeMode: mode,
              proposition: ref(propositionId),
              polarity: polarity,
              scope: scope,
              validity: validity,
              persistence: p.persistence,
              precision: Precision.exact,
              basis: const ImportedClaimBasis(),
            ),
          ),
        );
      }
      additions.add(
        '${object.name}: ${fact.property} ${fact.negated ? 'not ' : ''}${fact.value.toWire().toText()}',
      );
    }
  }
  return (
    operations: List.unmodifiable(operations),
    additions: List.unmodifiable(additions),
    unchanged: List.unmodifiable(unchanged),
    excluded: List.unmodifiable(excluded),
    clarifications: List.unmodifiable(clarifications),
    unknowns: List.unmodifiable(unknowns),
  );
}
