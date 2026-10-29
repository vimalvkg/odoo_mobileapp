import 'package:flutter/material.dart';

import '../l10n.dart';
import '../odoo/domain.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../theme.dart';
import 'many2one_picker.dart';

/// Field types the app can edit; others are shown read-only.
const editableTypes = {
  'char',
  'text',
  'integer',
  'float',
  'monetary',
  'boolean',
  'selection',
  'date',
  'datetime',
  'many2one',
  'many2many',
};

/// The domain a relational field's picker should use: the view's `domain`
/// attribute, else the field's own. Unevaluable domains are ignored (the
/// server still validates on save).
List<dynamic> pickerDomain(String? viewDomain, dynamic fieldDomain, Map<String, dynamic> env) =>
    parseDomain(viewDomain ?? fieldDomain, env) ?? const [];

/// An editor for one field value, in the format `read` returns (many2one is
/// `[id, name]`, many2many a list of ids). Used by forms and line editors.
class FieldEditor extends StatelessWidget {
  final OdooRpc rpc;
  final String name;
  final Map<String, dynamic> field;
  final String label;
  final bool required;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;

  /// Changes when the value is reset from outside, so text fields refresh.
  final Object version;
  final Map<String, dynamic> recordContext;
  final List<dynamic> domain;

  /// Names of many2many ids, and how to learn new ones from the picker.
  final Map<int, String> tagNames;
  final void Function(int id, String name)? onTagName;

  const FieldEditor({
    super.key,
    required this.rpc,
    required this.name,
    required this.field,
    required this.label,
    required this.required,
    required this.value,
    required this.onChanged,
    required this.version,
    this.recordContext = const {},
    this.domain = const [],
    this.tagNames = const {},
    this.onTagName,
  });

  @override
  Widget build(BuildContext context) {
    final type = field['type'] as String? ?? 'char';
    final text = label + (required ? ' *' : '');

    switch (type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(text),
          value: value == true,
          onChanged: onChanged,
        );
      case 'selection':
        final options = [
          for (final o in (field['selection'] as List? ?? const []))
            if (o is List && o.length > 1) (o[0], o[1].toString()),
        ];
        return DropdownButtonFormField<Object>(
          key: ValueKey('$name-$version-$value'),
          initialValue: options.any((o) => o.$1 == value) ? value as Object : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: text),
          items: [
            if (!required) const DropdownMenuItem<Object>(value: false, child: Text('—')),
            for (final (k, v) in options) DropdownMenuItem<Object>(value: k as Object, child: Text(v)),
          ],
          onChanged: (v) => onChanged(v ?? false),
        );
      case 'many2one':
        return _TapField(
          label: text,
          text: formatFieldValue(value, field),
          icon: Icons.arrow_drop_down,
          onTap: () async {
            final picked = await showMany2onePicker(
              context,
              rpc: rpc,
              model: field['relation'] as String,
              title: label,
              allowClear: !required,
              recordContext: recordContext,
              domain: domain,
            );
            if (picked != null) onChanged(picked);
          },
        );
      case 'many2many':
        final ids = value is List ? value.whereType<int>().toList() : <int>[];
        return InputDecorator(
          decoration: InputDecoration(labelText: text),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final id in ids)
                InputChip(
                  label: Text(tagNames[id] ?? '#$id'),
                  backgroundColor: colorFor(tagNames[id] ?? '').withValues(alpha: 0.12),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () => onChanged([
                    for (final i in ids)
                      if (i != id) i,
                  ]),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: Text(tr('Add')),
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  final picked = await showMany2onePicker(
                    context,
                    rpc: rpc,
                    model: field['relation'] as String,
                    title: label,
                    allowClear: false,
                    recordContext: recordContext,
                    domain: andDomains([
                      domain,
                      if (ids.isNotEmpty)
                        [
                          ['id', 'not in', ids],
                        ],
                    ]),
                  );
                  if (picked is List && picked.first is int) {
                    onTagName?.call(picked.first as int, picked[1].toString());
                    onChanged([...ids, picked.first]);
                  }
                },
              ),
            ],
          ),
        );
      case 'date':
      case 'datetime':
        final isDate = type == 'date';
        final current = isDate ? parseOdooDate(value) : parseOdooDateTime(value);
        return _TapField(
          label: text,
          text: formatFieldValue(value, field),
          icon: Icons.calendar_today,
          onClear: required || value == false || value == null ? null : () => onChanged(false),
          onTap: () async {
            final now = DateTime.now();
            final day = await showDatePicker(
              context: context,
              initialDate: current ?? now,
              firstDate: DateTime(1900),
              lastDate: DateTime(2200),
            );
            if (day == null || !context.mounted) return;
            if (isDate) {
              onChanged(serializeOdooDate(day));
              return;
            }
            final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current ?? now));
            if (time == null) return;
            onChanged(serializeOdooDateTime(DateTime(day.year, day.month, day.day, time.hour, time.minute)));
          },
        );
      default:
        final numeric = type == 'integer' || type == 'float' || type == 'monetary';
        final initial = value == null || value == false
            ? ''
            : (value is double && value == value.truncateToDouble() ? value.toInt().toString() : value.toString());
        return TextFormField(
          key: ValueKey('$name-$version'),
          initialValue: initial,
          minLines: type == 'text' ? 2 : 1,
          maxLines: type == 'text' ? 6 : 1,
          keyboardType: numeric
              ? TextInputType.numberWithOptions(decimal: type != 'integer', signed: true)
              : (type == 'text' ? TextInputType.multiline : TextInputType.text),
          decoration: InputDecoration(labelText: text),
          onChanged: (raw) {
            final t = raw.trim();
            if (!numeric) {
              onChanged(raw.isEmpty ? false : raw);
            } else if (t.isEmpty) {
              onChanged(type == 'integer' ? 0 : 0.0);
            } else {
              final cleaned = t.replaceAll(',', '');
              // Keep unparsable input as text so save can flag it.
              onChanged((type == 'integer' ? int.tryParse(cleaned) : double.tryParse(cleaned)) ?? raw);
            }
          },
        );
    }
  }
}

class _TapField extends StatelessWidget {
  final String label;
  final String text;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  const _TapField({required this.label, required this.text, required this.icon, required this.onTap, this.onClear});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null
              ? IconButton(icon: const Icon(Icons.clear), tooltip: tr('Clear'), onPressed: onClear)
              : Icon(icon),
        ),
        isEmpty: text.isEmpty,
        child: Text(text),
      ),
    );
  }
}

/// A value in `read` format converted for `create`/`write`.
dynamic toWriteValue(dynamic value, Map<String, dynamic> field) {
  switch (field['type']) {
    case 'many2one':
      return value is List && value.isNotEmpty ? value.first : (value is int ? value : false);
    case 'many2many':
      return [
        [6, 0, value is List ? value.whereType<int>().toList() : <int>[]],
      ];
    default:
      return value;
  }
}
