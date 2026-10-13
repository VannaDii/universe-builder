import 'package:flutter/material.dart';

import 'connection.dart';

class SqliteSettings extends StatefulWidget {
  const SqliteSettings({
    super.key,
    required this.test,
    required this.apply,
    required this.enabled,
    required this.connected,
  });
  final Future<TestedSqliteConnection> Function() test;
  final Future<void> Function(TestedSqliteConnection) apply;
  final bool enabled, connected;
  @override
  State<SqliteSettings> createState() => _SqliteSettingsState();
}

class _SqliteSettingsState extends State<SqliteSettings> {
  TestedSqliteConnection? _target;
  String? _message;
  bool _busy = false;
  Future<void> _test() async {
    setState(() {
      _busy = true;
      _target = null;
      _message = null;
    });
    try {
      final target = await widget.test();
      if (mounted) {
        setState(() {
          _target = target;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Could not open this device’s existing SQLite installation. Check its local author setup, then reconnect or try again.';
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

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.apply(_target!);
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Could not apply the local connection. Check saved settings and reconnect before retrying.';
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

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Use local SQLite', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 12),
      const Text(
        'Return to the existing installation on this device. Testing stops the current local engine. No data is copied, replaced or published.',
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: widget.enabled && !_busy ? _test : null,
        child: Text(
          widget.connected
              ? 'Stop engine and test SQLite'
              : 'Test local SQLite',
        ),
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_target case final target?) ...[
        const SizedBox(height: 16),
        const Text('Local SQLite is available'),
        SelectableText('Instance: ${target.instance.value}'),
        const SizedBox(height: 12),
        const Text(
          'Your saved PostgreSQL connection remains encrypted. Service environment overrides still take precedence.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.enabled && !_busy ? _save : null,
          child: const Text('Save and reconnect to SQLite'),
        ),
      ],
      if (_message case final message?)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(message)),
    ],
  );
}
