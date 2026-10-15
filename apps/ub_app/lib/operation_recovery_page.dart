import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'operation_recovery.dart';
import 'record_fields.dart';

class OperationRecoveryPage extends StatefulWidget {
  const OperationRecoveryPage({
    super.key,
    required this.recovery,
    this.initialOperation,
  });
  final OperationRecovery recovery;
  final OperationId? initialOperation;
  @override
  State<OperationRecoveryPage> createState() => _OperationRecoveryPageState();
}

class _OperationRecoveryPageState extends State<OperationRecoveryPage> {
  late final TextEditingController _reference;
  OperationStatusV3? _status;
  bool _busy = false;
  String? _error, _message;
  @override
  void initState() {
    super.initState();
    _reference = TextEditingController(
      text: widget.initialOperation?.value ?? '',
    );
    if (widget.initialOperation != null) _read();
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
      _status = null;
    });
    try {
      final id = OperationId.parse(_reference.text.trim());
      final status = await widget.recovery.read(id);
      if (mounted) setState(() => _status = status);
    } on FormatException {
      if (mounted) {
        setState(
          () => _error = 'Enter a valid operation reference, or retry if its complete result could not be read.',
        );
      }
    } on Object {
      if (mounted) {
        setState(
          () => _error = 'Could not read this operation. Check the reference, connection and current profile access.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final current = _status;
    if (_busy || current == null || !canCancelOperation(current)) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      final status = await widget.recovery.cancel(current.operationId);
      if (mounted) {
        setState(() {
          _status = status;
          _message = status.state == OperationState.cancelled
              ? 'Operation cancelled. Completed publications remain intact.'
              : status.cancellationRequested
              ? 'Cancellation was requested. Check the current status again.'
              : 'The operation finished before cancellation. Its recorded result is retained.';
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _status = null;
          _error = 'Cancellation was not confirmed. Check this operation’s status to recover the outcome before retrying.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final kind = switch (status?.kind) {
      OperationKind.propose => 'Proposal',
      OperationKind.validate => 'Checks',
      OperationKind.commit => 'Publication',
      OperationKind.cancel => 'Cancellation',
      null => '',
    };
    final state = switch (status?.state) {
      OperationState.queued => 'Waiting',
      OperationState.running => 'Running',
      OperationState.awaitingAuthority => 'Waiting to proceed',
      OperationState.committing => 'Saving result',
      OperationState.succeeded => 'Completed',
      OperationState.failed => 'Failed',
      OperationState.cancelled => 'Cancelled',
      OperationState.interrupted => 'Interrupted',
      null => '',
    };
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Operation recovery')),
        body: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Inspect work owned by your current profile. This does not approve or retry publication. Cancellation does not undo completed work or withdraw a proposal.',
                ),
                ExpansionTile(
                  title: const Text('Operation reference'),
                  initiallyExpanded: widget.initialOperation == null,
                  children: [
                    TextField(
                      controller: _reference,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() {
                        _status = null;
                        _message = null;
                        _error = null;
                      }),
                      onSubmitted: (_) => _read(),
                      decoration: const InputDecoration(
                        labelText: 'Operation reference',
                        helperText: 'Use the opened operation, or paste a reference supplied by your connected writer.',
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: _busy || _reference.text.trim().isEmpty
                      ? null
                      : _read,
                  child: const Text('Check operation status'),
                ),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Semantics(liveRegion: true, child: Text(_error!)),
                if (_message != null)
                  Semantics(liveRegion: true, child: Text(_message!)),
                if (status != null) ...[
                  Text(
                    'Operation: $kind',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('Status: $state'),
                  if (status.cancellationRequested)
                    const Text('Cancellation has been requested.'),
                  if (status.receipt case final receipt?) ...[
                    const Text(
                      'Publication completed. Its revision is retained.',
                    ),
                    SelectableText('Revision: ${receipt.revision.value}'),
                  ],
                  if (status.failure != null) SelectableText(status.failure!),
                  if (canCancelOperation(status))
                    OutlinedButton(
                      onPressed: _busy ? null : _cancel,
                      child: const Text('Cancel pending operation'),
                    ),
                  ExpansionTile(
                    title: const Text('Operation result details'),
                    children: [ExactFields(value: status.toWire())],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
