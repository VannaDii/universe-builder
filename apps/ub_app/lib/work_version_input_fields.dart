import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';

class WorkVersionInputFields extends StatefulWidget {
  const WorkVersionInputFields({
    super.key,
    required this.form,
    required this.continuities,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedWorkVersionForm form;
  final List<ContinuitySummary> continuities;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedWorkVersionForm> onChanged;
  @override
  State<WorkVersionInputFields> createState() => _WorkVersionInputFieldsState();
}

class _WorkVersionInputFieldsState extends State<WorkVersionInputFields> {
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
    void change(UnfinishedWorkVersionForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _reference(
          'External work',
          f.work,
          (v) => change(f.copyWith(work: v)),
          kind: RecordKind.work,
        ),
        TextFormField(
          initialValue: f.versionLabel,
          enabled: !disabled,
          decoration: const InputDecoration(labelText: 'Edition label'),
          onChanged: (v) => change(f.copyWith(versionLabel: v)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('binding', f.bindingKind)),
          initialValue: f.bindingKind.isEmpty ? null : f.bindingKind,
          decoration: const InputDecoration(labelText: 'Canon binding'),
          items: const [
            DropdownMenuItem(value: 'unbound', child: Text('Unbound')),
            DropdownMenuItem(
              value: 'bound',
              child: Text('One pinned continuity'),
            ),
            DropdownMenuItem(
              value: 'segments',
              child: Text('Separately pinned segments'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(bindingKind: v));
                },
        ),
        if (f.bindingKind == 'bound')
          _PinFields(
            continuities: widget.continuities,
            continuity: f.continuity,
            revision: f.revision,
            disabled: disabled,
            onChanged: (c, r) => change(f.copyWith(continuity: c, revision: r)),
          ),
        if (f.bindingKind == 'segments') ...[
          for (var i = 0; i < f.segments.length; i++)
            Card(
              semanticContainer: false,
              key: ValueKey((_layout, i)),
              child: Column(
                children: [
                  TextFormField(
                    initialValue: f.segments[i].segment,
                    enabled: !disabled,
                    decoration: InputDecoration(
                      labelText: 'Segment ${i + 1} label',
                    ),
                    onChanged: (v) {
                      final rows = [...f.segments];
                      rows[i] = rows[i].copyWith(segment: v);
                      change(f.copyWith(segments: rows));
                    },
                  ),
                  _PinFields(
                    continuities: widget.continuities,
                    continuity: f.segments[i].continuity,
                    revision: f.segments[i].revision,
                    disabled: disabled,
                    onChanged: (c, r) {
                      final rows = [...f.segments];
                      rows[i] = rows[i].copyWith(continuity: c, revision: r);
                      change(f.copyWith(segments: rows));
                    },
                  ),
                  _controls(
                    i,
                    f.segments.length,
                    (offset) {
                      final rows = [...f.segments], row = rows.removeAt(i);
                      rows.insert(i + offset, row);
                      _layout++;
                      change(f.copyWith(segments: rows));
                    },
                    () {
                      _layout++;
                      change(
                        f.copyWith(segments: [...f.segments]..removeAt(i)),
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
                        segments: [...f.segments, const WorkSegmentInput()],
                      ),
                    );
                  },
            child: const Text('Add segment'),
          ),
        ],
      ],
    );
  }
}

class _PinFields extends StatefulWidget {
  const _PinFields({
    required this.continuities,
    required this.continuity,
    required this.revision,
    required this.disabled,
    required this.onChanged,
  });
  final List<ContinuitySummary> continuities;
  final String continuity, revision;
  final bool disabled;
  final void Function(String, String) onChanged;
  @override
  State<_PinFields> createState() => _PinFieldsState();
}

class _PinFieldsState extends State<_PinFields> {
  late final TextEditingController _revision;
  @override
  void initState() {
    super.initState();
    _revision = TextEditingController(text: widget.revision);
  }

  @override
  void didUpdateWidget(_PinFields old) {
    super.didUpdateWidget(old);
    if (_revision.text != widget.revision) _revision.text = widget.revision;
  }

  @override
  void dispose() {
    _revision.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey(widget.continuity),
        initialValue: widget.continuity.isEmpty ? null : widget.continuity,
        decoration: const InputDecoration(labelText: 'Pinned continuity'),
        items: [
          for (final c in widget.continuities)
            DropdownMenuItem(value: c.id.value, child: Text(c.name)),
          if (widget.continuity.isNotEmpty &&
              !widget.continuities.any((c) => c.id.value == widget.continuity))
            DropdownMenuItem(
              value: widget.continuity,
              child: const Text('Saved continuity (not in the loaded list)'),
            ),
        ],
        onChanged: widget.disabled
            ? null
            : (v) {
                if (v != null) {
                  final chosen = widget.continuities
                      .where((c) => c.id.value == v)
                      .firstOrNull;
                  if (chosen != null) {
                    _revision.text = chosen.revisionId.value;
                    widget.onChanged(v, _revision.text);
                  }
                }
              },
      ),
      const Text(
        'Choosing a continuity captures its currently listed revision. Retain this pin or enter an exact historical revision; reopening does not advance it.',
      ),
      TextField(
        controller: _revision,
        enabled: !widget.disabled,
        decoration: const InputDecoration(labelText: 'Pinned canon revision'),
        onChanged: (v) => widget.onChanged(widget.continuity, v),
      ),
    ],
  );
}
