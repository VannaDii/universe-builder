import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'draft_record_choice_field.dart';
import 'saved_changes.dart';

class IssueDecisionInputFields extends StatefulWidget {
  const IssueDecisionInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedIssueDecisionForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedIssueDecisionForm> onChanged;
  @override
  State<IssueDecisionInputFields> createState() =>
      _IssueDecisionInputFieldsState();
}

class _IssueDecisionInputFieldsState extends State<IssueDecisionInputFields> {
  late final TextEditingController _scope;
  int _layout = 0;
  @override
  void initState() {
    super.initState();
    _scope = TextEditingController(text: widget.form.scope);
  }

  @override
  void didUpdateWidget(IssueDecisionInputFields old) {
    super.didUpdateWidget(old);
    if (_scope.text != widget.form.scope) _scope.text = widget.form.scope;
  }

  @override
  void dispose() {
    _scope.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedIssueDecisionForm v) => widget.onChanged(v);
    void rows(List<String> values) {
      _layout++;
      change(f.copyWith(fingerprints: values));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey(('mode', f.mode)),
          initialValue: f.mode.isEmpty ? null : f.mode,
          decoration: const InputDecoration(labelText: 'Decision'),
          items: const [
            DropdownMenuItem(value: 'accept', child: Text('Accept')),
            DropdownMenuItem(value: 'defer', child: Text('Defer')),
            DropdownMenuItem(value: 'resolve', child: Text('Resolve')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(mode: v));
                },
        ),
        const Text('Exact finding identities'),
        const Text(
          'Use the fingerprint shown in a check result’s rule, records and evidence. Preserve the exact value; a decision does not establish facts or grant permissions.',
        ),
        for (var i = 0; i < f.fingerprints.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, i)),
            child: Column(
              children: [
                TextFormField(
                  initialValue: f.fingerprints[i],
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: 'Finding identity ${i + 1}',
                  ),
                  onChanged: (v) {
                    final values = [...f.fingerprints];
                    values[i] = v;
                    change(f.copyWith(fingerprints: values));
                  },
                ),
                Wrap(
                  children: [
                    TextButton(
                      onPressed: disabled || i == 0
                          ? null
                          : () {
                              final values = [...f.fingerprints],
                                  row = values.removeAt(i);
                              values.insert(i - 1, row);
                              rows(values);
                            },
                      child: const Text('Move earlier'),
                    ),
                    TextButton(
                      onPressed: disabled || i == f.fingerprints.length - 1
                          ? null
                          : () {
                              final values = [...f.fingerprints],
                                  row = values.removeAt(i);
                              values.insert(i + 1, row);
                              rows(values);
                            },
                      child: const Text('Move later'),
                    ),
                    TextButton(
                      onPressed: disabled
                          ? null
                          : () => rows([...f.fingerprints]..removeAt(i)),
                      child: const Text('Remove identity'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled ? null : () => rows([...f.fingerprints, '']),
          child: const Text('Add finding identity'),
        ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: null,
          label: 'Scope record',
          record: '',
          universe: '',
          disabled: disabled,
          onChanged: (ref) {
            _scope.text = ref.record.value;
            change(f.copyWith(scope: ref.record.value));
          },
        ),
        TextField(
          controller: _scope,
          enabled: !disabled,
          decoration: const InputDecoration(
            labelText: 'Authored decision scope',
          ),
          onChanged: (v) => change(f.copyWith(scope: v)),
        ),
        TextFormField(
          initialValue: f.rationale,
          enabled: !disabled,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Decision rationale'),
          onChanged: (v) => change(f.copyWith(rationale: v)),
        ),
      ],
    );
  }
}
