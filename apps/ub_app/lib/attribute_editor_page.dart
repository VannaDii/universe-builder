import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'attribute_draft.dart';
import 'connection.dart';
import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'record_fields.dart';
import 'record_reference_fields.dart';
import 'saved_changes.dart';
import 'value_input_fields.dart';
import 'assertion_evidence_fields.dart';

class AttributeEditorPage extends StatefulWidget {
  const AttributeEditorPage({
    super.key,
    required this.changes,
    required this.draft,
    required this.index,
  }) : publishedEntity = null,
       openedRevision = null,
       relationship = false;
  const AttributeEditorPage.create({
    super.key,
    required this.changes,
    required this.draft,
    required this.publishedEntity,
    required this.openedRevision,
    this.relationship = false,
  }) : index = null;
  final bool relationship;
  final SavedChanges changes;
  final SavedDraft draft;
  final int? index;
  final RecordVersion? publishedEntity;
  final RevisionId? openedRevision;
  bool get creating => publishedEntity != null;
  @override
  State<AttributeEditorPage> createState() => _AttributeEditorPageState();
}

class _AttributeEditorPageState extends State<AttributeEditorPage> {
  late SavedDraft _draft;
  UnfinishedAttributeForm? _form;
  SavedDraft get _choices => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: _form!.baseRevision,
      representedContext: _form!.representedContext,
      operations: [],
      rationale: '',
    ),
  );

  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _updating = false,
      _dirty = false,
      _leaving = false,
      _stale = false;
  String? _error, _updated;
  Timer? _autosave;
  SavedDraft? _result;
  late EditorFormScope _scope;
  bool get _added =>
      widget.creating &&
      _form?.creationInput != null &&
      _draft.content.operations.any(
        (op) =>
            (op is AssertPropositionOperation ||
                op is RecordRelationOperation) &&
            attributeClientRef(op) == _form!.creationInput!.operationRef,
      );
  bool get _disabled =>
      _loading || _saving || _updating || _form == null || _added;
  DomainOperation? get _source =>
      widget.creating ? null : _draft.content.operations[widget.index!];
  DomainValue? get _value => _source == null ? null : attributeValue(_source!);
  AttributeEvidence get _evidence => widget.creating
      ? newAttributeEvidence(
          widget.changes.scope.universe,
          _form?.representedContext ?? widget.changes.scope.representedContext!,
        )
      : attributeEvidence(_source!);
  UnfinishedAttributeForm _freshForm() => widget.creating
      ? newAttributeForm(
          draft: _draft,
          entity: widget.publishedEntity!,
          relationship: widget.relationship,
          baseRevision: widget.openedRevision,
          representedContext: widget.changes.scope.representedContext,
        )
      : attributeFormFromDraft(_draft, widget.index!);
  @override
  void initState() {
    super.initState();
    _draft = widget.draft;
    final scope = widget.changes.scope;
    _scope = EditorFormScope(
      instance: scope.instance,
      profile: scope.profile,
      universe: scope.universe,
      continuity: scope.continuity,
      representedContext: widget.creating
          ? scope.representedContext
          : _draft.content.representedContext,
      attributeClientRef: widget.creating
          ? '${widget.relationship ? 'new-relationship' : 'new-attribute'}:${widget.publishedEntity!.identity.recordId.value}'
          : attributeClientRef(_source!),
    );
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.loadAttributeForm(_scope);
      if (!mounted) return;
      final form = saved?.form ?? _freshForm();
      setState(() {
        _form = form;
        _roleGeneration++;
        _generation = saved?.generation ?? BigInt.zero;
        _dirty = false;
        _stale =
            form.draftVersion != _draft.version ||
            form.baseRevision != _draft.content.baseRevision ||
            form.representedContext != _draft.content.representedContext ||
            (widget.creating &&
                (widget.openedRevision != _draft.content.baseRevision ||
                    _scope.representedContext !=
                        _draft.content.representedContext ||
                    form.creationInput?.subject.version !=
                        widget.publishedEntity!.recordVersionId));
      });
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not open the saved fields. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change(
    QualifierInput value, {
    AttributeEvidenceInput? evidence,
    AttributeCreationInput? creation,
    List<PropositionRoleInput>? roles,
  }) {
    final old = _form!;
    setState(() {
      _form = UnfinishedAttributeForm(
        baseRevision: old.baseRevision,
        representedContext: old.representedContext,
        clientRef: old.clientRef,
        draftVersion: old.draftVersion,
        value: value,
        evidenceInput: evidence ?? old.evidenceInput,
        creationInput: creation ?? old.creationInput,
        roles: roles ?? old.roles,
      );
      _dirty = true;
      _updated = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  String? _declaredRoles;
  Future<void> _selectDefinition(RecordRef ref) async {
    final creation = _form!.creationInput!;
    _change(
      _form!.value,
      creation: AttributeCreationInput(
        subject: creation.subject,
        operationRef: creation.operationRef,
        relationship: creation.relationship,
        propertyRecord: ref.record.value,
        propertyUniverse: ref.universe?.value ?? '',
      ),
    );
    if (!widget.relationship) return;
    setState(() {
      _updating = true;
      _declaredRoles = null;
    });
    try {
      final context = await openDraftChoiceContext(widget.changes, _choices);
      final record = await readContextRecord(
        session: widget.changes.session,
        universe: LibraryEntry(
          widget.changes.scope.universe,
          widget.changes.universe.value,
        ),
        context: context,
        record: ref.record,
      );
      final relation = record.payload;
      if (relation is! RelationRecord) {
        throw const FormatException('Choose a published relation definition.');
      }
      if (!mounted) return;
      setState(
        () => _declaredRoles = relation.roles
            .map(
              (r) =>
                  '${r.name}: ${r.multiplicity == Multiplicity.single ? 'single participant' : 'multiple participants'}${r.ordered ? ', ordered' : ''}',
            )
            .join('; '),
      );
      if (_roles.isEmpty) {
        _change(
          _form!.value,
          roles: [
            for (final role in relation.roles)
              PropositionRoleInput(role: role.name),
          ],
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read the relation roles. Your selected definition and input remain saved; retry when connected.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  bool get _relationship =>
      widget.relationship ||
      (_source != null && isRelationshipAssertion(_source!));
  List<PropositionRoleInput> get _roles =>
      _form!.roles ??
      [
        if (_source
            case AssertPropositionOperation(:final proposition) ||
                RecordRelationOperation(:final proposition))
          for (final r in proposition.roles)
            PropositionRoleInput(
              role: r.role,
              record: r.participant.record.value,
              universe: r.participant.universe?.value ?? '',
            ),
      ];
  Widget _roleFields() => ExpansionTile(
    key: const ValueKey('assertion participants'),
    initiallyExpanded: _relationship,
    title: const Text('Relationship participants'),
    children: [
      const Text(
        'Role order and repeated participants remain explicit. Changing a participant does not transfer ownership or create an event.',
      ),
      for (var i = 0; i < _roles.length; i++)
        Card(
          key: ValueKey((_roleGeneration, i)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  initialValue: _roles[i].role,
                  enabled: !_disabled,
                  decoration: const InputDecoration(labelText: 'Role name'),
                  onChanged: (v) {
                    final rows = [..._roles], r = rows[i];
                    rows[i] = PropositionRoleInput(
                      role: v,
                      record: r.record,
                      universe: r.universe,
                    );
                    _change(_form!.value, roles: rows);
                  },
                ),
                RecordReferenceFields(
                  changes: widget.changes,
                  draft: _choices,
                  record: _roles[i].record,
                  universe: _roles[i].universe,
                  label: 'Participant',
                  disabled: _disabled,
                  onChanged: (record, universe) {
                    final rows = [..._roles], r = rows[i];
                    rows[i] = PropositionRoleInput(
                      role: r.role,
                      record: record,
                      universe: universe,
                    );
                    _change(_form!.value, roles: rows);
                  },
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: _disabled || i == 0
                          ? null
                          : () {
                              final rows = [..._roles], row = rows.removeAt(i);
                              rows.insert(i - 1, row);
                              _roleGeneration++;
                              _change(_form!.value, roles: rows);
                            },
                      child: const Text('Move earlier'),
                    ),
                    TextButton(
                      onPressed: _disabled || i == _roles.length - 1
                          ? null
                          : () {
                              final rows = [..._roles], row = rows.removeAt(i);
                              rows.insert(i + 1, row);
                              _roleGeneration++;
                              _change(_form!.value, roles: rows);
                            },
                      child: const Text('Move later'),
                    ),
                    TextButton(
                      onPressed: _disabled
                          ? null
                          : () {
                              _roleGeneration++;
                              _change(
                                _form!.value,
                                roles: [..._roles]..removeAt(i),
                              );
                            },
                      child: const Text('Remove participant'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      TextButton(
        onPressed: _disabled
            ? null
            : () => _change(
                _form!.value,
                roles: [..._roles, const PropositionRoleInput()],
              ),
        child: const Text('Add participant'),
      ),
    ],
  );
  int _roleGeneration = 0;

  Future<void> _save() async {
    if (!_dirty || _saving || _form == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.changes.session.saveAttributeForm(
        _scope,
        _form!,
        _generation,
      );
      if (mounted) {
        setState(() {
          _form = saved.form;
          _generation = saved.generation;
          _dirty = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save these fields. Another window may have changed them. Your input remains here.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _useCurrent() async {
    _autosave?.cancel();
    try {
      if (widget.creating) {
        final latest = await widget.changes.load();
        if (latest != null) _draft = latest;
        if (_draft.content.baseRevision != widget.openedRevision ||
            _draft.content.representedContext != _scope.representedContext ||
            _draft.content.proposal != null) {
          throw const FormatException(
            'Review Changes and reopen the dossier at its current revision.',
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _form = _freshForm();
        _roleGeneration++;
        _stale = false;
        _dirty = true;
        _updated = null;
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not open the current draft. Retry when connected.',
        );
      }
    }
  }

  Future<void> _update() async {
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _form == null || _stale) return;
    setState(() {
      _updating = true;
      _error = null;
    });
    try {
      final DraftContent content;
      SavedDraft current = _draft;
      if (widget.creating) {
        current = await widget.changes.load() ?? _draft;
        _draft = current;
        final creation = _form!.creationInput!;
        final context = await openDraftChoiceContext(widget.changes, current);
        if (creation.propertyUniverse != widget.changes.scope.universe.value) {
          throw const FormatException(
            'Choose an existing definition in this universe.',
          );
        }
        final property = await readContextRecord(
          session: widget.changes.session,
          universe: LibraryEntry(
            widget.changes.scope.universe,
            widget.changes.universe.value,
          ),
          context: context,
          record: RecordId.parse(creation.propertyRecord),
        );
        final entity = await readContextRecord(
          session: widget.changes.session,
          universe: LibraryEntry(
            widget.changes.scope.universe,
            widget.changes.universe.value,
          ),
          context: context,
          record: creation.subject.record,
        );
        content = appendDraftAttribute(
          draft: current,
          form: _form!,
          entity: entity,
          property: property,
        );
      } else {
        content = replaceDraftAttribute(
          draft: current,
          index: widget.index!,
          form: _form!,
        );
      }
      final saved =
          content.toWire().toText() == current.content.toWire().toText()
          ? current
          : await widget.changes.saveContent(current, content);
      if (!mounted) return;
      setState(() {
        _draft = saved;
        _result = saved;
        _roleGeneration++;
        _form = widget.creating
            ? UnfinishedAttributeForm(
                baseRevision: _form!.baseRevision,
                representedContext: _form!.representedContext,
                clientRef: _form!.clientRef,
                draftVersion: saved.version,
                value: _form!.value,
                evidenceInput: _form!.evidenceInput,
                creationInput: _form!.creationInput,
                roles: _form!.roles,
              )
            : attributeFormFromDraft(saved, widget.index!);
        _dirty = true;
        _stale = false;
        _updated = _relationship
            ? 'Relationship assertion saved in Changes. Return to Changes to review it.'
            : 'Attribute saved in Changes. Return to Changes to review it.';
      });
      await _save();
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          if (widget.creating) {
            _stale =
                _form!.draftVersion != _draft.version ||
                _form!.baseRevision != _draft.content.baseRevision ||
                _form!.representedContext != _draft.content.representedContext;
          }
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm saving the attribute. Your entered fields remain saved. Check Changes before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _leave() async {
    if (_loading || _saving || _updating) return;
    _autosave?.cancel();
    await _save();
    if (!mounted || _dirty || _saving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop(_result);
  }

  @override
  Widget build(BuildContext context) => PopScope<SavedDraft>(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.creating
              ? widget.relationship
                    ? 'Add relationship'
                    : 'Add factual attribute'
              : _relationship
              ? 'Edit relationship assertion'
              : 'Edit attribute',
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (_source) {
                  AddNamedAttributeOperation(:final namespace, :final key) =>
                    '$namespace: $key',
                  _ =>
                    _relationship
                        ? 'Relationship assertion'
                        : 'Factual attribute',
                }, style: Theme.of(context).textTheme.titleLarge),
                Text(
                  _relationship
                      ? 'Unfinished edits stay on this device. The relation definition and subject remain intact. Save into Changes for review before publication.'
                      : 'Unfinished edits stay on this device. The property definition remains intact. Assertion details change only when edited. Save into Changes for review before publication.',
                ),
                if (_loading || _saving || _updating)
                  const LinearProgressIndicator(),
                if (_stale) ...[
                  const Text(
                    'Recovered edits belong to an earlier draft. Use current draft fields before saving changes.',
                  ),
                  TextButton(
                    onPressed: _disabled ? null : _useCurrent,
                    child: const Text('Use current draft fields'),
                  ),
                ],
                if (widget.creating && _form?.creationInput != null)
                  DraftRecordChoiceField(
                    changes: widget.changes,
                    draft: _draft,
                    kind: widget.relationship
                        ? RecordKind.relation
                        : RecordKind.property,
                    label: widget.relationship
                        ? 'Relation definition'
                        : 'Property',
                    record: _form!.creationInput!.propertyRecord,
                    universe: _form!.creationInput!.propertyUniverse,
                    disabled: _disabled,
                    onChanged: _selectDefinition,
                  ),
                if (widget.relationship &&
                    _form?.creationInput != null &&
                    _form!.creationInput!.propertyRecord.isNotEmpty) ...[
                  if (_declaredRoles != null)
                    Text('Declared roles: $_declaredRoles'),
                  TextButton(
                    onPressed: _disabled
                        ? null
                        : () => _selectDefinition(
                            RecordRef(
                              record: RecordId.parse(
                                _form!.creationInput!.propertyRecord,
                              ),
                              universe: UniverseId.parse(
                                _form!.creationInput!.propertyUniverse,
                              ),
                            ),
                          ),
                    child: const Text('Show relation roles'),
                  ),
                ],
                if (_form != null &&
                    !_relationship &&
                    (widget.creating || _value != null))
                  ValueInputFields(
                    changes: widget.changes,
                    draft: _choices,
                    key: const ValueKey('attribute value'),
                    input: _form!.value,
                    original: _value,
                    disabled: _disabled,
                    label: 'Attribute value',
                    onChanged: _change,
                  ),
                if (_form != null) ...[
                  if (widget.relationship ||
                      _source is AssertPropositionOperation ||
                      _source is RecordRelationOperation)
                    _roleFields(),
                  AssertionEvidenceFields(
                    input: _form!.evidenceInput,
                    original: _evidence,
                    changes: widget.changes,
                    draft: _draft,
                    disabled: _disabled,
                    onChanged: (v) => _change(_form!.value, evidence: v),
                  ),
                ],
                if (_source != null)
                  ExpansionTile(
                    key: const ValueKey('original attribute'),
                    title: const Text('Original attribute and evidence'),
                    children: [ExactFields(value: _source!.toWire())],
                  ),
                Text(
                  _dirty
                      ? 'Unsaved fields'
                      : _generation == BigInt.zero
                      ? 'No saved fields yet'
                      : 'Saved on this device',
                ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_updated != null)
                  Semantics(liveRegion: true, child: Text(_updated!)),
                FilledButton(
                  onPressed: _disabled || _stale ? null : _update,
                  child: Text(
                    widget.creating
                        ? 'Add to Changes'
                        : _relationship
                        ? 'Save relationship changes'
                        : 'Save attribute changes',
                  ),
                ),
                if (_added) ...[
                  const Text(
                    'This fact is in Changes. Review or edit it there before publication.',
                  ),
                  TextButton(
                    onPressed: _loading || _saving || _updating
                        ? null
                        : _useCurrent,
                    child: Text(
                      widget.relationship
                          ? 'Start another relationship'
                          : 'Start another attribute',
                    ),
                  ),
                ],
                TextButton(
                  onPressed: _disabled || !_dirty ? null : _save,
                  child: const Text('Save unfinished work'),
                ),
                if (_error != null)
                  TextButton(
                    onPressed: _loading || _saving || _updating ? null : _load,
                    child: const Text('Reload saved fields'),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
