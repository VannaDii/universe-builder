import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'saved_changes.dart';
import 'scope_input_fields.dart';

class InitializationInputFields extends StatefulWidget {
  const InitializationInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusy,
  });
  final UnfinishedInitializationForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedInitializationForm> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<InitializationInputFields> createState() =>
      _InitializationInputFieldsState();
}

class _InitializationInputFieldsState extends State<InitializationInputFields> {
  String? _error;
  ExpressionReferenceInput _input(RecordRef ref) => ExpressionReferenceInput(
    record: ref.record.value,
    universe: ref.universe?.value ?? '',
  );
  Future<void> _chooseDefinition(RecordRef ref) async {
    widget.onBusy(true);
    try {
      final context = await openDraftChoiceContext(
        widget.changes,
        widget.draft,
      );
      final source = await readDraftChoiceVersion(
        changes: widget.changes,
        context: context,
        reference: ref,
        kind: RecordKind.assertion,
      );
      if ((source.payload as AssertionRecord).attributeMode !=
          AttributeMode.initialValue) {
        throw const FormatException('Choose an initial-value assertion.');
      }
      if (!mounted) return;
      setState(() => _error = null);
      widget.onChanged(
        widget.form.copyWith(
          definition: VersionRef(
            universe: source.identity.universeId,
            record: source.identity.recordId,
            version: source.recordVersionId,
          ),
        ),
      );
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not read this assertion. Check the connection and retry.',
        );
      }
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.entity,
          label: 'Instance',
          record: f.instance.record,
          universe: f.instance.universe,
          disabled: widget.disabled,
          onChanged: (ref) =>
              widget.onChanged(f.copyWith(instance: _input(ref))),
        ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.event,
          label: 'Exact occurred start event',
          record: f.start.record,
          universe: f.start.universe,
          disabled: widget.disabled,
          onChanged: (ref) => widget.onChanged(f.copyWith(start: _input(ref))),
        ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.assertion,
          label: 'Source initial-value assertion',
          record: f.definition?.record.value ?? '',
          universe: f.definition?.universe?.value ?? '',
          version: f.definition?.version.value ?? '',
          disabled: widget.disabled,
          onChanged: _chooseDefinition,
        ),
        const Text(
          'Selecting a source pins its published version at this draft’s revision. Initialization applies its starting value once; it does not refill an instance after use.',
        ),
        ScopeInputFields(
          input: f.scope,
          changes: widget.changes,
          draft: widget.draft,
          disabled: widget.disabled,
          explicitWorldScope: true,
          contextReadOnly: true,
          onChanged: (scope) => widget.onChanged(f.copyWith(scope: scope)),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('end', f.endKind)),
          initialValue: f.endKind.isEmpty ? null : f.endKind,
          decoration: const InputDecoration(
            labelText: 'Starting fact validity',
          ),
          items: const [
            DropdownMenuItem(value: 'unbounded', child: Text('Unbounded end')),
            DropdownMenuItem(
              value: 'exact',
              child: Text('Exact exclusive end'),
            ),
          ],
          onChanged: widget.disabled
              ? null
              : (v) {
                  if (v != null) widget.onChanged(f.copyWith(endKind: v));
                },
        ),
        if (f.endKind == 'exact')
          TextFormField(
            initialValue: f.endCoordinate,
            enabled: !widget.disabled,
            decoration: const InputDecoration(
              labelText: 'Exclusive end',
              helperText: 'Use a date in the context’s calendar, or an exact coordinate in the start event’s calendar.',
            ),
            onChanged: (v) => widget.onChanged(f.copyWith(endCoordinate: v)),
          ),
        TextFormField(
          initialValue: f.rationale,
          enabled: !widget.disabled,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Reason for these changes',
          ),
          onChanged: (v) => widget.onChanged(f.copyWith(rationale: v)),
        ),
        if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
      ],
    );
  }
}
