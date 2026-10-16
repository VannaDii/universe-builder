import 'package:flutter/material.dart';

/// Guidance opens the existing editors; choosing a writing project creates no
/// records, policies or defaults in the universe.
class GettingStartedGuide extends StatefulWidget {
  const GettingStartedGuide({
    super.key,
    required this.author,
    this.enabled = true,
    this.onOpen,
  });
  final bool author;
  final bool enabled;
  final void Function(String editor)? onOpen;

  @override
  State<GettingStartedGuide> createState() => _GettingStartedGuideState();
}

class _GettingStartedGuideState extends State<GettingStartedGuide> {
  String _project = 'Campaign';

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    explicitChildNodes: true,
    child: ExpansionTile(
      title: const Text('Getting started'),
      subtitle: const Text('Campaigns, novels and life stories'),
      childrenPadding: const EdgeInsets.all(16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _project,
          isExpanded: true,
          decoration: const InputDecoration(
            labelText: 'What are you working on?',
          ),
          items: [
            for (final project in ['Campaign', 'Novel', 'Life story'])
              DropdownMenuItem(value: project, child: Text(project)),
          ],
          onChanged: (value) {
            if (value != null) setState(() => _project = value);
          },
        ),
        const SizedBox(height: 16),
        Text(switch (_project) {
          'Campaign' => 'Start with the people and places your players encounter. Keep session notes as sources, record what happened as events, and track story secrets and their fictional knowers separately from application access.',
          'Novel' => 'Start with your cast and setting. A work links your external manuscript; scene references track narrative order and source passages. Story chronology and the order in which readers learn things can differ.',
          _ => 'Start with a person and a source for their recollections. Record a memory by linking its holder to remembered content. Attribute recollections to their tellers, keep uncertainty explicit, and distinguish an account from the events it describes. Conflicting accounts can remain attributed.',
        }),
        if (widget.author && widget.onOpen != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _action('Add a person or place', 'entity'),
              _action('Import a source', 'source'),
              if (_project == 'Campaign') ...[
                _action('Record an event', 'event'),
                _action('Add a story secret', 'secret'),
              ],
              if (_project == 'Novel') ...[
                _action('Link a work', 'work'),
                _action('Link a work edition', 'work-version'),
                _action('Add a scene reference', 'scene'),
              ],
              if (_project == 'Life story') ...[
                _action('Record a memory', 'memory'),
                _action('Record an event', 'event'),
              ],
            ],
          ),
        ],
        const SizedBox(height: 16),
        const Text(
          'A universe holds your people, places, sources and history. A continuity is one version of that history. A represented context identifies whose account or reality you are working in.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Linked forms use published records or matching records already added to Changes. Add the supporting records first: a memory needs a holder and remembered content, and a scene reference needs a work edition.',
        ),
        const SizedBox(height: 12),
        const Text(
          'Save unfinished work to keep your input on this device. Add it to Changes when ready. In Changes, submit, run checks, review the exact changes and findings, approve, then publish separately. Saving or adding to Changes does not publish facts.',
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Using Real World'),
          childrenPadding: const EdgeInsets.all(12),
          children: [
            Text(
              'For strict real-world adherence, clone the Real World root policy when creating a universe. Worlds inherit that policy, with explicitly authored scoped deviations. Import the sources researched by your writer, then choose qualifying sources in the inherited evidence policy. Required unresolved facts prevent publication; interpretation review is required only where the scoped policy requests it. Attributed personal recollections can qualify without public corroboration when the policy permits them.',
            ),
          ],
        ),
        if (!widget.author) ...[
          const SizedBox(height: 12),
          const Text(
            'Your current access lets you inspect available records. Ask the approval owner about authoring and publication; this guide does not change your access.',
          ),
        ],
        if (widget.onOpen != null) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              _action('Browse records', 'records'),
              if (widget.author) _action('Review Changes', 'changes'),
            ],
          ),
        ] else ...[
          const SizedBox(height: 12),
          const Text(
            'Open a universe in Library, choose its continuity and represented context, then use Getting started there to open these forms.',
          ),
        ],
      ],
    ),
  );

  Widget _action(String label, String editor) => OutlinedButton(
    onPressed: widget.enabled ? () => widget.onOpen!(editor) : null,
    child: Text(label),
  );
}
