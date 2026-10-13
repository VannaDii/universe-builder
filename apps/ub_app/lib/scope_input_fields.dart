import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

/// Factual scope controls retain incomplete reference and world inputs.
class ScopeInputFields extends StatefulWidget {
  const ScopeInputFields({
    super.key,
    required this.input,
    required this.disabled,
    required this.onChanged,
  });
  final ScopeInput input;
  final bool disabled;
  final ValueChanged<ScopeInput> onChanged;
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
        key: ValueKey(_applicability),
        initialValue: _applicability,
        decoration: const InputDecoration(labelText: 'Applies in'),
        items: const [
          DropdownMenuItem(
            value: 'universe_wide',
            child: Text('Whole universe'),
          ),
          DropdownMenuItem(value: 'worlds', child: Text('Selected worlds')),
          DropdownMenuItem(value: 'conditional', child: Text('Conditional')),
          DropdownMenuItem(value: 'unspecified', child: Text('Unspecified')),
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
        _field(_worlds, 'World IDs, one per line', multiline: true),
        const Text(
          'An empty world list applies nowhere. Order and repeated worlds are retained.',
        ),
      ],
      _field(_contextRecord, 'Factual context record ID'),
      _field(_contextUniverse, 'Context universe ID (optional)'),
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
        _field(_realmRecord, 'Realm record ID'),
        _field(_realmUniverse, 'Realm universe ID (optional)'),
      ],
    ],
  );
}
