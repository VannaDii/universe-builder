import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'connection.dart';

({int count, AnchorRecord? selected}) sourceExcerptMatch({
  required String text,
  required String excerpt,
  required VersionRef source,
  required RecordRef context,
  int? occurrence,
}) {
  if (excerpt.isEmpty) throw const FormatException('Enter an exact excerpt.');
  if (occurrence != null && occurrence < 1) {
    throw const FormatException('Occurrences start at 1.');
  }
  var count = 0, offset = 0;
  final starts = <int>[];
  while (offset <= text.length) {
    final found = text.indexOf(excerpt, offset);
    if (found < 0) break;
    count++;
    if (count == occurrence || count == 1) starts.add(found);
    offset = found + 1;
  }
  final selectedOccurrence = occurrence ?? (count == 1 ? 1 : null);
  if (selectedOccurrence == null || selectedOccurrence > count) {
    return (count: count, selected: null);
  }
  final index = starts.last;
  final bytes = utf8.encode(excerpt);
  final start = BigInt.from(utf8.encode(text.substring(0, index)).length);
  return (
    count: count,
    selected: AnchorRecord(
      sourceVersion: source,
      locator: ByteRangeLocator(start, start + BigInt.from(bytes.length)),
      excerptDigest: sha256.convert(bytes).toString(),
      excerpt: excerpt,
      context: context,
    ),
  );
}

Future<String> readSourceText({
  required AppSession session,
  required Selector universe,
  required ContextId context,
  required VersionRef source,
}) async {
  final result = StringBuffer();
  var after = BigInt.zero;
  while (true) {
    final page = WireFields(
      await session.call(
        ReadSourceEngineRequest(
          universe: universe,
          contextId: context,
          sourceVersion: source,
          after: after,
        ),
      ),
      {'text', 'after', 'next'},
    );
    if (page.u64('after') != after) {
      throw const FormatException('Invalid source offset.');
    }
    result.write(page.string('text'));
    if (page.require('next') is CanonicalNull) return result.toString();
    final next = page.u64('next');
    if (next <= after) {
      throw const FormatException('Invalid source continuation.');
    }
    after = next;
  }
}
