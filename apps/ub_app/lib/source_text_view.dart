import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

class SourceTextView extends StatefulWidget {
  const SourceTextView({
    super.key,
    required this.session,
    required this.universe,
    required this.context,
    required this.version,
  });
  final AppSession session;
  final Selector universe;
  final ContextId context;
  final VersionRef version;
  @override
  State<SourceTextView> createState() => _SourceTextViewState();
}

class _SourceTextViewState extends State<SourceTextView> {
  String? _text, _error;
  BigInt? _next;
  BigInt _start = BigInt.zero;
  bool _busy = false;
  int _generation = 0;
  @override
  void didUpdateWidget(SourceTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.context != widget.context ||
        oldWidget.version != widget.version ||
        oldWidget.universe != widget.universe) {
      _generation++;
      _text = _error = null;
      _next = null;
      _start = BigInt.zero;
      _busy = false;
    }
  }

  Future<void> _read(BigInt after) async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final fields = WireFields(
        await widget.session.call(
          ReadSourceEngineRequest(
            universe: widget.universe,
            contextId: widget.context,
            sourceVersion: widget.version,
            after: after,
          ),
        ),
        {'text', 'after', 'next'},
      );
      final start = fields.u64('after');
      final text = fields.string('text');
      final next = fields.require('next') is CanonicalNull
          ? null
          : fields.u64('next');
      if (start != after || (next != null && next <= start)) {
        throw const FormatException('Invalid source page');
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _text = text;
        _start = start;
        _next = next;
        _busy = false;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error.toString();
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: _busy ? null : () => _read(BigInt.zero),
            child: Text(
              _text == null ? 'Read source text' : 'Read from beginning',
            ),
          ),
          if (_next != null)
            OutlinedButton(
              onPressed: _busy ? null : () => _read(_next!),
              child: const Text('Next text section'),
            ),
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_error != null) SelectableText(_error!),
      if (_text != null) ...[
        Text(
          'UTF-8 byte offset $_start · ${_next == null ? 'end of source' : 'more text available'}',
        ),
        SelectableText(_text!),
      ],
    ],
  );
}
