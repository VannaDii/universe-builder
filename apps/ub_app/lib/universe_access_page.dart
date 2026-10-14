import 'package:flutter/material.dart';
import 'package:ub_contracts/ub_contracts.dart' hide State;
import 'package:ub_domain/ub_domain.dart';

import 'saved_changes.dart';
import 'access_management.dart';
import 'grant_editor_page.dart';

class UniverseAccessPage extends StatefulWidget {
  const UniverseAccessPage({
    super.key,
    required this.changes,
    required this.revision,
    required this.continuities,
    required this.worlds,
  });
  final SavedChanges changes;
  final RevisionId revision;
  final List<ContinuitySummary> continuities;
  final List<WorldSummary> worlds;
  @override
  State<UniverseAccessPage> createState() => _UniverseAccessPageState();
}

class _UniverseAccessPageState extends State<UniverseAccessPage> {
  AccessDirectory? _directory;
  bool _busy = false;
  String? _error, _message;
  @override
  void initState() {
    super.initState();
    _run(_refresh);
  }

  Future<void> _refresh() async {
    final directory = await readAccessDirectory(widget.changes.session);
    if (mounted) setState(() => _directory = directory);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await action();
    } on Object {
      if (mounted) {
        setState(
          () => _error =
              'Could not confirm current access. Refresh before retrying.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _enroll() async {
    final f = WireFields(
      await widget.changes.session.call(const EnrollEngineRequest()),
      {'profile_id'},
    );
    final profile = ProfileId.parse(f.string('profile_id'));
    await _refresh();
    if (mounted) {
      setState(
        () => _message =
            'Enrolled contributor ${profile.value}. It has no universe access until granted. Credentials remain in the protected local store.',
      );
    }
  }

  Future<void> _withdraw(AccessProfile profile) async {
    await withdrawAccessGrant(
      widget.changes.session,
      profile.id,
      widget.changes.scope.universe,
    );
    await _refresh();
    if (mounted) {
      setState(
        () => _message =
            'Removed this profile’s access to ${widget.changes.universe.value}.',
      );
    }
  }

  Future<void> _revoke(AccessProfile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke this profile?'),
        content: Text(
          'This disables ${profile.label} across every universe in this instance. It is separate from removing one universe grant.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Revoke profile'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final f = WireFields(
      await widget.changes.session.call(
        RevokeEngineRequest(profileId: profile.id),
      ),
      {'revoked'},
    );
    if (!f.boolean('revoked')) {
      throw const FormatException('Revocation was not confirmed.');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text('Access · ${widget.changes.universe.value}')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text(
                'Profiles belong to this instance. Grants control access to this universe; revoking a profile disables it across the instance.',
              ),
              Wrap(
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => _run(_refresh),
                    child: const Text('Refresh access'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : () => _run(_enroll),
                    child: const Text('Enroll contributor'),
                  ),
                ],
              ),
              if (_directory case final directory?)
                for (final profile in directory.profiles)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            profile.label,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SelectableText(profile.id.value),
                          if (profile.author)
                            const Text(
                              'Approval owner · author authority is managed by the service',
                            )
                          else if (profile.revoked)
                            const Text('Revoked')
                          else ...[
                            Text(
                              directory.grant(
                                        profile.id,
                                        widget.changes.scope.universe,
                                      ) ==
                                      null
                                  ? 'No grant for this universe'
                                  : 'Universe grant present',
                            ),
                            if (directory.grant(
                                  profile.id,
                                  widget.changes.scope.universe,
                                )
                                case final grant?)
                              Text(
                                '${grant.propose ? 'Can propose' : 'Cannot propose'} · ${grant.edit ? 'Can edit' : 'Cannot edit'} · ${grant.protected ? 'Protected content allowed' : 'Protected content denied'}',
                              ),
                            Wrap(
                              children: [
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () async {
                                          await Navigator.of(
                                            context,
                                          ).push<bool>(
                                            MaterialPageRoute(
                                              builder: (_) => GrantEditorPage(
                                                changes: widget.changes,
                                                profile: profile,
                                                original: directory.grant(
                                                  profile.id,
                                                  widget.changes.scope.universe,
                                                ),
                                                revision: widget.revision,
                                                continuities:
                                                    widget.continuities,
                                                worlds: widget.worlds,
                                              ),
                                            ),
                                          );
                                          if (mounted) await _run(_refresh);
                                        },
                                  child: const Text('Edit universe grant'),
                                ),
                                if (directory.grant(
                                      profile.id,
                                      widget.changes.scope.universe,
                                    ) !=
                                    null)
                                  TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _run(() => _withdraw(profile)),
                                    child: const Text('Remove universe access'),
                                  ),
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _run(() => _revoke(profile)),
                                  child: const Text(
                                    'Revoke profile across instance',
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              if (_busy) const LinearProgressIndicator(),
              if (_message != null)
                Semantics(liveRegion: true, child: Text(_message!)),
              if (_error != null)
                Semantics(liveRegion: true, child: Text(_error!)),
            ],
          ),
        ),
      ),
    ),
  );
}
