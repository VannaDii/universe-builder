import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'access_management.dart';
import 'draft_record_choice_field.dart';

class GrantEditorPage extends StatefulWidget {
  const GrantEditorPage({
    super.key,
    required this.changes,
    required this.profile,
    required this.continuities,
    required this.worlds,
    required this.revision,
    this.original,
  });
  final SavedChanges changes;
  final AccessProfile profile;
  final List<ContinuitySummary> continuities;
  final List<WorldSummary> worlds;
  final RevisionId revision;
  final GrantSpec? original;
  @override
  State<GrantEditorPage> createState() => _GrantEditorPageState();
}

class _GrantEditorPageState extends State<GrantEditorPage> {
  late bool _propose, _edit, _protected, _delegated, _shared;
  List<String>? _worlds, _entities, _predicates, _continuities;
  late TextEditingController _expiry;
  bool _busy = false;
  String? _error;
  int _layout = 0;
  @override
  void initState() {
    super.initState();
    final g = widget.original;
    _propose = g?.propose ?? false;
    _edit = g?.edit ?? false;
    _protected = g?.protected ?? false;
    _delegated = g?.limits.delegatedCommit ?? false;
    _shared = g?.limits.allowShared ?? false;
    _worlds = g?.worlds?.map((v) => v.value).toList();
    _entities = g?.limits.entities?.map((v) => v.value).toList();
    _predicates = g?.limits.predicates?.map((v) => v.value).toList();
    _continuities = g?.limits.continuities?.map((v) => v.value).toList();
    _expiry = TextEditingController(
      text: g?.limits.expiresAt?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _expiry.dispose();
    super.dispose();
  }

  SavedDraft get _choices => SavedDraft(
    version: BigInt.zero,
    content: DraftContent(
      baseRevision: widget.revision,
      representedContext: widget.changes.scope.representedContext!,
      operations: [],
      rationale: '',
    ),
  );
  Widget _flag(
    String label,
    bool value,
    ValueChanged<bool> change, {
    String? detail,
  }) => SwitchListTile(
    title: Text(label),
    subtitle: detail == null ? null : Text(detail),
    value: value,
    onChanged: _busy ? null : (v) => setState(() => change(v)),
  );
  Widget _records(
    String label,
    List<String>? values,
    RecordKind? kind,
    ValueChanged<List<String>?> change,
  ) => Column(
    children: [
      _flag(
        'Limit $label',
        values != null,
        (v) {
          _layout++;
          change(v ? [] : null);
        },
        detail: 'Off means unrestricted. When on, select 1–100 entries before saving.',
      ),
      if (values != null) ...[
        for (var i = 0; i < values.length; i++)
          Row(
            children: [
              Expanded(
                child: DraftRecordChoiceField(
                  key: ValueKey((_layout, label, i)),
                  changes: widget.changes,
                  draft: _choices,
                  kind: kind,
                  label: label,
                  record: values[i],
                  universe: '',
                  disabled: _busy,
                  onChanged: (ref) {
                    if (ref.universe != null &&
                        ref.universe != widget.changes.scope.universe) {
                      setState(
                        () => _error = 'Choose a record in this universe.',
                      );
                      return;
                    }
                    setState(() {
                      final rows = [...values];
                      rows[i] = ref.record.value;
                      change(rows);
                    });
                  },
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        _layout++;
                        change([...values]..removeAt(i));
                      }),
                child: const Text('Remove'),
              ),
            ],
          ),
        TextButton(
          onPressed: _busy
              ? null
              : () => setState(() {
                  _layout++;
                  change([...values, '']);
                }),
          child: Text('Add $label'),
        ),
      ],
    ],
  );
  Widget _namedScope(
    String label,
    List<String>? values,
    Map<String, String> names,
    ValueChanged<List<String>?> change,
  ) => Column(
    children: [
      _flag(
        'Limit $label',
        values != null,
        (v) => change(v ? [] : null),
        detail: 'Off means unrestricted. When on, select 1–100 entries before saving.',
      ),
      if (values != null) ...[
        for (final e in names.entries)
          CheckboxListTile(
            title: Text(e.value),
            value: values.contains(e.key),
            onChanged: _busy
                ? null
                : (v) => setState(
                    () => change(
                      v == true ? [...values, e.key] : [...values]
                        ..remove(e.key),
                    ),
                  ),
          ),
        for (final id in values.where((v) => !names.containsKey(v)))
          ListTile(
            title: Text('Unavailable $label selection'),
            subtitle: SelectableText(id),
            trailing: TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() => change([...values]..remove(id))),
              child: const Text('Remove'),
            ),
          ),
      ],
    ],
  );
  Future<void> _chooseExpiry() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(9999, 12, 31),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time == null || !mounted) return;
    setState(
      () => _expiry.text =
          (DateTime(
                    date.year,
                    date.month,
                    date.day,
                    time.hour,
                    time.minute,
                  ).toUtc().millisecondsSinceEpoch ~/
                  1000)
              .toString(),
    );
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final grant = GrantSpec(
        profileId: widget.profile.id,
        universeId: widget.changes.scope.universe,
        worlds: _worlds?.map(WorldId.parse),
        propose: _propose,
        edit: _edit,
        protected: _protected,
        limits: GrantLimits(
          entities: _entities?.map(RecordId.parse),
          predicates: _predicates?.map(RecordId.parse),
          continuities: _continuities?.map(ContinuityId.parse),
          expiresAt: _expiry.text.isEmpty ? null : BigInt.parse(_expiry.text),
          delegatedCommit: _delegated,
          allowShared: _shared,
        ),
      );
      for (final scope in [
        grant.worlds,
        grant.limits.entities,
        grant.limits.predicates,
        grant.limits.continuities,
      ]) {
        if (scope != null && (scope.isEmpty || scope.length > 100)) {
          throw const FormatException(
            'Each limited scope needs 1–100 selections.',
          );
        }
      }
      if (grant.limits.delegatedCommit &&
          (!grant.edit ||
              grant.limits.entities == null ||
              grant.limits.predicates == null ||
              grant.limits.continuities == null ||
              grant.limits.expiresAt == null)) {
        throw const FormatException(
          'Delegated publication requires edit permission, entity, predicate and continuity limits, and an expiry.',
        );
      }
      await saveAccessGrant(widget.changes.session, grant);
      if (mounted) Navigator.of(context).pop(true);
    } on FormatException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm the grant. Fields remain here; check current access before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text('Access · ${widget.profile.label}')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Saving replaces this profile’s grant for this universe. It does not make the profile an approval owner.',
                ),
                SelectableText('Profile: ${widget.profile.id.value}'),
                _flag('Propose changes', _propose, (v) => _propose = v),
                _flag('Edit', _edit, (v) => _edit = v),
                _flag(
                  'Access protected content',
                  _protected,
                  (v) => _protected = v,
                ),
                _namedScope('worlds', _worlds, {
                  for (final w in widget.worlds) w.id.value: w.name.value,
                }, (v) => _worlds = v),
                ExpansionTile(
                  title: const Text('Authored operation limits'),
                  children: [
                    _records(
                      'entities',
                      _entities,
                      RecordKind.entity,
                      (v) => _entities = v,
                    ),
                    _records(
                      'predicates',
                      _predicates,
                      null,
                      (v) => _predicates = v,
                    ),
                    _namedScope('continuities', _continuities, {
                      for (final c in widget.continuities) c.id.value: c.name,
                    }, (v) => _continuities = v),
                    _flag(
                      'Delegated publication',
                      _delegated,
                      (v) => _delegated = v,
                      detail: 'Permit the service’s existing delegated commit flow within this grant.',
                    ),
                    _flag('Shared applicability', _shared, (v) => _shared = v),
                    TextButton(
                      onPressed: _busy ? null : _chooseExpiry,
                      child: const Text('Choose expiry date and time'),
                    ),
                    TextField(
                      controller: _expiry,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Expiry (exact Unix seconds; empty means no expiry)',
                      ),
                    ),
                  ],
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: const Text('Save universe grant'),
                ),
                const Text(
                  'Unsubmitted access fields stay on this screen; leaving discards them.',
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
