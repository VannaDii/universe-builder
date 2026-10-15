import 'package:flutter/material.dart';

import 'connection.dart';
import 'universe_name.dart';

class UniverseNamePage extends StatefulWidget {
  const UniverseNamePage({
    super.key,
    required this.session,
    required this.universe,
  });
  final AppSession session;
  final LibraryEntry universe;
  @override
  State<UniverseNamePage> createState() => _UniverseNamePageState();
}

class _UniverseNamePageState extends State<UniverseNamePage> {
  late final TextEditingController _name;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.universe.name);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _rename() async {
    if (_busy || !widget.session.author || _name.text.trim().isEmpty) return;
    final name = _name.text;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final renamed = await renameUniverse(
        widget.session,
        widget.universe,
        name,
      );
      if (!mounted) return;
      setState(() => _busy = false);
      Navigator.of(context).pop(renamed);
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not confirm the rename. Check that the name is valid and available and your author access is current. Your entered name remains here; retry it or refresh Library.',
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
      appBar: AppBar(title: const Text('Rename universe')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                widget.universe.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Text(
                'Change the universe’s name in this instance. Its identity, history and saved work stay intact. The previous name remains an alias for the same universe.',
              ),
              if (!widget.session.author)
                const Text(
                  'Only the installation author can rename a universe.',
                )
              else ...[
                TextField(
                  controller: _name,
                  enabled: !_busy,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _rename(),
                  decoration: const InputDecoration(
                    labelText: 'Universe name',
                    helperText: 'Choose a name that is not reserved for another universe.',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _busy || _name.text.trim().isEmpty
                      ? null
                      : _rename,
                  child: const Text('Rename universe'),
                ),
              ],
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
