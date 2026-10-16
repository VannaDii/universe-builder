import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'changes_page.dart';
import 'connection.dart';
import 'pack_editor_page.dart';
import 'record_browser_page.dart';
import 'record_browser.dart';
import 'saved_changes.dart';
import 'universe_policies.dart';

class UniversePoliciesPage extends StatefulWidget {
  const UniversePoliciesPage({
    super.key,
    required this.changes,
    required this.continuity,
    required this.representedContext,
  });
  final SavedChanges changes;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  @override
  State<UniversePoliciesPage> createState() => _UniversePoliciesPageState();
}

class _UniversePoliciesPageState extends State<UniversePoliciesPage> {
  UniversePolicyChoices? _policies;
  ContinuitySummary? _continuity;
  bool _busy = true;
  String? _error, _added;
  SavedDraft _empty(RevisionId revision) => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: revision,
      representedContext: widget.representedContext.id,
      operations: [],
      rationale: '',
    ),
  );
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _policies = null;
    });
    try {
      final summary = Envelope<Description>.fromWire(
        await widget.changes.session.call(
          ToolEngineRequest(
            request: DescribeSummaryRequest(
              universe: widget.changes.universe,
              universeId: widget.changes.scope.universe,
            ),
          ),
        ),
        Description.fromWire,
      ).result;
      final continuity = summary.continuities.singleWhere(
        (c) => c.id == widget.continuity.id,
      );
      final policies = await readUniversePolicyChoices(
        widget.changes,
        _empty(continuity.revisionId),
      );
      if (mounted) {
        setState(() {
          _policies = policies;
          _continuity = continuity;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read the root policy. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  String _name(RecordVersion row) => (row.payload as DomainPackRecord).key
      .substring(universePolicyDefinitionPrefix.length);
  Future<void> _define() async {
    final policies = _policies;
    if (_busy || policies == null) {
      return;
    }
    await Navigator.of(context).push<SavedDraft>(
      MaterialPageRoute(
        builder: (_) => PackEditorPage(
          revision: _continuity!.revisionId,
          definePolicy: true,
          rootVersion: policies.selection?.recordVersionId,
          changes: SavedChanges(
            session: widget.changes.session,
            universe: widget.changes.universe,
            scope: EditorFormScope(
              instance: widget.changes.scope.instance,
              profile: widget.changes.scope.profile,
              universe: widget.changes.scope.universe,
              continuity: widget.changes.scope.continuity,
              representedContext: widget.representedContext.id,
              typeClientRef: universePolicyEditorKey,
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      await _load();
    }
  }

  Future<void> _select(RecordVersion definition) async {
    final policies = _policies;
    if (_busy || policies?.selection == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _added = null;
    });
    try {
      final draft =
          await widget.changes.load() ?? _empty(_continuity!.revisionId);
      await widget.changes.session.call(
        universePolicySelectionDraftRequest(
          draft: draft,
          universe: widget.changes.universe,
          continuity: widget.continuity.id,
          representedContext: widget.representedContext.id,
          revision: _continuity!.revisionId,
          selection: policies!.selection!,
          definition: definition,
        ),
      );
      if (mounted) {
        setState(
          () => _added = 'Root selection is in Changes. It takes effect after review and publication.',
        );
      }
    } on FormatException catch (error) {
      if (mounted) {
        setState(() => _error = error.message);
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the root selection. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Universe policies')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Every world inherits the selected root. Define scoped deviations when a world or subject departs from that baseline. Other applicable rules still apply.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_added != null)
              Semantics(liveRegion: true, child: Text(_added!)),
            if (_policies case final policies?) ...[
              if (policies.selection == null)
                const Text(
                  'This older universe needs an explicit root policy. Define and select one through Changes; historical records remain unchanged.',
                ),
              for (final definition in policies.definitions)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name(definition),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          definition.identity.recordId == policies.selected
                              ? 'Selected root'
                              : 'Available replacement',
                        ),
                        Text(
                          '${(definition.payload as DomainPackRecord).records.length} policy rules',
                        ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => RecordDetailPage(
                                          session: widget.changes.session,
                                          universe: LibraryEntry(
                                            widget.changes.scope.universe,
                                            widget.changes.universe.value,
                                          ),
                                          context: policies.context,
                                          record: definition.identity.recordId,
                                          kind: RecordKind.domainPack,
                                          label: _name(definition),
                                          scope: widget.changes.scope,
                                          continuity: _continuity!,
                                          representedContext:
                                              widget.representedContext,
                                        ),
                                      ),
                                    ),
                              child: const Text('Inspect policy'),
                            ),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => _PolicyRulesPage(
                                          changes: widget.changes,
                                          context: policies.context,
                                          definition: definition,
                                          continuity: _continuity!,
                                          representedContext:
                                              widget.representedContext,
                                        ),
                                      ),
                                    ),
                              child: const Text('View policy rules'),
                            ),
                            if (definition.identity.recordId !=
                                policies.selected)
                              TextButton(
                                onPressed: _busy || _added != null
                                    ? null
                                    : () => _select(definition),
                                child: const Text(
                                  'Add root selection to Changes',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _busy ? null : _define,
                child: const Text('Define policy'),
              ),
            ],
            TextButton(
              onPressed: _busy ? null : _load,
              child: const Text('Refresh policies'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await Navigator.of(context).push<SavedDraft>(
                        MaterialPageRoute(
                          builder: (_) => ChangesPage(changes: widget.changes),
                        ),
                      );
                      if (mounted) {
                        setState(() => _added = null);
                        await _load();
                      }
                    },
              child: const Text('Review Changes'),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PolicyRulesPage extends StatefulWidget {
  const _PolicyRulesPage({
    required this.changes,
    required this.context,
    required this.definition,
    required this.continuity,
    required this.representedContext,
  });
  final SavedChanges changes;
  final OpenedContext context;
  final RecordVersion definition;
  final ContinuitySummary continuity;
  final RepresentedContextSummary representedContext;
  @override
  State<_PolicyRulesPage> createState() => _PolicyRulesPageState();
}

class _PolicyRulesPageState extends State<_PolicyRulesPage> {
  int _offset = 0;
  List<RecordVersion> _rules = const [];
  bool _busy = true;
  String? _error;
  int get _count =>
      (widget.definition.payload as DomainPackRecord).records.length;
  @override
  void initState() {
    super.initState();
    _load(0);
  }

  Future<void> _load(int offset) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final rows = await readUniversePolicyRulePage(
        changes: widget.changes,
        context: widget.context,
        definition: widget.definition,
        offset: offset,
      );
      if (mounted) {
        setState(() {
          _rules = rows;
          _offset = offset;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read all rules on this page. Check your connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Policy rules')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Rules at the opened revision. Return and refresh policies to read later changes.',
            ),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (!_busy && _error == null && _count == 0)
              const Text(
                'This is an empty policy. Add existing rules by editing its policy definition.',
              ),
            for (final row in _rules)
              ListTile(
                title: Text(
                  dossierReferenceLabel(
                    Records(records: [row]),
                    widget.changes.scope.universe,
                    RecordRef(record: row.identity.recordId),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: _busy
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => RecordDetailPage(
                            session: widget.changes.session,
                            universe: LibraryEntry(
                              widget.changes.scope.universe,
                              widget.changes.universe.value,
                            ),
                            context: widget.context,
                            record: row.identity.recordId,
                            kind: RecordKind.rule,
                            label: dossierReferenceLabel(
                              Records(records: [row]),
                              widget.changes.scope.universe,
                              RecordRef(record: row.identity.recordId),
                            ),
                            scope: widget.changes.scope,
                            continuity: widget.continuity,
                            representedContext: widget.representedContext,
                          ),
                        ),
                      ),
              ),
            if (_count > 0)
              Text(
                'Rules ${_offset + 1}–${_offset + _rules.length} of $_count',
              ),
            Wrap(
              children: [
                if (_offset > 0)
                  TextButton(
                    onPressed: _busy ? null : () => _load(_offset - 50),
                    child: const Text('Previous rules'),
                  ),
                if (_offset + 50 < _count)
                  TextButton(
                    onPressed: _busy ? null : () => _load(_offset + 50),
                    child: const Text('Next rules'),
                  ),
                TextButton(
                  onPressed: _busy ? null : () => _load(_offset),
                  child: const Text('Retry read'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
