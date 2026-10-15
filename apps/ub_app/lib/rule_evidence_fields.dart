import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'draft_record_choice_field.dart';
import 'draft_record_choices.dart';
import 'saved_changes.dart';

class RuleEvidenceFields extends StatefulWidget {
  const RuleEvidenceFields({
    super.key,
    required this.input,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusyChanged,
  });
  final RuleEvidenceInput input;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<RuleEvidenceInput> onChanged;
  final ValueChanged<bool> onBusyChanged;
  @override
  State<RuleEvidenceFields> createState() => _RuleEvidenceFieldsState();
}

class _RuleEvidenceFieldsState extends State<RuleEvidenceFields> {
  bool _busy = false;
  String? _error;
  Future<void> _select(int index, RecordRef reference) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    widget.onBusyChanged(true);
    try {
      final context = await openDraftChoiceContext(
        widget.changes,
        widget.draft,
      );
      final row = await readDraftChoiceVersion(
        changes: widget.changes,
        context: context,
        reference: reference,
        kind: RecordKind.domainPack,
      );
      if (!mounted || index >= widget.input.categories.length) return;
      final categories = [...widget.input.categories];
      categories[index] = RuleEvidenceCategoryInput(
        universe: row.identity.universeId.value,
        record: row.identity.recordId.value,
        version: row.recordVersionId.value,
      );
      widget.onChanged(widget.input.copyWith(categories: categories));
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not select this published source category. Reconnect or choose again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onBusyChanged(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final input = widget.input;
    final disabled = widget.disabled || _busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Required evidence', style: TextStyle(fontSize: 20)),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Require qualifying sources'),
          subtitle: const Text(
            'Applies to this rule’s selected worlds, subjects and time. Changes take effect after review and publication.',
          ),
          value: input.enabled,
          onChanged: disabled
              ? null
              : (value) => widget.onChanged(input.copyWith(enabled: value)),
        ),
        if (input.enabled) ...[
          const Text(
            'Choose the published source categories that may support these claims. Private recollections can qualify without a public URL.',
          ),
          for (var i = 0; i < input.categories.length; i++)
            Column(
              children: [
                DraftRecordChoiceField(
                  changes: widget.changes,
                  draft: widget.draft,
                  kind: RecordKind.domainPack,
                  label: 'Source category ${i + 1}',
                  record: input.categories[i].record,
                  universe: input.categories[i].universe,
                  version: input.categories[i].version,
                  disabled: disabled,
                  onChanged: (ref) => _select(i, ref),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: disabled
                        ? null
                        : () => widget.onChanged(
                            input.copyWith(
                              categories: [...input.categories]..removeAt(i),
                            ),
                          ),
                    child: const Text('Remove category'),
                  ),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: disabled
                  ? null
                  : () => widget.onChanged(
                      input.copyWith(
                        categories: [
                          ...input.categories,
                          const RuleEvidenceCategoryInput(),
                        ],
                      ),
                    ),
              child: const Text('Add source category'),
            ),
          ),
          const Text(
            'A policy keeps its selected published source list. Publish category changes first, then choose the new selection here.',
          ),
          const SizedBox(height: 12),
          const Text('Accepted interpretation review (optional)'),
          const Text(
            'Leave both off for no interpretation-review duty. When selected, either accepted method may review what the source supports.',
          ),
          for (final method in EvidenceReviewMethod.values)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                method == EvidenceReviewMethod.humanReview
                    ? 'Human review'
                    : 'External writer review',
              ),
              value: input.reviewMethods.contains(method.wireName),
              onChanged: disabled
                  ? null
                  : (selected) => widget.onChanged(
                      input.copyWith(
                        reviewMethods: selected == true
                            ? [...input.reviewMethods, method.wireName]
                            : input.reviewMethods.where(
                                (m) => m != method.wireName,
                              ),
                      ),
                    ),
            ),
        ],
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Semantics(
            liveRegion: true,
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
