import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

class SecretInputFields extends StatefulWidget {
  const SecretInputFields({
    super.key,
    required this.changes,
    required this.draft,
    required this.form,
    required this.disabled,
    required this.onChanged,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final UnfinishedSecretForm form;
  final bool disabled;
  final ValueChanged<UnfinishedSecretForm> onChanged;
  @override
  State<SecretInputFields> createState() => _SecretInputFieldsState();
}

class _SecretInputFieldsState extends State<SecretInputFields> {
  int _layout = 0;
  Widget _references(
    String label,
    List<ExpressionReferenceInput> refs,
    RecordKind? kind,
    ValueChanged<List<ExpressionReferenceInput>> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      for (var i = 0; i < refs.length; i++)
        Card(
          key: ValueKey((label, _layout, i)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                DraftRecordChoiceField(
                  changes: widget.changes,
                  draft: widget.draft,
                  kind: kind,
                  label: '$label ${i + 1}',
                  record: refs[i].record,
                  universe: refs[i].universe,
                  disabled: widget.disabled,
                  onChanged: (ref) {
                    final values = [...refs];
                    values[i] = ExpressionReferenceInput(
                      record: ref.record.value,
                      universe: ref.universe?.value ?? '',
                    );
                    change(values);
                  },
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: widget.disabled || i == 0
                          ? null
                          : () {
                              final values = [...refs],
                                  moved = values.removeAt(i);
                              values.insert(i - 1, moved);
                              _layout++;
                              change(values);
                            },
                      child: const Text('Move up'),
                    ),
                    TextButton(
                      onPressed: widget.disabled || i == refs.length - 1
                          ? null
                          : () {
                              final values = [...refs],
                                  moved = values.removeAt(i);
                              values.insert(i + 1, moved);
                              _layout++;
                              change(values);
                            },
                      child: const Text('Move down'),
                    ),
                    TextButton(
                      onPressed: widget.disabled
                          ? null
                          : () {
                              final values = [...refs]..removeAt(i);
                              _layout++;
                              change(values);
                            },
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () => change([...refs, const ExpressionReferenceInput()]),
        child: Text('Add to $label'),
      ),
    ],
  );
  Widget _text(
    String label,
    String value,
    ValueChanged<String> change, {
    int lines = 1,
  }) => TextFormField(
    initialValue: value,
    enabled: !widget.disabled,
    maxLines: lines,
    decoration: InputDecoration(labelText: label),
    onChanged: change,
  );
  @override
  Widget build(BuildContext context) {
    final form = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _references(
          'Facts and entries covered',
          form.scope,
          null,
          (refs) => widget.onChanged(form.copyWith(scope: refs)),
        ),
        const SizedBox(height: 16),
        _references(
          'Characters who know',
          form.fictionalKnowers,
          RecordKind.entity,
          (refs) => widget.onChanged(form.copyWith(fictionalKnowers: refs)),
        ),
        DropdownButtonFormField<bool>(
          initialValue: form.readerDisclosed,
          decoration: const InputDecoration(
            labelText: 'Has the reader been told?',
          ),
          items: const [
            DropdownMenuItem(value: false, child: Text('Not yet disclosed')),
            DropdownMenuItem(
              value: true,
              child: Text('Disclosed to the reader'),
            ),
          ],
          onChanged: widget.disabled
              ? null
              : (value) =>
                    widget.onChanged(form.copyWith(readerDisclosed: value)),
        ),
        SwitchListTile(
          title: const Text('Add concealment notes'),
          value: form.hasConcealment,
          onChanged: widget.disabled
              ? null
              : (value) =>
                    widget.onChanged(form.copyWith(hasConcealment: value)),
        ),
        if (form.hasConcealment)
          _text(
            'Concealment notes',
            form.concealment,
            (value) => widget.onChanged(form.copyWith(concealment: value)),
            lines: 3,
          ),
        DropdownButtonFormField<String>(
          initialValue: form.validityKind,
          decoration: const InputDecoration(
            labelText: 'When does this secret declaration apply?',
          ),
          items: [
            const DropdownMenuItem(
              value: 'unspecified',
              child: Text('Time scope unspecified'),
            ),
            const DropdownMenuItem(
              value: 'calendar_interval',
              child: Text('Authored calendar interval'),
            ),
            if (form.original != null)
              const DropdownMenuItem(
                value: 'retain',
                child: Text('Keep current authored time scope'),
              ),
          ],
          onChanged: widget.disabled
              ? null
              : (value) => widget.onChanged(form.copyWith(validityKind: value)),
        ),
        if (form.validityKind == 'calendar_interval') ...[
          const Text(
            'Start is inclusive; end is exclusive. Enter authored coordinates; this does not change the story clock.',
          ),
          DraftRecordChoiceField(
            changes: widget.changes,
            draft: widget.draft,
            kind: RecordKind.calendar,
            label: 'Calendar',
            record: form.calendar.isEmpty
                ? ''
                : form.calendar.replaceFirst('cal_', 'rec_'),
            universe: '',
            disabled: widget.disabled,
            onChanged: (ref) => widget.onChanged(
              form.copyWith(
                calendar: ref.record.value.replaceFirst('rec_', 'cal_'),
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Start explicitly unbounded'),
            value: form.startUnbounded,
            onChanged: widget.disabled
                ? null
                : (value) =>
                      widget.onChanged(form.copyWith(startUnbounded: value)),
          ),
          if (!form.startUnbounded)
            _text(
              'Start coordinate',
              form.start,
              (value) => widget.onChanged(form.copyWith(start: value)),
            ),
          SwitchListTile(
            title: const Text('End explicitly unbounded'),
            value: form.endUnbounded,
            onChanged: widget.disabled
                ? null
                : (value) =>
                      widget.onChanged(form.copyWith(endUnbounded: value)),
          ),
          if (!form.endUnbounded)
            _text(
              'End coordinate',
              form.end,
              (value) => widget.onChanged(form.copyWith(end: value)),
            ),
        ],
      ],
    );
  }
}
