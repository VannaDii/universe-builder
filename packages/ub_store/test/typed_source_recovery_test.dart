@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/editor_forms.dart';
import 'package:ub_store/installation.dart' show protectedFile;

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

void legacy(String path, List<(EditorFormScope, BigInt, String)> entries) {
  protectedFile(path, createNew: true);
  final db = sqlite3.open(path);
  try {
    db.execute(
      'CREATE TABLE source_form(instance TEXT NOT NULL,profile TEXT NOT NULL,universe TEXT NOT NULL,continuity TEXT NOT NULL,context TEXT NOT NULL,editor_key TEXT NOT NULL,generation TEXT NOT NULL,form_input TEXT NOT NULL,PRIMARY KEY(instance,profile,universe,continuity,context,editor_key)) STRICT; PRAGMA user_version=1',
    );
    for (final (s, generation, text) in entries) {
      db.execute('INSERT INTO source_form VALUES(?,?,?,?,?,?,?,?)', [
        ...binding(s),
        generation.toString(),
        text,
      ]);
    }
  } finally {
    db.close();
  }
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
  test('legacy source conversion preserves all profiles, source pins and generations without orphaning prior staged rows', () {
    final root = Directory('/tmp').createTempSync('ub-source-conversion-');
    final path = '${root.path}/forms.sqlite', first = scope(), second = scope();
    final input = sourceForm(first), other = sourceForm(second);
    legacy(path, [
      (first, BigInt.from(42), input.toWire().toText()),
      (second, maxU64, other.toWire().toText()),
    ]);
    var store = SourceFormRecoveryStore.open(path);
    final competing = SourceFormRecoveryStore.open(path);
    try {
      expect(
        store.load(first)!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(store.load(second)!.generation, maxU64);
      expect(
        store.load(second)!.form.toWire().toText(),
        other.toWire().toText(),
      );
      final reset = UnfinishedSourceForm(
        baseRevision: input.baseRevision,
        representedContext: input.representedContext,
        clientRef: input.clientRef,
        label: '\ufeffStill typing',
        text: originalText,
      );
      expect(
        store.save(first, reset, BigInt.from(42)).generation,
        BigInt.from(43),
      );
      expect(
        store.save(first, reset, BigInt.from(42)).generation,
        BigInt.from(43),
      );
      expect(
        () => competing.save(first, input, BigInt.from(42)),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        () => store.save(second, other, maxU64),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.generationExhausted,
          ),
        ),
      );
      store.close();
      store = SourceFormRecoveryStore.open(path);
      expect(
        store.load(first)!.form.toWire().toText(),
        reset.toWire().toText(),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 2);
        expect(
          db.select(
            'SELECT count(*) AS n FROM source_operation WHERE profile=?',
            [first.profile.value],
          ).single['n'],
          0,
        );
        expect(
          db.select(
            'SELECT count(*) AS n FROM source_operation_item WHERE profile=?',
            [first.profile.value],
          ).single['n'],
          0,
        );
        expect(
          db.select(
            'SELECT count(*) AS n FROM source_operation WHERE profile=?',
            [second.profile.value],
          ).single['n'],
          other.staged.length,
        );
      } finally {
        db.close();
      }
    } finally {
      competing.close();
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('failed source conversion rolls back every row and retains original unfinished input', () {
    final root = Directory('/tmp')
        .createTempSync('ub-source-conversion-failed-');
    final path = '${root.path}/forms.sqlite', first = scope(), second = scope();
    final text = sourceForm(first).toWire().toText();
    legacy(path, [
      (first, BigInt.one, text),
      (second, BigInt.two, '{unfinished'),
    ]);
    try {
      expect(
        () => SourceFormRecoveryStore.open(path),
        throwsA(isA<EditorRecoveryException>()),
      );
      final db = sqlite3.open(path, mode: OpenMode.readOnly);
      try {
        expect(db.select('PRAGMA user_version').single.values.single, 1);
        expect(
          db
              .select('SELECT form_input FROM source_form ORDER BY generation')
              .map((r) => r['form_input']),
          [text, '{unfinished'],
        );
        expect(
          db
              .select("SELECT name FROM sqlite_master WHERE type='table'")
              .map((r) => r['name']),
          ['source_form'],
        );
      } finally {
        db.close();
      }
    } finally {
      root.deleteSync(recursive: true);
    }
  });
}
