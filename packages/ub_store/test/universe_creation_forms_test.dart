import 'dart:io';

import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart' show sqlite3;
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/universe_creation_forms.dart';

void main() {
  test('creation input survives restart with exact partial fields, scope and unknown attempt', () {
    final root = Directory.systemTemp.createTempSync('ub-creation-form-');
    final path = '${root.path}/form.sqlite';
    var store = UniverseCreationFormRecoveryStore.open(path);
    final scope = (OperationId.generate(), ProfileId.generate());
    const form = UniverseCreationForm(
      name: '\uFEFFMemoir 記憶 😀\r\n',
      calendar: CreationCalendar.fictional,
      date: '2040-0',
      time: '12:',
      offset: '-03:',
      calendarName: 'Before dawn',
      initialTick: '-123456789012345678901234567890',
      tickLabel: 'beat\u0000 retained',
      ticksPerMonth: '',
      realWorld: true,
    );
    try {
      final saved = store.save(scope, form, BigInt.zero);
      expect(store.save(scope, form, BigInt.zero).generation, saved.generation);
      store.close();
      store = UniverseCreationFormRecoveryStore.open(path);
      expect(store.load(scope)!.form.toWire().toText(), form.toWire().toText());
      expect(store.load((scope.$1, ProfileId.generate())), isNull);
      expect(store.load((OperationId.generate(), scope.$2)), isNull);
      expect(
        () => store.save(scope, form.withPending(true), BigInt.zero),
        throwsA(isA<EditorRecoveryException>()),
      );
      store.save(scope, form.withPending(true), saved.generation);
      store.close();
      store = UniverseCreationFormRecoveryStore.open(path);
      final pending = store.load(scope)!;
      expect(pending.form.creationPending, isTrue);
      expect(
        pending.form.withPending(false).toWire().toText(),
        form.toWire().toText(),
      );
      store.save(scope, form, pending.generation);
      expect(store.load(scope)!.form.creationPending, isFalse);
      expect(
        () => store.save(
          scope,
          const UniverseCreationForm(
            name: '\uD800',
            calendar: CreationCalendar.gregorian,
          ),
          store.load(scope)!.generation,
        ),
        throwsA(
          isA<EditorRecoveryException>().having(
            (e) => e.failure,
            'failure',
            EditorRecoveryFailure.invalidText,
          ),
        ),
      );
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
  test('older creation recovery keeps its input and unknown outcome when the setting field is added', () {
    final root = Directory.systemTemp.createTempSync('ub-creation-upgrade-');
    final path = '${root.path}/form.sqlite';
    final scope = (OperationId.generate(), ProfileId.generate());
    const form = UniverseCreationForm(
      name: 'Older memoir 記憶',
      calendar: CreationCalendar.gregorian,
      date: '2040-0',
      creationPending: true,
    );
    var store = UniverseCreationFormRecoveryStore.open(path);
    try {
      store.save(scope, form, BigInt.zero);
      store.close();
      final old = sqlite3.open(path);
      try {
        old.execute(
          'ALTER TABLE universe_creation_form DROP COLUMN realWorld; PRAGMA user_version=1',
        );
      } finally {
        old.close();
      }
      store = UniverseCreationFormRecoveryStore.open(path);
      final recovered = store.load(scope)!;
      expect(recovered.generation, BigInt.one);
      expect(recovered.form.toWire().toText(), form.toWire().toText());
      expect(recovered.form.realWorld, isFalse);
      expect(recovered.form.request, throwsFormatException);
    } finally {
      store.close();
      root.deleteSync(recursive: true);
    }
  });
}
