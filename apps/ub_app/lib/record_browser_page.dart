import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';
import 'record_fields.dart';
import 'world_browser.dart';
import 'entity_editor_page.dart';

class RecordBrowserPage extends StatefulWidget {
  const RecordBrowserPage({
    super.key,
    required this.session,
    required this.universe,
    required this.continuity,
    required this.representedContext,
    required this.scope,
  });
  final EditorFormScope scope;
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
                            scope: widget.scope,
                            continuity: widget.continuity,
                            representedContext: widget.representedContext,
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
    required this.scope,
    required this.continuity,
    required this.representedContext,
  });
  final EditorFormScope scope;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  final AppSession session;
  final LibraryEntry universe;
  final OpenedContext context;
  final SearchHit hit;
  @override
  State<_RecordDetailPage> createState() => _RecordDetailPageState();
}

class _RecordDetailPageState extends State<_RecordDetailPage> {
  Envelope<Records>? _material;
  FieldGroup _group = FieldGroup.payload;
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
      _material = null;
    });
    try {
      final material = await readContextRecordMaterial(
        session: widget.session,
        universe: widget.universe,
        context: widget.context,
        record: widget.hit.recordId,
        group: _group,
      );
      if (_group == FieldGroup.payload &&
          (material.result.records.length != 1 ||
              material.result.records.single.identity.recordId !=
                  widget.hit.recordId)) {
        throw const FormatException('Record unavailable.');
      }
      if (mounted) setState(() => _material = material);
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
            const Text(
              'Published fields, supporting records and history are separate views at the same opened revision.',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                for (final option in const {
                  FieldGroup.payload: 'Published fields',
                  FieldGroup.evidence: 'Supporting records',
                  FieldGroup.history: 'History',
                }.entries)
                  ChoiceChip(
                    label: Text(option.value),
                    selected: _group == option.key,
                    onSelected: _busy
                        ? null
                        : (_) {
                            if (_group == option.key) return;
                            setState(() => _group = option.key);
                            _read();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_material != null) ...[
              if (!_material!.delivery.complete)
                const Text('Only part of this view was returned.'),
              if (_group == FieldGroup.payload)
                for (final record in _material!.result.records)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExactFields(value: record.payload.toWire()),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => EntityEditorPage(
                                session: widget.session,
                                universe: widget.universe,
                                continuity: widget.continuity,
                                representedContext: widget.representedContext,
                                publishedEntity: record,
                                scope: EditorFormScope(
                                  instance: widget.scope.instance,
                                  profile: widget.scope.profile,
                                  universe: widget.universe.id,
                                  continuity: widget.continuity.id,
                                  representedContext:
                                      widget.representedContext.id,
                                  entityNameRecord: record.identity.recordId,
                                ),
                              ),
                            ),
                          ),
                          child: const Text('Add contextual name'),
                        ),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: () => Navigator.of(context).push<void>(
                            MaterialPageRoute(
                              builder: (_) => EntityEditorPage(
                                session: widget.session,
                                universe: widget.universe,
                                continuity: widget.continuity,
                                representedContext: widget.representedContext,
                                publishedEntity: record,
                                refineClassification: true,
                                scope: EditorFormScope(
                                  instance: widget.scope.instance,
                                  profile: widget.scope.profile,
                                  universe: widget.universe.id,
                                  continuity: widget.continuity.id,
                                  representedContext:
                                      widget.representedContext.id,
                                  entityClassificationRecord:
                                      record.identity.recordId,
                                ),
                              ),
                            ),
                          ),
                          child: const Text('Refine classification'),
                        ),
                    ],
                  ),
              if (_group == FieldGroup.evidence) ...[
                const Text(
                  'Sources, assertions and related declarations accessible in this context.',
                ),
                if (_material!.result.evidence.isEmpty)
                  const Text(
                    'No supporting records were returned in this view.',
                  ),
                for (final record in _material!.result.evidence)
                  Card(
                    child: ExpansionTile(
                      title: Text(
                        record.identity.recordKind.wireName.replaceAll(
                          '_',
                          ' ',
                        ),
                      ),
                      childrenPadding: const EdgeInsets.all(16),
                      expandedCrossAxisAlignment: CrossAxisAlignment.start,
                      children: [ExactFields(value: record.payload.toWire())],
                    ),
                  ),
              ],
              if (_group == FieldGroup.history) ...[
                Text(switch (_material!.result.historyCoverage) {
                  Coverage.complete =>
                    'Complete retained history through this revision.',
                  Coverage.restricted => 'History is restricted in this view.',
                  _ => 'Complete history was not returned in this view.',
                }),
                if (_material!.result.history.isEmpty)
                  const Text('No history entries were returned in this view.'),
                for (final entry in _material!.result.history)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Publication reason'),
                          SelectableText(entry.reason),
                          ExpansionTile(
                            title: const Text('Publication details'),
                            children: [
                              SelectableText(
                                'Published by: ${entry.principal.value}',
                              ),
                              SelectableText(
                                'Revision: ${entry.revision.value}',
                              ),
                            ],
                          ),
                          if (entry.record == null)
                            const Text('Record removed in this revision.')
                          else
                            ExactFields(value: entry.record!.payload.toWire()),
                        ],
                      ),
                    ),
                  ),
              ],
            ],
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
