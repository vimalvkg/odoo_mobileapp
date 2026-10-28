class ExprError implements Exception {
  final String message;

  ExprError(this.message);

  @override
  String toString() => 'ExprError: $message';
}

/// Evaluates the subset of Python that Odoo puts in view modifiers
/// (`invisible="state != 'draft'"`), action domains and action contexts:
/// literals, lists/tuples/dicts, names from [env], `and`/`or`/`not`,
/// comparisons, `in`, `x if c else y`, `dict.get()` and a few builtins.
///
/// Anything else (e.g. `context_today()`, `relativedelta`) throws
/// [ExprError] so callers can fall back instead of guessing.
dynamic evalPy(String source, [Map<String, dynamic> env = const {}]) {
  try {
    final parser = _Parser(_tokenize(source), env);
    final node = parser.parseExpression();
    parser.expectEnd();
    return node();
  } on ExprError {
    rethrow;
  } catch (e) {
    throw ExprError(e.toString());
  }
}

/// Evaluates a view modifier such as `invisible` or `readonly`. Expressions
/// the app can't evaluate count as false, so they never hide a field.
bool evalModifier(String? source, Map<String, dynamic> env) {
  if (source == null || source.trim().isEmpty) return false;
  try {
    return pyTruthy(evalPy(source, env));
  } on ExprError {
    return false;
  }
}

bool pyTruthy(dynamic v) {
  if (v == null || v == false) return false;
  if (v is num) return v != 0;
  if (v is String) return v.isNotEmpty;
  if (v is Iterable) return v.isNotEmpty;
  if (v is Map) return v.isNotEmpty;
  return true;
}

bool pyEquals(dynamic a, dynamic b) {
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!pyEquals(a[i], b[i])) return false;
    }
    return true;
  }
  return a == b;
}

final Map<String, Function> _builtins = {
  'bool': (dynamic v) => pyTruthy(v),
  'len': (dynamic v) {
    if (v is String) return v.length;
    if (v is Iterable) return v.length;
    if (v is Map) return v.length;
    throw ExprError('len() of unsupported value');
  },
  'str': (dynamic v) => v.toString(),
  'int': (dynamic v) => v is num ? v.toInt() : int.parse(v.toString()),
  'float': (dynamic v) => v is num ? v.toDouble() : double.parse(v.toString()),
  'list': (dynamic v) => List<dynamic>.of(v as Iterable),
  'tuple': (dynamic v) => List<dynamic>.of(v as Iterable),
  'set': (dynamic v) => List<dynamic>.of((v as Iterable).toSet()),
};

const _keywords = {'and', 'or', 'not', 'in', 'is', 'if', 'else', 'lambda', 'for'};

enum _T { number, string, name, op, end }

class _Tok {
  final _T type;
  final String text;
  final dynamic value;

  const _Tok(this.type, this.text, [this.value]);
}

bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

bool _isNameStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || c == '_';
}

bool _isNamePart(String c) => _isNameStart(c) || _isDigit(c);

List<_Tok> _tokenize(String s) {
  final out = <_Tok>[];
  var i = 0;
  while (i < s.length) {
    final c = s[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (_isDigit(c)) {
      final start = i;
      while (i < s.length && (_isDigit(s[i]) || s[i] == '.')) {
        i++;
      }
      final text = s.substring(start, i);
      out.add(_Tok(_T.number, text, text.contains('.') ? double.parse(text) : int.parse(text)));
      continue;
    }
    if (c == '"' || c == "'") {
      final quote = c;
      final buf = StringBuffer();
      i++;
      while (i < s.length && s[i] != quote) {
        if (s[i] == '\\' && i + 1 < s.length) {
          i++;
          buf.write(s[i] == 'n' ? '\n' : (s[i] == 't' ? '\t' : s[i]));
        } else {
          buf.write(s[i]);
        }
        i++;
      }
      if (i >= s.length) throw ExprError('Unterminated string');
      i++;
      out.add(_Tok(_T.string, quote, buf.toString()));
      continue;
    }
    if (_isNameStart(c)) {
      final start = i;
      while (i < s.length && _isNamePart(s[i])) {
        i++;
      }
      out.add(_Tok(_T.name, s.substring(start, i)));
      continue;
    }
    if (i + 1 < s.length) {
      final two = s.substring(i, i + 2);
      if (two == '==' || two == '!=' || two == '<=' || two == '>=') {
        out.add(_Tok(_T.op, two));
        i += 2;
        continue;
      }
    }
    if ('()[]{},:.<>+-*/%'.contains(c)) {
      out.add(_Tok(_T.op, c));
      i++;
      continue;
    }
    throw ExprError('Unexpected character "$c"');
  }
  out.add(const _Tok(_T.end, ''));
  return out;
}

typedef _Node = dynamic Function();

/// Parses to closures so `and`, `or` and `if/else` only evaluate the branch
/// they need, like Python (`x and x.get('a')` must not fail when x is False).
class _Parser {
  final List<_Tok> _toks;
  final Map<String, dynamic> _env;
  int _pos = 0;

  _Parser(this._toks, this._env);

  _Tok get _peek => _toks[_pos];

  bool _isOp(String op) => _peek.type == _T.op && _peek.text == op;

  bool _isKeyword(String k, [int offset = 0]) {
    final t = _toks[_pos + offset < _toks.length ? _pos + offset : _toks.length - 1];
    return t.type == _T.name && t.text == k;
  }

  void _expectOp(String op) {
    if (!_isOp(op)) throw ExprError('Expected "$op" but found "${_peek.text}"');
    _pos++;
  }

  void expectEnd() {
    if (_peek.type != _T.end) throw ExprError('Unexpected "${_peek.text}"');
  }

  _Node parseExpression() {
    final value = _parseOr();
    if (_isKeyword('if')) {
      _pos++;
      final cond = _parseOr();
      if (!_isKeyword('else')) throw ExprError('Expected "else"');
      _pos++;
      final other = parseExpression();
      return () => pyTruthy(cond()) ? value() : other();
    }
    return value;
  }

  _Node _parseOr() {
    var left = _parseAnd();
    while (_isKeyword('or')) {
      _pos++;
      final l = left;
      final r = _parseAnd();
      left = () {
        final v = l();
        return pyTruthy(v) ? v : r();
      };
    }
    return left;
  }

  _Node _parseAnd() {
    var left = _parseNot();
    while (_isKeyword('and')) {
      _pos++;
      final l = left;
      final r = _parseNot();
      left = () {
        final v = l();
        return pyTruthy(v) ? r() : v;
      };
    }
    return left;
  }

  _Node _parseNot() {
    if (_isKeyword('not')) {
      _pos++;
      final inner = _parseNot();
      return () => !pyTruthy(inner());
    }
    return _parseComparison();
  }

  String? _comparisonOp() {
    if (_peek.type == _T.op && const ['==', '!=', '<', '>', '<=', '>='].contains(_peek.text)) {
      return _toks[_pos++].text;
    }
    if (_isKeyword('in')) {
      _pos++;
      return 'in';
    }
    if (_isKeyword('not') && _isKeyword('in', 1)) {
      _pos += 2;
      return 'not in';
    }
    if (_isKeyword('is')) {
      _pos++;
      if (_isKeyword('not')) {
        _pos++;
        return '!=';
      }
      return '==';
    }
    return null;
  }

  _Node _parseComparison() {
    final first = _parseAdditive();
    final operands = <_Node>[first];
    final ops = <String>[];
    for (var op = _comparisonOp(); op != null; op = _comparisonOp()) {
      ops.add(op);
      operands.add(_parseAdditive());
    }
    if (ops.isEmpty) return first;
    return () {
      var a = operands[0]();
      for (var i = 0; i < ops.length; i++) {
        final b = operands[i + 1]();
        if (!_compare(ops[i], a, b)) return false;
        a = b;
      }
      return true;
    };
  }

  static bool _compare(String op, dynamic a, dynamic b) {
    switch (op) {
      case '==':
        return pyEquals(a, b);
      case '!=':
        return !pyEquals(a, b);
      case 'in':
        return _contains(b, a);
      case 'not in':
        return !_contains(b, a);
    }
    final int order;
    if (a is num && b is num) {
      order = a.compareTo(b);
    } else if (a is String && b is String) {
      order = a.compareTo(b);
    } else {
      throw ExprError('Cannot compare $a and $b');
    }
    switch (op) {
      case '<':
        return order < 0;
      case '>':
        return order > 0;
      case '<=':
        return order <= 0;
      default:
        return order >= 0;
    }
  }

  static bool _contains(dynamic container, dynamic item) {
    if (container is List) return container.any((e) => pyEquals(e, item));
    if (container is String) return item is String && container.contains(item);
    if (container is Map) return container.containsKey(item);
    throw ExprError('"in" needs a list, string or dict');
  }

  _Node _parseAdditive() {
    var left = _parseUnary();
    while (_isOp('+') || _isOp('-')) {
      final op = _toks[_pos++].text;
      final l = left;
      final r = _parseUnary();
      left = () {
        final a = l();
        final b = r();
        if (op == '+') {
          if (a is num && b is num) return a + b;
          if (a is String && b is String) return a + b;
          if (a is List && b is List) return [...a, ...b];
        } else if (a is num && b is num) {
          return a - b;
        }
        throw ExprError('Unsupported operands for $op');
      };
    }
    return left;
  }

  _Node _parseUnary() {
    if (_isOp('-')) {
      _pos++;
      final inner = _parseUnary();
      return () {
        final v = inner();
        if (v is num) return -v;
        throw ExprError('Cannot negate $v');
      };
    }
    if (_isOp('+')) {
      _pos++;
      return _parseUnary();
    }
    return _parsePostfix();
  }

  List<_Node> _parseArgs(String close) {
    final args = <_Node>[];
    while (!_isOp(close)) {
      args.add(parseExpression());
      if (!_isOp(',')) break;
      _pos++;
    }
    _expectOp(close);
    return args;
  }

  _Node _parsePostfix() {
    var node = _parsePrimary();
    while (true) {
      if (_isOp('.')) {
        _pos++;
        if (_peek.type != _T.name) throw ExprError('Expected a name after "."');
        final attr = _toks[_pos++].text;
        final target = node;
        if (_isOp('(')) {
          _pos++;
          final args = _parseArgs(')');
          node = () => _callMethod(target(), attr, [for (final a in args) a()]);
        } else {
          node = () {
            final v = target();
            if (v is Map && v.containsKey(attr)) return v[attr];
            throw ExprError('Unknown attribute "$attr"');
          };
        }
      } else if (_isOp('[')) {
        _pos++;
        final index = parseExpression();
        _expectOp(']');
        final target = node;
        node = () {
          final v = target();
          final i = index();
          if (v is List && i is int) return v[i < 0 ? v.length + i : i];
          if (v is Map) return v[i];
          throw ExprError('Unsupported index');
        };
      } else if (_isOp('(')) {
        _pos++;
        final args = _parseArgs(')');
        final target = node;
        node = () {
          final fn = target();
          if (fn is! Function) throw ExprError('Not callable');
          return Function.apply(fn, [for (final a in args) a()]);
        };
      } else {
        return node;
      }
    }
  }

  static dynamic _callMethod(dynamic target, String name, List<dynamic> args) {
    if (target is Map && name == 'get' && args.isNotEmpty) {
      return target.containsKey(args[0]) ? target[args[0]] : (args.length > 1 ? args[1] : null);
    }
    throw ExprError('Unsupported method "$name"');
  }

  _Node _parsePrimary() {
    final tok = _peek;
    switch (tok.type) {
      case _T.number:
      case _T.string:
        _pos++;
        final value = tok.value;
        return () => value;
      case _T.name:
        _pos++;
        switch (tok.text) {
          case 'True':
            return () => true;
          case 'False':
            return () => false;
          case 'None':
            return () => null;
        }
        if (_keywords.contains(tok.text)) throw ExprError('Unexpected "${tok.text}"');
        final name = tok.text;
        return () {
          if (_env.containsKey(name)) return _env[name];
          final builtin = _builtins[name];
          if (builtin != null) return builtin;
          throw ExprError('Unknown name "$name"');
        };
      case _T.op:
        if (tok.text == '(') {
          _pos++;
          if (_isOp(')')) {
            _pos++;
            return () => <dynamic>[];
          }
          final first = parseExpression();
          if (!_isOp(',')) {
            _expectOp(')');
            return first;
          }
          _pos++;
          final rest = _parseArgs(')');
          final items = [first, ...rest];
          return () => <dynamic>[for (final n in items) n()];
        }
        if (tok.text == '[') {
          _pos++;
          final items = _parseArgs(']');
          return () => <dynamic>[for (final n in items) n()];
        }
        if (tok.text == '{') {
          _pos++;
          final entries = <(_Node, _Node)>[];
          while (!_isOp('}')) {
            final key = parseExpression();
            _expectOp(':');
            entries.add((key, parseExpression()));
            if (!_isOp(',')) break;
            _pos++;
          }
          _expectOp('}');
          return () => <String, dynamic>{for (final (k, v) in entries) k().toString(): v()};
        }
        throw ExprError('Unexpected "${tok.text}"');
      case _T.end:
        throw ExprError('Unexpected end of expression');
    }
  }
}
