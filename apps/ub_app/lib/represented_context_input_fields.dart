import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';

class RepresentedContextInputFields extends StatefulWidget {
  const RepresentedContextInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedRepresentedContextForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedRepresentedContextForm> onChanged;
  @override
  State<RepresentedContextInputFields> createState() =>
      _RepresentedContextInputFieldsState();
}

class _RepresentedContextInputFieldsState
    extends State<RepresentedContextInputFields> {
  int _layout = 0;
  Widget _text(String label, String value, ValueChanged<String> change) =>
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextFormField(
          key: ValueKey(label),
          initialValue: value,
          enabled: !widget.disabled,
          decoration: InputDecoration(labelText: label),
          onChanged: change,
        ),
      );
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
  @override
  Widget build(BuildContext context) {
    final f = widget.form, c = f.chronology, disabled = widget.disabled;
    void change(UnfinishedRepresentedContextForm v) => widget.onChanged(v);
    void clock(ChronologyInput v) => change(f.copyWith(chronology: v));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('kind', f.kind)),
          initialValue: f.kind.isEmpty ? null : f.kind,
          decoration: const InputDecoration(labelText: 'Context kind'),
          items: const [
            DropdownMenuItem(value: 'objective', child: Text('Objective')),
            DropdownMenuItem(value: 'character', child: Text('Character')),
            DropdownMenuItem(value: 'source', child: Text('Source')),
            DropdownMenuItem(value: 'narrator', child: Text('Narrator')),
            DropdownMenuItem(
              value: 'authored',
              child: Text('Authored context'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(kind: v));
                },
        ),
        if (f.kind == 'authored')
          _text(
            'Authored context label',
            f.authoredLabel,
            (v) => change(f.copyWith(authoredLabel: v)),
          ),
        if (f.kind == 'character')
          _reference(
            'Character',
            f.reference,
            RecordKind.entity,
            (v) => change(f.copyWith(reference: v)),
          ),
        if (f.kind == 'source')
          _reference(
            'Source',
            f.reference,
            RecordKind.source,
            (v) => change(f.copyWith(reference: v)),
          ),
        if (f.kind == 'narrator')
          _reference(
            'Narrator',
            f.reference,
            null,
            (v) => change(f.copyWith(reference: v)),
          ),
        SwitchListTile(
          title: const Text('Include a parent context'),
          value: f.parentEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(parentEnabled: v)),
        ),
        if (f.parentEnabled)
          _reference(
            'Parent context',
            f.parent,
            RecordKind.representedContext,
            (v) => change(f.copyWith(parent: v)),
          ),
        const Text('Display labels'),
        for (var i = 0; i < f.labels.length; i++)
          Card(
            key: ValueKey((_layout, 'label', i)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _text('Language', f.labels[i].language, (v) {
                    final rows = [...f.labels];
                    rows[i] = PropertyLabelInput(
                      language: v,
                      text: rows[i].text,
                    );
                    change(f.copyWith(labels: rows));
                  }),
                  _text('Label', f.labels[i].text, (v) {
                    final rows = [...f.labels];
                    rows[i] = PropertyLabelInput(
                      language: rows[i].language,
                      text: v,
                    );
                    change(f.copyWith(labels: rows));
                  }),
                  TextButton(
                    onPressed: disabled
                        ? null
                        : () {
                            _layout++;
                            change(
                              f.copyWith(labels: [...f.labels]..removeAt(i)),
                            );
                          },
                    child: const Text('Remove label'),
                  ),
                ],
              ),
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
          child: const Text('Add display label'),
        ),
        SwitchListTile(
          title: const Text('Include an authored clock'),
          value: c.enabled,
          onChanged: disabled ? null : (v) => clock(c.copyWith(enabled: v)),
        ),
        if (c.enabled) ...[
          DraftRecordChoiceField(
            changes: widget.changes,
            draft: widget.draft,
            kind: RecordKind.calendar,
            label: 'Clock calendar',
            record: c.calendar.isEmpty
                ? ''
                : calendarChoiceRecord(c.calendar).value,
            universe: widget.changes.scope.universe.value,
            disabled: disabled,
            onChanged: (ref) =>
                clock(c.copyWith(calendar: calendarFromChoice(ref).value)),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey(('clock', c.system)),
            initialValue: c.system.isEmpty ? null : c.system,
            decoration: const InputDecoration(labelText: 'Clock system'),
            items: const [
              DropdownMenuItem(value: 'gregorian', child: Text('Gregorian')),
              DropdownMenuItem(
                value: 'fictional',
                child: Text('Fictional ticks'),
              ),
            ],
            onChanged: disabled
                ? null
                : (v) {
                    if (v != null) clock(c.copyWith(system: v));
                  },
          ),
          if (c.system == 'gregorian')
            _text(
              'Offset in seconds',
              c.offsetSeconds,
              (v) => clock(c.copyWith(offsetSeconds: v)),
            ),
          if (c.system == 'fictional') ...[
            _text(
              'Tick label',
              c.tickLabel,
              (v) => clock(c.copyWith(tickLabel: v)),
            ),
            SwitchListTile(
              title: const Text('Include ticks per month'),
              value: c.ticksPerMonthEnabled,
              onChanged: disabled
                  ? null
                  : (v) => clock(c.copyWith(ticksPerMonthEnabled: v)),
            ),
            if (c.ticksPerMonthEnabled)
              _text(
                'Ticks per month',
                c.ticksPerMonth,
                (v) => clock(c.copyWith(ticksPerMonth: v)),
              ),
          ],
          _text(
            c.system == 'gregorian'
                ? 'First interaction timestamp (with UTC offset)'
                : 'First interaction tick',
            c.firstInteraction,
            (v) => clock(c.copyWith(firstInteraction: v)),
          ),
          _text(
            c.system == 'gregorian'
                ? 'Current story timestamp (with UTC offset)'
                : 'Current story tick',
            c.current,
            (v) => clock(c.copyWith(current: v)),
          ),
          const Text(
            'Enter authored timestamps or ticks. No current timestamp or clock mapping is supplied automatically.',
          ),
        ],
      ],
    );
  }
}
