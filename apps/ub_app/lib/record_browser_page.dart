import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';
import 'record_fields.dart';
import 'world_browser.dart';

class RecordBrowserPage extends StatefulWidget {
  const RecordBrowserPage({
    super.key,
    required this.session,
    required this.universe,
    required this.continuity,
    required this.representedContext,
  });
  final AppSession session;
  final LibraryEntry universe;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  @override
  State<RecordBrowserPage> createState() => _RecordBrowserPageState();
}

class _RecordBrowserPageState extends State<RecordBrowserPage> {
  final _query = TextEditingController();
  OpenedContext? _context;
  final List<SearchHit> _hits = [];
  RecordKind? _kind;
  Delivery? _delivery;
  String _searchedQuery = '';
  bool _busy = true;
  String? _error;

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
        _searchedQuery = _query.text;
        _hits.clear();
        _delivery = null;
      }
    });
    try {
      _context ??= await openAuthorReadContext(
        widget.session,
        widget.universe,
        widget.continuity,
        widget.representedContext,
      );
      final result = await searchContextRecords(
        session: widget.session,
        universe: widget.universe,
        context: _context!,
        query: _searchedQuery,
        kind: _kind,
        cursor: more ? _delivery?.cursor : null,
      );
      if (mounted) {
        setState(() {
          _hits.addAll(result.result.hits);
          _delivery = result.delivery;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not read these records. Check your connection and access, then try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Records')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              widget.continuity.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Context: ${representedContextName(widget.representedContext)}',
            ),
            const Text(
              'Reads stay at the revision opened here. Reopen Records from the overview to read later changes.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _query,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Find records',
                hintText: 'Leave blank to browse',
              ),
              onSubmitted: (_) {
                if (!_busy) _search();
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<RecordKind>(
              initialValue: _kind,
              decoration: const InputDecoration(labelText: 'Record type'),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All record types'),
                ),
                for (final kind in RecordKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(kind.wireName.replaceAll('_', ' ')),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (kind) {
                      setState(() => _kind = kind);
                      _search();
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
              const Text('No accessible records match this search.'),
            for (final hit in _hits)
              ListTile(
                title: Text(hit.label.isEmpty ? 'Unnamed record' : hit.label),
                subtitle: Text(hit.kind.wireName.replaceAll('_', ' ')),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => _RecordDetailPage(
                            session: widget.session,
                            universe: widget.universe,
                            context: _context!,
                            hit: hit,
                          ),
                        ),
                      ),
              ),
            if (_delivery?.complete == false) ...[
              const Text('More records remain in this search.'),
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

class _RecordDetailPage extends StatefulWidget {
  const _RecordDetailPage({
    required this.session,
    required this.universe,
    required this.context,
    required this.hit,
  });
  final AppSession session;
  final LibraryEntry universe;
  final OpenedContext context;
  final SearchHit hit;
  @override
  State<_RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<_RecordDetailPage> {
  RecordVersion? _record;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
      _record = null;
    });
    try {
      final record = await readContextRecord(
        session: widget.session,
        universe: widget.universe,
        context: widget.context,
        record: widget.hit.recordId,
      );
      if (mounted) setState(() => _record = record);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read this record in full. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.hit.label.isEmpty ? 'Record' : widget.hit.label),
    ),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_record != null) ExactFields(value: _record!.payload.toWire()),
            TextButton(
              onPressed: _busy ? null : _read,
              child: const Text('Retry read'),
            ),
          ],
        ),
      ),
    ),
  );
}
