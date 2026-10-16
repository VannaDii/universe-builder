@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';

final maxU64 = (BigInt.one << 64) - BigInt.one;
EditorFormScope scope() => EditorFormScope(
  instance: OperationId.generate(),
  profile: ProfileId.generate(),
  universe: UniverseId.generate(),
  continuity: ContinuityId.generate(),
  representedContext: RecordId.generate(),
);
List<String> binding(EditorFormScope s) => [
  s.instance.value,
  s.profile.value,
  s.universe.value,
  s.continuity.value,
  s.representedContext!.value,
  s.typeClientRef ?? '',
];
const originalText = '\ufeffAé😀\r\n記憶 e\u0301\n\u0000';
UnfinishedSourceForm sourceForm(EditorFormScope s) {
  final source = RecordId.generate(), version = RecordId.generate();
  final pin = VersionRef(
    record: version,
    version: RecordVersionId.generate(),
    universe: s.universe,
  );
  return UnfinishedSourceForm(
    baseRevision: RevisionId.generate(),
    representedContext: s.representedContext!,
    clientRef: '\ufeffPending import',
    label: '\ufeffSource label',
    text: originalText,
    rationale: '\ufeffReason\r\n',
    draftVersion: maxU64,
    anchorSource: pin,
    staged: [
      RecordNarrativeReferenceOperation(
        clientRef: source.value,
        record: RecordKind.source,
        payload: SourceRecord(
          label: '\ufeffStaged label',
          externalId: '',
          origin: const OriginMetadata(
            externallyAssertedAuthor: '\ufeffAttributed author',
            originNote: null,
          ),
          versions: [version, source, version],
        ),
      ),
      RecordNarrativeReferenceOperation(
        clientRef: version.value,
        record: RecordKind.sourceVersion,
        payload: SourceVersionRecord(
          source: RecordRef(record: source),
          contentDigest: 'a' * 64,
          mediaType: '\ufefftext/plain',
          byteSize: maxU64,
          importActor: PrincipalId.generate(),
          importTime: '\ufeffAuthored import time',
          decoding: DecodingDescriptor(
            encoding: 'UTF-8',
            representation: '\ufeffOriginal bytes',
            byteLength: maxU64,
          ),
          origin: const OriginMetadata(
            externallyAssertedAuthor: null,
            originNote: '',
          ),
        ),
      ),
      AddSourceAnchorOperation(
        clientRef: '\ufeffByte anchor',
        record: AnchorRecord(
          sourceVersion: pin,
          locator: ByteRangeLocator(BigInt.parse('9007199254740993'), maxU64),
          excerptDigest: 'b' * 64,
          excerpt: originalText,
          context: RecordRef(
            record: s.representedContext!,
            universe: s.universe,
          ),
        ),
      ),
      AddSourceAnchorOperation(
        clientRef: '\ufeffPath anchor',
        record: AnchorRecord(
          sourceVersion: VersionRef(record: version, version: pin.version),
          locator: StructuralPathLocator([
            '\ufeffChapter',
            '',
            'Repeated',
            'Repeated',
          ]),
          excerptDigest: 'c' * 64,
          excerpt: '\ufeffPath excerpt\r\n',
          context: null,
        ),
      ),
    ],
  );
}

void main() {
  test(
    'source draft versions retain the existing unsigned 64-bit wire bound',
    () {
      final s = scope();
      for (final invalid in [-BigInt.one, maxU64 + BigInt.one]) {
        expect(
          () => UnfinishedSourceForm(
            baseRevision: RevisionId.generate(),
            representedContext: s.representedContext!,
            clientRef: 'unfinished',
            draftVersion: invalid,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('typed source recovery retains staged identities, metadata, both locators and exact text across restart', () {
    final root = Directory('/tmp').createTempSync('ub-typed-source-');
    final path = '${root.path}/forms.sqlite',
        s = scope(),
        input = sourceForm(s);
    var store = SourceFormRecoveryStore.open(path);
    try {
      store.save(s, input, BigInt.zero);
      store.close();
      store = SourceFormRecoveryStore.open(path);
      expect(store.load(s)!.form.toWire().toText(), input.toWire().toText());
      expect(store.save(s, input, BigInt.zero).generation, BigInt.one);
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(
          db.select('PRAGMA table_info(source_form)').map((r) => r['name']),
          isNot(contains('form_input')),
        );
        expect(
          db
              .select(
                'SELECT CAST(source_text AS BLOB) AS text FROM source_form',
              )
              .single['text'],
          utf8.encode(originalText),
        );
        expect(
          db
              .select(
                'SELECT record_kind FROM source_operation ORDER BY ordinal',
              )
              .map((r) => r['record_kind']),
          ['source', 'source_version', 'anchor', 'anchor'],
        );
        expect(
          db
              .select(
                "SELECT CAST(item AS BLOB) AS text FROM source_operation_item WHERE list_kind='path' ORDER BY ordinal",
              )
              .map((r) => r['text']),
          ['\ufeffChapter', '', 'Repeated', 'Repeated'].map(utf8.encode),
        );
      } finally {
        db.close();
      }
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
