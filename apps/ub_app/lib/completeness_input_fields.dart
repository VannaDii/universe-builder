import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'connection.dart';
import 'draft_record_choices.dart';
import 'draft_record_choice_field.dart';
import 'record_browser.dart';
import 'scope_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class CompletenessInputFields extends StatefulWidget {
  const CompletenessInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onSubject,
    required this.onPredicate,
    required this.onKind,
    required this.onObserver,
    required this.onMembers,
    required this.onScope,
    required this.onValidity,
    required this.onBusy,
  });
  final UnfinishedCompletenessForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<ExpressionReferenceInput> onSubject;
  final ValueChanged<String> onPredicate, onKind, onObserver;
  final ValueChanged<List<ExpressionReferenceInput>> onMembers;
  final ValueChanged<ScopeInput> onScope;
  final ValueChanged<TemporalValidityInput> onValidity;
  final ValueChanged<bool> onBusy;
  @override
  State<CompletenessInputFields> createState() =>
      _CompletenessInputFieldsState();
}

class _CompletenessInputFieldsState extends State<CompletenessInputFields> {
  late final TextEditingController _predicate;
  int _layout = 0;
  String? _error;
  @override
  void initState() {
    super.initState();
    _predicate = TextEditingController(text: widget.form.predicate);
  }

  @override
  void didUpdateWidget(CompletenessInputFields old) {
    super.didUpdateWidget(old);
    if (_predicate.text != widget.form.predicate) {
      _predicate.text = widget.form.predicate;
    }
  }

  @override
  void dispose() {
    _predicate.dispose();
    super.dispose();
  }

  Future<void> _choosePredicate(RecordRef ref) async {
    widget.onBusy(true);
    try {
      if (ref.universe != null && ref.universe != widget.changes.scope.universe) {
        throw const FormatException('Choose a predicate in this universe.');
      }
      final context = await openDraftChoiceContext(
        widget.changes,
        widget.draft,
      );
      final row = await readContextRecord(
        session: widget.changes.session,
        universe: LibraryEntry(
          widget.changes.scope.universe,
          widget.changes.universe.value,
        ),
        context: context,
        record: ref.record,
      );
      if (row.payload case PropertyRecord(:final namespace, :final key)) {
        if (mounted) {
          _predicate.text = '$namespace:$key';
          widget.onPredicate(_predicate.text);
        }
      } else {
        throw const FormatException('Choose a property definition.');
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the selected property. Check access and retry.',
        );
      }
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  Widget _reference(
    String label,
    ExpressionReferenceInput value,
    ValueChanged<ExpressionReferenceInput> change, {
    Key? key,
  }) => DraftRecordChoiceField(
    key: key,
    changes: widget.changes,
    draft: widget.draft,
    kind: null,
    label: label,
    record: value.record,
    universe: value.universe,
    disabled: widget.disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  void _members(List<ExpressionReferenceInput> members) {
    _layout++;
    widget.onMembers(members);
  }

  @override
  Widget build(BuildContext context) {
    final form = widget.form, disabled = widget.disabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reference('Collection subject', form.subject, widget.onSubject),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.property,
          label: 'Collection property',
          record: '',
          universe: '',
          disabled: disabled,
          onChanged: _choosePredicate,
        ),
        TextField(
          controller: _predicate,
          enabled: !disabled,
          decoration: const InputDecoration(
            labelText: 'Authored predicate (namespace:key)',
          ),
          onChanged: widget.onPredicate,
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('kind', form.kind)),
          initialValue: form.kind.isEmpty ? null : form.kind,
          decoration: const InputDecoration(labelText: 'Completeness kind'),
          items: const [
            DropdownMenuItem(
              value: 'objective_reality',
              child: Text('Objective reality'),
            ),
            DropdownMenuItem(
              value: 'observer_known',
              child: Text('Known to an observer'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) widget.onKind(v);
                },
        ),
        if (form.kind == 'observer_known')
          DraftRecordChoiceField(
            changes: widget.changes,
            draft: widget.draft,
            kind: null,
            label: 'Observer',
            record: form.observer,
            universe: widget.changes.scope.universe.value,
            disabled: disabled,
            onChanged: (ref) => widget.onObserver(ref.record.value),
          ),
        const Text('Declared complete members'),
        for (var i = 0; i < form.members.length; i++)
          Card(
            key: ValueKey((_layout, 'member', i)),
            child: Column(
              children: [
                _reference('Member ${i + 1}', form.members[i], (v) {
                  final members = [...form.members];
                  members[i] = v;
                  widget.onMembers(members);
                }),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: disabled || i == 0
                          ? null
                          : () {
                              final members = [...form.members],
                                  member = members.removeAt(i);
                              members.insert(i - 1, member);
                              _members(members);
                            },
                      child: const Text('Move earlier'),
                    ),
                    TextButton(
                      onPressed: disabled || i == form.members.length - 1
                          ? null
                          : () {
                              final members = [...form.members],
                                  member = members.removeAt(i);
                              members.insert(i + 1, member);
                              _members(members);
                            },
                      child: const Text('Move later'),
                    ),
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => _members([...form.members]..removeAt(i)),
                      child: const Text('Remove member'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () => _members([
                  ...form.members,
                  const ExpressionReferenceInput(),
                ]),
          child: const Text('Add member'),
        ),
        if (form.members.isEmpty)
          const Text(
            'This declaration has no members. Choosing a completeness kind makes the empty list an explicit scoped declaration.',
          ),
        ExpansionTile(
          title: const Text('Completeness scope'),
          children: [
            ScopeInputFields(
              input: form.scope,
              changes: widget.changes,
              draft: widget.draft,
              disabled: disabled,
              onChanged: widget.onScope,
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('validity-kind', form.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(form.validity.kind)
              ? form.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Completeness validity'),
          items: const [
            DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
            DropdownMenuItem(value: 'unspecified', child: Text('Unspecified')),
            DropdownMenuItem(
              value: 'condition_dependent',
              child: Text('Condition dependent'),
            ),
            DropdownMenuItem(
              value: 'temporal',
              child: Text('Temporal validity'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) {
                    widget.onValidity(
                      v == 'temporal'
                          ? const TemporalValidityInput()
                          : TemporalValidityInput(kind: v),
                    );
                  }
                },
        ),
        if (!{
          'unknown',
          'unspecified',
          'condition_dependent',
        }.contains(form.validity.kind))
          TemporalValidityFields(
            input: form.validity,
            originalAmounts: temporalOriginalAmounts(form.original?.validity),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: widget.onValidity,
          ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}
