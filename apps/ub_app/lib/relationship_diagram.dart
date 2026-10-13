import 'package:flutter/material.dart';
import 'package:ub_domain/ub_domain.dart';

/// A declared relation is a subject with ordered role bindings, not a set of
/// inferred pairwise relationships. Repeated participants retain separate roles.
class RelationshipDiagram extends StatelessWidget {
  const RelationshipDiagram({
    super.key,
    required this.proposition,
    required this.label,
  });
  final PropositionRecord proposition;
  final String Function(RecordRef) label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget node(String role, String name, {bool relation = false}) => Semantics(
      container: true,
      label: '$role: $name',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: relation
              ? colors.primaryContainer
              : colors.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(role, style: Theme.of(context).textTheme.labelLarge),
            SelectableText(name),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Subject → relation → role participants. Numbered roles retain their authored order.',
        ),
        const SizedBox(height: 12),
        node('Subject', label(proposition.subject)),
        const ExcludeSemantics(child: Icon(Icons.arrow_downward)),
        node('Relation', label(proposition.predicate), relation: true),
        if (proposition.roles.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('No participant roles were declared.'),
          ),
        for (var index = 0; index < proposition.roles.length; index++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ExcludeSemantics(
                  child: SizedBox(
                    width: 36,
                    child: Stack(
                      children: [
                        Positioned(
                          left: 10,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: colors.outlineVariant,
                          ),
                        ),
                        const Align(
                          alignment: Alignment.centerRight,
                          child: Icon(Icons.arrow_forward, size: 20),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: node(
                      '${index + 1}. ${proposition.roles[index].role}',
                      label(proposition.roles[index].participant),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
