import 'package:ub_domain/ub_domain.dart';

import 'mcp_metadata.g.dart';

final _tools = CanonicalValue.parseWireJson(mcpToolCatalog) as CanonicalArray;
const _advancedOnly = {
  'universe_propose',
  'universe_validate',
  'universe_get',
  'universe_get_state',
  'universe_get_context',
};

/// Discovery filtering does not grant authority or prohibit explicitly named
/// advanced requests. The service authenticates and admits every actual call.
CanonicalArray mcpToolSchemas({bool advanced = false}) => CanonicalArray(
  _tools.items.where(
    (tool) =>
        advanced ||
        !_advancedOnly.contains(
          ((tool as CanonicalObject).fields
                      .singleWhere((f) => f.key == 'name')
                      .value
                  as CanonicalString)
              .value,
        ),
  ),
);

String mcpInstructions({bool fixture = false, bool advanced = false}) =>
    '${fixture ? mcpFixtureInstructions : mcpPersistentInstructions}\n\n${advanced ? mcpAdvancedInstructions : mcpOrdinaryInstructions}';
