import 'package:flutter/material.dart';
import 'package:ub_domain/ub_domain.dart';

import 'story_date.dart';

/// A disposable date preview, separate from unfinished publication fields.
class StoryDateResolver extends StatefulWidget {
  const StoryDateResolver({super.key, required this.clock});
  final Chronology clock;
  @override
  State<StoryDateResolver> createState() => _StoryDateResolverState();
}

class _StoryDateResolverState extends State<StoryDateResolver> {
  final _months = TextEditingController();
  String? _result, _error;
  @override
  void dispose() {
    _months.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(StoryDateResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.clock.toWire().toText() != widget.clock.toWire().toText()) {
      _months.clear();
      _result = _error = null;
    }
  }

  void _resolve() {
    setState(() {
      _result = _error = null;
      try {
        _result = resolveStoryMonthsAgo(widget.clock, _months.text);
      } on FormatException catch (error) {
        _error = error.message;
      }
    });
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('Resolve “N months ago”'),
    childrenPadding: const EdgeInsets.all(12),
    children: [
      const Text(
        'Measured from this pinned authored date. This preview does not advance time or create an event.',
      ),
      TextField(
        controller: _months,
        decoration: const InputDecoration(labelText: 'Number of months'),
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _resolve(),
        onChanged: (_) => setState(() => _result = _error = null),
      ),
      TextButton(onPressed: _resolve, child: const Text('Resolve date')),
      if (_result != null)
        Semantics(
          liveRegion: true,
          label: 'Resolved date: $_result',
          child: ExcludeSemantics(child: SelectableText(_result!)),
        ),
      if (_error != null) Semantics(liveRegion: true, child: Text(_error!)),
    ],
  );
}
