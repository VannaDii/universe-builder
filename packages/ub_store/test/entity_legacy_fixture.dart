import 'dart:io';

import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';
import 'package:ub_store/src/ownership.dart';

// Historical schemas are independent of the current recovery schema.
void writeLegacyEntityForms(
  String path,
  int version,
  List<(EditorFormScope, UnfinishedEntityForm, BigInt)> entries,
) {
  if (File(path).existsSync()) File(path).deleteSync();
  protectedFile(path, create: true);
  final db = sqlite3.open(path);
  final keys =
      'instance,profile,universe,continuity,context${version >= 2 ? ',editor_key' : ''}';
  final keyFields = keys.split(',').map((k) => '$k TEXT NOT NULL').join(',');
  try {
    db.execute('''
CREATE TABLE entity_form($keyFields,generation TEXT NOT NULL,base_revision TEXT NOT NULL,client_ref TEXT NOT NULL,name TEXT NOT NULL,classification TEXT NOT NULL,world_role TEXT NOT NULL,rationale TEXT NOT NULL${version >= 2 ? ',draft_version TEXT' : ''}${version >= 3 ? ',association_edits_present INTEGER NOT NULL CHECK(association_edits_present IN (0,1))' : ''}${version >= 7 ? ',name_input TEXT' : ''}${version >= 8 ? ',expected_record_version TEXT' : ''},PRIMARY KEY($keys)) STRICT;
CREATE TABLE entity_form_world($keyFields,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world TEXT NOT NULL,PRIMARY KEY($keys,ordinal),FOREIGN KEY($keys) REFERENCES entity_form($keys) ON DELETE CASCADE) STRICT;
${version >= 3 ? 'CREATE TABLE entity_form_association($keyFields,ordinal INTEGER NOT NULL CHECK(ordinal>=0),world TEXT NOT NULL,role TEXT NOT NULL,original_ordinal INTEGER CHECK(original_ordinal>=0)${version >= 4 ? ',validity TEXT' : ''}${version >= 5 ? ',temporal_input TEXT' : ''}${version >= 6 ? ',qualifier_input TEXT' : ''},PRIMARY KEY($keys,ordinal),FOREIGN KEY($keys) REFERENCES entity_form($keys) ON DELETE CASCADE) STRICT;' : ''}
PRAGMA user_version=$version;
''');
    void insert(String table, List<Object?> values) => db.execute(
      'INSERT INTO $table VALUES(${List.filled(values.length, '?').join(',')})',
      values,
    );
    for (final (s, f, generation) in entries) {
      final target = s.entityNameRecord ?? s.entityClassificationRecord;
      final binding = <Object?>[
        s.instance.value,
        s.profile.value,
        s.universe.value,
        s.continuity.value,
        s.representedContext!.value,
        if (version >= 2)
          target == null
              ? s.entityClientRef ?? ''
              : '${s.entityNameRecord == null ? 'classification' : 'name'}:${target.value}${s.entityOperationIndex == null ? '' : ':edit:${s.entityOperationIndex}'}',
      ];
      insert('entity_form', [
        ...binding,
        generation.toString(),
        f.baseRevision.value,
        f.clientRef,
        f.name,
        f.classification,
        f.worldRole,
        f.rationale,
        if (version >= 2) f.draftVersion?.toString(),
        if (version >= 3) f.associations == null ? 0 : 1,
        if (version >= 7) f.nameDetails?.toWire().toText(),
        if (version >= 8) f.expectedRecordVersion?.value,
      ]);
      for (var i = 0; i < f.worlds.length; i++) {
        insert('entity_form_world', [...binding, i, f.worlds[i].value]);
      }
      if (version >= 3) {
        final associations = f.associations ?? <EntityAssociationForm>[];
        for (var i = 0; i < associations.length; i++) {
          final a = associations[i];
          insert('entity_form_association', [
            ...binding,
            i,
            a.world,
            a.role,
            a.originalOrdinal,
            if (version >= 4) a.validity?.toWire().toText(),
            if (version >= 5) a.temporalValidity?.toWire().toText(),
            if (version >= 6)
              a.qualifiers == null
                  ? null
                  : CanonicalArray(a.qualifiers!.map((q) => q.toWire()))
                        .toText(),
          ]);
        }
      }
    }
  } finally {
    db.close();
  }
}
