import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'connection.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'draft_record_choice_field.dart';

class PassageInputFields extends StatefulWidget {
  const PassageInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusy,
  });
  final UnfinishedPassageForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedPassageForm> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<PassageInputFields> createState() => _PassageInputFieldsState();
}

class _PassageInputFieldsState extends State<PassageInputFields> {
  late final TextEditingController _version;
  String? _error;
  @override
  void initState() {
    super.initState();
    _version = TextEditingController(text: widget.form.editionVersion);
  }

  @override
  void didUpdateWidget(PassageInputFields old) {
    super.didUpdateWidget(old);
    if (_version.text != widget.form.editionVersion) {
      _version.text = widget.form.editionVersion;
    }
  }

  @override
  void dispose() {
    _version.dispose();
    super.dispose();
  }

  Future<void> _chooseEdition(RecordRef ref) async {
    widget.onBusy(true);
    try {
      if (ref.universe != null &&
          ref.universe != widget.changes.scope.universe) {
        throw const FormatException('Choose an edition in this universe.');
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
      if (row.payload is! WorkVersionRecord) {
        throw const FormatException('Choose a work edition.');
      }
      if (mounted) {
        _version.text = row.recordVersionId.value;
        setState(() => _error = null);
        widget.onChanged(
          widget.form.copyWith(
            edition: ExpressionReferenceInput(
              record: row.identity.recordId.value,
              universe: row.identity.universeId.value,
            ),
            editionVersion: _version.text,
          ),
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not read the selected edition. Check access and retry.',
        );
      }
    } finally {
      if (mounted) widget.onBusy(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedPassageForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          initialValue: f.passageId,
          enabled: !disabled,
          decoration: const InputDecoration(
            labelText: 'Authored passage identifier',
          ),
          onChanged: (v) => change(f.copyWith(passageId: v)),
        ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.workVersion,
          label: 'Pinned work edition',
          record: f.edition.record,
          universe: f.edition.universe,
          disabled: disabled,
          onChanged: _chooseEdition,
        ),
        const Text(
          'Choosing an edition pins its version at this draft’s saved revision. Reopening does not advance that pin.',
        ),
        TextField(
          controller: _version,
          enabled: !disabled,
          decoration: const InputDecoration(
            labelText: 'Exact edition record version',
          ),
          onChanged: (v) => change(f.copyWith(editionVersion: v)),
        ),
        SwitchListTile(
          title: const Text('Include a source anchor'),
          value: f.anchorEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(anchorEnabled: v)),
        ),
        if (f.anchorEnabled)
          DraftRecordChoiceField(
            changes: widget.changes,
            draft: widget.draft,
            kind: RecordKind.anchor,
            label: 'Source anchor',
            record: f.anchor.record,
            universe: f.anchor.universe,
            disabled: disabled,
            onChanged: (ref) => change(
              f.copyWith(
                anchor: ExpressionReferenceInput(
                  record: ref.record.value,
                  universe: ref.universe?.value ?? '',
                ),
              ),
            ),
          ),
        if (_error != null) Text(_error!),
      ],
    );
  }
}
