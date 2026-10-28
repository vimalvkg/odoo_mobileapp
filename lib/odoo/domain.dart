import 'expr.dart';

/// Turns an action/filter domain (a list, or a Python string such as
/// `"[('user_id', '=', uid)]"`) into a JSON-ready list.
///
/// Returns null when the domain uses Python the app can't evaluate.
List<dynamic>? parseDomain(dynamic raw, Map<String, dynamic> env) {
  if (raw == null || raw == false) return [];
  if (raw is List) return raw;
  if (raw is! String) return null;
  if (raw.trim().isEmpty) return [];
  try {
    final value = evalPy(raw, env);
    return value is List ? value : null;
  } on ExprError {
    return null;
  }
}

/// Same as [parseDomain] for an action context dict.
Map<String, dynamic>? parseContext(dynamic raw, Map<String, dynamic> env) {
  if (raw == null || raw == false) return {};
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is! String) return null;
  if (raw.trim().isEmpty) return {};
  try {
    final value = evalPy(raw, env);
    return value is Map ? Map<String, dynamic>.from(value) : null;
  } on ExprError {
    return null;
  }
}

/// Adds the implicit `&` operators so the domain can be combined with
/// others in prefix notation (port of Odoo's `normalize_domain`).
List<dynamic> normalizeDomain(List<dynamic> domain) {
  if (domain.isEmpty) return [];
  final result = <dynamic>[];
  var expected = 1;
  for (final token in domain) {
    if (expected == 0) {
      result.insert(0, '&');
      expected = 1;
    }
    if (token is List) {
      expected -= 1;
    } else {
      expected += (token == '!' ? 1 : (token == '&' || token == '|' ? 2 : 0)) - 1;
    }
    result.add(token);
  }
  return result;
}

List<dynamic> _combine(String op, List<List<dynamic>> domains) {
  final parts = [for (final d in domains) if (d.isNotEmpty) normalizeDomain(d)];
  if (parts.isEmpty) return [];
  return [for (var i = 1; i < parts.length; i++) op, for (final p in parts) ...p];
}

List<dynamic> andDomains(List<List<dynamic>> domains) => _combine('&', domains);

List<dynamic> orDomains(List<List<dynamic>> domains) => _combine('|', domains);
