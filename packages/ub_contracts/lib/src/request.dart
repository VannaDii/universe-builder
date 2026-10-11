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

/// Closed implemented request contracts. Writing-language tools remain pending.
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
    if (bytes.length > 1024 * 1024) {
      throw const FormatException('Frame too large');
    }
    return fromWire(CanonicalValue.parseJson(utf8.decode(bytes)));
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
    'universe_describe' ||
    'universe_open_context' ||
    'universe_search' ||
    'universe_get' ||
    'universe_get_state' ||
    'universe_get_context' => ReadRequest._parse(name, args),
    _ => WorkflowRequest._parse(name, args),
  };
  void validate() {
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
        final first = text.runes.firstOrNull;
        if (!hasRustText(text) ||
            utf8.encode(text).length > 256 ||
            (text.contains('*') || text.contains('/') || text.contains('\\')) ||
            text.runes.any((r) => r <= 0x1f || (r >= 0x7f && r <= 0x9f)) ||
            (first != null && !hasRustText(String.fromCharCode(first)))) {
          throw InvalidArgumentError(
            field: key,
            message: 'expected an exact nonblank selector',
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
