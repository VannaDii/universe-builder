@TestOn('vm')
library;

import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:ub_store/src/restore_copy.dart';

Database empty() => sqlite3.openInMemory()
  ..execute('''
PRAGMA foreign_keys=ON;
CREATE TABLE universes(id TEXT PRIMARY KEY);
CREATE TABLE a_child(id INTEGER PRIMARY KEY, parent INTEGER REFERENCES z_parent(id), value INTEGER CHECK(value>=0));
CREATE TABLE z_parent(id INTEGER PRIMARY KEY, child INTEGER REFERENCES a_child(id));
''');

void main() {
  late Database source, target;
  setUp(() {
    source = empty();
    target = empty();
    source.execute("INSERT INTO universes VALUES('fixture')");
  });
  tearDown(() {
    source.close();
    target.close();
  });
  void enforcementRestored() {
    expect(target.autocommit, isTrue);
    expect(target.select('PRAGMA foreign_keys').single.values.single, 1);
    expect(
      () => target.execute('INSERT INTO a_child VALUES(999999,999999,0)'),
      throwsA(isA<SqliteException>()),
    );
  }

  test(
    'large reverse-order and cyclic references copy without changing values',
    () {
      source.execute('BEGIN');
      final parent = source.prepare('INSERT INTO z_parent VALUES(?,NULL)');
      final child = source.prepare('INSERT INTO a_child VALUES(?,?,?)');
      final link = source.prepare('UPDATE z_parent SET child=? WHERE id=?');
      try {
        for (var n = 0; n < 10000; n++) {
          parent.execute([n]);
          child.execute([n, n, n]);
          link.execute([n, n]);
        }
      } finally {
        parent.close();
        child.close();
        link.close();
      }
      source.execute('COMMIT');
      copyTrustedRows(source, target);
      expect(target.select('PRAGMA foreign_key_check'), isEmpty);
      expect(
        target.select('SELECT id,parent,value FROM a_child ORDER BY id'),
        source.select('SELECT id,parent,value FROM a_child ORDER BY id'),
      );
      expect(
        target.select('SELECT count(*) FROM z_parent').single.values.single,
        10000,
      );
      enforcementRestored();
    },
  );

  test(
    'dangling references roll back every copied table and allow a clean retry',
    () {
      source.execute('PRAGMA foreign_keys=OFF');
      source.execute('INSERT INTO a_child VALUES(1,7,1)');
      source.execute('PRAGMA foreign_keys=ON');
      expect(
        () => copyTrustedRows(source, target),
        throwsA(
          isA<SqliteException>().having(
            (e) => e.extendedResultCode,
            'foreign key result',
            SqlExtendedError.SQLITE_CONSTRAINT_FOREIGNKEY,
          ),
        ),
      );
      expect(target.select('SELECT * FROM universes'), isEmpty);
      expect(target.select('SELECT * FROM a_child'), isEmpty);
      enforcementRestored();
      source.execute('INSERT INTO z_parent VALUES(7,1)');
      copyTrustedRows(source, target);
      expect(
        target.select('SELECT parent FROM a_child').single.values.single,
        7,
      );
      enforcementRestored();
    },
  );

  test(
    'ordinary SQL constraint failure restores enforcement and leaves no rows',
    () {
      source.execute('PRAGMA ignore_check_constraints=ON');
      source.execute('INSERT INTO a_child VALUES(1,NULL,-1)');
      source.execute('PRAGMA ignore_check_constraints=OFF');
      expect(
        () => copyTrustedRows(source, target),
        throwsA(isA<SqliteException>()),
      );
      expect(target.select('SELECT * FROM universes'), isEmpty);
      expect(target.select('SELECT * FROM a_child'), isEmpty);
      enforcementRestored();
    },
  );

  test('caller transactions and targets without enforcement are refused', () {
    target.execute('BEGIN');
    expect(() => copyTrustedRows(source, target), throwsStateError);
    expect(target.autocommit, isFalse);
    target.execute('ROLLBACK');
    target.execute('PRAGMA foreign_keys=OFF');
    expect(() => copyTrustedRows(source, target), throwsStateError);
    expect(target.select('SELECT * FROM universes'), isEmpty);
  });
}
