import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import 'navigation_location.dart';

import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'record_browser.dart';
import 'record_fields.dart';
import 'evidence_review_summary.dart';
import 'evidence_policy_view.dart';
import 'world_browser.dart';
import 'record_editor_page.dart';
import 'record_edit_action.dart';
import 'dossier_timeline_view.dart';
import 'dossier_facts_view.dart';

import 'package:ub_contracts/ub_contracts.dart' as data show State;

import 'relationship_diagram.dart';
import 'dossier_appearance_view.dart';
import 'image_preview_view.dart';
import 'dossier_sources_view.dart';
import 'event_withdrawal_draft.dart';

enum _DossierView {
  fields,
  evidence,
  history,
  relationships,
  timeline,
  facts,
  appearance,
  sources,
}

class _RelationshipList extends StatelessWidget {
  const _RelationshipList({
    required this.material,
    required this.universe,
    required this.entity,
    required this.name,
    required this.graph,
    required this.onGraphChanged,
  });
  final Records material;
  final UniverseId universe;
  final RecordId entity;
  final String name;
  final bool graph;
  final ValueChanged<bool> onGraphChanged;

  String label(RecordRef ref) =>
      ref.record == entity && (ref.universe == null || ref.universe == universe)
      ? name
      : dossierReferenceLabel(material, universe, ref);

  @override
  Widget build(BuildContext context) {
    final relationships = dossierRelationships(material, universe, entity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('List'),
              selected: !graph,
              onSelected: (_) => onGraphChanged(false),
            ),
            ChoiceChip(
              label: const Text('Graph'),
              selected: graph,
              onSelected: (_) => onGraphChanged(true),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Declared relationships in this opened revision. Subject and role order are authored; assertions retain their own scope, validity and evidence. This view does not decide which assertions hold at a particular time.',
        ),
        if (relationships.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No declared relationships were returned in this view. This does not establish that none exist.',
            ),
          ),
        for (final relationship in relationships)
          Builder(
            builder: (context) {
              final proposition =
                  relationship.proposition.payload as PropositionRecord;
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label(proposition.predicate),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (graph)
                        RelationshipDiagram(
                          proposition: proposition,
                          label: label,
                        )
                      else ...[
                        SelectableText(
                          'Subject: ${label(proposition.subject)}',
                        ),
                        for (
                          var index = 0;
                          index < proposition.roles.length;
                          index++
                        )
                          SelectableText(
                            '${index + 1}. ${proposition.roles[index].role}: ${label(proposition.roles[index].participant)}',
                          ),
                      ],
                      Text(
                        'Quantification: ${proposition.quantification.wireName}',
                      ),
                      if (relationship.assertions.isEmpty)
                        const Text(
                          'No assertions were returned for this declaration.',
                        ),
                      for (final row in relationship.assertions)
                        Builder(
                          builder: (context) {
                            final assertion = row.payload as AssertionRecord;
                            return ExpansionTile(
                              title: Text(
                                '${assertion.polarity.wireName} · ${assertion.attributeMode.wireName}',
                              ),
                              subtitle: const Text(
                                'Scope, validity and evidence',
                              ),
                              expandedCrossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                ExactFields(value: assertion.toWire()),
                              ],
                            );
                          },
                        ),
                      ExpansionTile(
                        title: const Text('Exact declaration'),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [ExactFields(value: proposition.toWire())],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

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
                          settings: kIsWeb
                              ? RouteSettings(
                                  name: LibraryLocation(
                                    universe: widget.universe.id,
                                    continuity: widget.continuity.id,
                                    context: widget.representedContext.id,
                                    revision: _context!.frame.revision,
                                    record: hit.recordId,
                                  ).uri.toString(),
                                )
                              : null,
                          builder: (_) => RecordDetailPage(
                            session: widget.session,
                            universe: widget.universe,
                            context: _context!,
                            record: hit.recordId,
                            kind: hit.kind,
                            label: hit.label,
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

class RecordDetailPage extends StatefulWidget {
  const RecordDetailPage({
    required this.session,
    required this.universe,
    required this.context,
    required this.record,
    required this.kind,
    required this.label,
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
  final RecordId record;
  final RecordKind kind;
  final String label;
  @override
  State<RecordDetailPage> createState() => RecordDetailPageState();
}

class RecordDetailPageState extends State<RecordDetailPage> {
  Envelope<Records>? _material;
  Envelope<data.State>? _state;
  _DossierView _view = _DossierView.fields;
  FieldGroup get _group => switch (_view) {
    _DossierView.fields => FieldGroup.payload,
    _DossierView.history => FieldGroup.history,
    _ => FieldGroup.evidence,
  };
  bool get _relationships => _view == _DossierView.relationships;
  bool get _timeline => _view == _DossierView.timeline;
  bool _relationshipGraph = false;
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
      _state = null;
    });
    try {
      if (_view == _DossierView.facts) {
        final result = await readContextEntityState(
          session: widget.session,
          universe: widget.universe,
          context: widget.context,
          entity: widget.record,
        );
        if (result.result.objects.length != 1 ||
            result.result.objects.single.identity.identity.recordId !=
                widget.record) {
          throw const FormatException('Entity state unavailable.');
        }
        if (mounted) setState(() => _state = result);
        return;
      }
      final material = await readContextRecordMaterial(
        session: widget.session,
        universe: widget.universe,
        context: widget.context,
        record: widget.record,
        group: _group,
        includePayload:
            _view == _DossierView.appearance || _view == _DossierView.sources,
      );
      if (_group == FieldGroup.payload &&
          (material.result.records.length != 1 ||
              material.result.records.single.identity.recordId !=
                  widget.record)) {
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

  Future<void> _edit(RecordVersion record, RecordEditAction action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await recordEditorPage(
        session: widget.session,
        universe: widget.universe,
        continuity: widget.continuity,
        representedContext: widget.representedContext,
        opened: widget.context,
        scope: widget.scope,
        record: record,
        action: action,
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          settings: kIsWeb
              ? RouteSettings(
                  name: LibraryLocation(
                    universe: widget.universe.id,
                    continuity: widget.continuity.id,
                    context: widget.representedContext.id,
                    revision: widget.context.frame.revision,
                    record: record.identity.recordId,
                    recordAction: action,
                  ).uri.toString(),
                )
              : null,
          builder: (_) => page,
        ),
      );
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open these fields. Check the connection and access, then retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.label.isEmpty ? 'Record' : widget.label)),
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
                for (final option in {
                  _DossierView.fields: 'Published fields',
                  _DossierView.evidence: 'Supporting records',
                  _DossierView.history: 'History',
                  _DossierView.appearance: 'Appearance',
                  _DossierView.sources: 'Sources',
                  if (widget.kind == RecordKind.entity) ...{
                    _DossierView.facts: 'Facts',
                    _DossierView.relationships: 'Relationships',
                    _DossierView.timeline: 'Timeline',
                  },
                }.entries)
                  ChoiceChip(
                    label: Text(option.value),
                    selected: _view == option.key,
                    onSelected: _busy
                        ? null
                        : (_) {
                            if (_view == option.key) return;
                            setState(() => _view = option.key);
                            _read();
                          },
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Semantics(liveRegion: true, child: Text(_error!)),
            if (_state != null) ...[
              if (!_state!.delivery.complete)
                const Text('Only part of this view was returned.'),
              DossierFacts(state: _state!.result, universe: widget.universe.id),
            ],
            if (_material != null) ...[
              if (!_material!.delivery.complete)
                const Text('Only part of this view was returned.'),
              if (_group == FieldGroup.payload)
                for (final record in _material!.result.records)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (record.payload
                          case RuleRecord(:final requiredEvidence)
                          when requiredEvidence != null)
                        EvidencePolicyView(
                          summary: EvidencePolicySummary(
                            record.payload as RuleRecord,
                            {
                              for (final row in [
                                ..._material!.result.evidence,
                                ..._material!.result.records,
                              ])
                                row.identity.recordId: row,
                            },
                          ),
                        ),
                      ExactFields(value: record.payload.toWire()),
                      if (widget.session.author &&
                          record.payload is SecretRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.secretRevision,
                                ),
                          child: const Text('Revise story secret'),
                        ),
                      if (widget.session.author &&
                          RecordEditAction.storyTime.supports(record.payload))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(record, RecordEditAction.storyTime),
                          child: const Text('Change story time'),
                        ),
                      if (widget.session.author &&
                          record.payload is AppearanceRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.appearanceRevision,
                                ),
                          child: const Text('Revise appearance'),
                        ),
                      if (record.payload is WorkRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.workAssociation,
                                ),
                          child: const Text('Add world association'),
                        ),
                      if (record.payload is SagaRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.sagaMembership,
                                ),
                          child: const Text('Set work membership'),
                        ),
                      if (record.payload is WorkVersionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.canonBinding,
                                ),
                          child: const Text('Change canon binding'),
                        ),
                      if (record.payload is SceneRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.sceneCorrection,
                                ),
                          child: const Text('Correct scene reference'),
                        ),
                      if (record.payload is ItemPowerRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.itemPowerCorrection,
                                ),
                          child: const Text('Correct item power'),
                        ),
                      if (record.payload is CommunicationRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.communicationCorrection,
                                ),
                          child: const Text('Correct communication'),
                        ),
                      if (record.payload is EpistemicAttitudeRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.attitudeCorrection,
                                ),
                          child: const Text('Correct belief or knowledge'),
                        ),
                      if (record.payload is PropertyRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.propertyRevision,
                                ),
                          child: const Text('Revise property definition'),
                        ),
                      if (record.payload is RelationRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.relationRevision,
                                ),
                          child: const Text('Revise relation definition'),
                        ),
                      if (record.payload is UnitRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.unitRevision,
                                ),
                          child: const Text('Revise unit definition'),
                        ),
                      if (record.payload is CalendarRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.calendarRevision,
                                ),
                          child: const Text('Revise calendar definition'),
                        ),
                      if (record.payload is DomainPackRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () =>
                                    _edit(record, RecordEditAction.packUpgrade),
                          child: const Text('Upgrade domain pack'),
                        ),
                      if (record.payload is ActionDefinitionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.actionRevision,
                                ),
                          child: const Text('Revise action definition'),
                        ),
                      if (record.payload is RuleRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.ruleRevision,
                                ),
                          child: const Text('Revise rule definition'),
                        ),
                      if (record.payload is AssertionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.assertionRetraction,
                                ),
                          child: const Text('Retract assertion'),
                        ),
                      if (isWithdrawableEvent(record.payload))
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.eventWithdrawal,
                                ),
                          child: const Text('Withdraw occurrence'),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () =>
                                  _edit(record, RecordEditAction.recordRemoval),
                        child: const Text('Remove from canon'),
                      ),
                      if (record.payload is EventRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.eventRevision,
                                ),
                          child: const Text('Revise event'),
                        ),
                      if (record.payload is AssertionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.assertionCorrection,
                                ),
                          child: const Text('Correct assertion'),
                        ),
                      if (record.payload is AssertionRecord &&
                          (record.payload as AssertionRecord).validity
                              is CalendarIntervalValidity)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.assertionEnd,
                                ),
                          child: const Text('End assertion at a time'),
                        ),
                      if (record.payload is ValueDefinitionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.valueRevision,
                                ),
                          child: const Text('Revise value definition'),
                        ),
                      if (record.payload is EntityTypeRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.typeRevision,
                                ),
                          child: const Text('Revise type definition'),
                        ),
                      if (record.payload is EpistemicAttitudeRecord &&
                          (record.payload as EpistemicAttitudeRecord)
                                  .attitude ==
                              EpistemicAttitudeKind.knows &&
                          (record.payload as EpistemicAttitudeRecord)
                                  .acquisition
                                  ?.basis
                              is CommunicationKnowledge)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.interpretationCorrection,
                                ),
                          child: const Text('Correct receipt interpretation'),
                        ),
                      if (widget.session.author &&
                          record.payload is SourceVersionRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.sourceExcerpt,
                                ),
                          child: const Text('Anchor an excerpt'),
                        ),
                      if (record.payload is ImageAssetRecord)
                        ImagePreviewView(
                          session: widget.session,
                          universe: widget.universe,
                          context: widget.context,
                          reference: RecordRef(
                            universe: widget.universe.id,
                            record: record.identity.recordId,
                          ),
                        ),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(record, RecordEditAction.attribute),
                          child: const Text('Add factual attribute'),
                        ),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _edit(
                                  record,
                                  RecordEditAction.relationship,
                                ),
                          child: const Text('Add relationship'),
                        ),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: () =>
                              _edit(record, RecordEditAction.entityName),
                          child: const Text('Add contextual name'),
                        ),
                      if (widget.session.author &&
                          _material!.delivery.complete &&
                          record.payload is EntityRecord)
                        TextButton(
                          onPressed: () => _edit(
                            record,
                            RecordEditAction.entityClassification,
                          ),
                          child: const Text('Refine classification'),
                        ),
                    ],
                  ),
              if (_relationships)
                _RelationshipList(
                  material: _material!.result,
                  universe: widget.universe.id,
                  entity: widget.record,
                  name: widget.label,
                  graph: _relationshipGraph,
                  onGraphChanged: (graph) =>
                      setState(() => _relationshipGraph = graph),
                ),
              if (_timeline)
                DossierTimeline(
                  material: _material!.result,
                  universe: widget.universe.id,
                  entity: widget.record,
                  name: widget.label,
                  representedContext: widget.representedContext.id,
                ),
              if (_view == _DossierView.appearance)
                DossierAppearance(
                  session: widget.session,
                  universe: widget.universe,
                  context: widget.context,
                  entry: widget.record,
                  material: _material!.result,
                ),
              if (_view == _DossierView.sources)
                DossierSources(
                  material: _material!.result,
                  universe: widget.universe.id,
                  session: widget.session,
                  selector: Selector(widget.universe.name),
                  openedContext: widget.context.contextId,
                ),
              if (_group == FieldGroup.evidence &&
                  !_relationships &&
                  !_timeline &&
                  _view != _DossierView.appearance &&
                  _view != _DossierView.sources) ...[
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
