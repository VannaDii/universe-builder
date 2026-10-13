import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'record_fields.dart';
import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

class EvidenceBasisFields extends StatefulWidget {
  const EvidenceBasisFields({
    super.key,
    required this.input,
    required this.original,
    required this.disabled,
    required this.onChanged,
    required this.changes,
    required this.draft,
  });
  final EvidenceBasisInput input;
  final EvidenceBasis original;
  final bool disabled;
  final ValueChanged<EvidenceBasisInput> onChanged;
  final SavedChanges changes;
  final SavedDraft draft;
  @override
  State<EvidenceBasisFields> createState() => _EvidenceBasisFieldsState();
}

class _EvidenceBasisFieldsState extends State<EvidenceBasisFields> {
  late final TextEditingController _note, _anchorRecord, _anchorUniverse;
  late String _kind;
  late bool _verified;
  @override
  void initState() {
    super.initState();
    _note = TextEditingController(text: widget.input.note);
    _anchorRecord = TextEditingController(text: widget.input.anchorRecord);
    _anchorUniverse = TextEditingController(text: widget.input.anchorUniverse);
    _kind = widget.input.kind;
    _verified = widget.input.verified;
  }

  @override
  void didUpdateWidget(EvidenceBasisFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_form.toWire().toText() == widget.input.toWire().toText()) return;
    _note.text = widget.input.note;
    _anchorRecord.text = widget.input.anchorRecord;
    _anchorUniverse.text = widget.input.anchorUniverse;
    _kind = widget.input.kind;
    _verified = widget.input.verified;
  }

  EvidenceBasisInput get _form => EvidenceBasisInput(
    kind: _kind,
    note: _note.text,
    anchorRecord: _anchorRecord.text,
    anchorUniverse: _anchorUniverse.text,
    verified: _verified,
  );
  void _changed() => widget.onChanged(_form);
  @override
  void dispose() {
    _note.dispose();
    _anchorRecord.dispose();
    _anchorUniverse.dispose();
    super.dispose();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool multiline = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextField(
      controller: controller,
      enabled: !widget.disabled,
      maxLines: multiline ? null : 1,
      decoration: InputDecoration(labelText: label),
      onChanged: (_) => _changed(),
    ),
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        key: ValueKey(_kind),
        initialValue: _kind,
        decoration: const InputDecoration(labelText: 'Source basis'),
        items: const [
          DropdownMenuItem(
            value: 'retain',
            child: Text('Keep current exact basis'),
          ),
          DropdownMenuItem(
            value: 'author_decision',
            child: Text('Author decision'),
          ),
          DropdownMenuItem(
            value: 'source_anchor',
            child: Text('Source anchor'),
          ),
          DropdownMenuItem(
            value: 'imported_claim',
            child: Text('Imported claim'),
          ),
        ],
        onChanged: widget.disabled
            ? null
            : (v) {
                if (v == null) return;
                setState(() => _kind = v);
                _changed();
              },
      ),
      if (_kind == 'retain') ...[
        ExactFields(value: widget.original.toWire()),
        if (widget.original is EventEffectBasis ||
            widget.original is DerivationBasis ||
            widget.original is InstanceInitializationBasis)
          const Text(
            'This basis comes from its event, evaluator or initialization workflow. Keeping it retains those exact links.',
          ),
      ],
      if (_kind == 'author_decision')
        _field(_note, 'Author decision note', multiline: true),
      if (_kind == 'source_anchor') ...[
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.anchor,
          label: 'Source anchor',
          record: _anchorRecord.text,
          universe: _anchorUniverse.text,
          disabled: widget.disabled,
          onChanged: (ref) {
            _anchorRecord.text = ref.record.value;
            _anchorUniverse.text = ref.universe?.value ?? '';
            _changed();
          },
        ),
        ExpansionTile(
          title: const Text('Advanced anchor reference'),
          children: [
            _field(_anchorRecord, 'Source anchor record ID'),
            _field(_anchorUniverse, 'Anchor universe ID (optional)'),
          ],
        ),
        CheckboxListTile(
          title: const Text('Content match recorded as verified'),
          value: _verified,
          onChanged: widget.disabled
              ? null
              : (v) {
                  setState(() => _verified = v!);
                  _changed();
                },
        ),
        const Text(
          'This flag does not establish truth or entailment. Validation checks the retained source and anchor.',
        ),
      ],
      if (_kind == 'imported_claim')
        const Text(
          'An imported claim retains its unresolved provenance; it does not become a sourced fact.',
        ),
    ],
  );
}
