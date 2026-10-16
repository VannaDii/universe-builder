import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_domain/ub_domain.dart';

import 'wire.dart';
import 'protocol_error.dart';
import 'workflow.dart';
import 'assessment.dart';
import 'validation_scope.dart';

part 'read_request.dart';
part 'workflow_request.dart';
part 'writing.dart';
part 'writing_knowledge.dart';
part 'writing_delta.dart';

/// Closed application requests shared by service, desktop and MCP transports.
/// Parsing and request validation do not route, evaluate or grant authority.
sealed class Request {
  const Request();
  Selector get universe;
  String get toolName;
  CanonicalObject toArgs();
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('tool', CanonicalString(toolName)),
    MapEntry('args', toArgs()),
  ]);
  static Request decode(Uint8List bytes) {
    return fromWire(decodeWireFrame(bytes));
  }

  static Request fromWire(CanonicalValue value) {
    final f = WireFields(value, {'tool', 'args'});
    return _parse(f.string('tool'), f.require('args'));
  }

  static Request fromTool(String name, CanonicalValue args) {
    try {
      final request = _parse(name, args);
      request.validate();
      return request;
    } on FormatException catch (e) {
      throw InvalidArgumentError(field: 'arguments', message: e.message);
    }
  }

  static Request _parse(String name, CanonicalValue args) => switch (name) {
    'universe_check_changes' => CheckChangesRequest.fromWire(args),
    'universe_read_facts' ||
    'universe_read_contracts' ||
    'universe_describe' ||
    'universe_open_context' ||
    'universe_search' ||
    'universe_get' ||
    'universe_get_state' ||
    'universe_get_context' => ReadRequest._parse(name, args),
    _ => WorkflowRequest._parse(name, args),
  };
  void validate() {
    if (this case CheckChangesRequest()) {
      final input = this as CheckChangesRequest;
      if (input.events.length +
                  input.messages.length +
                  input.attitudes.length +
                  input.corrections.length >
              100 ||
          input.changes.length > 100 ||
          input.changes.fold<int>(0, (sum, o) => sum + o.facts.length) > 100 ||
          input.questions.length > 20) {
        throw const InvalidArgumentError(
          field: 'changes',
          message: 'at most 100 objects/facts and 20 questions',
        );
      }
      for (final fact in input.changes.expand((o) => o.facts)) {
        if (!{
              'objective',
              'dialogue',
              'belief',
              'plan',
              'hypothetical',
              'metaphor',
            }.contains(fact.statement) ||
            !{'scene', 'unspecified'}.contains(fact.when) ||
            !hasRustText(fact.scope)) {
          throw const InvalidArgumentError(
            field: 'changes',
            message: 'unknown statement, time or empty scope intent',
          );
        }
      }
    }
    if (this case ReadFactsRequest(:final objectNames)) {
      if (objectNames.isEmpty ||
          objectNames.length > 100 ||
          objectNames.any((n) => !hasRustText(n))) {
        throw const InvalidArgumentError(
          field: 'object_names',
          message: 'one to 100 nonempty object names required',
        );
      }
    }
    if (this case ReadContractsRequest(:final actionNames)) {
      if (actionNames.length > 100 || actionNames.any((n) => !hasRustText(n))) {
        throw const InvalidArgumentError(
          field: 'action_names',
          message: 'at most 100 nonempty exact action names',
        );
      }
    }
    if (this case GetProposalRequest(
      :final assessmentReference,
      :final viewGroup,
    )) {
      if (assessmentReference != null && viewGroup != ProposalView.assessment) {
        throw const InvalidArgumentError(
          field: 'assessment_reference',
          message: 'requires assessment view',
        );
      }
    }
    final args = {for (final e in toArgs().fields) e.key: e.value};
    for (final key in ['universe', 'world']) {
      final value = args[key];
      if (value != null) {
        final text = wireString(value);
        // Selectors are literal JSON strings, not paths or wildcard patterns.
        // Use the same name contract as creation, rename and import.
        try {
          selectorKey(text);
        } on FormatException {
          throw InvalidArgumentError(
            field: key,
            message: 'expected a valid literal selector name',
          );
        }
      }
    }
    if (args.containsKey('world_id') && !args.containsKey('world')) {
      throw const InvalidArgumentError(
        field: 'world_id',
        message: 'requires world',
      );
    }
    if (args.containsKey('event') != args.containsKey('event_side')) {
      throw const InvalidArgumentError(
        field: 'event',
        message: 'event and event_side must be supplied together',
      );
    }
    for (final key in ['idempotency_key', 'rationale', 'purpose']) {
      final value = args[key];
      if (value != null) {
        final text = wireString(value);
        if (!hasRustText(text) || utf8.encode(text).length > 4096) {
          throw InvalidArgumentError(
            field: key,
            message: 'expected 1..4096 bytes',
          );
        }
      }
    }
    for (final key in [
      'operations',
      'record_ids',
      'entity_ids',
      'focus_ids',
      'changed_records',
    ]) {
      final list = args[key];
      if (list is CanonicalArray &&
          (list.items.isEmpty || list.items.length > 100)) {
        throw InvalidArgumentError(
          field: key,
          message: 'expected 1..100 items',
        );
      }
    }
    for (final (key, lo, hi) in [
      ('limit', 1, 100),
      ('byte_budget', 256, 65536),
    ]) {
      final value = args[key];
      if (value != null) {
        final number = _requestU32(value);
        if (number < lo || number > hi) {
          throw InvalidArgumentError(
            field: key,
            message: 'outside request limits',
          );
        }
      }
    }
  }
}
