import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'connection.dart';
import 'draft_record_choices.dart';
import 'record_browser.dart';
import 'world_association_input_fields.dart';
import 'draft_record_choice_field.dart';

class SceneInputFields extends StatefulWidget {
  const SceneInputFields({
    super.key,
    required this.form,
    required this.changes,
    required this.draft,
    required this.disabled,
    required this.onChanged,
    required this.onBusy,
  });
  final UnfinishedSceneForm form;
  final SavedChanges changes;
  final SavedDraft draft;
  final bool disabled;
  final ValueChanged<UnfinishedSceneForm> onChanged;
  final ValueChanged<bool> onBusy;
  @override
  State<SceneInputFields> createState() => _SceneInputFieldsState();
}

class _SceneInputFieldsState extends State<SceneInputFields> {
  int _layout = 0;
  late final TextEditingController _version;
  String? _error;
  @override
  void initState() {
    super.initState();
    _version = TextEditingController(text: widget.form.editionVersion);
  }

  @override
  void didUpdateWidget(SceneInputFields old) {
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
  Widget _list(
    String label,
    List<ExpressionReferenceInput> values,
    ValueChanged<List<ExpressionReferenceInput>> change, {
    RecordKind? kind,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(label),
      for (var i = 0; i < values.length; i++)
        Card(
          semanticContainer: false,
          key: ValueKey((_layout, label, i)),
          child: Column(
            children: [
              _reference('$label ${i + 1}', values[i], (v) {
                final rows = [...values];
                rows[i] = v;
                change(rows);
              }, kind: kind),
              _controls(
                i,
                values.length,
                (offset) {
                  final rows = [...values], row = rows.removeAt(i);
                  rows.insert(i + offset, row);
                  _layout++;
                  change(rows);
                },
                () {
                  _layout++;
                  change([...values]..removeAt(i));
                },
              ),
            ],
          ),
        ),
      TextButton(
        onPressed: widget.disabled
            ? null
            : () {
                _layout++;
                change([...values, const ExpressionReferenceInput()]);
              },
        child: Text('Add $label'),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) {
    final f = widget.form, disabled = widget.disabled;
    void change(UnfinishedSceneForm v) => widget.onChanged(v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (f.correctionTarget != null) ...[
          Text('Published scene: ${f.sceneId}'),
          const Text(
            'Corrections retain the scene identifier, edition pin and world associations. Explain the correction in the rationale.',
          ),
        ],
        if (f.correctionTarget == null)
          TextFormField(
            initialValue: f.sceneId,
            enabled: !disabled,
            decoration: const InputDecoration(
              labelText: 'Authored scene identifier',
            ),
            onChanged: (v) => change(f.copyWith(sceneId: v)),
          ),
        DraftRecordChoiceField(
          changes: widget.changes,
          draft: widget.draft,
          kind: RecordKind.workVersion,
          label: 'Pinned work edition',
          record: f.edition.record,
          universe: f.edition.universe,
          disabled: disabled || f.correctionTarget != null,
          onChanged: _chooseEdition,
        ),
        const Text(
          'Choosing an edition pins its version at this draft’s saved revision. Reopening does not advance that pin. Reader disclosures require an edition bound to one canon revision and records matching that canon.',
        ),
        if (f.correctionTarget != null)
          Text('Pinned edition: ${f.edition.record} · ${f.editionVersion}'),
        if (f.correctionTarget == null)
          TextField(
            controller: _version,
            enabled: !disabled,
            decoration: const InputDecoration(
              labelText: 'Exact edition record version',
            ),
            onChanged: (v) => change(f.copyWith(editionVersion: v)),
          ),
        SwitchListTile(
          title: const Text('Include a viewpoint'),
          value: f.viewpointEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(viewpointEnabled: v)),
        ),
        if (f.viewpointEnabled)
          _reference(
            'Viewpoint',
            f.viewpoint,
            (v) => change(f.copyWith(viewpoint: v)),
          ),
        SwitchListTile(
          title: const Text('Include a narration context'),
          value: f.narrationEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(narrationEnabled: v)),
        ),
        if (f.narrationEnabled)
          _reference(
            'Narration context',
            f.narration,
            (v) => change(f.copyWith(narration: v)),
            kind: RecordKind.representedContext,
          ),
        SwitchListTile(
          title: const Text('Include a reader-order position'),
          value: f.positionEnabled,
          onChanged: disabled
              ? null
              : (v) => change(f.copyWith(positionEnabled: v)),
        ),
        if (f.positionEnabled)
          TextFormField(
            initialValue: f.position,
            enabled: !disabled,
            decoration: const InputDecoration(
              labelText: 'Authored reader-order position',
            ),
            onChanged: (v) => change(f.copyWith(position: v)),
          ),
        _list(
          'Disclosed record',
          f.disclosed,
          (v) => change(f.copyWith(disclosed: v)),
        ),
        _list(
          'Depicted event',
          f.depicted,
          (v) => change(f.copyWith(depicted: v)),
          kind: RecordKind.event,
        ),
        if (f.correctionTarget != null)
          Text('Retained world associations: ${f.associations.length}'),
        if (f.correctionTarget == null) ...[
          const Text('World associations'),
          for (var i = 0; i < f.associations.length; i++)
            Card(
              semanticContainer: false,
              key: ValueKey((_layout, 'world', i)),
              child: Column(
                children: [
                  WorldAssociationInputFields(
                    input: f.associations[i],
                    original: f.associations[i].originalOrdinal == null
                        ? null
                        : f.original?.worldAssociations.elementAtOrNull(
                            f.associations[i].originalOrdinal!,
                          ),
                    changes: widget.changes,
                    draft: widget.draft,
                    disabled: disabled,
                    onChanged: (v) {
                      final rows = [...f.associations];
                      rows[i] = v;
                      change(f.copyWith(associations: rows));
                    },
                  ),
                  _controls(
                    i,
                    f.associations.length,
                    (offset) {
                      final rows = [...f.associations], row = rows.removeAt(i);
                      rows.insert(i + offset, row);
                      _layout++;
                      change(f.copyWith(associations: rows));
                    },
                    () {
                      _layout++;
                      change(
                        f.copyWith(
                          associations: [...f.associations]..removeAt(i),
                        ),
                      );
                    },
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
                        associations: [
                          ...f.associations,
                          WorkAssociationInput(),
                        ],
                      ),
                    );
                  },
            child: const Text('Add world association'),
          ),
        ],
        if (_error != null) Text(_error!),
      ],
    );
  }
}
