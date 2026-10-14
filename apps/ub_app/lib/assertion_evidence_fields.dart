import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'qualifier_draft.dart';
import 'temporal_validity_draft.dart';
import 'temporal_validity_fields.dart';
import 'value_input_fields.dart';
import 'scope_draft.dart';
import 'scope_input_fields.dart';
import 'evidence_basis_draft.dart';
import 'evidence_basis_fields.dart';

class AssertionEvidenceFields extends StatelessWidget {
  const AssertionEvidenceFields({
    super.key,
    required this.input,
    required this.original,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final AttributeEvidenceInput? input;
  final AttributeEvidence original;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<AttributeEvidenceInput> onChanged;
  void _editEvidence({
    EvidenceBasisInput? basis,
    AttributeMode? attributeMode,
    ScopeInput? scope,
    Polarity? polarity,
    Precision? precision,
    PersistenceSemantics? persistence,
    String? validityChoice,
    TemporalValidityInput? temporal,
    List<QualifierInput>? alternatives,
  }) {
    final old = input ?? const AttributeEvidenceInput();
    onChanged(
      AttributeEvidenceInput(
        basis: basis ?? old.basis,
        attributeMode: attributeMode ?? old.attributeMode,
        scope: scope ?? old.scope,
        alternatives: alternatives ?? old.alternatives,
        polarity: polarity ?? old.polarity,
        precision: precision ?? old.precision,
        persistence: persistence ?? old.persistence,
        validity: validityChoice == null
            ? old.validity
            : switch (validityChoice) {
                'unspecified' => const UnspecifiedValidity(),
                'unknown' => const UnknownValidity(),
                'conditional' => const ConditionalValidity(),
                _ => null,
              },
        temporalValidity: validityChoice == null
            ? temporal ?? old.temporalValidity
            : validityChoice == 'temporal'
            ? temporalValidityInput(original.validity)
            : null,
      ),
    );
  }

  List<QualifierInput> get _alternatives =>
      input?.alternatives ??
      [
        for (var i = 0; i < original.alternatives.length; i++)
          qualifierInput(i.toString(), original.alternatives[i]),
      ];
  void _moveAlternative(int index, int destination) {
    final rows = [..._alternatives];
    rows.insert(destination, rows.removeAt(index));
    _editEvidence(alternatives: rows);
  }

  Widget _alternativeFields() {
    final rows = _alternatives;
    final originalValues = qualifierChildren(
      SequenceValue(original.alternatives),
    );
    return ExpansionTile(
      key: const ValueKey('attribute alternatives'),
      title: const Text('Alternative values'),
      children: [
        const Text(
          'These are authored alternatives, not additional established facts. Precision is selected separately.',
        ),
        if (rows.isEmpty) const Text('No alternatives'),
        for (var i = 0; i < rows.length; i++)
          Column(
            key: ValueKey(('attribute alternative', i)),
            children: [
              ValueInputFields(
                changes: changes,
                draft: draft,
                input: rows[i],
                original: originalValues[rows[i].originalKey],
                disabled: disabled,
                label: 'Alternative ${i + 1}',
                onChanged: (value) {
                  final changed = [..._alternatives];
                  changed[i] = value;
                  _editEvidence(alternatives: changed);
                },
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: disabled || i == 0
                        ? null
                        : () => _moveAlternative(i, i - 1),
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: disabled || i == rows.length - 1
                        ? null
                        : () => _moveAlternative(i, i + 1),
                    child: const Text('Move later'),
                  ),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () {
                            final changed = [..._alternatives]..removeAt(i);
                            _editEvidence(alternatives: changed);
                          },
                    child: const Text('Remove alternative'),
                  ),
                ],
              ),
            ],
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () => _editEvidence(
                  alternatives: [..._alternatives, const QualifierInput()],
                ),
          child: const Text('Add alternative'),
        ),
      ],
    );
  }

  Widget _choice<T>(
    String label,
    T value,
    Map<T, String> choices,
    ValueChanged<T> change,
  ) => DropdownButtonFormField<T>(
    key: ValueKey((label, value)),
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final e in choices.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: disabled
        ? null
        : (v) {
            if (v != null) change(v);
          },
  );
  Widget _detailsFields() {
    final choice = input?.temporalValidity != null
        ? 'temporal'
        : switch (input?.validity) {
            UnspecifiedValidity() => 'unspecified',
            UnknownValidity() => 'unknown',
            ConditionalValidity() => 'conditional',
            _ => 'retain',
          };
    return ExpansionTile(
      key: const ValueKey('attribute assertion details'),
      title: const Text('Assertion details'),
      children: [
        _choice(
          'Attribute mode',
          input?.attributeMode ?? original.attributeMode,
          const {
            AttributeMode.instance: 'Instance fact',
            AttributeMode.shared: 'Shared attribute',
            AttributeMode.initialValue: 'Initial value',
          },
          (v) => _editEvidence(attributeMode: v),
        ),
        _choice('Polarity', input?.polarity ?? original.polarity, const {
          Polarity.support: 'Supports this fact',
          Polarity.refutation: 'Refutes this fact',
        }, (v) => _editEvidence(polarity: v)),
        _choice('Precision', input?.precision ?? original.precision, const {
          Precision.exact: 'Exact',
          Precision.approximate: 'Approximate',
          Precision.range: 'Range',
          Precision.oneOf: 'One of the authored alternatives',
          Precision.unresolved: 'Unresolved',
        }, (v) => _editEvidence(precision: v)),
        _choice(
          'Persistence',
          input?.persistence ?? original.persistence,
          const {
            PersistenceSemantics.explicitInterval: 'Explicit interval',
            PersistenceSemantics.persistentUntilChanged:
                'Persistent until changed',
            PersistenceSemantics.instantaneousObservation:
                'Instantaneous observation',
            PersistenceSemantics.conditionDependent: 'Condition dependent',
            PersistenceSemantics.unspecified: 'Unspecified',
          },
          (v) => _editEvidence(persistence: v),
        ),
        _choice('Validity', choice, const {
          'retain': 'Keep current validity',
          'unspecified': 'Unspecified',
          'unknown': 'Unknown',
          'conditional': 'Conditional',
          'temporal': 'Temporal validity',
        }, (v) => _editEvidence(validityChoice: v)),
        if (input?.temporalValidity != null)
          TemporalValidityFields(
            changes: changes,
            draft: draft,
            key: const ValueKey('attribute temporal'),
            input: input!.temporalValidity!,
            originalAmounts: temporalOriginalAmounts(original.validity),
            disabled: disabled,
            onChanged: (v) => _editEvidence(temporal: v),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _detailsFields(),
      ExpansionTile(
        key: const ValueKey('attribute factual scope'),
        title: const Text('Factual scope'),
        children: [
          ScopeInputFields(
            changes: changes,
            draft: draft,
            input: input?.scope ?? scopeInput(original.scope),
            disabled: disabled,
            onChanged: (v) => _editEvidence(scope: v),
          ),
        ],
      ),
      _alternativeFields(),
      ExpansionTile(
        key: const ValueKey('attribute source basis'),
        title: const Text('Source basis'),
        children: [
          EvidenceBasisFields(
            changes: changes,
            draft: draft,
            input: input?.basis ?? evidenceBasisInput(original.basis),
            original: original.basis,
            disabled: disabled,
            onChanged: (v) => _editEvidence(basis: v),
          ),
        ],
      ),
    ],
  );
}
