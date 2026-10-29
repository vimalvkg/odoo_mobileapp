import '../l10n.dart';

const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const _monthsLong = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

const _monthsArabic = [
  'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
  'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
];

/// Full month name (1–12) in the app's language.
String monthName(int month) => (isArabic ? _monthsArabic : _monthsLong)[month - 1];

String _two(int n) => n.toString().padLeft(2, '0');

/// Odoo dates are `YYYY-MM-DD`.
DateTime? parseOdooDate(dynamic value) => value is String ? DateTime.tryParse(value) : null;

/// Odoo datetimes are `YYYY-MM-DD HH:MM:SS` in UTC; returns local time.
DateTime? parseOdooDateTime(dynamic value) {
  if (value is! String) return null;
  return DateTime.tryParse('${value.replaceFirst(' ', 'T')}Z')?.toLocal();
}

String serializeOdooDate(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

String serializeOdooDateTime(DateTime local) {
  final d = local.toUtc();
  return '${serializeOdooDate(d)} ${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}';
}

String formatDate(DateTime d) => '${d.day} ${isArabic ? _monthsArabic[d.month - 1] : _months[d.month - 1]} ${d.year}';

String formatDateTime(DateTime d) => '${formatDate(d)} ${_two(d.hour)}:${_two(d.minute)}';

String formatNumber(num value, {int decimals = 2}) {
  final fixed = value.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final buf = StringBuffer(value < 0 ? '-' : '');
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) buf.write(',');
    buf.write(whole[i]);
  }
  if (dot >= 0) buf.write(fixed.substring(dot));
  return buf.toString();
}

String stripHtml(String html) => html
    .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</li>', caseSensitive: false), '\n')
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
    .trim();

/// Label for a selection key, using the field definition from `fields_get`.
String selectionLabel(dynamic key, Map<String, dynamic> field) {
  final options = field['selection'];
  if (options is List) {
    for (final option in options) {
      if (option is List && option.length > 1 && option[0] == key) return option[1].toString();
    }
  }
  return key.toString();
}

/// Display text for a value as returned by `read`/`search_read`.
String formatFieldValue(dynamic value, Map<String, dynamic> field) {
  final type = field['type'];
  if (type == 'boolean') return value == true ? tr('Yes') : tr('No');
  if (value == null || value == false) return '';
  switch (type) {
    case 'many2one':
      return value is List && value.length > 1 ? value[1].toString() : '';
    case 'selection':
      return selectionLabel(value, field);
    case 'date':
      final d = parseOdooDate(value);
      return d == null ? value.toString() : formatDate(d);
    case 'datetime':
      final dt = parseOdooDateTime(value);
      return dt == null ? value.toString() : formatDateTime(dt);
    case 'monetary':
      return value is num ? formatNumber(value) : value.toString();
    case 'float':
      if (value is! num) return value.toString();
      final digits = field['digits'];
      final decimals = digits is List && digits.length > 1 && digits[1] is int ? digits[1] as int : 2;
      return formatNumber(value, decimals: decimals);
    case 'integer':
      return value.toString();
    case 'one2many':
    case 'many2many':
      if (value is! List) return '';
      return value.length == 1 ? tr('1 record') : tr('{n} records', {'n': value.length});
    case 'html':
      return stripHtml(value.toString());
    case 'binary':
      return tr('File');
    default:
      return value.toString();
  }
}
