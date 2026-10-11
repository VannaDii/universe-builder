part of 'records.dart';

sealed class AppearanceTarget {
  const AppearanceTarget();
  CanonicalObject toWire();
  static AppearanceTarget fromWire(CanonicalValue value) {
    final f = Fields(value);
    switch (f.string('kind')) {
      case 'universe':
        f.allow({'kind'});
        return const UniverseAppearance();
      case 'entry':
        f.allow({'kind', 'entry'});
        return EntryAppearance(RecordRef.fromCanonical(f.require('entry')));
      default:
        throw const FormatException('Unknown appearance target');
    }
  }
}

final class UniverseAppearance extends AppearanceTarget {
  const UniverseAppearance();
  @override
  CanonicalObject toWire() => tagged('universe', []);
}

final class EntryAppearance extends AppearanceTarget {
  const EntryAppearance(this.entry);
  final RecordRef entry;
  @override
  CanonicalObject toWire() =>
      tagged('entry', [MapEntry('entry', entry.toCanonical())]);
}

enum ImagePurpose {
  appearance,
  detail,
  inspiration;

  static ImagePurpose fromName(String name) => values.firstWhere(
    (v) => v.name == name,
    orElse: () => throw const FormatException('Unknown image purpose'),
  );
}

enum AppearanceRelationship {
  matches('matches'),
  complements('complements'),
  contrasts('contrasts'),
  detailOf('detail_of');

  const AppearanceRelationship(this.wireName);
  final String wireName;
  static AppearanceRelationship fromName(String name) => values.firstWhere(
    (v) => v.wireName == name,
    orElse: () =>
        throw const FormatException('Unknown appearance relationship'),
  );
}

final class AppearanceImage {
  const AppearanceImage({
    required this.asset,
    required this.caption,
    required this.purpose,
  });
  final RecordRef asset;
  final String caption;
  final ImagePurpose purpose;
  factory AppearanceImage.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'asset', 'caption', 'purpose'});
    return AppearanceImage(
      asset: RecordRef.fromCanonical(f.require('asset')),
      caption: f.string('caption'),
      purpose: ImagePurpose.fromName(f.string('purpose')),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('asset', asset.toCanonical()),
    MapEntry('caption', CanonicalString(caption)),
    MapEntry('purpose', CanonicalString(purpose.name)),
  ]);
}

final class AppearanceLink {
  const AppearanceLink({
    required this.entry,
    required this.relationship,
    required this.note,
  });
  final RecordRef entry;
  final AppearanceRelationship relationship;
  final String note;
  factory AppearanceLink.fromWire(CanonicalValue value) {
    final f = Fields(value)..allow({'entry', 'relationship', 'note'});
    return AppearanceLink(
      entry: RecordRef.fromCanonical(f.require('entry')),
      relationship: AppearanceRelationship.fromName(f.string('relationship')),
      note: f.string('note'),
    );
  }
  CanonicalObject toWire() => CanonicalObject([
    MapEntry('entry', entry.toCanonical()),
    MapEntry('relationship', CanonicalString(relationship.wireName)),
    MapEntry('note', CanonicalString(note)),
  ]);
}

final class AppearanceRecord extends RecordPayload {
  AppearanceRecord({
    required this.target,
    required this.label,
    required this.physicalDescription,
    required this.atmosphere,
    required Iterable<AppearanceImage> images,
    required Iterable<AppearanceLink> links,
    required this.validity,
  }) : images = List.unmodifiable(images),
       links = List.unmodifiable(links);
  final AppearanceTarget target;
  final String label, physicalDescription, atmosphere;
  final List<AppearanceImage> images;
  final List<AppearanceLink> links;
  final Validity validity;
  factory AppearanceRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.appearance, {
      'target',
      'label',
      'physical_description',
      'atmosphere',
      'images',
      'links',
      'validity',
    });
    return AppearanceRecord(
      target: AppearanceTarget.fromWire(f.require('target')),
      label: f.string('label'),
      physicalDescription: f.string('physical_description'),
      atmosphere: f.string('atmosphere'),
      images: f.array('images').map(AppearanceImage.fromWire),
      links: f.array('links').map(AppearanceLink.fromWire),
      validity: Validity.fromWire(f.require('validity')),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.appearance;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('target', target.toWire()),
    MapEntry('label', CanonicalString(label)),
    MapEntry('physical_description', CanonicalString(physicalDescription)),
    MapEntry('atmosphere', CanonicalString(atmosphere)),
    MapEntry('images', CanonicalArray(images.map((i) => i.toWire()))),
    MapEntry('links', CanonicalArray(links.map((l) => l.toWire()))),
    MapEntry('validity', validity.toWire()),
  ]);
}

int _u32(Fields fields, String key) {
  final value = _u64(fields, key);
  if (value > BigInt.from(4294967295)) {
    throw const FormatException('Unsigned 32-bit value outside range');
  }
  return value.toInt();
}

int _checkedU32(int value) {
  if (value < 0 || value > 4294967295) {
    throw const FormatException('Unsigned 32-bit value outside range');
  }
  return value;
}

final class ImageAssetRecord extends RecordPayload {
  ImageAssetRecord({
    required this.contentDigest,
    required this.mediaType,
    required BigInt byteSize,
    required int width,
    required int height,
    required this.originalName,
  }) : byteSize = _checkedU64(byteSize),
       width = _checkedU32(width),
       height = _checkedU32(height);
  final String contentDigest, mediaType, originalName;
  final BigInt byteSize;
  final int width, height;
  factory ImageAssetRecord.fromWire(CanonicalValue value) {
    final f = _recordFields(value, RecordKind.imageAsset, {
      'digest',
      'media_type',
      'byte_size',
      'width',
      'height',
      'original_name',
    });
    return ImageAssetRecord(
      contentDigest: f.string('digest'),
      mediaType: f.string('media_type'),
      byteSize: _u64(f, 'byte_size'),
      width: _u32(f, 'width'),
      height: _u32(f, 'height'),
      originalName: f.string('original_name'),
    );
  }
  @override
  RecordKind get recordKind => RecordKind.imageAsset;
  @override
  CanonicalObject toWire() => _recordWire(recordKind, [
    MapEntry('digest', CanonicalString(contentDigest)),
    MapEntry('media_type', CanonicalString(mediaType)),
    MapEntry('byte_size', CanonicalNumber(byteSize.toString())),
    MapEntry('width', CanonicalNumber(width.toString())),
    MapEntry('height', CanonicalNumber(height.toString())),
    MapEntry('original_name', CanonicalString(originalName)),
  ]);
}
