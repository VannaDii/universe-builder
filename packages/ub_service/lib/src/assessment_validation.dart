import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'proposal_state.dart';
import 'source_verification.dart';

InvalidArgumentError _invalid(String message) =>
    InvalidArgumentError(field: 'assessment', message: message);

/// Overlay the entire frozen proposal, preserving unchanged base versions.
List<RecordVersion> assessmentCandidate(
  StoredProposal proposal,
  List<RecordVersion> base,
) {
  final rows = [...base];
  for (final change in proposal.changes) {
    rows.removeWhere((r) => r.identity.recordId == change.recordId);
    if (change.next != null) {
      rows.add(RecordVersion.fromWire(change.next!.toCanonical()));
    }
  }
  return List.unmodifiable(rows);
}

/// Verify attachment admission after current proposal and dependency visibility
/// checks. Structural accounting does not certify interpretation or approval.
Future<void> verifyAssessmentCandidate({
  required StoredProposal proposal,
  required UniverseId universe,
  required SourceAssessmentV1 body,
  required FutureOr<List<RecordVersion>> Function(ContinuityId, RevisionId)
  readCanon,
  required FutureOr<RecordVersion> Function(RecordVersionId) readVersion,
  required FutureOr<CanonicalValue?> Function(String) readWorkflow,
}) async {
  try {
    body.bindFrozenProposal(proposal.reference, proposal.proposal.baseFrame);
  } on FormatException catch (e) {
    throw _invalid(e.message);
  }
  final frame = proposal.proposal.baseFrame;
  final candidate = assessmentCandidate(
    proposal,
    await readCanon(frame.continuity, frame.revision),
  );
  bool active(AssessmentVersionRef ref) => candidate.any(
    (r) =>
        r.identity.recordId == ref.record && r.recordVersionId == ref.version,
  );
  Future<RecordVersion> historical(
    RecordVersionId version,
    String message,
  ) async {
    try {
      return await readVersion(version);
    } on Object {
      throw _invalid(message);
    }
  }

  final records = [...candidate];
  for (final dep in body.dependencies) {
    if (dep.universe != universe) throw _invalid('cross-universe dependency');
    RecordVersion? row;
    for (final r in candidate) {
      if (r.identity.recordId == dep.record &&
          r.recordVersionId == dep.version) {
        row = r;
        break;
      }
    }
    if (row == null) {
      final permitted = body.claimMappings
          .expand((m) => m.candidateLinks)
          .any(
            (l) =>
                l.kind == CandidateLinkKind.historicalEvidence &&
                l.version.toWire().toText() == dep.toWire().toText(),
          );
      if (!permitted) {
        throw _invalid('dependency is not active in frozen candidate');
      }
      row = await historical(dep.version, 'missing historical version');
    }
    if (row.identity.recordId != dep.record) {
      throw _invalid('record/version mismatch');
    }
    if (!records.any((r) => r.recordVersionId == row!.recordVersionId)) {
      records.add(row);
    }
  }
  void activeReferences(CanonicalValue value) {
    switch (value) {
      case CanonicalObject(:final fields):
        final f = {for (final entry in fields) entry.key: entry.value};
        if (f.containsKey('record') && f.containsKey('version')) {
          if (!active(AssessmentVersionRef.fromWire(value))) {
            throw _invalid(
              'semantic reference is not active in frozen candidate',
            );
          }
        }
        for (final entry in fields) {
          activeReferences(entry.value);
        }
      case CanonicalArray(:final items):
        for (final item in items) {
          activeReferences(item);
        }
      default:
        break;
    }
  }

  for (final mapping in body.claimMappings) {
    activeReferences(
      CanonicalObject(
        mapping.toWire().fields.where((f) => f.key != 'candidate_links'),
      ),
    );
    for (final link in mapping.candidateLinks) {
      if (link.kind == CandidateLinkKind.historicalEvidence) {
        final retained = await historical(
          link.version.version,
          'historical evidence must be a retained version',
        );
        if (retained.identity.recordId != link.version.record) {
          throw _invalid('historical record/version mismatch');
        }
      }
      final changed = proposal.changes.any(
        (c) => c.next?.versionId == link.version.version,
      );
      if (link.kind == CandidateLinkKind.proposedRecord &&
              (!changed || !active(link.version)) ||
          link.kind == CandidateLinkKind.unchangedRecord &&
              (changed || !active(link.version))) {
        throw _invalid('candidate link kind mismatch');
      }
    }
  }
  for (final source in body.sources) {
    RecordVersion? row;
    for (final r in candidate) {
      if (r.identity.recordId == source.sourceVersion.record &&
          r.recordVersionId == source.sourceVersion.version) {
        row = r;
        break;
      }
    }
    if (row == null) {
      throw _invalid('source version is not active in frozen candidate');
    }
    final payload = row.payload;
    if (payload is! SourceVersionRecord) {
      throw _invalid('source reference is not a source version');
    }
    if (source.blobDigest.value != payload.contentDigest ||
        source.byteSize != payload.byteSize) {
      throw _invalid('source metadata mismatch');
    }
    final edition = source.workEdition;
    if (edition != null) {
      if (!candidate.any(
        (r) =>
            r.identity.recordId == edition.record &&
            r.recordVersionId == edition.version &&
            r.payload is WorkVersionRecord,
      )) {
        throw _invalid('edition version is not active in frozen candidate');
      }
      if (source.passageId != null) {
        final valid = candidate.any((r) {
          final passage = r.payload;
          if (passage is! PassageRecord ||
              passage.passageId != source.passageId ||
              passage.workVersion.record != edition.record ||
              passage.workVersion.version != edition.version) {
            return false;
          }
          final anchor = passage.anchor;
          return anchor != null &&
              candidate.any((a) {
                final payload = a.payload;
                if (a.identity.recordId != anchor.record ||
                    payload is! AnchorRecord ||
                    payload.sourceVersion.record !=
                        source.sourceVersion.record ||
                    payload.sourceVersion.version !=
                        source.sourceVersion.version) {
                  return false;
                }
                final locator = payload.locator;
                return locator is ByteRangeLocator &&
                    source.ranges.any(
                      (range) =>
                          range.start <= locator.start &&
                          locator.end <= range.end,
                    );
              });
        });
        if (!valid) throw _invalid('passage/edition/source anchor mismatch');
      }
    }
  }
  for (final dep in body.dependencies) {
    for (final row in records) {
      if (row.recordVersionId != dep.version) continue;
      final anchor = row.payload;
      if (anchor is AnchorRecord) {
        final locator = anchor.locator;
        final valid = body.sources.any(
          (s) =>
              anchor.sourceVersion.universe == s.sourceVersion.universe &&
              anchor.sourceVersion.record == s.sourceVersion.record &&
              anchor.sourceVersion.version == s.sourceVersion.version &&
              locator is ByteRangeLocator &&
              s.ranges.any(
                (r) => r.start <= locator.start && locator.end <= r.end,
              ),
        );
        if (!valid) throw _invalid('anchor is outside declared source binding');
      }
      break;
    }
  }
  await verifyCandidateSources(
    records: records,
    readWorkflow: readWorkflow,
    readVersion: readVersion,
  );
  final bytes = <String, Uint8List>{};
  for (final source in body.sources) {
    try {
      final value = await readWorkflow('source:${source.blobDigest.value}');
      if (value is CanonicalString) {
        bytes[source.sourceVersion.toWire().toText()] = Uint8List.fromList(
          utf8.encode(value.value),
        );
      }
    } on Object {
      /* Missing retained bytes are rejected by the contract below. */
    }
  }
  try {
    body.verifySourceBytes((ref) => bytes[ref.toWire().toText()]);
  } on FormatException catch (e) {
    throw _invalid(e.message);
  }
}
