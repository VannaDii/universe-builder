part of 'records.dart';

/// Origin is attributed source metadata, not a service claim of authorship.
final class OriginMetadata {
  const OriginMetadata({this.externallyAssertedAuthor, this.originNote});
  final String? externallyAssertedAuthor, originNote;
  factory OriginMetadata.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'externallyAssertedAuthor', 'originNote'});
    return OriginMetadata(
      externallyAssertedAuthor: f.optionalString('externallyAssertedAuthor'),
      originNote: f.optionalString('originNote'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    if (externallyAssertedAuthor != null)
      MapEntry(
        'externallyAssertedAuthor',
        CanonicalString(externallyAssertedAuthor!),
      ),
    MapEntry('originNote', _nullableString(originNote)),
  ]);
}

/// The external identifier is descriptive data and does not request a fetch.
final class SourceRecord extends RecordPayload {
  SourceRecord({
    required this.label,
    this.externalId,
    required this.origin,
    required Iterable<RecordId> versions,
  }) : versions = List.unmodifiable(versions);
  final String label;
  final String? externalId;
  final OriginMetadata origin;
  final List<RecordId> versions;
  factory SourceRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.source, {
      'label',
      'externalId',
      'origin',
      'versions',
    });
    return SourceRecord(
      label: f.string('label'),
      externalId: f.optionalString('externalId'),
      origin: OriginMetadata.fromWire(f.require('origin')),
      versions: _ids(f.array('versions')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.source;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('label', CanonicalString(label)),
    if (externalId != null)
      MapEntry('externalId', CanonicalString(externalId!)),
    MapEntry('origin', origin.toWire()),
    MapEntry('versions', _idArray(versions)),
  ]);
}

/// Text anchor offsets name UTF-8 bytes in this declared representation.
final class DecodingDescriptor {
  DecodingDescriptor({
    required this.encoding,
    required this.representation,
    required BigInt byteLength,
  }) : byteLength = _checkedU64(byteLength);
  final String encoding, representation;
  final BigInt byteLength;
  factory DecodingDescriptor.fromWire(CanonicalValue value) {
    final f = Fields(value)
      ..allow({'encoding', 'representation', 'byteLength'});
    return DecodingDescriptor(
      encoding: f.string('encoding'),
      representation: f.string('representation'),
      byteLength: _u64(f, 'byteLength'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('encoding', CanonicalString(encoding)),
    MapEntry('representation', CanonicalString(representation)),
    MapEntry('byteLength', CanonicalNumber(byteLength.toString())),
  ]);
}

/// Retained-content digest and import metadata do not establish factual truth.
final class SourceVersionRecord extends RecordPayload {
  SourceVersionRecord({
    required this.source,
    required this.contentDigest,
    required this.mediaType,
    required BigInt byteSize,
    required this.importActor,
    required this.importTime,
    required this.decoding,
    required this.origin,
  }) : byteSize = _checkedU64(byteSize);
  final RecordRef source;
  final String contentDigest;
  final String mediaType, importTime;
  final BigInt byteSize;
  final PrincipalId importActor;
  final DecodingDescriptor decoding;
  final OriginMetadata origin;
  factory SourceVersionRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.sourceVersion, {
      'source',
      'digest',
      'mediaType',
      'byteSize',
      'importActor',
      'importTime',
      'decoding',
      'origin',
    });
    return SourceVersionRecord(
      source: RecordRef.fromCanonical(f.require('source')),
      contentDigest: f.string('digest'),
      mediaType: f.string('mediaType'),
      byteSize: _u64(f, 'byteSize'),
      importActor: PrincipalId.parse(f.string('importActor')),
      importTime: f.string('importTime'),
      decoding: DecodingDescriptor.fromWire(f.require('decoding')),
      origin: OriginMetadata.fromWire(f.require('origin')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.sourceVersion;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('source', source.toCanonical()),
    MapEntry('digest', CanonicalString(contentDigest)),
    MapEntry('mediaType', CanonicalString(mediaType)),
    MapEntry('byteSize', CanonicalNumber(byteSize.toString())),
    MapEntry('importActor', CanonicalString(importActor.value)),
    MapEntry('importTime', CanonicalString(importTime)),
    MapEntry('decoding', decoding.toWire()),
    MapEntry('origin', origin.toWire()),
  ]);
}

sealed class AnchorLocator {
  const AnchorLocator();
  CanonicalObject toWire();
  CanonicalObject toCanonical() => toWire();
  static AnchorLocator fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'byte_range':
        f.allow({'kind', 'start', 'end'});
        return ByteRangeLocator(_u64(f, 'start'), _u64(f, 'end'));
      case 'structural_path':
        f.allow({'kind', 'path'});
        return StructuralPathLocator(f.array('path').map(_string));
      default:
        throw const FormatException('Unknown anchor locator');
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AnchorLocator && toWire().toText() == other.toWire().toText();
  @override
  int get hashCode => toWire().toText().hashCode;
}

final class ByteRangeLocator extends AnchorLocator {
  ByteRangeLocator(BigInt start, BigInt end)
    : start = _checkedU64(start),
      end = _checkedU64(end);
  final BigInt start, end;
  @override
  CanonicalObject toWire() => tagged('byte_range', [
    MapEntry('start', CanonicalNumber(start.toString())),
    MapEntry('end', CanonicalNumber(end.toString())),
  ]);
}

final class StructuralPathLocator extends AnchorLocator {
  StructuralPathLocator(Iterable<String> path) : path = List.unmodifiable(path);
  final List<String> path;
  @override
  CanonicalObject toWire() => tagged('structural_path', [
    MapEntry('path', CanonicalArray(path.map(CanonicalString.new))),
  ]);
}

final class AnchorRecord extends RecordPayload {
  const AnchorRecord({
    required this.sourceVersion,
    required this.locator,
    required this.excerptDigest,
    required this.excerpt,
    this.context,
  });
  final VersionRef sourceVersion;
  final AnchorLocator locator;
  final String excerptDigest, excerpt;
  final RecordRef? context;
  factory AnchorRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.anchor, {
      'sourceVersion',
      'locator',
      'excerptDigest',
      'excerpt',
      'context',
    });
    return AnchorRecord(
      sourceVersion: VersionRef.fromCanonical(f.require('sourceVersion')),
      locator: AnchorLocator.fromWire(f.require('locator')),
      excerptDigest: f.string('excerptDigest'),
      excerpt: f.string('excerpt'),
      context: _optionalRef(f, 'context'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.anchor;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('sourceVersion', sourceVersion.toCanonical()),
    MapEntry('locator', locator.toWire()),
    MapEntry('excerptDigest', CanonicalString(excerptDigest)),
    MapEntry('excerpt', CanonicalString(excerpt)),
    MapEntry('context', _nullableRef(context)),
  ]);
}
