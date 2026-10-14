import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'saved_changes.dart';

/// Factual scope controls retain incomplete reference and world inputs.
class ScopeInputFields extends StatefulWidget {
  const ScopeInputFields({
    super.key,
    this.applicabilityOnly = false,
    this.contextReadOnly = false,
    this.explicitWorldScope = false,
    required this.input,
    required this.disabled,
    required this.onChanged,
    required this.changes,
    required this.draft,
  });
  final ScopeInput input;
  final bool disabled, applicabilityOnly, explicitWorldScope, contextReadOnly;
  final ValueChanged<ScopeInput> onChanged;
  final SavedChanges changes;
  final SavedDraft draft;
  @override
  State<ScopeInputFields> createState() => _ScopeInputFieldsState();
}

class _ScopeInputFieldsState extends State<ScopeInputFields> {
  late final TextEditingController _contextRecord,
      _contextUniverse,
      _realmRecord,
      _realmUniverse,
      _worlds;
  late String _applicability;
  late bool _hasRealm;
  @override
  void initState() {
    super.initState();
    _contextRecord = TextEditingController(text: widget.input.contextRecord);
    _contextUniverse = TextEditingController(
      text: widget.input.contextUniverse,
    );
    _realmRecord = TextEditingController(text: widget.input.realmRecord);
    _realmUniverse = TextEditingController(text: widget.input.realmUniverse);
    _worlds = TextEditingController(text: widget.input.worlds.join('\n'));
    _applicability = widget.input.applicability;
    _hasRealm = widget.input.hasRealm;
  }

  @override
  void didUpdateWidget(ScopeInputFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    final input = widget.input;
    if (_form.toWire().toText() == input.toWire().toText()) return;
    _contextRecord.text = input.contextRecord;
    _contextUniverse.text = input.contextUniverse;
    _realmRecord.text = input.realmRecord;
    _realmUniverse.text = input.realmUniverse;
    _worlds.text = input.worlds.join('\n');
    _applicability = input.applicability;
    _hasRealm = input.hasRealm;
  }

  ScopeInput get _form => ScopeInput(
    applicability: _applicability,
    worlds: _worlds.text.isEmpty ? const [] : _worlds.text.split('\n'),
    contextRecord: _contextRecord.text,
    contextUniverse: _contextUniverse.text,
    hasRealm: _hasRealm,
    realmRecord: _realmRecord.text,
    realmUniverse: _realmUniverse.text,
  );
  void _changed() => widget.onChanged(_form);
  String _worldRecord(String world) {
    try {
      return worldChoiceRecord(world).value;
    } on FormatException {
      return '';
    }
  }

  Widget _choice(
    String label,
    RecordKind kind,
    String record,
    String universe,
    ValueChanged<RecordRef> changed,
  ) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: record,
    universe: universe,
    disabled:
        widget.disabled ||
        (widget.contextReadOnly && kind == RecordKind.representedContext),
    onChanged: changed,
  );
  void _moveWorld(int index, int destination) {
    final worlds = [..._form.worlds];
    worlds.insert(destination, worlds.removeAt(index));
    _worlds.text = worlds.join('\n');
    _changed();
  }

  @override
  void dispose() {
    for (final c in [
      _contextRecord,
      _contextUniverse,
      _realmRecord,
      _realmUniverse,
      _worlds,
    ]) {
      c.dispose();
    }
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
        key: ValueKey((_applicability, widget.explicitWorldScope)),
        initialValue:
            widget.explicitWorldScope &&
                !{'universe_wide', 'worlds'}.contains(_applicability)
            ? null
            : _applicability,
        decoration: const InputDecoration(labelText: 'Applies in'),
        items: [
          const DropdownMenuItem(
            value: 'universe_wide',
            child: Text('Whole universe'),
          ),
          const DropdownMenuItem(
            value: 'worlds',
            child: Text('Selected worlds'),
          ),
          if (!widget.explicitWorldScope)
            const DropdownMenuItem(
              value: 'conditional',
              child: Text('Conditional'),
            ),
          if (!widget.explicitWorldScope)
            const DropdownMenuItem(
              value: 'unspecified',
              child: Text('Unspecified'),
            ),
        ],
        onChanged: widget.disabled
            ? null
            : (v) {
                if (v == null) return;
                setState(() => _applicability = v);
                _changed();
              },
      ),
      if (_applicability == 'worlds') ...[
        for (var i = 0; i < _form.worlds.length; i++) ...[
          _choice(
            'World ${i + 1}',
            RecordKind.world,
            _worldRecord(_form.worlds[i]),
            widget.changes.scope.universe.value,
            (ref) {
              final worlds = [..._form.worlds];
              worlds[i] = worldFromChoice(ref).value;
              _worlds.text = worlds.join('\n');
              _changed();
            },
          ),
          Wrap(
            children: [
              TextButton(
                onPressed: widget.disabled || i == 0
                    ? null
                    : () => _moveWorld(i, i - 1),
                child: const Text('Move earlier'),
              ),
              TextButton(
                onPressed: widget.disabled || i == _form.worlds.length - 1
                    ? null
                    : () => _moveWorld(i, i + 1),
                child: const Text('Move later'),
              ),
              TextButton(
                onPressed: widget.disabled
                    ? null
                    : () {
                        final worlds = [..._form.worlds]..removeAt(i);
                        _worlds.text = worlds.join('\n');
                        _changed();
                      },
                child: const Text('Remove world'),
              ),
            ],
          ),
        ],
        _choice('World', RecordKind.world, '', '', (ref) {
          _worlds.text = [
            ..._form.worlds,
            worldFromChoice(ref).value,
          ].join('\n');
          _changed();
        }),
        const Text(
          'An empty world list applies nowhere. Order and repeated worlds are retained.',
        ),
      ],
      if (!widget.applicabilityOnly) ...[
        _choice(
          'Factual context',
          RecordKind.representedContext,
          _contextRecord.text,
          _contextUniverse.text,
          (ref) {
            _contextRecord.text = ref.record.value;
            _contextUniverse.text = ref.universe?.value ?? '';
            _changed();
          },
        ),
        CheckboxListTile(
          title: const Text('Limit to a realm'),
          value: _hasRealm,
          onChanged: widget.disabled
              ? null
              : (v) {
                  setState(() => _hasRealm = v!);
                  _changed();
                },
        ),
        if (_hasRealm) ...[
          _choice(
            'Realm',
            RecordKind.realm,
            _realmRecord.text,
            _realmUniverse.text,
            (ref) {
              _realmRecord.text = ref.record.value;
              _realmUniverse.text = ref.universe?.value ?? '';
              _changed();
            },
          ),
        ],
      ],
      ExpansionTile(
        title: const Text('Advanced references'),
        children: [
          if (_applicability == 'worlds')
            _field(_worlds, 'World IDs, one per line', multiline: true),
          if (!widget.applicabilityOnly) ...[
            _field(_contextRecord, 'Factual context record ID'),
            _field(_contextUniverse, 'Context universe ID (optional)'),
            if (_hasRealm) ...[
              _field(_realmRecord, 'Realm record ID'),
              _field(_realmUniverse, 'Realm universe ID (optional)'),
            ],
          ],
        ],
      ),
    ],
  );
}
