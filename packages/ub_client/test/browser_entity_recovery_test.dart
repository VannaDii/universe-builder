@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:test/test.dart';
import 'package:ub_client/browser_entity_recovery.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:web/web.dart' as web;

void main() {
  test('browser entity forms preserve contextual names, nested qualifiers, exact temporal text and omitted associations', () async {
    final name = 'ub-entity-test-${OperationId.generate().value}';
    var store = await BrowserEntityFormRecoveryStore.open(databaseName: name);
    final universe = UniverseId.generate(),
        context = RecordId.generate(),
        entity = RecordId.generate(),
        revision = RevisionId.generate();
    final instance = OperationId.generate(),
        profile = ProfileId.generate(),
        continuity = ContinuityId.generate();
    EditorFormScope scope({
      String? draft,
      bool contextualName = false,
      bool classification = false,
      int? index,
      RecordId? represented,
    }) => EditorFormScope(
      instance: instance,
      profile: profile,
      universe: universe,
      continuity: continuity,
      representedContext: represented ?? context,
      entityClientRef: draft,
      entityNameRecord: contextualName ? entity : null,
      entityClassificationRecord: classification ? entity : null,
      entityOperationIndex: index,
    );
    final world = WorldId.generate(), version = RecordVersionId.generate();
    final temporal = TemporalValidityInput(
      kind: 'relative',
      calendar: 'calendar choice',
      relation: 'before',
      targetUniverse: universe.value,
      targetRecord: 'unresolved event',
      start: TemporalBoundInput(
        kind: 'offset',
        value: '9007199254740993123456789',
        denominator: '7',
        amount: QualifierInput(
          kind: 'rational',
          value: '9007199254740993123456789',
          denominator: '13',
        ),
      ),
      end: TemporalBoundInput(
        kind: 'range',
        value: 'unfinished-',
        upper: '',
        uncertainty: '± ?',
      ),
    );
    final qualifiers = [
      QualifierInput(
        key: 'mémoire 😀',
        originalKey: '',
        kind: 'object',
        children: [
          QualifierInput(
            key: 'ordered',
            kind: 'list',
            children: [
              QualifierInput(
                kind: 'integer',
                value: '9007199254740993123456789',
              ),
              QualifierInput(kind: 'text', value: 'é😀\r\n'),
            ],
          ),
        ],
        temporal: temporal,
        lower: QualifierInput(kind: 'decimal', value: '-0.000000000000000001'),
        upper: QualifierInput(kind: 'rational', value: '5', denominator: '17'),
        lowerInclusive: '',
        upperInclusive: 'false',
      ),
    ];
    final associations = [
      EntityAssociationForm(
        world: 'world choice😀',
        role: 'resident',
        originalOrdinal: 2,
        validity: InstantValidity(
          DurationTime(
            CalendarId.generate(),
            SequenceValue([
              IntegerValue('9007199254740993123456789'),
              RationalValue('001', '03'),
            ]),
          ),
        ),
        temporalValidity: temporal,
        qualifiers: qualifiers,
      ),
      EntityAssociationForm(
        world: 'world choice😀',
        role: 'resident',
        qualifiers: [],
      ),
      EntityAssociationForm(world: '', role: '', qualifiers: null),
    ];
    UnfinishedEntityForm form({
      List<EntityAssociationForm>? rows,
      String label = 'Mémoire 😀\r\n',
    }) => UnfinishedEntityForm(
      baseRevision: revision,
      representedContext: context,
      clientRef: entity.value,
      name: label,
      classification: 'ambiguous choice',
      worldRole: '',
      rationale: '',
      worlds: [world, world],
      associations: rows,
      draftVersion: BigInt.parse('9007199254740993'),
      expectedRecordVersion: version,
      nameDetails: EntityNameForm(
        language: '',
        community: null,
        role: 'alias',
        validity: UnknownValidity(),
        temporalValidity: temporal,
      ),
    );
    try {
      final input = form(rows: associations);
      expect(
        (await store.save(
          scope(draft: entity.value),
          input,
          BigInt.zero,
        )).generation,
        BigInt.one,
      );
      store.close();
      store = await BrowserEntityFormRecoveryStore.open(databaseName: name);
      expect(
        (await store.load(scope(draft: entity.value)))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      expect(
        (await store.save(
          scope(draft: entity.value),
          input,
          BigInt.zero,
        )).generation,
        BigInt.one,
      );
      await expectLater(
        store.save(
          scope(draft: entity.value),
          form(label: 'Conflict'),
          BigInt.zero,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.conflict,
          ),
        ),
      );
      expect(
        (await store.load(scope(draft: entity.value)))!.form.toWire().toText(),
        input.toWire().toText(),
      );
      for (final slot in [
        scope(),
        scope(contextualName: true),
        scope(classification: true),
        scope(contextualName: true, index: 0),
        scope(classification: true, index: 0),
      ]) {
        expect(await store.load(slot), isNull);
        await store.save(slot, input, BigInt.zero);
        expect(
          (await store.load(slot))!.form.toWire().toText(),
          input.toWire().toText(),
        );
      }
      for (final rows in [<EntityAssociationForm>[], null]) {
        final current = (await store.load(scope(draft: entity.value)))!;
        final changed = form(rows: rows);
        await store.save(
          scope(draft: entity.value),
          changed,
          current.generation,
        );
        expect(
          (await store.load(scope(draft: entity.value)))!.form
              .toWire()
              .toText(),
          changed.toWire().toText(),
        );
      }
      final retained = (await store.load(scope(draft: entity.value)))!;
      await expectLater(
        store.save(
          scope(draft: entity.value),
          form(
            rows: [
              EntityAssociationForm(
                world: '',
                role: '',
                qualifiers: [
                  QualifierInput(children: [QualifierInput(value: '\uD800')]),
                ],
              ),
            ],
          ),
          retained.generation,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (error) => error.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
      expect(
        (await store.load(scope(draft: entity.value)))!.form.toWire().toText(),
        retained.form.toWire().toText(),
      );
      expect(await store.load(scope(represented: RecordId.generate())), isNull);
      await expectLater(
        store.save(scope(represented: RecordId.generate()), input, BigInt.zero),
        throwsFormatException,
      );
      await expectLater(
        store.save(scope(draft: 'different'), input, BigInt.zero),
        throwsFormatException,
      );
    } finally {
      store.close();
      final deleted = Completer<void>();
      final request = web.window.indexedDB.deleteDatabase(name);
      request.onsuccess = ((web.Event _) => deleted.complete()).toJS;
      request.onerror = ((web.Event _) => deleted.completeError(
        StateError('Test cleanup failed'),
      )).toJS;
      await deleted.future;
    }
  });
}
