import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'connection.dart';
import 'guarded_pop_scope.dart';
import 'universe_creation.dart';

typedef CreationResult = ({LibraryEntry? created, bool refresh});

class CreateUniversePage extends StatefulWidget {
  const CreateUniversePage({super.key, required this.session});
  final AppSession session;
  @override
  State<CreateUniversePage> createState() => _CreateUniversePageState();
}

class _CreateUniversePageState extends State<CreateUniversePage> {
  final _name = TextEditingController(),
      _date = TextEditingController(),
      _time = TextEditingController(),
      _offset = TextEditingController(),
      _calendarName = TextEditingController(),
      _tick = TextEditingController(),
      _tickLabel = TextEditingController(),
      _month = TextEditingController();
  CreationCalendar _calendar = CreationCalendar.gregorian;
  bool _realWorld = true;
  bool _busy = false,
      _uncertain = false,
      _loading = true,
      _loaded = false,
      _leaving = false;
  BigInt _generation = BigInt.zero;
  String? _saved;
  Future<void> _writes = Future.value();
  Timer? _autosave;
  String _saveLabel = 'No saved fields yet';
  String? _error;

  UniverseCreationForm get _form => UniverseCreationForm(
    name: _name.text,
    calendar: _calendar,
    date: _date.text,
    time: _time.text,
    offset: _offset.text,
    calendarName: _calendarName.text,
    initialTick: _tick.text,
    tickLabel: _tickLabel.text,
    ticksPerMonth: _month.text,
    creationPending: _uncertain,
    realWorld: _realWorld,
  );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final saved = await widget.session.loadUniverseCreationForm!();
      if (!mounted) return;
      final form = saved?.form;
      if (form != null) {
        _name.text = form.name;
        _date.text = form.date;
        _time.text = form.time;
        _offset.text = form.offset;
        _calendarName.text = form.calendarName;
        _tick.text = form.initialTick;
        _tickLabel.text = form.tickLabel;
        _month.text = form.ticksPerMonth;
        _calendar = form.calendar;
        _realWorld = form.realWorld;
        _uncertain = form.creationPending;
        _generation = saved!.generation;
        _saved = form.toWire().toText();
        _saveLabel = 'Recovered on this device';
      }
      _loaded = true;
    } on Object {
      _error = 'Could not open saved creation fields. Reconnect and try again.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _persist(UniverseCreationForm form) {
    final result = _writes.then((_) async {
      final exact = form.toWire().toText();
      if (_saved == exact) return;
      final saved = await widget.session.saveUniverseCreationForm!(
        form,
        _generation,
      );
      _generation = saved.generation;
      _saved = exact;
    });
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _changed() {
    setState(() {
      _error = null;
      _saveLabel = 'Unsaved input';
    });
    _autosave?.cancel();
    _autosave = Timer(const Duration(milliseconds: 500), _saveInput);
  }

  Future<bool> _saveInput() async {
    if (!_loaded) return false;
    final form = _form;
    try {
      await _persist(form);
      if (mounted) {
        setState(() {
          _saveLabel = _form.toWire().toText() == form.toWire().toText()
              ? 'Saved on this device'
              : 'Unsaved input';
        });
      }
      return true;
    } on Object {
      if (mounted) {
        setState(() {
          _error = 'Could not save creation fields. They remain here; another window may have changed them.';
        });
      }
      return false;
    }
  }

  Future<void> _leave() async {
    if (_busy || _uncertain || _loading) return;
    _autosave?.cancel();
    setState(() => _busy = true);
    final saved = !_loaded || await _saveInput();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _leaving = saved;
    });
    if (!saved) return;
    Navigator.of(context).pop();
  }

  void _checkLibrary() {
    // The parent reconnects before reading the catalog. A connection with an
    // interrupted request cannot be reused, and this action never resends it.
    setState(() {
      _leaving = true;
      _uncertain = false;
    });
    Navigator.of(context).pop<CreationResult>((created: null, refresh: true));
  }

  @override
  void dispose() {
    _autosave?.cancel();
    for (final controller in [
      _name,
      _date,
      _time,
      _offset,
      _calendarName,
      _tick,
      _tickLabel,
      _month,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _uncertain || !_loaded) return;
    _autosave?.cancel();
    CreateUniverseEngineRequest request;
    try {
      request = _form.request();
    } on FormatException catch (error) {
      setState(() {
        _error = error.message;
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _persist(_form.withPending(true));
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not save creation fields. Nothing was sent; keep this form open and try saving again.';
        });
      }
      return;
    }
    try {
      final entry = createdUniverse(await widget.session.call(request));
      try {
        await _persist(
          const UniverseCreationForm(
            name: '',
            calendar: CreationCalendar.gregorian,
          ),
        );
      } on Object {
        // The confirmed universe remains usable; the retained attempt will
        // require a library check before the next creation.
      }
      if (mounted) {
        setState(() {
          _leaving = true;
          _busy = false;
        });
        Navigator.of(context)
            .pop<CreationResult>((created: entry, refresh: false));
      }
    } on ProtocolError catch (error) {
      final unknown =
          error is StorageFailureError || error is MaintenanceRequiredError;
      var retainedUnknown = unknown;
      if (!unknown) {
        try {
          await _persist(_form.withPending(false));
        } on Object {
          retainedUnknown = true;
        }
      }
      if (mounted) {
        setState(() {
          _uncertain = retainedUnknown;
          _error = _uncertain
              ? 'Creation could not be confirmed. Check your library before trying again.'
              : 'Could not create this universe. Check the name, calendar and your access.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _uncertain = true;
          _error = 'Creation could not be confirmed. Check your library before trying again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    bool autofocus = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 20),
    child: Semantics(
      label: label,
      child: TextField(
        controller: controller,
        enabled: _loaded && !_busy && !_uncertain,
        autofocus: autofocus,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: (_) => _changed(),
        textInputAction: TextInputAction.next,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => GuardedPopScope<CreationResult>(
    canPop: _leaving,
    onLeave: _leave,
    onBackground: () async {
      if (!_busy) await _saveInput();
    },
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _leave();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Create universe'),
        automaticallyImplyLeading: false,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: _busy || _uncertain || _loading ? null : _leave,
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              if (_loading) const LinearProgressIndicator(),
              if (_loaded) ...[
                Text(_saveLabel),
                const Text(
                  'Unfinished input stays on this device. Reopening never creates a universe.',
                ),
                if (_uncertain)
                  const Text(
                    'Creation was interrupted or could not be confirmed. Check your library before trying again.',
                  ),
                const SizedBox(height: 20),
              ],
              _field(_name, 'Universe name', autofocus: true),
              const Text('Root policy', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  for (final realWorld in [true, false])
                    ChoiceChip(
                      label: Text(
                        realWorld
                            ? 'Clone Real World policy'
                            : 'Start from scratch',
                      ),
                      selected: _realWorld == realWorld,
                      onSelected: !_loaded || _busy || _uncertain
                          ? null
                          : (_) {
                              _realWorld = realWorld;
                              _changed();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _realWorld
                    ? 'Create an independent Real World root policy. Factual claims need qualifying sources; private recollections can be included. Interpretation review is required only where a scoped policy requests it.'
                    : 'Create an empty root policy and build your own canon. Add the requirements your campaign, novel or life story needs.',
              ),
              if (_realWorld)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'Start with an empty selection of qualifying sources. Add your chosen sources before publishing new factual claims.',
                  ),
                ),
              const SizedBox(height: 24),
              const Text('Starting calendar', style: TextStyle(fontSize: 20)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                children: [
                  for (final calendar in CreationCalendar.values)
                    ChoiceChip(
                      label: Text(
                        calendar == CreationCalendar.gregorian
                            ? 'Gregorian'
                            : 'Fictional',
                      ),
                      selected: _calendar == calendar,
                      onSelected: !_loaded || _busy || _uncertain
                          ? null
                          : (_) {
                              _calendar = calendar;
                              _changed();
                            },
                    ),
                ],
              ),
              const SizedBox(height: 24),
              if (_calendar == CreationCalendar.gregorian) ...[
                _field(_date, 'Starting date', hint: 'YYYY-MM-DD'),
                _field(_time, 'Starting time', hint: 'HH:MM:SS'),
                _field(_offset, 'Fixed UTC offset', hint: '+00:00'),
                const Text(
                  'Use the story’s authored time. The offset stays fixed; daylight saving is not inferred.',
                ),
                const SizedBox(height: 12),
                if (_date.text.isNotEmpty &&
                    _time.text.isNotEmpty &&
                    _offset.text.isNotEmpty)
                  SelectableText('Exact start: ${_form.timestamp}'),
              ] else ...[
                _field(_calendarName, 'Calendar name'),
                _field(
                  _tick,
                  'Initial tick',
                  hint: 'Whole number; may be negative',
                ),
                _field(_tickLabel, 'Tick label'),
                _field(_month, 'Ticks per month (optional)'),
                const Text(
                  'Leave the month conversion blank unless this calendar defines one.',
                ),
              ],
              const SizedBox(height: 24),
              if (_error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              if (_loaded && !_uncertain)
                TextButton(
                  onPressed: _busy ? null : _saveInput,
                  child: const Text('Save unfinished work'),
                ),
              if (_busy) const LinearProgressIndicator(),
              Align(
                alignment: Alignment.centerLeft,
                child: _uncertain
                    ? FilledButton(
                        onPressed: _busy ? null : _checkLibrary,
                        child: const Text('Check library'),
                      )
                    : FilledButton(
                        onPressed: _busy || !_loaded ? null : _submit,
                        child: const Text('Create universe'),
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
