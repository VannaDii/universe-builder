import 'package:test/test.dart';
import 'package:ub_app/dossier_sources.dart';
import 'package:ub_app/record_browser.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

void main() {
  test('source selection preserves exact historical bindings and text', () {
    final universe = UniverseId.generate(), foreign = UniverseId.generate();
    RecordVersion row(
      RecordPayload payload, {
      RecordId? id,
      UniverseId? inUniverse,
    }) => RecordVersion.build(
      recordVersionId: RecordVersionId.generate(),
      identity: RecordIdentity(
        universeId: inUniverse ?? universe,
        recordId: id ?? RecordId.generate(),
        recordKind: payload.recordKind,
      ),
      payload: payload,
    );
    final source = row(
      SourceRecord(
        label: 'Journal 記憶 😀',
        externalId: 'https://example.invalid/journal',
        origin: const OriginMetadata(externallyAssertedAuthor: 'Mara'),
        versions: [],
      ),
    );
    final payload = SourceVersionRecord(
      source: RecordRef(record: source.identity.recordId, universe: universe),
      contentDigest: 'a' * 64,
      mediaType: 'text/plain',
      byteSize: BigInt.from(9),
      importActor: PrincipalId.generate(),
      importTime: '2040-01-01T00:00:00Z',
      decoding: DecodingDescriptor(
        encoding: 'UTF-8',
        representation: 'exact-utf8-v1',
        byteLength: BigInt.from(9),
      ),
      origin: const OriginMetadata(originNote: 'Firsthand recollection'),
    );
    final version = row(payload);
    final newer = row(payload, id: version.identity.recordId);
    AnchorRecord anchor({UniverseId? inUniverse}) => AnchorRecord(
      sourceVersion: VersionRef(
        record: version.identity.recordId,
        version: version.recordVersionId,
        universe: inUniverse ?? universe,
      ),
      locator: ByteRangeLocator(BigInt.from(2), BigInt.from(9)),
      excerptDigest: 'b' * 64,
      excerpt: '記憶 😀\n',
    );
    final excerpt = row(anchor());
    final foreignSource = row(source.payload, inUniverse: foreign);
    final material = Records(
      records: [excerpt],
      evidence: [source, version, excerpt, foreignSource],
    );
    final selected = dossierSourceRecords(material, universe);
    expect(selected, [excerpt, source, version]);
    expect((selected.first.payload as AnchorRecord).excerpt, '記憶 😀\n');
    expect(dossierAnchorSource(selected, universe, anchor()), same(version));
    expect(dossierAnchorSource([newer, source], universe, anchor()), isNull);
    expect(
      dossierAnchorSource(selected, universe, anchor(inUniverse: foreign)),
      isNull,
    );
    expect(
      dossierReferenceLabel(material, universe, payload.source),
      'Journal 記憶 😀',
    );
    expect(
      sourceLocatorText(anchor().locator),
      'UTF-8 bytes 2–9 (end excluded)',
    );
    expect(
      sourceLocatorText(StructuralPathLocator(['chapter', '2'])),
      'Structural path: chapter / 2',
    );
  });
}
