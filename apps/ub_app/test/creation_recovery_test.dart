@TestOn('vm')
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:ub_app/connection.dart';
import 'package:ub_app/connection_native.dart';
import 'package:ub_contracts/ub_contracts.dart';

void main() {
  test('embedded sessions recover partial creation and an interrupted response without creating again', () async {
    final root = Directory.systemTemp.createTempSync('ub-creation-session-');
    final device = DeviceConnection([
      '--installation',
      root.path,
    ], embeddedLocal: true);
    AppSession? session;
    Future<void> restart() async {
      await session!.close();
      session = null;
      session = await device.connect();
    }

    const partial = UniverseCreationForm(
      name: 'Ages 記憶',
      calendar: CreationCalendar.fictional,
      date: '2040-02-',
      time: '',
      offset: '',
      calendarName: 'Before dawn',
      initialTick: '-123456789012345678901234567890',
      tickLabel: '',
      realWorld: true,
    );
    const complete = UniverseCreationForm(
      name: 'Ages 記憶',
      calendar: CreationCalendar.fictional,
      date: '2040-02-',
      time: '',
      offset: '',
      calendarName: 'Before dawn',
      initialTick: '-123456789012345678901234567890',
      tickLabel: 'beat',
      realWorld: true,
    );
    try {
      session = await device.connect();
      final saved = await session!.saveUniverseCreationForm!(
        partial,
        BigInt.zero,
      );
      await restart();
      expect(
        (await session!.loadUniverseCreationForm!())!.form.toWire().toText(),
        partial.toWire().toText(),
      );
      expect(
        InstanceLibrary.fromWire(
          await session!.call(const StatusEngineRequest()),
        ).universes,
        isEmpty,
      );
      // Persist the attempt before sending. Discard its response to represent
      // a caller that did not receive confirmation after the service completed.
      await session!.saveUniverseCreationForm!(
        complete.withPending(true),
        saved.generation,
      );
      await session!.call(complete.request());
      await restart();
      final pending = (await session!.loadUniverseCreationForm!())!;
      expect(pending.form.creationPending, isTrue);
      expect(
        pending.form.withPending(false).toWire().toText(),
        complete.toWire().toText(),
      );
      final catalog = InstanceLibrary.fromWire(
        await session!.call(const StatusEngineRequest()),
      );
      expect(catalog.universes, hasLength(1));
      expect(catalog.universes.single.name, complete.name);
      await session!.saveUniverseCreationForm!(complete, pending.generation);
      await restart();
      expect(
        (await session!.loadUniverseCreationForm!())!.form.creationPending,
        isFalse,
      );
      expect(
        InstanceLibrary.fromWire(
          await session!.call(const StatusEngineRequest()),
        ).universes,
        hasLength(1),
      );
    } finally {
      await session?.close();
      root.deleteSync(recursive: true);
    }
  });
}
