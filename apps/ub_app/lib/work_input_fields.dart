import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'draft_record_choice_field.dart';
import 'value_input_fields.dart';
import 'draft_record_choices.dart';
import 'temporal_validity_fields.dart';
import 'temporal_validity_draft.dart';

class WorkInputFields extends StatefulWidget {
  const WorkInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
  });
  final UnfinishedWorkForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedWorkForm> onChanged;
  @override
  State<WorkInputFields> createState() => _WorkInputFieldsState();
}

class _WorkInputFieldsState extends State<WorkInputFields> {
  int _layout = 0;
  Widget _reference(
    String label,
    ExpressionReferenceInput input,
    ValueChanged<ExpressionReferenceInput> change, {
    RecordKind? kind,
  }) => DraftRecordChoiceField(
    changes: widget.changes,
    draft: widget.draft,
    kind: kind,
    label: label,
    record: input.record,
    universe: input.universe,
    disabled: widget.disabled,
    onChanged: (ref) => change(
      ExpressionReferenceInput(
        record: ref.record.value,
        universe: ref.universe?.value ?? '',
      ),
    ),
  );
  Widget _controls(
    int i,
    int length,
    void Function(int) move,
    VoidCallback remove,
  ) => Wrap(
    children: [
      TextButton(
        onPressed: widget.disabled || i == 0 ? null : () => move(-1),
        child: const Text('Move earlier'),
      ),
      TextButton(
        onPressed: widget.disabled || i == length - 1 ? null : () => move(1),
        child: const Text('Move later'),
      ),
      TextButton(
        onPressed: widget.disabled ? null : remove,
        child: const Text('Remove entry'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedWorkForm v) => widget.onChanged(v);
    Widget text(String label, String value, ValueChanged<String> callback) =>
        TextFormField(
          initialValue: value,
          enabled: !disabled,
          decoration: InputDecoration(labelText: label),
          onChanged: callback,
        );
    Widget controls<T>(int i, List<T> values, ValueChanged<List<T>> callback) =>
        _controls(
          i,
          values.length,
          (offset) {
            final rows = [...values], row = rows.removeAt(i);
            rows.insert(i + offset, row);
            _layout++;
            callback(rows);
          },
          () {
            _layout++;
            callback([...values]..removeAt(i));
          },
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        text('Work title', f.title, (v) => change(f.copyWith(title: v))),
        DropdownButtonFormField<String>(
          key: ValueKey(('kind', f.kind)),
          initialValue: f.kind.isEmpty ? null : f.kind,
          decoration: const InputDecoration(labelText: 'Work kind'),
          items: const [
            DropdownMenuItem(value: 'novel', child: Text('Novel')),
            DropdownMenuItem(value: 'story', child: Text('Story')),
            DropdownMenuItem(
              value: 'series_chapter',
              child: Text('Series chapter'),
            ),
            DropdownMenuItem(value: 'play', child: Text('Play')),
            DropdownMenuItem(value: 'film', child: Text('Film')),
            DropdownMenuItem(value: 'other', child: Text('Other')),
          ],
          onChanged: disabled
              ? null
              : (v) {
                  if (v != null) change(f.copyWith(kind: v));
                },
        ),
        const Text('Work labels'),
        for (var i = 0; i < f.labels.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, 'label', i)),
            child: Column(
              children: [
                text('Label language', f.labels[i].language, (v) {
                  final rows = [...f.labels];
                  rows[i] = PropertyLabelInput(language: v, text: rows[i].text);
                  change(f.copyWith(labels: rows));
                }),
                text('Label text', f.labels[i].text, (v) {
                  final rows = [...f.labels];
                  rows[i] = PropertyLabelInput(
                    language: rows[i].language,
                    text: v,
                  );
                  change(f.copyWith(labels: rows));
                }),
                controls(i, f.labels, (v) => change(f.copyWith(labels: v))),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      labels: [...f.labels, const PropertyLabelInput()],
                    ),
                  );
                },
          child: const Text('Add label'),
        ),
        const Text('Source references'),
        for (var i = 0; i < f.sources.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, 'source', i)),
            child: Column(
              children: [
                _reference('Source reference ${i + 1}', f.sources[i], (v) {
                  final rows = [...f.sources];
                  rows[i] = v;
                  change(f.copyWith(sources: rows));
                }),
                controls(i, f.sources, (v) => change(f.copyWith(sources: v))),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      sources: [...f.sources, const ExpressionReferenceInput()],
                    ),
                  );
                },
          child: const Text('Add source reference'),
        ),
        const Text('Edition references'),
        for (var i = 0; i < f.versions.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, 'version', i)),
            child: Column(
              children: [
                _reference(
                  'Edition ${i + 1}',
                  ExpressionReferenceInput(
                    record: f.versions[i],
                    universe: widget.changes.scope.universe.value,
                  ),
                  (v) {
                    final rows = [...f.versions];
                    rows[i] = v.record;
                    change(f.copyWith(versions: rows));
                  },
                  kind: RecordKind.workVersion,
                ),
                controls(i, f.versions, (v) => change(f.copyWith(versions: v))),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(f.copyWith(versions: [...f.versions, '']));
                },
          child: const Text('Add edition reference'),
        ),
        const Text('World associations'),
        for (var i = 0; i < f.associations.length; i++)
          Card(
            semanticContainer: false,
            key: ValueKey((_layout, 'association', i)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Builder(
                  builder: (context) {
                    final a = f.associations[i];
                    final original = a.originalOrdinal == null
                        ? null
                        : f.original?.worldAssociations.elementAtOrNull(
                            a.originalOrdinal!,
                          );
                    void association(WorkAssociationInput v) {
                      final rows = [...f.associations];
                      rows[i] = v;
                      change(f.copyWith(associations: rows));
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DraftRecordChoiceField(
                          changes: widget.changes,
                          draft: widget.draft,
                          kind: RecordKind.world,
                          label: 'Associated world',
                          record: a.world.isEmpty
                              ? ''
                              : worldChoiceRecord(a.world).value,
                          universe: widget.changes.scope.universe.value,
                          disabled: disabled,
                          onChanged: (ref) => association(
                            a.copyWith(world: worldFromChoice(ref).value),
                          ),
                        ),
                        text(
                          'World role',
                          a.role,
                          (v) => association(a.copyWith(role: v)),
                        ),
                        DropdownButtonFormField<String>(
                          key: ValueKey(('validity', a.validity.kind)),
                          initialValue:
                              {
                                'unknown',
                                'unspecified',
                                'condition_dependent',
                              }.contains(a.validity.kind)
                              ? a.validity.kind
                              : 'temporal',
                          decoration: const InputDecoration(
                            labelText: 'Association validity',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'unknown',
                              child: Text('Unknown'),
                            ),
                            DropdownMenuItem(
                              value: 'unspecified',
                              child: Text('Unspecified'),
                            ),
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
                                    association(
                                      a.copyWith(
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
                        }.contains(a.validity.kind))
                          TemporalValidityFields(
                            input: a.validity,
                            originalAmounts: temporalOriginalAmounts(
                              original?.validity,
                            ),
                            changes: widget.changes,
                            draft: widget.draft,
                            disabled: disabled,
                            onChanged: (v) =>
                                association(a.copyWith(validity: v)),
                          ),
                        const Text('Association qualifiers'),
                        for (var q = 0; q < a.qualifiers.length; q++)
                          Column(
                            key: ValueKey((_layout, 'qualifier', q)),
                            children: [
                              ValueInputFields(
                                input: a.qualifiers[q],
                                original: original
                                    ?.qualifiers[a.qualifiers[q].originalKey],
                                changes: widget.changes,
                                draft: widget.draft,
                                disabled: disabled,
                                named: true,
                                onChanged: (v) {
                                  final rows = [...a.qualifiers];
                                  rows[q] = v;
                                  association(a.copyWith(qualifiers: rows));
                                },
                              ),
                              TextButton(
                                onPressed: disabled
                                    ? null
                                    : () {
                                        _layout++;
                                        association(
                                          a.copyWith(
                                            qualifiers: [...a.qualifiers]
                                              ..removeAt(q),
                                          ),
                                        );
                                      },
                                child: const Text('Remove qualifier'),
                              ),
                            ],
                          ),
                        TextButton(
                          onPressed: disabled
                              ? null
                              : () {
                                  _layout++;
                                  association(
                                    a.copyWith(
                                      qualifiers: [
                                        ...a.qualifiers,
                                        const QualifierInput(),
                                      ],
                                    ),
                                  );
                                },
                          child: const Text('Add qualifier'),
                        ),
                      ],
                    );
                  },
                ),
                controls(
                  i,
                  f.associations,
                  (v) => change(f.copyWith(associations: v)),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: disabled
              ? null
              : () {
                  _layout++;
                  change(
                    f.copyWith(
                      associations: [...f.associations, WorkAssociationInput()],
                    ),
                  );
                },
          child: const Text('Add world association'),
        ),
      ],
    );
  }
}
