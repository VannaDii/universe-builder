import 'guarded_pop_scope.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';
import 'package_import.dart';

class PackageImportPage extends StatefulWidget {
  const PackageImportPage({super.key, required this.session});
  final AppSession session;
  @override
  State<PackageImportPage> createState() => _PackageImportPageState();
}

class _PackageImportPageState extends State<PackageImportPage> {
  PackageImportDraft? _form;
  BigInt _generation = BigInt.zero;
  bool _loading = true,
      _saving = false,
      _busy = false,
      _dirty = false,
      _leaving = false;
  String? _error;
  bool _cancelled = false;
  Timer? _autosave;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _autosave?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.session.loadPackageImport!();
      if (mounted) {
        setState(() {
          _form =
              saved?.form ??
              PackageImportDraft(operation: OperationId.generate());
          _generation = saved?.generation ?? BigInt.zero;
        });
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not open saved import choices. Reconnect and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _change({String? name, ImportMode? mode}) {
    setState(() {
      _form = _form!.copyWith(name: name, mode: mode);
      _dirty = true;
      _error = null;
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _save);
  }

  Future<bool> _save() async {
    if (!_dirty) return true;
    if (_saving) return false;
    setState(() => _saving = true);
    try {
      final input = _form!;
      final saved = await widget.session.savePackageImport!(input, _generation);
      if (mounted) {
        setState(() {
          _generation = saved.generation;
          _dirty = _form != input;
        });
      }
      return !_dirty;
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not save import choices. They remain here; another tab may have changed them.',
        );
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_dirty && _error == null) {
          _autosave?.cancel();
          _autosave = Timer(const Duration(milliseconds: 500), _save);
        }
      }
    }
  }

  Future<void> _review() async {
    SelectedArchiveFile? selected;
    if (_form!.name.trim().isEmpty) {
      setState(() => _error = 'Enter the imported universe name.');
      return;
    }
    _autosave?.cancel();
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
    });
    try {
      // Open the picker directly from the gesture, before any async storage work.
      final file = selected = await widget.session.pickArchiveFile!();
      if (!mounted || file == null) return;
      setState(() {
        _form = _form!.copyWith(
          fileName: file.name,
          phase: PackageImportPhase.uploading,
        );
        _dirty = true;
      });
      if (!await _save()) return;
      final report = await widget.session.reviewArchiveFile!(
        file,
        _form!,
      ) as CanonicalObject;
      final fields = Map.fromEntries(report.fields);
      if (wireString(fields['preview_id']!) != _form!.operation.value ||
          wireString(fields['name']!) != _form!.name) {
        throw const FormatException(
          'Review does not match these import choices',
        );
      }
      if (mounted) {
        setState(() {
          _form = _form!.copyWith(
            phase: PackageImportPhase.review,
            review: report,
          );
          _dirty = true;
        });
        await _save();
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = _cancelled
              ? 'Upload canceled. Reconnect before retrying with the same file. The package has not been admitted.'
              : 'Could not confirm the package review. Reconnect if needed, then select the same file to retry this import.',
        );
      }
    } finally {
      try {
        await selected?.release?.call();
      } on Object {
        // A cache cleanup failure does not discard a confirmed review.
      }
      if (mounted) {
        setState(() => _busy = false);
        if (_dirty && _error == null) {
          _autosave = Timer(const Duration(milliseconds: 500), _save);
        }
      }
    }
  }

  Future<void> _admit() async {
    _autosave?.cancel();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = _form!.admission();
      setState(() {
        _form = _form!.copyWith(phase: PackageImportPhase.admitting);
        _dirty = true;
      });
      if (!await _save()) return;
      final receipt = await widget.session.call(request) as CanonicalObject;
      final fields = Map.fromEntries(receipt.fields);
      if (wireString(fields['universe_id']!) !=
              wireString(
                Map.fromEntries(_form!.review!.fields)['target_universe']!,
              ) ||
          wireString(fields['name']!) != _form!.name ||
          wireString(fields['preview_id']!) != request.previewId.value ||
          wireString(fields['digest']!) != request.digest ||
          fields['imported'] is! CanonicalBool ||
          !(fields['imported'] as CanonicalBool).value) {
        throw const FormatException('Import was not confirmed');
      }
      if (mounted) {
        setState(() {
          _form = _form!.copyWith(
            phase: PackageImportPhase.admitted,
            receipt: receipt,
          );
          _dirty = true;
        });
        await _save();
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm admission. Reconnect if needed and retry this exact admission to recover the outcome.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_dirty && _error == null) {
          _autosave = Timer(const Duration(milliseconds: 500), _save);
        }
      }
    }
  }

  Future<void> _reset() async {
    setState(() {
      _form = PackageImportDraft(operation: OperationId.generate());
      _dirty = true;
      _error = null;
    });
    await _save();
  }

  Future<void> _leave() async {
    if (_busy || _saving) return;
    _autosave?.cancel();
    if (!await _save() || !mounted || _dirty) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final form = _form;
    final disabled = _busy || _saving || _loading;
    final fields = form?.review == null
        ? null
        : Map.fromEntries(form!.review!.fields);
    final conflicts =
        (fields?['conflicts'] as CanonicalArray?)?.items ??
        const <CanonicalValue>[];
    return GuardedPopScope(
      onLeave: _leave,
      onBackground: () async { await _save(); },
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Import a package')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Choose a Universe Builder relational archive. Review its contents before admitting it into this instance.',
                ),
                if (disabled) const LinearProgressIndicator(),
                if (_busy &&
                    form?.phase == PackageImportPhase.uploading &&
                    widget.session.cancelArchiveUpload != null)
                  TextButton(
                    onPressed: () {
                      _cancelled = true;
                      widget.session.cancelArchiveUpload!();
                    },
                    child: const Text('Cancel upload'),
                  ),
                if (form != null) ...[
                  TextFormField(
                    key: ValueKey(form.operation),
                    initialValue: form.name,
                    enabled:
                        !disabled && form.phase == PackageImportPhase.input,
                    decoration: const InputDecoration(
                      labelText: 'Imported universe name',
                    ),
                    onChanged: (value) => _change(name: value),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ImportMode>(
                    segments: const [
                      ButtonSegment(
                        value: ImportMode.clone,
                        label: Text('Clone'),
                      ),
                      ButtonSegment(
                        value: ImportMode.restore,
                        label: Text('Restore identity'),
                      ),
                    ],
                    selected: {form.mode},
                    onSelectionChanged:
                        disabled || form.phase != PackageImportPhase.input
                        ? null
                        : (value) => _change(mode: value.single),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    form.mode == ImportMode.clone
                        ? 'Clone creates a new universe identity and preserves references within it. The source stays unchanged.'
                        : 'Restore keeps the archive’s original universe identity. That identity must be absent from this instance.',
                  ),
                  if (form.phase == PackageImportPhase.input ||
                      form.phase == PackageImportPhase.uploading) ...[
                    if (form.phase == PackageImportPhase.uploading)
                      const Text(
                        'This upload was started. Select the same file to retry; recovery never uploads automatically.',
                      ),
                    FilledButton.icon(
                      onPressed: disabled ? null : _review,
                      icon: const Icon(Icons.upload_file),
                      label: Text(
                        form.phase == PackageImportPhase.uploading
                            ? 'Select same file and retry review'
                            : 'Choose package and review',
                      ),
                    ),
                  ],
                  if (fields != null) ...[
                    const Divider(),
                    Text('Selected file: ${form.fileName}'),
                    Text(
                      'Retained records: ${(fields['record_count'] as CanonicalNumber).digits}',
                    ),
                    Text(
                      (fields['complete'] as CanonicalBool).value
                          ? 'Complete archive'
                          : 'Incomplete archive · ${(fields['omitted_records'] as CanonicalNumber).digits} records omitted',
                    ),
                    if ((fields['includes_history'] as CanonicalBool).value)
                      const Text('Retained history included'),
                    Text(
                      (fields['includes_workflow'] as CanonicalBool).value
                          ? 'Historical workflow evidence included. Imported approvals and permissions remain inactive.'
                          : 'Historical workflow evidence omitted by the source export.',
                    ),
                    for (final conflict in conflicts)
                      Text(
                        wireString(conflict),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (form.phase == PackageImportPhase.review ||
                        form.phase == PackageImportPhase.admitting) ...[
                      if (form.phase == PackageImportPhase.admitting)
                        const Text(
                          'Admission was attempted. Retry the same admission to recover its outcome.',
                        ),
                      FilledButton(
                        onPressed:
                            disabled ||
                                conflicts.isNotEmpty &&
                                    form.phase != PackageImportPhase.admitting
                            ? null
                            : _admit,
                        child: Text(
                          form.phase == PackageImportPhase.admitting
                              ? 'Retry exact admission'
                              : 'Admit reviewed package',
                        ),
                      ),
                    ],
                  ],
                  if (form.phase == PackageImportPhase.admitted)
                    const Text(
                      'Import confirmed. Return to the library to open the universe.',
                    ),
                  if (form.phase != PackageImportPhase.input)
                    TextButton(
                      onPressed: disabled ? null : _reset,
                      child: const Text('Start another import'),
                    ),
                  Text(_dirty ? 'Unsaved choices' : 'Saved on this device'),
                  if (_dirty)
                    TextButton(
                      onPressed: disabled ? null : _save,
                      child: const Text('Save import choices'),
                    ),
                ],
                if (_error != null && !disabled)
                  TextButton(
                    onPressed: () async {
                      setState(() {
                        _loading = true;
                        _dirty = false;
                        _error = null;
                      });
                      await _load();
                    },
                    child: const Text('Reload saved choices'),
                  ),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
