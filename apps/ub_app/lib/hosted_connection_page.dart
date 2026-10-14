import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

class HostedConnectionPage extends StatefulWidget {
  const HostedConnectionPage({super.key, required this.connect});
  final Future<void> Function(HostedConnectionChoice) connect;
  @override
  State<HostedConnectionPage> createState() => _HostedConnectionPageState();
}

class _HostedConnectionPageState extends State<HostedConnectionPage> {
  final _address = TextEditingController(),
      _profile = TextEditingController(),
      _key = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _address.dispose();
    _profile.dispose();
    _key.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    HostedConnectionChoice choice;
    try {
      final endpoint = Uri.parse(_address.text.trim());
      if (endpoint.scheme != 'https' ||
          endpoint.host.isEmpty ||
          endpoint.userInfo.isNotEmpty ||
          endpoint.hasQuery ||
          endpoint.hasFragment ||
          !{'', '/'}.contains(endpoint.path) ||
          endpoint.port < 1 ||
          endpoint.port > 65535 ||
          _key.text.isEmpty) {
        throw const FormatException('Invalid service connection');
      }
      choice = HostedConnectionChoice(
        endpoint: endpoint,
        profile: ProfileId.parse(_profile.text.trim()),
        credential: Credential(_key.text),
      );
    } on Object {
      setState(
        () => _error =
            'Enter an HTTPS service address, profile ID and access key.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.connect(choice);
      if (mounted) {
        _key.clear();
        Navigator.of(context).pop();
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not connect. Check the service address, certificate and profile access, then try again.',
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
      appBar: AppBar(title: const Text('Connect to a service')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Open an instance hosted by you or your provider. Ask its owner for your profile ID and access key.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _address,
                enabled: !_busy,
                autocorrect: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Service address',
                  hintText: 'https://ub.example.com',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _profile,
                enabled: !_busy,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Profile ID'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _key,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(labelText: 'Access key'),
                onSubmitted: (_) {
                  if (!_busy) _connect();
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'The key stays in memory for this session. Re-enter it after quitting. Unfinished author input is saved privately on this device.',
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : _connect,
                icon: const Icon(Icons.link),
                label: const Text('Connect'),
              ),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(_error!),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
