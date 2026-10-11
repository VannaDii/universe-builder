part of 'assessment.dart';

const _assessmentFrameLimit = 1024 * 1024;

/// Validates accounting and trusted retained bytes. Authentication, visibility,
/// candidate activity and factual interpretation belong to service admission.
extension SourceAssessmentIntegrity on SourceAssessmentV1 {
  Uint8List canonicalBytes() {
    validate();
    return toWire().toBytes();
  }

  Sha256Hex digest() {
    validate();
    return Sha256Hex(payloadDigest('source-assessment:v1', toWire()));
  }

  Sha256Hex inventoryDigest() {
    validate();
    return Sha256Hex(
      canonicalDigest(CanonicalArray(declaredInventory.map((i) => i.toWire()))),
    );
  }

  Sha256Hex bindFrozenProposal(ProposalRef reference, Frame frame) {
    _assessmentEnsure(
      proposal == reference &&
          baseFrame.toWire().toText() == frame.toWire().toText(),
      'Frozen proposal/frame mismatch',
    );
    return digest();
  }

  void verifySourceBytes(Uint8List? Function(AssessmentVersionRef) lookup) {
    validate();
    for (final source in sources) {
      final raw = lookup(source.sourceVersion);
      if (raw == null) {
        throw const FormatException('Missing retained source bytes');
      }
      utf8.decode(raw); // Strict UTF-8, even when a supplied digest matches.
      _assessmentEnsure(
        BigInt.from(raw.length) == source.byteSize &&
            sha256.convert(raw).toString() == source.blobDigest.value,
        'Source byte binding mismatch',
      );
      bool aligned(ByteRange range) {
        bool boundary(BigInt position) {
          final offset = position
              .toInt(); // Range and byte-size checks precede conversion.
          return offset == raw.length || raw[offset] & 0xc0 != 0x80;
        }

        return boundary(range.start) && boundary(range.end);
      }

      for (final range in source.ranges) {
        _assessmentEnsure(aligned(range), 'Source range splits UTF-8');
      }
      for (final item in declaredInventory.where(
        (i) => i.sourceKey == source.key,
      )) {
        _assessmentEnsure(aligned(item.range), 'Item range splits UTF-8');
      }
      for (final exclusion in inventoryDeclaration.exclusions.where(
        (e) => e.sourceKey == source.key,
      )) {
        _assessmentEnsure(
          aligned(exclusion.range),
          'Exclusion range splits UTF-8',
        );
      }
    }
  }

  void validate() {
    final tree = toWire();
    _assessmentEnsure(
      tree.toBytes().length <= _assessmentFrameLimit,
      'Assessment exceeds frame limit',
    );
    Sha256Hex(proposal.digest);
    _assessmentEnsure(
      proposal.version > BigInt.zero,
      'Proposal version must be positive',
    );
    _assessmentEnsure(
      sources.isNotEmpty && sources.length <= 64,
      'Source count outside limits',
    );
    _assessmentEnsure(
      dependencies.length <= 16384 &&
          declaredInventory.length <= 4096 &&
          claimMappings.length <= 4096 &&
          unresolved.length <= 4096,
      'Assessment list limit exceeded',
    );
    _assessmentTimestamp(assessor.assessedAt);
    _assessmentEnsure(
      (assessor.method == Method.humanReview && assessor.tool == null) ||
          (assessor.method == Method.externalModelReview &&
              assessor.tool != null),
      'Assessor method/tool mismatch',
    );
    _assessmentTextLimits(tree);
    _assessmentUnique(dependencies.map((d) => d.toWire()));
    final declared = dependencies.map((d) => d.toWire().toText()).toSet();
    final sourceByKey = <String, SourceBinding>{};
    for (final source in sources) {
      _assessmentEnsure(
        !sourceByKey.containsKey(source.key),
        'Duplicate source key',
      );
      sourceByKey[source.key] = source;
      _assessmentEnsure(source.ranges.isNotEmpty, 'Source requires ranges');
      _assessmentUnique(source.ranges.map((r) => r.toWire()));
      for (final range in source.ranges) {
        _assessmentEnsure(
          _rangeValid(range, source.byteSize),
          'Invalid source range',
        );
      }
      declared.add(source.sourceVersion.toWire().toText());
      if (source.workEdition != null) {
        declared.add(source.workEdition!.toWire().toText());
      }
    }
    _assessmentReferences(tree, baseFrame.universe.value, declared);
    _assessmentEnsure(
      baseFrame.context.universe == null ||
          baseFrame.context.universe == baseFrame.universe,
      'Cross-universe frame context',
    );
    final historical = claimMappings
        .expand((m) => m.candidateLinks)
        .where((l) => l.kind == CandidateLinkKind.historicalEvidence)
        .map((l) => l.version.toWire().toText())
        .toSet();
    final active = <RecordId, RecordVersionId>{};
    for (final dep in [
      ...dependencies,
      for (final source in sources) ...[
        source.sourceVersion,
        if (source.workEdition != null) source.workEdition!,
      ],
    ]) {
      if (!historical.contains(dep.toWire().toText())) {
        _assessmentEnsure(
          active[dep.record] == null || active[dep.record] == dep.version,
          'Conflicting active versions',
        );
        active[dep.record] = dep.version;
      }
    }
    bool inScope(String key, ByteRange range) {
      final source = sourceByKey[key];
      return source != null &&
          _rangeValid(range, source.byteSize) &&
          source.ranges.any(
            (r) => r.start <= range.start && range.end <= r.end,
          );
    }

    final items = <String, MaterialItem>{};
    for (final item in declaredInventory) {
      _assessmentEnsure(!items.containsKey(item.itemId), 'Duplicate item ID');
      items[item.itemId] = item;
      _assessmentEnsure(
        inScope(item.sourceKey, item.range),
        'Inventory range outside source scope',
      );
      _assessmentUnique(item.mappingIds.map(CanonicalString.new));
      _assessmentUnique(item.unresolvedIds.map(CanonicalString.new));
      _assessmentEnsure(
        item.mappingIds.isNotEmpty || item.unresolvedIds.isNotEmpty,
        'Unaccounted material item',
      );
    }
    _assessmentUnique(inventoryDeclaration.exclusions.map((e) => e.toWire()));
    for (final exclusion in inventoryDeclaration.exclusions) {
      _assessmentEnsure(
        inScope(exclusion.sourceKey, exclusion.range),
        'Exclusion outside source scope',
      );
    }
    _assessmentEnsure(switch (inventoryDeclaration.kind) {
      InventoryKind.noMaterialClaims =>
        items.isEmpty && claimMappings.isEmpty && unresolved.isEmpty,
      InventoryKind.materialInventoryDeclared => items.isNotEmpty,
    }, 'Inventory declaration mismatch');
    final pendingById = <String, UnresolvedDisposition>{};
    for (final u in unresolved) {
      _assessmentEnsure(
        !pendingById.containsKey(u.unresolvedId),
        'Duplicate unresolved ID',
      );
      pendingById[u.unresolvedId] = u;
      _assessmentUnique(u.itemIds.map(CanonicalString.new));
      _assessmentEnsure(
        u.itemIds.isNotEmpty,
        'Unresolved disposition lacks items',
      );
      for (final id in u.itemIds) {
        _assessmentEnsure(
          items[id]?.unresolvedIds.contains(u.unresolvedId) ?? false,
          'Unresolved/item links disagree',
        );
      }
      _assessmentEnsure(
        u.itemIds.map((id) => items[id]!.sourceKey).toSet().length == 1,
        'Unresolved disposition crosses source scopes',
      );
    }
    final mappingById = <String, ClaimMapping>{};
    for (final m in claimMappings) {
      _assessmentEnsure(
        !mappingById.containsKey(m.mappingId),
        'Duplicate mapping ID',
      );
      mappingById[m.mappingId] = m;
      _assessmentUnique(m.itemIds.map(CanonicalString.new));
      _assessmentUnique(m.referents.map((r) => r.toWire()));
      _assessmentUnique(m.candidateLinks.map((l) => l.toWire()));
      _assessmentEnsure(m.itemIds.isNotEmpty, 'Mapping lacks items');
      for (final id in m.itemIds) {
        _assessmentEnsure(
          items[id]?.mappingIds.contains(m.mappingId) ?? false,
          'Mapping/item links disagree',
        );
      }
      _assessmentEnsure(
        m.itemIds.map((id) => items[id]!.sourceKey).toSet().length == 1,
        'Mapping crosses source scopes',
      );
      m.storyTime.validate();
      final time = m.storyTime;
      final unknown =
          time is UnspecifiedTime ||
          (time is IntervalTime &&
              (!time.start.isKnown || !time.end.isKnown)) ||
          m.narrationPosition is UnknownPosition ||
          m.readerPosition is UnknownPosition ||
          m.occurrence == Occurrence.unknown ||
          m.modality == Modality.unknown;
      _assessmentEnsure(
        !unknown || m.judgment == MappingJudgment.unresolved,
        'Unknown material must be unresolved',
      );
      if (m.judgment == MappingJudgment.unresolved) {
        _assessmentEnsure(
          m.itemIds.every(
            (id) => items[id]!.unresolvedIds.any(
              (u) => pendingById[u]?.itemIds.contains(id) ?? false,
            ),
          ),
          'Unresolved mapping lacks disposition',
        );
      }
      switch (m.semantic) {
        case ClaimSemanticMapping(:final value, :final roles):
          value.validate();
          _assessmentUnique(roles.map((r) => r.toWire()));
        case ActionSemanticMapping(
          :final participants,
          :final prerequisites,
          :final effects,
        ):
          _assessmentUnique(participants.map((p) => p.toWire()));
          _assessmentUnique(prerequisites.map((p) => p.toWire()));
          _assessmentUnique(effects.map((e) => e.toWire()));
        case KnowledgeSemanticMapping(:final acquisition):
          _assessmentUnique(acquisition.map((a) => a.toWire()));
        case SourceDescriptionSemanticMapping(:final impliedClaims):
          _assessmentUnique(impliedClaims.map((c) => c.toWire()));
      }
    }
    for (final item in items.values) {
      for (final id in item.mappingIds) {
        _assessmentEnsure(
          mappingById[id]?.itemIds.contains(item.itemId) ?? false,
          'Dangling mapping link',
        );
      }
      for (final id in item.unresolvedIds) {
        _assessmentEnsure(
          pendingById[id]?.itemIds.contains(item.itemId) ?? false,
          'Dangling unresolved link',
        );
      }
    }
    final contradicted = claimMappings.any(
      (m) => m.judgment == MappingJudgment.contradicted,
    );
    final pending =
        unresolved.isNotEmpty ||
        claimMappings.any((m) => m.judgment == MappingJudgment.unresolved);
    _assessmentEnsure(switch (conclusion) {
      DeclaredConclusion.consistentWithDeclaredInventory =>
        !contradicted && !pending,
      DeclaredConclusion.inconsistent => contradicted,
      DeclaredConclusion.unresolved => !contradicted && pending,
    }, 'Conclusion disagrees with accounting');
  }
}

extension AssessmentEnvelopeIntegrity on AssessmentEnvelope {
  void verify() => _assessmentEnsure(
    digest == body.digest(),
    'Assessment envelope digest mismatch',
  );
}

void _assessmentEnsure(bool condition, String message) {
  if (!condition) throw FormatException(message);
}

bool _rangeValid(ByteRange range, BigInt size) =>
    range.start < range.end && range.end <= size;
void _assessmentUnique(Iterable<CanonicalValue> values) {
  final seen = <String>{};
  for (final value in values) {
    _assessmentEnsure(seen.add(value.toText()), 'Duplicate list entry');
  }
}

void _assessmentTextLimits(CanonicalValue value) {
  switch (value) {
    case CanonicalString(:final value):
      _assessmentEnsure(
        hasRustText(value) && utf8.encode(value).length <= 16384,
        'Empty or oversized text',
      );
    case CanonicalArray(:final items):
      for (final item in items) {
        _assessmentTextLimits(item);
      }
    case CanonicalObject(:final fields):
      for (final field in fields) {
        if (field.key != 'value' && field.key != 'base_frame') {
          _assessmentTextLimits(field.value);
        }
      }
    default:
      break;
  }
}

void _assessmentReferences(
  CanonicalValue value,
  String universe,
  Set<String> declared,
) {
  switch (value) {
    case CanonicalObject(:final fields):
      final object = {for (final field in fields) field.key: field.value};
      if (object.containsKey('record') && object.containsKey('version')) {
        final namespace = object['universe'];
        _assessmentEnsure(
          namespace is CanonicalString && namespace.value == universe,
          'Cross-universe reference',
        );
        _assessmentEnsure(
          declared.contains(value.toText()),
          'Undeclared exact reference',
        );
      }
      for (final field in fields) {
        _assessmentReferences(field.value, universe, declared);
      }
    case CanonicalArray(:final items):
      for (final item in items) {
        _assessmentReferences(item, universe, declared);
      }
    default:
      break;
  }
}

// Matches the locked Chrono RFC3339 decoder without DateTime normalization.
void _assessmentTimestamp(String value) {
  final match = RegExp(
    r'^([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt ]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?([Zz]|[+\-−][0-9]{2}:[0-9]{2})$',
  ).firstMatch(value);
  _assessmentEnsure(
    match != null && match.end == value.length,
    'Invalid assessment timestamp',
  );
  final m = match!;
  final year = int.parse(m[1]!);
  final month = int.parse(m[2]!);
  final day = int.parse(m[3]!);
  _assessmentEnsure(month >= 1 && month <= 12, 'Invalid assessment timestamp');
  final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  _assessmentEnsure(
    day >= 1 &&
        day <= days[month - 1] &&
        int.parse(m[4]!) <= 23 &&
        int.parse(m[5]!) <= 59 &&
        int.parse(m[6]!) <= 60,
    'Invalid assessment timestamp',
  );
  final offset = m[7]!;
  if (offset != 'Z' && offset != 'z') {
    final hours = int.parse(offset.substring(1, 3));
    final minutes = int.parse(offset.substring(4, 6));
    _assessmentEnsure(
      hours <= 23 && minutes <= 59,
      'Invalid assessment timestamp',
    );
    _assessmentEnsure(
      hours == 0 && minutes == 0,
      'Assessment timestamp must be UTC',
    );
  }
}
