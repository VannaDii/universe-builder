import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;

import 'connection.dart';
import 'universe_creation.dart';

typedef CreationResult = ({LibraryEntry? created, bool refresh});

class CreateUniversePage extends StatefulWidget {
  const CreateUniversePage({super.key, required this.create});
  final Future<LibraryEntry> Function(CreateUniverseEngineRequest) create;
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
  bool _busy = false, _uncertain = false;
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
  );

  @override
  void dispose() {
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
      final entry = await widget.create(request);
      if (mounted) {
        Navigator.of(context)
            .pop<CreationResult>((created: entry, refresh: false));
      }
    } on ProtocolError catch (error) {
      if (mounted) {
        setState(() {
          _uncertain =
              error is StorageFailureError || error is MaintenanceRequiredError;
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
        enabled: !_busy && !_uncertain,
        autofocus: autofocus,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onChanged: (_) => setState(() {
          _error = null;
        }),
        textInputAction: TextInputAction.next,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy && !_uncertain,
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Create universe'),
        automaticallyImplyLeading: !_busy,
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _field(_name, 'Universe name', autofocus: true),
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
                      onSelected: _busy || _uncertain
                          ? null
                          : (_) => setState(() {
                              _calendar = calendar;
                              _error = null;
                            }),
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
              if (_busy) const LinearProgressIndicator(),
              Align(
                alignment: Alignment.centerLeft,
                child: _uncertain
                    ? FilledButton(
                        onPressed: () => Navigator.of(
                          context,
                        ).pop<CreationResult>((created: null, refresh: true)),
                        child: const Text('Check library'),
                      )
                    : FilledButton(
                        onPressed: _busy ? null : _submit,
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
