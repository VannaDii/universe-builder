import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'connection.dart';
import 'type_editor_page.dart';
import 'entity_editor_page.dart';
import 'record_fields.dart';
import 'world_editor_page.dart';

class ChangesPage extends StatefulWidget {
  const ChangesPage({super.key, required this.changes});
  final SavedChanges changes;
  @override
  State<ChangesPage> createState() => _ChangesPageState();
}

class _ChangesPageState extends State<ChangesPage> {
  SavedDraft? _draft;
  Proposal? _proposal;
  Map<RecordId, RecordVersion> _before = {};
  bool _busy = true;
  String? _error;
  final _rationale = TextEditingController();
  bool _rationaleDirty = false;
  ValidationV3? _validation;
  bool _approved = false;
  CommitReceipt? _receipt;
  ({ValidationRunId run, OperationStatusV3 status})? _publication;
  List<RecordVersion> _publishedRecords = [];
  final _undo = <DraftContent>[], _redo = <DraftContent>[];
  @override
  void dispose() {
    _rationale.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
      _draft = null;
      _proposal = null;
      _before = {};
      _validation = null;
      _approved = false;
      _receipt = null;
      _publication = null;
      _publishedRecords = [];
      _undo.clear();
      _redo.clear();
    });
    try {
      final draft = await widget.changes.load();
      final proposal = draft == null
          ? null
          : await widget.changes.recover(draft);
      final before = proposal == null
          ? <RecordId, RecordVersion>{}
          : await widget.changes.before(proposal);
      final publication = proposal == null
          ? null
          : await widget.changes.publication(proposal);
      if (mounted) {
        setState(() {
          _draft = draft;
          _proposal = proposal;
          _before = before;
          _rationale.text = draft?.content.rationale ?? '';
          _rationaleDirty = false;
          _publication = publication;
          _receipt = publication?.status.receipt;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not open saved changes. Check your connection and access, then try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _submit() async {
    if (_rationaleDirty) await _saveRationale();
    if (!mounted || _rationaleDirty) return;
    final draft = _draft;
    if (draft == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final proposal = await widget.changes.submit(draft);
      final before = await widget.changes.before(proposal);
      final saved = await widget.changes.load();
      if (saved?.content.proposal !=
          ProposalRef(
            proposalId: proposal.proposalId,
            version: proposal.version,
            digest: proposal.digest,
          )) {
        throw const FormatException(
          'Saved changes have changed. Reload before continuing.',
        );
      }
      if (mounted) {
        setState(() {
          _proposal = proposal;
          _before = before;
          _draft = saved;
        });
      }
    } on InvalidArgumentError catch (error) {
      if (mounted) {
        setState(() {
          _error = error.field.contains('rationale')
              ? 'Add a rationale explaining these changes, save it, then submit the proposal.'
              : 'The proposal contains an invalid value. Your saved changes remain; review the entered fields.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not confirm submission. Your saved changes remain. Check saved changes before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _saveRationale() async {
    final draft = _draft;
    if (draft == null || _busy || !_rationaleDirty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.saveRationale(draft, _rationale.text);
      if (mounted) {
        setState(() {
          _undo.add(draft.content);
          _redo.clear();
          _draft = saved;
          _rationaleDirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not save the rationale. Your text is still here. Another window may have saved newer changes; check before replacing work.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _leave() async {
    if (_busy) return;
    if (_rationaleDirty) await _saveRationale();
    if (!mounted || _busy || _rationaleDirty) return;
    await WidgetsBinding.instance.endOfFrame;
    if (mounted && !_busy && !_rationaleDirty) Navigator.of(context).pop();
  }

  Future<void> _validate() async {
    final proposal = _proposal;
    if (proposal == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _validation = null;
      _approved = false;
    });
    try {
      final validation = await widget.changes.validate(proposal);
      if (mounted) {
        setState(() {
          _validation = validation;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not finish checks. Check your connection and access, then run them again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _approve() async {
    final proposal = _proposal, report = _validation;
    if (proposal == null || report is! EvaluatedValidation || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _approved = false;
    });
    try {
      await widget.changes.approve(proposal, report);
      if (mounted) {
        setState(() {
          _approved = true;
        });
      }
    } on PolicyDeniedError {
      if (mounted) {
        setState(() {
          _error = 'Checks block approval. Review the findings and resolve the proposed changes.';
        });
      }
    } on ApprovalStaleError {
      if (mounted) {
        setState(() {
          _error = 'The proposal or its supporting context changed since review. Review it and run checks again before approval.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not confirm approval. Canon is unchanged. Check your connection before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _publish() async {
    final proposal = _proposal;
    final run = _approved ? _validation?.execution?.runId : _publication?.run;
    if (proposal == null || run == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final receipt = await widget.changes.publish(proposal, run);
      if (mounted) {
        setState(() {
          _receipt = receipt;
        });
      }
    } on ApprovalStaleError {
      if (mounted) {
        setState(() {
          _approved = false;
          _error = 'Publication was refused because the reviewed proposal or context changed. Review and run checks again.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not confirm publication. Check publication to recover its outcome before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _checkPublication() async {
    final proposal = _proposal;
    if (proposal == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final publication = await widget.changes.publication(proposal);
      if (mounted) {
        setState(() {
          _publication = publication;
          _receipt = publication?.status.receipt;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not check publication. Check your connection and current access.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _readPublished() async {
    final proposal = _proposal, receipt = _receipt;
    if (proposal == null || receipt == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final records = await widget.changes.readPublished(proposal, receipt);
      if (mounted) {
        setState(() {
          _publishedRecords = records;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Publication is confirmed, but the committed records could not be read with your current connection and access.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<SavedDraft> _editType(SavedDraft draft, int index) async {
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
      (item) => item.id == widget.changes.scope.continuity,
    );
    final representedContext = continuity.representedContexts.singleWhere(
      (item) => item.id == draft.content.representedContext,
    );
    if (!mounted) return draft;
    return await Navigator.of(context).push<SavedDraft>(
          MaterialPageRoute(
            builder: (_) => TypeEditorPage(
              session: widget.changes.session,
              universe: LibraryEntry(
                widget.changes.scope.universe,
                widget.changes.universe.value,
              ),
              continuity: continuity,
              representedContext: representedContext,
              scope: EditorFormScope(
                instance: widget.changes.scope.instance,
                profile: widget.changes.scope.profile,
                universe: widget.changes.scope.universe,
                continuity: widget.changes.scope.continuity,
                representedContext: draft.content.representedContext,
                typeClientRef:
                    (draft.content.operations[index]
                            as IntroduceDefinitionOperation)
                        .clientRef,
              ),
              editingDraft: draft,
              operationIndex: index,
            ),
          ),
        ) ??
        draft;
  }

  Future<SavedDraft> _editEntity(SavedDraft draft, int index) async {
    final operation = draft.content.operations[index];
    final name = operation is AddNameOperation ? operation : null;
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
      (item) => item.id == widget.changes.scope.continuity,
    );
    final representedContext = continuity.representedContexts.singleWhere(
      (item) => item.id == draft.content.representedContext,
    );
    if (!mounted) return draft;
    return await Navigator.of(context).push<SavedDraft>(
          MaterialPageRoute(
            builder: (_) => EntityEditorPage(
              session: widget.changes.session,
              universe: LibraryEntry(
                widget.changes.scope.universe,
                widget.changes.universe.value,
              ),
              continuity: continuity,
              representedContext: representedContext,
              scope: EditorFormScope(
                instance: widget.changes.scope.instance,
                profile: widget.changes.scope.profile,
                universe: widget.changes.scope.universe,
                continuity: widget.changes.scope.continuity,
                representedContext: draft.content.representedContext,
                entityClientRef: name == null
                    ? (operation as IntroduceInstanceOperation).clientRef
                    : null,
                entityNameRecord: name?.record.record,
                entityNameOperationIndex: name == null ? null : index,
              ),
              editingDraft: draft,
              operationIndex: index,
            ),
          ),
        ) ??
        draft;
  }

  Future<bool> _changeDraft(
    Future<SavedDraft> Function(SavedDraft) change, {
    bool keepUndo = true,
  }) async {
    if (_rationaleDirty) await _saveRationale();
    final draft = _draft;
    if (!mounted || draft == null || _busy || _rationaleDirty) return false;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final saved = await change(draft);
      final proposal = await widget.changes.recover(saved);
      final before = proposal == null
          ? <RecordId, RecordVersion>{}
          : await widget.changes.before(proposal);
      final publication = proposal == null
          ? null
          : await widget.changes.publication(proposal);
      if (!mounted) return false;
      setState(() {
        if (keepUndo &&
            saved.content.toWire().toText() !=
                draft.content.toWire().toText()) {
          _undo.add(draft.content);
          _redo.clear();
        }
        _draft = saved;
        _proposal = proposal;
        _before = before;
        _publication = publication;
        _receipt = publication?.status.receipt;
        _validation = null;
        _approved = false;
        _publishedRecords = [];
        _rationale.text = saved.content.rationale;
        _rationaleDirty = false;
      });
      return true;
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
        });
      }
      return false;
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not confirm the draft change. Your saved work remains. Check saved changes before trying again; another window may have saved newer work.';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _undoChange({bool redo = false}) async {
    if (_rationaleDirty) await _saveRationale();
    if (!mounted || _busy || _rationaleDirty) return;
    final stack = redo ? _redo : _undo;
    if (stack.isEmpty || _draft == null) return;
    final previous = _draft!.content, target = stack.last;
    if (await _changeDraft(
      (draft) => widget.changes.saveContent(draft, target),
      keepUndo: false,
    )) {
      if (mounted) {
        setState(() {
          stack.removeLast();
          (redo ? _undo : _redo).add(previous);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final operations =
        _proposal?.operations ?? _draft?.content.operations ?? [];
    return PopScope(
      canPop: !_busy && !_rationaleDirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Changes')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 850),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (_busy) const LinearProgressIndicator(),
                Text(
                  _receipt != null
                      ? 'Published changes'
                      : _proposal == null
                      ? 'Saved changes'
                      : 'Submitted proposal',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Canon stays unchanged until you review, approve and publish separately.',
                ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_receipt != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Publication confirmed'),
                          SelectableText(
                            'Revision: ${_receipt!.revision.value}',
                          ),
                          SelectableText(
                            'Operation: ${_receipt!.operationId.value}',
                          ),
                        ],
                      ),
                    ),
                  ),
                for (final record in _publishedRecords)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Published record'),
                          ExactFields(value: record.payload.toWire()),
                        ],
                      ),
                    ),
                  ),
                if (_publication != null && _receipt == null)
                  Text(
                    'Publication status: ${_publication!.status.state.wireName.replaceAll('_', ' ')}',
                  ),
                if (_approved && _receipt == null)
                  const Text(
                    'This exact proposal and check run are approved. Publication is a separate action.',
                  ),
                if (_draft == null && !_busy && _error == null)
                  const Text('No saved changes in this continuity.'),
                if (_draft != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    'Rationale',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_proposal == null) ...[
                    TextField(
                      controller: _rationale,
                      enabled: !_busy,
                      maxLines: 4,
                      decoration: const InputDecoration(labelText: 'Rationale'),
                      onChanged: (_) => setState(() {
                        _rationaleDirty = true;
                      }),
                    ),
                    TextButton(
                      onPressed: _busy || !_rationaleDirty
                          ? null
                          : _saveRationale,
                      child: const Text('Save rationale'),
                    ),
                  ] else
                    SelectableText(
                      _proposal?.rationale ?? _draft!.content.rationale,
                    ),
                  const SizedBox(height: 20),
                  for (var index = 0; index < operations.length; index++)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Change ${index + 1}: ${operations[index].kind.wireName.replaceAll('_', ' ')}',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            if (operations[index] case CreateWorldOperation(
                              :final record,
                            )) ...[
                              const Text('Before: no world'),
                              const Text('After'),
                              ExactFields(value: record.toWire()),
                            ] else if (operations[index]
                                case IntroduceInstanceOperation(
                                  :final name,
                                  :final classification,
                                  :final worldAssociations,
                                )) ...[
                              const Text('New entity'),
                              SelectableText(name.text),
                              Text(
                                classification == null
                                    ? 'Unclassified'
                                    : 'Classification selected',
                              ),
                              if (classification != null)
                                SelectableText(classification.value),
                              const Text('World associations (not location)'),
                              for (final association in worldAssociations)
                                ExactFields(value: association.toWire()),
                              if (worldAssociations.isEmpty)
                                const Text('No world associations'),
                            ] else if (operations[index]
                                case IntroduceDefinitionOperation(
                                  :final name,
                                  :final namespace,
                                  :final key,
                                  :final parent,
                                  :final applicability,
                                  :final classificationExecutable,
                                )) ...[
                              const Text('Type definition'),
                              SelectableText(name),
                              SelectableText('Namespace: $namespace'),
                              SelectableText('Definition key: $key'),
                              Text(
                                parent == null
                                    ? 'No parent (root definition)'
                                    : 'Parent definition selected',
                              ),
                              const Text('Applicability'),
                              ExactFields(value: applicability.toWire()),
                              Text(
                                classificationExecutable
                                    ? 'Executable classification: Yes'
                                    : 'Executable classification: No',
                              ),
                            ] else if (operations[index]
                                case RenameWorldSelectorOperation(
                                  :final newSelector,
                                )) ...[
                              const Text('New world name'),
                              SelectableText(newSelector),
                              const Text(
                                'The earlier name is retained as an alias when published.',
                              ),
                            ] else if (operations[index]
                                case AddWorldAliasOperation(:final alias)) ...[
                              const Text('Additional world name'),
                              SelectableText(alias),
                              const Text(
                                'The world’s current name and identity stay the same.',
                              ),
                            ] else
                              ExactFields(value: operations[index].toWire()),
                            if (_proposal == null &&
                                (operations[index]
                                        is IntroduceInstanceOperation ||
                                    operations[index] is AddNameOperation))
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _changeDraft(
                                        (draft) => _editEntity(draft, index),
                                      ),
                                child: Text(
                                  operations[index] is AddNameOperation
                                      ? 'Edit name fields'
                                      : 'Edit entity fields',
                                ),
                              ),
                            if (_proposal == null &&
                                operations[index]
                                    is IntroduceDefinitionOperation)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _changeDraft(
                                        (draft) => _editType(draft, index),
                                      ),
                                child: const Text('Edit type fields'),
                              ),
                            if (_proposal == null)
                              if (operations[index] is CreateWorldOperation)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _changeDraft(
                                          (draft) async =>
                                              await Navigator.of(
                                                context,
                                              ).push<SavedDraft>(
                                                MaterialPageRoute(
                                                  builder: (_) =>
                                                      WorldEditorPage.edit(
                                                        changes: widget.changes,
                                                        draft: draft,
                                                        index: index,
                                                      ),
                                                ),
                                              ) ??
                                              draft,
                                        ),
                                  child: const Text('Edit world fields'),
                                ),
                            if (_proposal == null)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _changeDraft(
                                        (draft) => widget.changes
                                            .removeOperation(draft, index),
                                      ),
                                child: const Text('Remove from draft'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_proposal != null) ...[
                    const SizedBox(height: 16),
                    const Text('Compiled record changes'),
                    for (final change in _proposal!.compiledChanges)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText(
                                'Record: ${change.recordId.value}',
                              ),
                              const Text('Before'),
                              if (change.expected == null)
                                const Text('No record')
                              else
                                ExactFields(
                                  value: _before[change.recordId]!.payload
                                      .toWire(),
                                ),
                              const Text('After'),
                              if (change.next == null)
                                const Text('After: removed')
                              else
                                ExactFields(
                                  value: change.next!.payload.toWire(),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ExpansionTile(
                      title: const Text('Revision and proposal details'),
                      children: [
                        SelectableText(
                          'Base revision: ${_proposal!.baseFrame.revision.value}',
                        ),
                        SelectableText(
                          'Represented context: ${_proposal!.baseFrame.context.record.value}',
                        ),
                        SelectableText(
                          'Proposal: ${_proposal!.proposalId.value} · version ${_proposal!.version}',
                        ),
                        SelectableText('Digest: ${_proposal!.digest}'),
                      ],
                    ),
                  ],
                ],
                const SizedBox(height: 20),
                if (_validation case final report?) ...[
                  Text(
                    'Check results',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  if (report is RestrictedValidation)
                    const Text(
                      'Checks are restricted with this access. An approval owner must review the complete universe.',
                    )
                  else if (report is EvaluatedValidation) ...[
                    Text('Coverage: ${report.execution.coverage.wireName}'),
                    if (report.execution.findings.isEmpty)
                      const Text(
                        'No findings were returned. Coverage and unsupported checks still apply.',
                      ),
                    for (final finding in report.execution.findings)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${finding.outcome.wireName.replaceAll('_', ' ')} · ${finding.coverage.wireName}',
                              ),
                              if (finding.message != null)
                                SelectableText(finding.message!),
                              ExpansionTile(
                                title: const Text('Rule, records and evidence'),
                                children: [
                                  ExactFields(value: finding.toWire()),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (report
                        .execution
                        .unsupportedCapabilities
                        .isNotEmpty) ...[
                      const Text('Unsupported checks'),
                      for (final capability
                          in report.execution.unsupportedCapabilities)
                        SelectableText(capability),
                    ],
                    for (final evidence in report.execution.opposingEvidence)
                      ExpansionTile(
                        title: const Text('Opposing evidence'),
                        children: [ExactFields(value: evidence.toWire())],
                      ),
                    ExpansionTile(
                      title: const Text('Submitted evidence and assessment'),
                      children: [
                        ExactFields(value: report.submittedInput.toWire()),
                        ExactFields(value: report.assessment.toWire()),
                      ],
                    ),
                  ],
                ],
                if (_draft != null && _proposal == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Rebase preserves entered operations and expected record versions. Conflicting record edits still need review.',
                    ),
                  ),
                if (_proposal != null && _receipt == null)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Editing separately retains this proposal and its approvals. New changes require a new submission and review.',
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    if (_draft != null) ...[
                      OutlinedButton(
                        onPressed: _busy || _undo.isEmpty ? null : _undoChange,
                        child: const Text('Undo draft change'),
                      ),
                      OutlinedButton(
                        onPressed: _busy || _redo.isEmpty
                            ? null
                            : () => _undoChange(redo: true),
                        child: const Text('Redo draft change'),
                      ),
                      if (_proposal == null)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _changeDraft(
                                  (draft) => widget.changes.rebase(draft),
                                ),
                          child: const Text('Rebase draft to current revision'),
                        ),
                      if (_proposal != null && _receipt == null)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _changeDraft(
                                  widget.changes.continueEditing,
                                ),
                          child: const Text('Continue editing separately'),
                        ),
                      if (_receipt != null)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _changeDraft(
                                  (draft) => widget.changes.rebase(
                                    draft,
                                    startNew: true,
                                  ),
                                ),
                          child: const Text('Start new changes'),
                        ),
                    ],
                    if (_receipt != null)
                      OutlinedButton(
                        onPressed: _busy ? null : _readPublished,
                        child: const Text('Read published records'),
                      ),
                    if (_proposal != null && _receipt == null) ...[
                      OutlinedButton(
                        onPressed: _busy ? null : _validate,
                        child: const Text('Run checks'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _checkPublication,
                        child: const Text('Check publication'),
                      ),
                      if (_validation is EvaluatedValidation && !_approved)
                        FilledButton(
                          onPressed: _busy ? null : _approve,
                          child: const Text('Approve reviewed changes'),
                        ),
                      if (_approved ||
                          (_publication != null &&
                              !{
                                OperationState.failed,
                                OperationState.cancelled,
                              }.contains(_publication!.status.state)))
                        FilledButton(
                          onPressed: _busy ? null : _publish,
                          child: Text(
                            _publication == null
                                ? 'Publish approved changes'
                                : 'Continue publication',
                          ),
                        ),
                    ],
                    OutlinedButton(
                      onPressed: _busy || _rationaleDirty ? null : _load,
                      child: const Text('Check saved changes'),
                    ),
                    if (_draft != null &&
                        _proposal == null &&
                        operations.isNotEmpty)
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: const Text('Submit proposal'),
                      ),
                    if (_draft != null &&
                        _proposal != null &&
                        _draft!.content.proposal == null)
                      FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: const Text('Save proposal with changes'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
