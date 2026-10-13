import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_fields.dart';
import 'world_browser.dart';
import 'world_editor_page.dart';

class WorldDetailPage extends StatefulWidget {
  const WorldDetailPage({
    super.key,
    required this.session,
    required this.universe,
    required this.scope,
    required this.continuity,
    required this.representedContext,
    required this.world,
  });
  final AppSession session;
  final LibraryEntry universe;
  final EditorFormScope scope;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  final WorldSummary world;
  @override
  State<WorldDetailPage> createState() => _WorldDetailPageState();
}

class _WorldDetailPageState extends State<WorldDetailPage> {
  RecordVersion? _record;
  late ContinuitySummary _continuity;
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _continuity = widget.continuity;
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
      _record = null;
    });
    try {
      var continuity = _continuity;
      if (refresh) {
        final summary = Envelope<Description>.fromWire(
          await widget.session.call(
            ToolEngineRequest(
              request: DescribeSummaryRequest(
                universe: Selector(widget.universe.name),
                universeId: widget.universe.id,
              ),
            ),
          ),
          Description.fromWire,
        );
        continuity = summary.result.continuities.singleWhere(
          (item) => item.id == widget.scope.continuity,
        );
      }
      final record = await readPublishedWorld(
        session: widget.session,
        universe: widget.universe,
        continuity: continuity,
        representedContext: widget.representedContext,
        world: widget.world,
      );
      if (!mounted) return;
      setState(() {
        _continuity = continuity;
        _record = record;
      });
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not read this world in the selected context. Check your connection and access, then refresh.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _rename() async {
    final record = _record;
    if (record == null || _loading) return;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => WorldEditorPage.rename(
          session: widget.session,
          universe: Selector(widget.universe.name),
          continuity: _continuity,
          representedContext: widget.representedContext,
          world: record,
          scope: EditorFormScope(
            instance: widget.scope.instance,
            profile: widget.scope.profile,
            universe: widget.scope.universe,
            continuity: widget.scope.continuity,
            representedContext: widget.representedContext.id,
            worldRecord: record.identity.recordId,
          ),
        ),
      ),
    );
    if (mounted) await _load(refresh: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('World')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              _continuity.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Context: ${representedContextName(widget.representedContext)}',
            ),
            const SizedBox(height: 16),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_record != null) ...[
              Text(
                (_record!.payload as WorldRecord).selector,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              ExactFields(value: _record!.payload.toWire()),
              const SizedBox(height: 24),
              if (widget.session.author)
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton(
                    onPressed: _loading ? null : _rename,
                    child: const Text('Rename world'),
                  ),
                ),
              if (widget.session.author)
                const Text(
                  'Renames go into Changes for review. The previous name is retained as an alias when published.',
                ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading ? null : () => _load(refresh: true),
                child: const Text('Refresh world'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
