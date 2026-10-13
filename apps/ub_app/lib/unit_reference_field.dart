import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'saved_changes.dart';

/// A named unit choice with recoverable, exact advanced reference input.
class UnitReferenceField extends StatefulWidget {
  const UnitReferenceField({
    super.key,
    required this.changes,
    required this.draft,
    required this.unit,
    required this.disabled,
    required this.onChanged,
    this.label = 'Unit',
    this.optional = true,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final String unit, label;
  final bool disabled, optional;
  final ValueChanged<String> onChanged;
  @override
  State<UnitReferenceField> createState() => _UnitReferenceFieldState();
}

class _UnitReferenceFieldState extends State<UnitReferenceField> {
  late final TextEditingController _unit;
  @override
  void initState() {
    super.initState();
    _unit = TextEditingController(text: widget.unit);
  }

  @override
  void didUpdateWidget(UnitReferenceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_unit.text != widget.unit) _unit.text = widget.unit;
  }

  @override
  void dispose() {
    _unit.dispose();
    super.dispose();
  }

  String get _record {
    try {
      return unitChoiceRecord(widget.unit).value;
    } on FormatException {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DraftRecordChoiceField(
        changes: widget.changes,
        draft: widget.draft,
        kind: RecordKind.unit,
        label: widget.label,
        record: _record,
        universe: widget.changes.scope.universe.value,
        disabled: widget.disabled,
        onChanged: (ref) => widget.onChanged(unitFromChoice(ref).value),
      ),
      if (widget.optional && widget.unit.isNotEmpty)
        TextButton(
          onPressed: widget.disabled ? null : () => widget.onChanged(''),
          child: const Text('Remove unit'),
        ),
      ExpansionTile(
        title: const Text('Advanced references'),
        children: [
          TextField(
            controller: _unit,
            enabled: !widget.disabled,
            decoration: InputDecoration(
              labelText:
                  '${widget.label} ID${widget.optional ? ' (optional)' : ''}',
            ),
            onChanged: widget.onChanged,
          ),
        ],
      ),
    ],
  );
}
