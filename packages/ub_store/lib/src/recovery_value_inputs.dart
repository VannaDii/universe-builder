import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

/// Typed unfinished value/time trees shared by editors that use QualifierInput.
final class RecoveryValueInputs {
  RecoveryValueInputs(this._db, this._prefix);
  final Database _db;
  final String _prefix;
  static String schema(String prefix) =>
      """
CREATE TABLE ${prefix}_qualifier (
 id INTEGER PRIMARY KEY, input_key TEXT NOT NULL, kind TEXT NOT NULL, input_value TEXT NOT NULL, denominator TEXT NOT NULL, unit TEXT NOT NULL, universe TEXT NOT NULL, definition TEXT NOT NULL, original_key TEXT,
 lower_input INTEGER REFERENCES ${prefix}_qualifier(id), upper_input INTEGER REFERENCES ${prefix}_qualifier(id), temporal INTEGER REFERENCES ${prefix}_temporal(id), lower_inclusive TEXT NOT NULL, upper_inclusive TEXT NOT NULL
) STRICT;
CREATE TABLE ${prefix}_child (
 owner INTEGER NOT NULL REFERENCES ${prefix}_qualifier(id), ordinal INTEGER NOT NULL CHECK(ordinal>=0), child INTEGER NOT NULL REFERENCES ${prefix}_qualifier(id), PRIMARY KEY(owner,ordinal)
) STRICT;
CREATE TABLE ${prefix}_temporal (
 id INTEGER PRIMARY KEY, kind TEXT NOT NULL, calendar TEXT NOT NULL, relation TEXT NOT NULL, target_universe TEXT NOT NULL, target_record TEXT NOT NULL, start_input INTEGER NOT NULL REFERENCES ${prefix}_bound(id), end_input INTEGER NOT NULL REFERENCES ${prefix}_bound(id)
) STRICT;
CREATE TABLE ${prefix}_bound (
 id INTEGER PRIMARY KEY, kind TEXT NOT NULL, input_value TEXT NOT NULL, upper_value TEXT NOT NULL, uncertainty_kind TEXT NOT NULL, uncertainty TEXT NOT NULL, denominator TEXT NOT NULL, unit TEXT NOT NULL, amount INTEGER REFERENCES ${prefix}_qualifier(id)
) STRICT;
""";
  static Map<String, String> columns(String prefix) => {
    '${prefix}_qualifier': 'id,input_key,kind,input_value,denominator,unit,universe,definition,original_key,lower_input,upper_input,temporal,lower_inclusive,upper_inclusive',
    '${prefix}_child': 'owner,ordinal,child',
    '${prefix}_temporal': 'id,kind,calendar,relation,target_universe,target_record,start_input,end_input',
    '${prefix}_bound': 'id,kind,input_value,upper_value,uncertainty_kind,uncertainty,denominator,unit,amount',
  };
  void _depth(int depth) {
    if (depth > 128) throw const FormatException('Value nesting limit');
  }

  Row _inputRow(String table, String columns, int id) => _db.select(
    'SELECT ${_textProjection(columns)} FROM ${_prefix}_$table WHERE id=?',
    [id],
  ).single;
  int writeQualifier(QualifierInput q, int depth) {
    _depth(depth);
    final lower = q.lower == null ? null : writeQualifier(q.lower!, depth + 1);
    final upper = q.upper == null ? null : writeQualifier(q.upper!, depth + 1);
    final temporal = q.temporal == null
        ? null
        : writeTemporal(q.temporal!, depth + 1);
    _db.execute(
      'INSERT INTO ${_prefix}_qualifier(input_key,kind,input_value,denominator,unit,universe,definition,original_key,lower_input,upper_input,temporal,lower_inclusive,upper_inclusive) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        q.key,
        q.kind,
        q.value,
        q.denominator,
        q.unit,
        q.universe,
        q.definition,
        q.originalKey,
        lower,
        upper,
        temporal,
        q.lowerInclusive,
        q.upperInclusive,
      ],
    );
    final id = _db.lastInsertRowId;
    for (var i = 0; i < q.children.length; i++) {
      final child = writeQualifier(q.children[i], depth + 1);
      _db.execute('INSERT INTO ${_prefix}_child VALUES(?,?,?)', [id, i, child]);
    }
    return id;
  }

  QualifierInput readQualifier(int id, int depth) {
    _depth(depth);
    final r = _inputRow(
      'qualifier',
      'input_key,kind,input_value,denominator,unit,universe,definition,original_key,lower_input,upper_input,temporal,lower_inclusive,upper_inclusive',
      id,
    );
    final children = _db.select(
      'SELECT ordinal,child FROM ${_prefix}_child WHERE owner=? ORDER BY ordinal',
      [id],
    );
    for (var i = 0; i < children.length; i++) {
      if (children[i]['ordinal'] != i) {
        throw const FormatException('Incomplete value input order');
      }
    }
    return QualifierInput(
      key: _text(r, 'input_key'),
      kind: _text(r, 'kind'),
      value: _text(r, 'input_value'),
      denominator: _text(r, 'denominator'),
      unit: _text(r, 'unit'),
      universe: _text(r, 'universe'),
      definition: _text(r, 'definition'),
      originalKey: r['original_key'] == null ? null : _text(r, 'original_key'),
      lowerInclusive: _text(r, 'lower_inclusive'),
      upperInclusive: _text(r, 'upper_inclusive'),
      lower: r['lower_input'] == null
          ? null
          : readQualifier(r['lower_input'] as int, depth + 1),
      upper: r['upper_input'] == null
          ? null
          : readQualifier(r['upper_input'] as int, depth + 1),
      temporal: r['temporal'] == null
          ? null
          : readTemporal(r['temporal'] as int, depth + 1),
      children: children
          .map((c) => readQualifier(c['child'] as int, depth + 1))
          .toList(),
    );
  }

  int writeTemporal(TemporalValidityInput t, int depth) {
    _depth(depth);
    final start = _writeBound(t.start, depth), end = _writeBound(t.end, depth);
    _db.execute(
      'INSERT INTO ${_prefix}_temporal(kind,calendar,relation,target_universe,target_record,start_input,end_input) VALUES(?,?,?,?,?,?,?)',
      [
        t.kind,
        t.calendar,
        t.relation,
        t.targetUniverse,
        t.targetRecord,
        start,
        end,
      ],
    );
    return _db.lastInsertRowId;
  }

  TemporalValidityInput readTemporal(int id, int depth) {
    _depth(depth);
    final r = _inputRow(
      'temporal',
      'kind,calendar,relation,target_universe,target_record,start_input,end_input',
      id,
    );
    return TemporalValidityInput(
      kind: _text(r, 'kind'),
      calendar: _text(r, 'calendar'),
      relation: _text(r, 'relation'),
      targetUniverse: _text(r, 'target_universe'),
      targetRecord: _text(r, 'target_record'),
      start: _readBound(r['start_input'] as int, depth),
      end: _readBound(r['end_input'] as int, depth),
    );
  }

  int _writeBound(TemporalBoundInput b, int depth) {
    final amount = b.amount == null
        ? null
        : writeQualifier(b.amount!, depth + 1);
    _db.execute(
      'INSERT INTO ${_prefix}_bound(kind,input_value,upper_value,uncertainty_kind,uncertainty,denominator,unit,amount) VALUES(?,?,?,?,?,?,?,?)',
      [
        b.kind,
        b.value,
        b.upper,
        b.uncertaintyKind,
        b.uncertainty,
        b.denominator,
        b.unit,
        amount,
      ],
    );
    return _db.lastInsertRowId;
  }

  TemporalBoundInput _readBound(int id, int depth) {
    final r = _inputRow(
      'bound',
      'kind,input_value,upper_value,uncertainty_kind,uncertainty,denominator,unit,amount',
      id,
    );
    return TemporalBoundInput(
      kind: _text(r, 'kind'),
      value: _text(r, 'input_value'),
      upper: _text(r, 'upper_value'),
      uncertaintyKind: _text(r, 'uncertainty_kind'),
      uncertainty: _text(r, 'uncertainty'),
      denominator: _text(r, 'denominator'),
      unit: _text(r, 'unit'),
      amount: r['amount'] == null
          ? null
          : readQualifier(r['amount'] as int, depth + 1),
    );
  }

  void deleteQualifier(int id) {
    final r = _db.select(
      'SELECT lower_input,upper_input,temporal FROM ${_prefix}_qualifier WHERE id=?',
      [id],
    ).single;
    final children = _db.select(
      'SELECT child FROM ${_prefix}_child WHERE owner=?',
      [id],
    );
    _db.execute('DELETE FROM ${_prefix}_child WHERE owner=?', [id]);
    _db.execute('DELETE FROM ${_prefix}_qualifier WHERE id=?', [id]);
    for (final c in children) {
      deleteQualifier(c['child'] as int);
    }
    for (final key in ['lower_input', 'upper_input']) {
      if (r[key] case final int q) deleteQualifier(q);
    }
    if (r['temporal'] case final int t) deleteTemporal(t);
  }

  void deleteTemporal(int id) {
    final r = _db.select(
      'SELECT start_input,end_input FROM ${_prefix}_temporal WHERE id=?',
      [id],
    ).single;
    _db.execute('DELETE FROM ${_prefix}_temporal WHERE id=?', [id]);
    for (final key in ['start_input', 'end_input']) {
      final b = r[key] as int;
      final amount = _db.select(
        'SELECT amount FROM ${_prefix}_bound WHERE id=?',
        [b],
      ).single['amount'];
      _db.execute('DELETE FROM ${_prefix}_bound WHERE id=?', [b]);
      if (amount case final int q) deleteQualifier(q);
    }
  }
}

String _textProjection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'lower_input',
            'upper_input',
            'temporal',
            'start_input',
            'end_input',
            'amount',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) =>
    decodeExactUtf8(row[column] as List<int>);
