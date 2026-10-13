import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choices.dart';
import 'saved_changes.dart';

class DraftRecordChoiceField extends StatefulWidget {
  const DraftRecordChoiceField({
    super.key,
    required this.changes,
    required this.draft,
    required this.kind,
    required this.label,
    required this.record,
    required this.universe,
    required this.disabled,
    required this.onChanged,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final RecordKind kind;
  final String label, record, universe;
  final bool disabled;
  final ValueChanged<RecordRef> onChanged;
  @override
  State<DraftRecordChoiceField> createState() => _DraftRecordChoiceFieldState();
}

class _DraftRecordChoiceFieldState extends State<DraftRecordChoiceField> {
  String? _name;
  bool _choosing = false;
  int _read = 0;
  @override
  void initState() {
    super.initState();
    _readName();
  }

  @override
  void didUpdateWidget(DraftRecordChoiceField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record != widget.record ||
        oldWidget.universe != widget.universe ||
        oldWidget.draft.content.baseRevision !=
            widget.draft.content.baseRevision) {
      _readName();
    }
  }

  Future<void> _readName() async {
    final read = ++_read;
    _name = null;
    try {
      if (widget.universe.isNotEmpty &&
          widget.universe != widget.changes.scope.universe.value) {
        return;
      }
      final record = RecordId.parse(widget.record);
      final context = await openDraftChoiceContext(
        widget.changes,
        widget.draft,
      );
      final summary = await readDraftChoiceSummary(
        changes: widget.changes,
        context: context,
        record: record,
        kind: widget.kind,
      );
      if (mounted && _read == read) setState(() => _name = summary.label);
    } on Object {
      // Keep the exact reference without exposing an inaccessible name.
      if (mounted && _read == read) setState(() => _name = null);
    }
  }

  Future<void> _choose() async {
    setState(() => _choosing = true);
    final choice = await Navigator.of(context).push<RecordRef>(
      MaterialPageRoute(
        builder: (_) => _DraftRecordPicker(
          changes: widget.changes,
          draft: widget.draft,
          kind: widget.kind,
          label: widget.label,
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _choosing = false);
    if (choice != null) widget.onChanged(choice);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(widget.label),
    subtitle: Text(
      _name?.isNotEmpty == true
          ? _name!
          : widget.record.isEmpty
          ? 'No selection'
          : 'Reference retained; name unavailable here',
    ),
    trailing: OutlinedButton(
      onPressed: widget.disabled || _choosing ? null : _choose,
      child: Text('Choose ${widget.label.toLowerCase()}'),
    ),
  );
}

class _DraftRecordPicker extends StatefulWidget {
  const _DraftRecordPicker({
    required this.changes,
    required this.draft,
    required this.kind,
    required this.label,
  });
  final SavedChanges changes;
  final SavedDraft draft;
  final RecordKind kind;
  final String label;
  @override
  State<_DraftRecordPicker> createState() => _DraftRecordPickerState();
}

class _DraftRecordPickerState extends State<_DraftRecordPicker> {
  final _query = TextEditingController();
  final List<SearchHit> _hits = [];
  OpenedContext? _context;
  Delivery? _delivery;
  String _searched = '';
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search({bool more = false}) async {
    setState(() {
      _busy = true;
      _error = null;
      if (!more) {
        _hits.clear();
        _delivery = null;
        _searched = _query.text;
      }
    });
    try {
      _context ??= await openDraftChoiceContext(widget.changes, widget.draft);
      final found = await searchDraftChoices(
        changes: widget.changes,
        context: _context!,
        kind: widget.kind,
        query: _searched,
        cursor: more ? _delivery?.cursor : null,
      );
      if (mounted) {
        setState(() {
          _hits.addAll(found.result.hits);
          _delivery = found.delivery;
        });
      }
    } on Object {
      _context = null;
      if (mounted) {
        setState(
          () => _error = 'Could not read choices. Check the connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _choose(SearchHit hit) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final chosen = await selectDraftChoice(
        changes: widget.changes,
        context: _context!,
        hit: hit,
        kind: widget.kind,
      );
      if (mounted) Navigator.of(context).pop(chosen);
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'This record is not available for selection. Your existing reference remains unchanged.';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Choose ${widget.label.toLowerCase()}')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('Choices use the revision saved in this draft.'),
            TextField(
              controller: _query,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Find a record',
                hintText: 'Leave blank to browse',
              ),
              onSubmitted: (_) {
                if (!_busy) _search();
              },
            ),
            TextButton(
              onPressed: _busy ? null : () => _search(),
              child: const Text('Search'),
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (!_busy && _error == null && _hits.isEmpty)
              const Text('No accessible records match this choice.'),
            for (final hit in _hits)
              ExpansionTile(
                key: ValueKey(hit.recordId),
                title: Text(
                  hit.label.isEmpty ? 'Unnamed record' : hit.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(hit.kind.wireName.replaceAll('_', ' ')),
                children: [
                  SelectableText('Reference: ${hit.recordId.value}'),
                  TextButton(
                    onPressed: _busy ? null : () => _choose(hit),
                    child: const Text('Use this record'),
                  ),
                ],
              ),
            if (_delivery?.complete == false) ...[
              const Text('More records remain.'),
              if (_delivery?.cursor != null)
                TextButton(
                  onPressed: _busy ? null : () => _search(more: true),
                  child: const Text('Load more'),
                ),
            ],
          ],
        ),
      ),
    ),
  );
}
