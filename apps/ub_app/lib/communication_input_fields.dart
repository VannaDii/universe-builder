import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class CommunicationInputFields extends StatefulWidget {
  const CommunicationInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedCommunicationForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedCommunicationForm> onChanged;
  @override
  State<CommunicationInputFields> createState() =>
      _CommunicationInputFieldsState();
}

class _CommunicationInputFieldsState extends State<CommunicationInputFields> {
  int _layout = 0;
  Widget _reference(
    String label,
    ExpressionReferenceInput value,
    RecordKind? kind,
    ValueChanged<ExpressionReferenceInput> change,
  ) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
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
  Widget _list(
    String label,
    List<ExpressionReferenceInput> values,
    RecordKind? kind,
    ValueChanged<List<ExpressionReferenceInput>> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      for (var i = 0; i < values.length; i++)
        Card(
          key: ValueKey((_layout, label, i)),
          child: Column(
            children: [
              _reference('$label ${i + 1}', values[i], kind, (v) {
                final rows = [...values];
                rows[i] = v;
                change(rows);
              }),
              Wrap(
                children: [
                  TextButton(
                    onPressed: widget.disabled || i == 0
                        ? null
                        : () {
                            final rows = [...values], row = rows.removeAt(i);
                            rows.insert(i - 1, row);
                            _layout++;
                            change(rows);
                          },
                    child: const Text('Move earlier'),
                  ),
                  TextButton(
                    onPressed: widget.disabled || i == values.length - 1
                        ? null
                        : () {
                            final rows = [...values], row = rows.removeAt(i);
                            rows.insert(i + 1, row);
                            _layout++;
                            change(rows);
                          },
                    child: const Text('Move later'),
                  ),
                  TextButton(
                    onPressed: widget.disabled
                        ? null
                        : () {
                            _layout++;
                            change([...values]..removeAt(i));
                          },
                    child: const Text('Remove entry'),
                  ),
                ],
              ),
            ],
          ),
        ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () {
                _layout++;
                change([...values, const ExpressionReferenceInput()]);
              },
        child: Text('Add ${label.toLowerCase()}'),
      ),
    ],
  );
  Widget _time(
    String label,
    TemporalValidityInput input,
    TemporalExpression? original,
    ValueChanged<TemporalValidityInput> change,
  ) => ExpansionTile(
    title: Text(label),
    children: [
      TemporalValidityFields(
        input: input,
        expressionOnly: true,
        originalAmounts: temporalOriginalAmounts(
          original == null ? null : InstantValidity(original),
        ),
        changes: widget.changes,
        draft: widget.draft,
        disabled: widget.disabled,
        onChanged: change,
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedCommunicationForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reference(
          'Sender',
          f.sender,
          RecordKind.entity,
          (v) => change(f.copyWith(sender: v)),
        ),
        const Text(
          'Recipient and content order and repeated entries remain explicit. Intended recipients do not establish actual receipt.',
        ),
        _list(
          'Intended recipient',
          f.intendedRecipients,
          RecordKind.entity,
          (v) => change(f.copyWith(intendedRecipients: v)),
        ),
        _list(
          'Actual recipient',
          f.actualRecipients,
          RecordKind.entity,
          (v) => change(f.copyWith(actualRecipients: v)),
        ),
        _list(
          'Content',
          f.content,
          null,
          (v) => change(f.copyWith(content: v)),
        ),
        SwitchListTile(
          title: const Text('Include a channel'),
          value: f.channelEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(channelEnabled: v)),
        ),
        if (f.channelEnabled)
          TextFormField(
            initialValue: f.channel,
            enabled: !disabled,
            decoration: const InputDecoration(labelText: 'Authored channel'),
            onChanged: (v) => change(f.copyWith(channel: v)),
          ),
        DropdownButtonFormField<bool>(
          key: ValueKey(('distorted', f.distorted)),
          initialValue: f.distorted,
          decoration: const InputDecoration(labelText: 'Distortion'),
          items: const [
            DropdownMenuItem(value: true, child: Text('Distorted')),
            DropdownMenuItem(value: false, child: Text('Not distorted')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(distorted: v));
                },
        ),
        _time(
          'Sent time',
          f.sentAt,
          f.original?.sentAt,
          (v) => change(f.copyWith(sentAt: v)),
        ),
        SwitchListTile(
          title: const Text('Include a receipt time'),
          value: f.receivedEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(receivedEnabled: v)),
        ),
        if (f.receivedEnabled)
          _time(
            'Receipt time',
            f.receivedAt,
            f.original?.receivedAt,
            (v) => change(f.copyWith(receivedAt: v)),
          ),
        if (f.actualRecipients.isNotEmpty && !f.receivedEnabled)
          const Text(
            'Actual recipients require a receipt time. Unfinished fields can still be saved.',
          ),
      ],
    );
  }
}
