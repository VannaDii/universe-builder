import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

/// Named local choices preserve explicit or omitted authored universe references.
class RecordReferenceFields extends StatefulWidget {
  const RecordReferenceFields({
    super.key,
    required this.changes,
    required this.draft,
    required this.record,
    required this.universe,
    required this.disabled,
    required this.onChanged,
    this.kind,
    this.label = 'Target record',
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final String record, universe, label;
  final RecordKind? kind;
  final bool disabled;
  final void Function(String record, String universe) onChanged;
  @override
  State<RecordReferenceFields> createState() => _RecordReferenceFieldsState();
}

class _RecordReferenceFieldsState extends State<RecordReferenceFields> {
  late final TextEditingController _record, _universe;
  @override
  void initState() {
    super.initState();
    _record = TextEditingController(text: widget.record);
    _universe = TextEditingController(text: widget.universe);
  }

  @override
  void didUpdateWidget(RecordReferenceFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_record.text != widget.record) _record.text = widget.record;
    if (_universe.text != widget.universe) _universe.text = widget.universe;
  }

  @override
  void dispose() {
    _record.dispose();
    _universe.dispose();
    super.dispose();
  }

  void _changed() => widget.onChanged(_record.text, _universe.text);
  Widget _field(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !widget.disabled,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DraftRecordChoiceField(
        changes: widget.changes,
        draft: widget.draft,
        kind: widget.kind,
        label: widget.label,
        record: widget.record,
        universe: widget.universe,
        disabled: widget.disabled,
        onChanged: (ref) {
          _record.text = ref.record.value;
          _universe.text = ref.universe?.value ?? '';
          _changed();
        },
      ),
      ExpansionTile(
        title: const Text('Advanced references'),
        children: [
          _field(_record, '${widget.label} ID'),
          _field(_universe, 'Target universe ID (optional)'),
        ],
      ),
    ],
  );
}
