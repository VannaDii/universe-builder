import 'package:sqlite3/sqlite3.dart';
import 'package:ub_contracts/ub_contracts.dart';
import 'package:ub_domain/ub_domain.dart';

import 'catalog.dart';
import 'relational.dart';
import 'recovery_domain_rows.dart';
import 'recovery_value_inputs.dart';

/// Typed rows for the recoverable expression grammar, separate from evaluation.
final class RecoveryExpressionInputs {
  RecoveryExpressionInputs(this._db, this._prefix, this._domains);
  final Database _db;
  final String _prefix;
  final RecoveryDomainSchema _domains;
  late final _values = RecoveryValueInputs(_db, _prefix);
  late final _codec = RelationalCodec(_db);
  static Map<String, String> columns(String prefix) => {
    '${prefix}_expression': 'id,kind,value_root,original',
    '${prefix}_expression_string': 'owner,ordinal,input_key,input_value',
    '${prefix}_expression_flag': 'owner,ordinal,input_key,flag_value',
    '${prefix}_expression_reference':
        'owner,ordinal,input_key,record_input,universe_input',
    '${prefix}_operand':
        'id,kind,input_name,record_input,universe_input,value_root,original',
    '${prefix}_expression_operand': 'owner,ordinal,input_key,operand_root',
    '${prefix}_expression_role': 'owner,ordinal,role_input,operand_root',
    '${prefix}_expression_child':
        'owner,list_kind,ordinal,input_key,expression_root',
  };
  static String schema(String p) =>
      """
CREATE TABLE ${p}_expression(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,value_root INTEGER REFERENCES ${p}_qualifier(id),original INTEGER REFERENCES "${BodyCatalog.instance.model('Expr').table}"(__row_id)) STRICT;
CREATE TABLE ${p}_expression_string(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT NOT NULL,input_value TEXT NOT NULL,PRIMARY KEY(owner,ordinal),UNIQUE(owner,input_key)) STRICT;
CREATE TABLE ${p}_expression_flag(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT NOT NULL,flag_value INTEGER CHECK(flag_value IN (0,1)),PRIMARY KEY(owner,ordinal),UNIQUE(owner,input_key)) STRICT;
CREATE TABLE ${p}_expression_reference(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT NOT NULL,record_input TEXT NOT NULL,universe_input TEXT NOT NULL,PRIMARY KEY(owner,ordinal),UNIQUE(owner,input_key)) STRICT;
CREATE TABLE ${p}_operand(id INTEGER PRIMARY KEY,kind TEXT NOT NULL,input_name TEXT NOT NULL,record_input TEXT NOT NULL,universe_input TEXT NOT NULL,value_root INTEGER REFERENCES ${p}_qualifier(id),original INTEGER REFERENCES "${BodyCatalog.instance.model('Operand').table}"(__row_id)) STRICT;
CREATE TABLE ${p}_expression_operand(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT NOT NULL,operand_root INTEGER NOT NULL REFERENCES ${p}_operand(id),PRIMARY KEY(owner,ordinal),UNIQUE(owner,input_key)) STRICT;
CREATE TABLE ${p}_expression_role(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),ordinal INTEGER NOT NULL CHECK(ordinal>=0),role_input TEXT NOT NULL,operand_root INTEGER NOT NULL REFERENCES ${p}_operand(id),PRIMARY KEY(owner,ordinal)) STRICT;
CREATE TABLE ${p}_expression_child(owner INTEGER NOT NULL REFERENCES ${p}_expression(id),list_kind TEXT NOT NULL CHECK(list_kind IN ('named','item')),ordinal INTEGER NOT NULL CHECK(ordinal>=0),input_key TEXT,expression_root INTEGER NOT NULL REFERENCES ${p}_expression(id),CHECK((list_kind='named' AND input_key IS NOT NULL) OR (list_kind='item' AND input_key IS NULL)),PRIMARY KEY(owner,list_kind,ordinal),UNIQUE(owner,list_kind,input_key)) STRICT;
""";
  void _depth(int depth) {
    if (depth > 128) throw const FormatException('Expression nesting limit');
  }

  Row _row(String table, String columns, int id) => _db.select(
    'SELECT ${_projection(columns)} FROM ${_prefix}_$table WHERE id=?',
    [id],
  ).single;
  List<Row> _rows(String table, String columns, int id, {String? kind}) {
    final rows = _db.select(
      'SELECT ordinal,${_projection(columns)} FROM ${_prefix}_expression_$table WHERE owner=?${kind == null ? '' : ' AND list_kind=?'} ORDER BY ordinal',
      [id, ?kind],
    );
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['ordinal'] != i) {
        throw const FormatException('Incomplete expression input order');
      }
    }
    return rows;
  }

  int write(ExpressionInput e, [int depth = 0]) {
    _depth(depth);
    final value = e.value == null ? null : _values.writeQualifier(e.value!, 0),
        original = e.original == null
            ? null
            : _codec.put('Expr', e.original!.toWire());
    _db.execute(
      'INSERT INTO ${_prefix}_expression(kind,value_root,original) VALUES(?,?,?)',
      [e.kind, value, original],
    );
    final id = _db.lastInsertRowId;
    var i = 0;
    for (final v in e.strings.entries) {
      _db.execute('INSERT INTO ${_prefix}_expression_string VALUES(?,?,?,?)', [
        id,
        i++,
        v.key,
        v.value,
      ]);
    }
    i = 0;
    for (final v in e.flags.entries) {
      _db.execute('INSERT INTO ${_prefix}_expression_flag VALUES(?,?,?,?)', [
        id,
        i++,
        v.key,
        v.value == null
            ? null
            : v.value!
            ? 1
            : 0,
      ]);
    }
    i = 0;
    for (final v in e.references.entries) {
      _db.execute(
        'INSERT INTO ${_prefix}_expression_reference VALUES(?,?,?,?,?)',
        [id, i++, v.key, v.value.record, v.value.universe],
      );
    }
    i = 0;
    for (final v in e.operands.entries) {
      final operand = _writeOperand(v.value);
      _db.execute('INSERT INTO ${_prefix}_expression_operand VALUES(?,?,?,?)', [
        id,
        i++,
        v.key,
        operand,
      ]);
    }
    for (i = 0; i < e.roles.length; i++) {
      final role = e.roles[i], operand = _writeOperand(e.roles[i].operand);
      _db.execute('INSERT INTO ${_prefix}_expression_role VALUES(?,?,?,?)', [
        id,
        i,
        role.role,
        operand,
      ]);
    }
    i = 0;
    for (final v in e.children.entries) {
      final child = write(v.value, depth + 1);
      _db.execute('INSERT INTO ${_prefix}_expression_child VALUES(?,?,?,?,?)', [
        id,
        'named',
        i++,
        v.key,
        child,
      ]);
    }
    for (i = 0; i < e.items.length; i++) {
      final child = write(e.items[i], depth + 1);
      _db.execute('INSERT INTO ${_prefix}_expression_child VALUES(?,?,?,?,?)', [
        id,
        'item',
        i,
        null,
        child,
      ]);
    }
    return id;
  }

  ExpressionInput read(int id, [int depth = 0]) {
    _depth(depth);
    final r = _row('expression', 'kind,value_root,original', id);
    return ExpressionInput(
      kind: _text(r, 'kind'),
      value: r['value_root'] == null
          ? null
          : _values.readQualifier(r['value_root'] as int, 0),
      original: r['original'] == null
          ? null
          : Expr.fromWire(_codec.get('Expr', r['original'])),
      strings: {
        for (final v in _rows('string', 'input_key,input_value', id))
          _text(v, 'input_key'): _text(v, 'input_value'),
      },
      flags: {
        for (final v in _rows('flag', 'input_key,flag_value', id))
          _text(v, 'input_key'): v['flag_value'] == null
              ? null
              : v['flag_value'] == 1,
      },
      references: {
        for (final v in _rows(
          'reference',
          'input_key,record_input,universe_input',
          id,
        ))
          _text(v, 'input_key'): ExpressionReferenceInput(
            record: _text(v, 'record_input'),
            universe: _text(v, 'universe_input'),
          ),
      },
      operands: {
        for (final v in _rows('operand', 'input_key,operand_root', id))
          _text(v, 'input_key'): _readOperand(v['operand_root'] as int),
      },
      roles: _rows('role', 'role_input,operand_root', id).map(
        (v) => ExpressionRoleInput(
          role: _text(v, 'role_input'),
          operand: _readOperand(v['operand_root'] as int),
        ),
      ),
      children: {
        for (final v in _rows(
          'child',
          'input_key,expression_root',
          id,
          kind: 'named',
        ))
          _text(v, 'input_key'): read(v['expression_root'] as int, depth + 1),
      },
      items: _rows(
        'child',
        'expression_root',
        id,
        kind: 'item',
      ).map((v) => read(v['expression_root'] as int, depth + 1)),
    );
  }

  int _writeOperand(OperandInput o) {
    final value = o.value == null ? null : _values.writeQualifier(o.value!, 0),
        original = o.original == null
            ? null
            : _codec.put('Operand', o.original!.toWire());
    _db.execute(
      'INSERT INTO ${_prefix}_operand(kind,input_name,record_input,universe_input,value_root,original) VALUES(?,?,?,?,?,?)',
      [
        o.kind,
        o.name,
        o.reference.record,
        o.reference.universe,
        value,
        original,
      ],
    );
    return _db.lastInsertRowId;
  }

  OperandInput _readOperand(int id) {
    final r = _row(
      'operand',
      'kind,input_name,record_input,universe_input,value_root,original',
      id,
    );
    return OperandInput(
      kind: _text(r, 'kind'),
      name: _text(r, 'input_name'),
      reference: ExpressionReferenceInput(
        record: _text(r, 'record_input'),
        universe: _text(r, 'universe_input'),
      ),
      value: r['value_root'] == null
          ? null
          : _values.readQualifier(r['value_root'] as int, 0),
      original: r['original'] == null
          ? null
          : Operand.fromWire(_codec.get('Operand', r['original'])),
    );
  }

  void delete(int id) {
    final r = _row('expression', 'kind,value_root,original', id),
        operands = [
          ..._rows('operand', 'operand_root', id),
          ..._rows('role', 'operand_root', id),
        ],
        children = [
          ..._rows('child', 'expression_root', id, kind: 'named'),
          ..._rows('child', 'expression_root', id, kind: 'item'),
        ];
    for (final table in [
      'string',
      'flag',
      'reference',
      'operand',
      'role',
      'child',
    ]) {
      _db.execute('DELETE FROM ${_prefix}_expression_$table WHERE owner=?', [
        id,
      ]);
    }
    _db.execute('DELETE FROM ${_prefix}_expression WHERE id=?', [id]);
    if (r['value_root'] case final int v) _values.deleteQualifier(v);
    _domains.deleteOwned(_db, 'Expr', r['original']);
    for (final o in operands) {
      _deleteOperand(o['operand_root'] as int);
    }
    for (final c in children) {
      delete(c['expression_root'] as int);
    }
  }

  void _deleteOperand(int id) {
    final r = _row('operand', 'kind,value_root,original', id);
    _db.execute('DELETE FROM ${_prefix}_operand WHERE id=?', [id]);
    if (r['value_root'] case final int v) _values.deleteQualifier(v);
    _domains.deleteOwned(_db, 'Operand', r['original']);
  }
}

String _projection(String columns) => columns
    .split(',')
    .map(
      (c) =>
          {
            'value_root',
            'original',
            'operand_root',
            'expression_root',
            'flag_value',
          }.contains(c)
          ? c
          : 'CAST($c AS BLOB) AS $c',
    )
    .join(',');
String _text(Row row, String column) => row[column] is String
    ? row[column] as String
    : decodeExactUtf8(row[column] as List<int>);
