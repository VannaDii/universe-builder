import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';

class SagaInputFields extends StatefulWidget {
  const SagaInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedSagaForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedSagaForm> onChanged;
  @override
  State<SagaInputFields> createState() => _SagaInputFieldsState();
}

class _SagaInputFieldsState extends State<SagaInputFields> {
  int _layout = 0;
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
    void change(UnfinishedSagaForm v) => widget.onChanged(v);
    Widget text(String label, String value, ValueChanged<String> callback) =>
        TextFormField(
          initialValue: value,
          enabled: !disabled,
          decoration: InputDecoration(labelText: label),
          onChanged: callback,
        );
    Widget controls<T>(int i, List<T> values, ValueChanged<List<T>> callback) =>
        _controls(
          i,
          values.length,
          (offset) {
            final rows = [...values], row = rows.removeAt(i);
            rows.insert(i + offset, row);
            _layout++;
            callback(rows);
          },
          () {
            _layout++;
            callback([...values]..removeAt(i));
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.membershipTarget == null) ...[
          text('Saga title', f.title, (v) => change(f.copyWith(title: v))),
          const Text('Saga labels'),
          for (var i = 0; i < f.labels.length; i++)
            Card(
              semanticContainer: false,
              key: ValueKey((_layout, 'label', i)),
              child: Column(
                children: [
                  text('Label language', f.labels[i].language, (v) {
                    final rows = [...f.labels];
                    rows[i] = PropertyLabelInput(
                      language: v,
                      text: rows[i].text,
                    );
                    change(f.copyWith(labels: rows));
                  }),
                  text('Label text', f.labels[i].text, (v) {
                    final rows = [...f.labels];
                    rows[i] = PropertyLabelInput(
                      language: rows[i].language,
                      text: v,
                    );
                    change(f.copyWith(labels: rows));
                  }),
                  controls(i, f.labels, (v) => change(f.copyWith(labels: v))),
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
                        labels: [...f.labels, const PropertyLabelInput()],
                      ),
                    );
                  },
            child: const Text('Add label'),
          ),
        ] else ...[
          DraftRecordChoiceField(
            changes: widget.changes,
            draft: widget.draft,
            kind: RecordKind.saga,
            label: 'Published saga',
            record: f.membershipTarget!.record,
            universe: f.membershipTarget!.universe,
            disabled: true,
            onChanged: (_) {},
          ),
          const Text(
            'Set one work-and-role membership. A matching pair updates its order; a different role adds another membership and retains prior roles.',
          ),
        ],
        const Text('Work memberships'),
        for (var i = 0; i < f.memberships.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, 'membership', i)),
            child: Column(
              children: [
                Builder(
                  builder: (context) {
                    final m = f.memberships[i];
                    void membership(SagaMembershipInput v) {
                      final rows = [...f.memberships];
                      rows[i] = v;
                      change(f.copyWith(memberships: rows));
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _reference(
                          'Member work ${i + 1}',
                          m.work,
                          (v) => membership(m.copyWith(work: v)),
                          kind: RecordKind.work,
                        ),
                        text(
                          'Membership role',
                          m.role,
                          (v) => membership(m.copyWith(role: v)),
                        ),
                        SwitchListTile(
                          title: const Text('Include an order value'),
                          value: m.orderEnabled,
                          onChanged: disabled
                              ? null
                              : (v) => membership(m.copyWith(orderEnabled: v)),
                        ),
                        if (m.orderEnabled)
                          text(
                            'Authored order',
                            m.order,
                            (v) => membership(m.copyWith(order: v)),
                          ),
                      ],
                    );
                  },
                ),
                if (f.membershipTarget == null)
                  controls(
                    i,
                    f.memberships,
                    (v) => change(f.copyWith(memberships: v)),
                  ),
              ],
            ),
          ),
        if (f.membershipTarget == null)
          TextButton(
            onPressed: disabled
                ? null
                : () {
                    _layout++;
                    change(
                      f.copyWith(
                        memberships: [
                          ...f.memberships,
                          const SagaMembershipInput(),
                        ],
                      ),
                    );
                  },
            child: const Text('Add work membership'),
          ),
      ],
    );
  }
}
