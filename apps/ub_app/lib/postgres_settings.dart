import 'package:flutter/material.dart';

import 'connection.dart';

class PostgresSettings extends StatefulWidget {
  const PostgresSettings({
    super.key,
    required this.test,
    required this.apply,
    required this.enabled,
  });
  final Future<TestedPostgresConnection> Function(String) test;
  final Future<void> Function(TestedPostgresConnection) apply;
  final bool enabled;
  @override
  State<PostgresSettings> createState() => _PostgresSettingsState();
}

class _PostgresSettingsState extends State<PostgresSettings> {
  final _endpoint = TextEditingController();
  TestedPostgresConnection? _target;
  String? _message;
  bool _busy = false;
  @override
  void dispose() {
    _endpoint.dispose();
    super.dispose();
  }

  Future<void> _test() async {
    setState(() {
      _busy = true;
      _target = null;
      _message = null;
    });
    try {
      final target = await widget.test(_endpoint.text);
      if (mounted) {
        setState(() {
          _target = target;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Could not connect. Check the connection details, trusted certificate and existing author setup on this device.';
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
    final target = _target!;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.apply(target);
      if (mounted) {
        setState(() {
          _endpoint.clear();
          _target = null;
          _message = 'Connection saved.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _message = 'Could not apply the connection. Check your saved settings and reconnect before retrying.';
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
      const Text('Use PostgreSQL', style: TextStyle(fontSize: 20)),
      const SizedBox(height: 12),
      const Text(
        'Connect this device to an existing database. Your universes and pending changes stay with their current instance; this does not move data.',
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _endpoint,
        enabled: widget.enabled && !_busy,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        maxLength: 16384,
        decoration: const InputDecoration(
          labelText: 'PostgreSQL connection',
          helperText: 'Connection URI, including credentials. Verified TLS is required.',
        ),
        onChanged: (_) => setState(() {
          _target = null;
          _message = null;
        }),
      ),
      const SizedBox(height: 12),
      OutlinedButton(
        onPressed: widget.enabled && !_busy ? _test : null,
        child: const Text('Test connection'),
      ),
      if (_busy)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: LinearProgressIndicator(),
        ),
      if (_target case final target?) ...[
        const SizedBox(height: 16),
        const Text('Connected to PostgreSQL'),
        SelectableText('Instance: ${target.instance.value}'),
        const SizedBox(height: 12),
        const Text(
          'Saving stops this local engine, protects the connection details on this device, and reconnects. Service environment overrides still take precedence.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: widget.enabled && !_busy ? _save : null,
          child: const Text('Save and reconnect'),
        ),
      ],
      if (_message case final message?)
        Padding(padding: const EdgeInsets.only(top: 12), child: Text(message)),
    ],
  );
}
