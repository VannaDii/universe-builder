import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'connection.dart';
import 'draft_record_choices.dart';
import 'draft_record_choice_field.dart';
import 'record_browser.dart';
import 'scope_input_fields.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class ExceptionInputFields extends StatefulWidget {
  const ExceptionInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusy,
  });
  final UnfinishedExceptionForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedExceptionForm> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<ExceptionInputFields> createState() => _ExceptionInputFieldsState();
}

class _ExceptionInputFieldsState extends State<ExceptionInputFields> {
  late final TextEditingController _pin;
  String? _error;
  @override
  void initState() {
    super.initState();
    _pin = TextEditingController(text: widget.form.ruleVersion);
  }

  @override
  void didUpdateWidget(ExceptionInputFields old) {
    super.didUpdateWidget(old);
    if (_pin.text != widget.form.ruleVersion) {
      _pin.text = widget.form.ruleVersion;
    }
  }

  @override
  void dispose() {
    _pin.dispose();
    super.dispose();
  }

  Future<void> _chooseRule(RecordRef ref) async {
    widget.onBusy(true);
    try {
      if (ref.universe != null &&
          ref.universe != widget.changes.scope.universe) {
        throw const FormatException(
          'Choose a rule or boundary in this universe.',
        );
      }
      final context = await openDraftChoiceContext(
        widget.changes,
        widget.draft,
      );
      final row = await readContextRecord(
        session: widget.changes.session,
        universe: LibraryEntry(
          widget.changes.scope.universe,
          widget.changes.universe.value,
        ),
        context: context,
        record: ref.record,
      );
      if (widget.form.fictionalDeparture && row.payload is! RuleRecord) {
        throw const FormatException('Choose a rule for a fictional departure.');
      }
      if (row.payload is! RuleRecord && row.payload is! BoundaryRecord) {
        throw const FormatException('Choose a rule or creative boundary.');
      }
      if (mounted) {
        _pin.text = row.recordVersionId.value;
        setState(() => _error = null);
        widget.onChanged(
          widget.form.copyWith(
            rule: ExpressionReferenceInput(
              record: ref.record.value,
              universe: ref.universe?.value ?? '',
            ),
            ruleVersionEnabled: true,
            ruleVersion: _pin.text,
          ),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Choose an accessible rule or creative boundary and retry.',
        );
      }
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedExceptionForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Fictional departure'),
          subtitle: const Text(
            'Declare fiction within this exception’s exact rule, context, worlds and time. Checks retain their factual outcome and identify the departure separately.',
          ),
          value: f.fictionalDeparture,
          onChanged: disabled
              ? null
              : (value) => change(f.copyWith(fictionalDeparture: value)),
        ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: f.fictionalDeparture ? RecordKind.rule : null,
          label: f.fictionalDeparture ? 'Rule' : 'Rule or boundary',
          record: f.rule.record,
          universe: f.rule.universe,
          disabled: disabled,
          onChanged: _chooseRule,
        ),
        const Text(
          'Selecting a rule or boundary pins the exact version at this draft’s saved revision. Existing checks require an applicable version and an accepting author decision for that target.',
        ),
        SwitchListTile(
          title: const Text('Pin a rule or boundary version'),
          value: f.ruleVersionEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(ruleVersionEnabled: v)),
        ),
        if (f.ruleVersionEnabled)
          TextField(
            controller: _pin,
            enabled: !disabled,
            decoration: const InputDecoration(
              labelText: 'Exact rule or boundary version',
            ),
            onChanged: (v) => change(f.copyWith(ruleVersion: v)),
          ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.issueDecision,
          label: 'Authorizing decision',
          record: f.decision.record,
          universe: f.decision.universe,
          disabled: disabled,
          onChanged: (ref) => change(
            f.copyWith(
              decision: ExpressionReferenceInput(
                record: ref.record.value,
                universe: ref.universe?.value ?? '',
              ),
            ),
          ),
        ),
        ExpansionTile(
          title: const Text('Exception scope'),
          children: [
            ScopeInputFields(
              input: f.scope,
              changes: widget.changes,
              draft: widget.draft,
              disabled: disabled,
              onChanged: (v) => change(f.copyWith(scope: v)),
            ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey(('validity', f.validity.kind)),
          initialValue:
              {
                'unknown',
                'unspecified',
                'condition_dependent',
              }.contains(f.validity.kind)
              ? f.validity.kind
              : 'temporal',
          decoration: const InputDecoration(labelText: 'Exception validity'),
          items: const [
            DropdownMenuItem(value: 'unknown', child: Text('Unknown')),
            DropdownMenuItem(value: 'unspecified', child: Text('Unspecified')),
            DropdownMenuItem(
              value: 'condition_dependent',
              child: Text('Condition dependent'),
            ),
            DropdownMenuItem(
              value: 'temporal',
              child: Text('Temporal validity'),
            ),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) {
                    change(
                      f.copyWith(
                        validity: v == 'temporal'
                            ? const TemporalValidityInput()
                            : TemporalValidityInput(kind: v),
                      ),
                    );
                  }
                },
        ),
        if (!{
          'unknown',
          'unspecified',
          'condition_dependent',
        }.contains(f.validity.kind))
          TemporalValidityFields(
            input: f.validity,
            originalAmounts: temporalOriginalAmounts(f.original?.validity),
            changes: widget.changes,
            draft: widget.draft,
            disabled: disabled,
            onChanged: (v) => change(f.copyWith(validity: v)),
          ),
        TextFormField(
          initialValue: f.rationale,
          enabled: !disabled,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Exception rationale'),
          onChanged: (v) => change(f.copyWith(rationale: v)),
        ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}
