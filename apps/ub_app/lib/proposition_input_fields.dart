import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'record_reference_fields.dart';
import 'value_input_fields.dart';

class PropositionInputFields extends StatefulWidget {
  const PropositionInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onSubject,
    required this.onPredicate,
    required this.onContext,
    required this.onQuantification,
    required this.onRoles,
    required this.onHasValue,
    required this.onValue,
  });
  final UnfinishedPropositionForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<ExpressionReferenceInput> onSubject,
      onPredicate,
      onContext;
  final ValueChanged<String> onQuantification;
  final ValueChanged<List<PropositionRoleInput>> onRoles;
  final ValueChanged<bool> onHasValue;
  final ValueChanged<QualifierInput> onValue;
  @override
  State<PropositionInputFields> createState() => _PropositionInputFieldsState();
}

class _PropositionInputFieldsState extends State<PropositionInputFields> {
  int _layout = 0;
  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> onChanged, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: input.record,
    universe: input.universe,
    disabled: widget.disabled,
    onChanged: (ref) => onChanged(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  void _roles(List<PropositionRoleInput> roles) {
    _layout++;
    widget.onRoles(roles);
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form, disabled = widget.disabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reference('Proposition subject', form.subject, widget.onSubject),
        _reference('Predicate', form.predicate, widget.onPredicate),
        const Text('Choose the property or relation that defines this claim.'),
        _reference(
          'Represented context',
          form.context,
          widget.onContext,
          kind: RecordKind.representedContext,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('quantification', form.quantification)),
          initialValue: form.quantification.isEmpty
              ? null
              : form.quantification,
          decoration: const InputDecoration(labelText: 'Quantification'),
          items: const [
            DropdownMenuItem(value: 'particular', child: Text('Particular')),
            DropdownMenuItem(value: 'universal', child: Text('Universal')),
            DropdownMenuItem(value: 'exists', child: Text('Exists')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) widget.onQuantification(v);
                },
        ),
        const Text('Role order and repeated participants remain explicit.'),
        for (var i = 0; i < form.roles.length; i++)
          Card(
            key: ValueKey((_layout, i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    initialValue: form.roles[i].role,
                    enabled: !disabled,
                    decoration: const InputDecoration(labelText: 'Role name'),
                    onChanged: (v) {
                      final rows = [...form.roles], r = rows[i];
                      rows[i] = PropositionRoleInput(
                        role: v,
                        record: r.record,
                        universe: r.universe,
                      );
                      widget.onRoles(rows);
                    },
                  ),
                  RecordReferenceFields(
                    changes: widget.changes,
                    draft: widget.draft,
                    record: form.roles[i].record,
                    universe: form.roles[i].universe,
                    label: 'Participant',
                    disabled: disabled,
                    onChanged: (record, universe) {
                      final rows = [...form.roles];
                      rows[i] = PropositionRoleInput(
                        role: rows[i].role,
                        record: record,
                        universe: universe,
                      );
                      widget.onRoles(rows);
                    },
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: disabled || i == 0
                            ? null
                            : () {
                                final rows = [...form.roles],
                                    r = rows.removeAt(i);
                                rows.insert(i - 1, r);
                                _roles(rows);
                              },
                        child: const Text('Move earlier'),
                      ),
                      TextButton(
                        onPressed: disabled || i == form.roles.length - 1
                            ? null
                            : () {
                                final rows = [...form.roles],
                                    r = rows.removeAt(i);
                                rows.insert(i + 1, r);
                                _roles(rows);
                              },
                        child: const Text('Move later'),
                      ),
                      TextButton(
                        onPressed: disabled
                            ? null
                            : () => _roles([...form.roles]..removeAt(i)),
                        child: const Text('Remove role'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () => _roles([...form.roles, const PropositionRoleInput()]),
          child: const Text('Add role'),
        ),
        SwitchListTile(
          title: const Text('Include a value'),
          value: form.hasValue,
          onChanged: disabled ? null : widget.onHasValue,
        ),
        if (form.hasValue)
          ValueInputFields(
            input: form.value,
            changes: widget.changes,
            draft: widget.draft,
            original: form.original?.value,
            disabled: disabled,
            onChanged: widget.onValue,
            label: 'Proposition value',
          ),
      ],
    );
  }
}
