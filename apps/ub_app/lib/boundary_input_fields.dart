import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'expression_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'scope_input_fields.dart';
import 'connection.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'temporal_validity_draft.dart';

class BoundaryInputFields extends StatefulWidget {
  const BoundaryInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusy,
  });
  final UnfinishedBoundaryForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedBoundaryForm> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<BoundaryInputFields> createState() => _BoundaryInputFieldsState();
}

class _BoundaryInputFieldsState extends State<BoundaryInputFields> {
  int _layout = 0;
  late final TextEditingController _predicate;
  String? _error;
  @override
  void initState() {
    super.initState();
    _predicate = TextEditingController(text: widget.form.predicate);
  }

  @override
  void didUpdateWidget(BoundaryInputFields old) {
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
      if (ref.universe != null &&
          ref.universe != widget.changes.scope.universe) {
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
      final predicate = switch (row.payload) {
        PropertyRecord(:final namespace, :final key) => '$namespace:$key',
        RelationRecord(:final namespace, :final key) => '$namespace:$key',
        _ => throw const FormatException(
          'Choose a property or relation definition.',
        ),
      };
      {
        if (mounted) {
          _predicate.text = predicate;
          setState(() => _error = null);
          widget.onChanged(widget.form.copyWith(predicate: predicate));
        }
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the selected predicate. Check access and retry.',
        );
      }
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: input.record,
    universe: input.universe,
    disabled: widget.disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  Widget _controls(
    int i,
    int length,
    void Function(int) move,
    VoidCallback remove,
  ) => Wrap(
    children: [
      TextButton(
        onPressed: widget.disabled || i == 0 ? null : () => move(-1),
        child: const Text('Move earlier'),
      ),
      TextButton(
        onPressed: widget.disabled || i == length - 1 ? null : () => move(1),
        child: const Text('Move later'),
      ),
      TextButton(
        onPressed: widget.disabled ? null : remove,
        child: const Text('Remove entry'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedBoundaryForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: f.key,
          enabled: !disabled,
          decoration: const InputDecoration(labelText: 'Boundary name'),
          onChanged: (v) => change(f.copyWith(key: v)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('area', f.areaKind)),
          initialValue: f.areaKind.isEmpty ? null : f.areaKind,
          decoration: const InputDecoration(labelText: 'Boundary area'),
          items: const [
            DropdownMenuItem(value: 'record', child: Text('A record')),
            DropdownMenuItem(value: 'predicate', child: Text('A predicate')),
            DropdownMenuItem(
              value: 'category',
              child: Text('An entity category'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(areaKind: v));
                },
        ),
        if (f.areaKind == 'record')
          _reference(
            'Boundary record',
            f.record,
            (v) => change(f.copyWith(record: v)),
          ),
        if (f.areaKind == 'category')
          _reference(
            'Entity category',
            ExpressionReferenceInput(
              record: f.category,
              universe: widget.changes.scope.universe.value,
            ),
            (v) => change(f.copyWith(category: v.record)),
            kind: RecordKind.entityType,
          ),
        if (f.areaKind == 'predicate') ...[
          for (final kind in [RecordKind.property, RecordKind.relation])
            DraftRecordChoiceField(
              changes: widget.changes,
              draft: widget.draft,
              kind: kind,
              label: kind == RecordKind.property
                  ? 'Predicate property'
                  : 'Predicate relation',
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
            onChanged: (v) => change(f.copyWith(predicate: v)),
          ),
          SwitchListTile(
            title: const Text('Limit to a subject'),
            value: f.subjectEnabled,
            onChanged: disabled
                ? null
                : (v) => change(f.copyWith(subjectEnabled: v)),
          ),
          if (f.subjectEnabled)
            _reference(
              'Predicate subject',
              f.subject,
              (v) => change(f.copyWith(subject: v)),
            ),
        ],
        DropdownButtonFormField<String>(
          key: ValueKey(('mode', f.mode)),
          initialValue: f.mode.isEmpty ? null : f.mode,
          decoration: const InputDecoration(labelText: 'Boundary mode'),
          items: const [
            DropdownMenuItem(value: 'fixed', child: Text('Fixed')),
            DropdownMenuItem(
              value: 'open_with_constraints',
              child: Text('Open with constraints'),
            ),
            DropdownMenuItem(
              value: 'proposal_required',
              child: Text('Proposal required'),
            ),
            DropdownMenuItem(
              value: 'author_reserved',
              child: Text('Author reserved'),
            ),
            DropdownMenuItem(
              value: 'intentionally_unresolved',
              child: Text('Intentionally unresolved'),
            ),
            DropdownMenuItem(value: 'prohibited', child: Text('Prohibited')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(mode: v));
                },
        ),
        const Text('Declared constraints'),
        for (var i = 0; i < f.constraints.length; i++)
          Card(
            key: ValueKey((_layout, 'constraint', i)),
            child: Column(
              children: [
                ExpressionInputFields(
                  input: f.constraints[i],
                  changes: widget.changes,
                  draft: widget.draft,
                  disabled: disabled,
                  onChanged: (v) {
                    final rows = [...f.constraints];
                    rows[i] = v;
                    change(f.copyWith(constraints: rows));
                  },
                ),
                _controls(
                  i,
                  f.constraints.length,
                  (offset) {
                    final rows = [...f.constraints], row = rows.removeAt(i);
                    rows.insert(i + offset, row);
                    _layout++;
                    change(f.copyWith(constraints: rows));
                  },
                  () {
                    _layout++;
                    change(
                      f.copyWith(constraints: [...f.constraints]..removeAt(i)),
                    );
                  },
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      constraints: [...f.constraints, ExpressionInput()],
                    ),
                  );
                },
          child: const Text('Add constraint'),
        ),
        ExpansionTile(
          title: const Text('Boundary scope'),
          children: [
            ScopeInputFields(
              input: f.scope,
              changes: widget.changes,
              draft: widget.draft,
              disabled: disabled,
              onChanged: (v) => change(f.copyWith(scope: v)),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('validity', f.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(f.validity.kind)
              ? f.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Boundary validity'),
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
                    change(
                      f.copyWith(
                        validity: v == 'temporal'
                            ? const TemporalValidityInput()
                            : TemporalValidityInput(kind: v),
                      ),
                    );
                  }
                },
        ),
        if (!{
          'unknown',
          'unspecified',
          'condition_dependent',
        }.contains(f.validity.kind))
          TemporalValidityFields(
            input: f.validity,
            originalAmounts: temporalOriginalAmounts(f.original?.validity),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: (v) => change(f.copyWith(validity: v)),
          ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}
