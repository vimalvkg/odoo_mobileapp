import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../theme.dart';
import 'field_editor.dart';
import 'record_avatar.dart';

/// One line of a one2many field: saved ([id] set) or new, with local edits.
class LineRecord {
  final int? id;
  final Map<String, dynamic> values;
  final Map<String, dynamic> changes;

  /// Stable key for widgets, also for unsaved lines.
  final String key;

  LineRecord({this.id, required this.values, Map<String, dynamic>? changes, required this.key})
    : changes = changes ?? {};

  dynamic value(String name) => changes.containsKey(name) ? changes[name] : values[name];

  bool get isSection => _displayType == 'line_section';
  bool get isNote => _displayType == 'line_note';

  String? get _displayType {
    final t = value('display_type');
    return t is String && t.isNotEmpty ? t : null;
  }
}

/// The lines of a one2many field, laid out from its inline views, with the
/// edits that become Odoo's x2many commands on save.
class X2ManyLines {
  final String relation;
  final Map<String, Map<String, dynamic>> fields;

  /// Columns of the inline list view (or the model's default list).
  final List<ArchField> columns;

  /// The inline form view, if the field has one; else [columns] are edited.
  final FormArch? form;

  /// Hidden list fields that the line conditions may use.
  final Set<String> extraFields;
  final bool canCreate;
  final bool canDelete;

  List<LineRecord> items;
  final Set<int> removed = {};
  int _newCount = 0;

  X2ManyLines({
    required this.relation,
    required this.fields,
    required this.columns,
    required this.form,
    required this.items,
    this.extraFields = const {},
    this.canCreate = true,
    this.canDelete = true,
  });

  bool get dirty => removed.isNotEmpty || items.any((l) => l.id == null || l.changes.isNotEmpty);

  String nextKey() => 'new-${_newCount++}';

  /// Fields to read for each line.
  Set<String> get readFields => {
    'display_name',
    for (final c in columns) c.name,
    if (form != null) ...form!.fieldNames,
    ...extraFields,
    if (fields.containsKey('display_type')) 'display_type',
  }.where((n) => fields.containsKey(n) && fields[n]!['type'] != 'binary').toSet();

  /// The editable fields of the line editor, in layout order.
  List<ArchField> get editorFields {
    final source = form != null ? formFields(form!.body) : columns;
    final seen = <String>{};
    return [
      for (final f in source)
        if (fields.containsKey(f.name) && fields[f.name]!['type'] != 'binary' && seen.add(f.name)) f,
    ];
  }

  /// Odoo x2many commands: 0 create, 1 update, 2 delete.
  List<dynamic> commands() => [
    for (final id in removed) [2, id, 0],
    for (final l in items)
      if (l.id == null)
        [
          0,
          0,
          _vals({...l.values, ...l.changes}),
        ]
      else if (l.changes.isNotEmpty)
        [1, l.id, _vals(l.changes)],
  ];

  Map<String, dynamic> _vals(Map<String, dynamic> source) => {
    for (final e in source.entries)
      if (fields[e.key] != null && editableTypes.contains(fields[e.key]!['type']) && e.key != 'display_name')
        e.key: toWriteValue(e.value, fields[e.key]!),
  };

  /// Values as a line's modifiers see them, with `parent` the order.
  Map<String, dynamic> env(LineRecord line, Map<String, dynamic> parentEnv) {
    final env = <String, dynamic>{
      // Unset fields read as False, as in Odoo (new lines have no values yet).
      for (final name in fields.keys) name: false,
      'uid': parentEnv['uid'],
      'context': parentEnv['context'],
      'parent': parentEnv,
      'id': line.id ?? false,
    };
    for (final name in {...line.values.keys, ...line.changes.keys}) {
      final v = line.value(name);
      env[name] = v is List && fields[name]?['type'] == 'many2one' ? (v.isEmpty ? false : v.first) : v;
    }
    return env;
  }

  bool columnVisible(ArchField c, Map<String, dynamic> parentEnv) =>
      fields.containsKey(c.name) &&
      !evalModifier(c.attrs['column_invisible'], {'parent': parentEnv, 'context': parentEnv['context']});
}

String _labelOf(ArchField f, Map<String, dynamic>? field) => f.label ?? field?['string']?.toString() ?? f.name;

/// Order-lines style list: one card per line, sections as headings, add
/// and remove in edit mode.
class X2ManyLinesView extends StatelessWidget {
  final X2ManyLines lines;
  final Map<String, dynamic> parentEnv;
  final bool editing;
  final bool readonly;
  final String addLabel;
  final VoidCallback onAdd;
  final ValueChanged<LineRecord> onOpen;
  final ValueChanged<LineRecord> onRemove;

  /// For product photos on lines; without it lines show initials.
  final OdooRpc? rpc;

  const X2ManyLinesView({
    super.key,
    required this.lines,
    required this.parentEnv,
    required this.editing,
    required this.readonly,
    required this.addLabel,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
    this.rpc,
  });

  static const _qtyFields = ['product_uom_qty', 'quantity', 'product_qty', 'qty', 'unit_amount'];
  static const _priceFields = ['price_unit', 'unit_price'];

  num? _num(LineRecord line, String name) {
    final v = line.value(name);
    return v is num ? v : null;
  }

  /// "2 × 1,750.00 · 10% off" for product lines, else the other columns.
  String _summary(LineRecord line, List<ArchField> columns, Set<ArchField> used) {
    final names = {for (final c in columns) c.name};
    final qtyName = _qtyFields.where(names.contains).firstOrNull;
    final priceName = _priceFields.where(names.contains).firstOrNull;
    final qty = qtyName == null ? null : _num(line, qtyName);
    final price = priceName == null ? null : _num(line, priceName);
    if (qty != null && price != null) {
      final discount = _num(line, 'discount') ?? 0;
      final q = qty == qty.truncate() ? qty.toInt().toString() : formatNumber(qty);
      return '$q × ${formatNumber(price)}${discount != 0 ? ' · ${tr('{n}% off', {'n': formatNumber(discount, decimals: discount == discount.truncate() ? 0 : 2)})}' : ''}';
    }
    return [
      for (final c in columns)
        if (!used.contains(c) && c.name != 'name')
          // Zero and empty values (e.g. "Disc.%: 0.00") are noise.
          if (formatFieldValue(line.value(c.name), lines.fields[c.name]!) case final v
              when v.isNotEmpty && v != 'No' && line.value(c.name) != 0)
            '${_labelOf(c, lines.fields[c.name])}: $v',
    ].join('  ·  ');
  }

  Widget _line(BuildContext context, LineRecord line, List<ArchField> columns, bool first) {
    final c = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    if (line.isSection || line.isNote) {
      final text = line.value('name')?.toString() ?? line.value('display_name')?.toString() ?? '';
      return InkWell(
        onTap: () => onOpen(line),
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, first ? 6 : 14, 0, 6),
          child: Text(
            line.isSection ? text.toUpperCase() : text,
            style: line.isSection
                ? TextStyle(fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.6, color: c.muted)
                : TextStyle(fontStyle: FontStyle.italic, color: c.muted),
          ),
        ),
      );
    }

    ArchField? titleCol;
    ArchField? amountCol;
    for (final col in columns) {
      final type = lines.fields[col.name]!['type'];
      if (titleCol == null && (type == 'many2one' || type == 'char' || type == 'text')) titleCol = col;
      if (type == 'monetary') amountCol = col;
    }
    final title = titleCol == null ? '' : formatFieldValue(line.value(titleCol.name), lines.fields[titleCol.name]!);
    final amount = amountCol == null ? '' : formatFieldValue(line.value(amountCol.name), lines.fields[amountCol.name]!);
    final summary = _summary(line, columns, {?titleCol, ?amountCol});
    final pending = line.id == null || line.changes.isNotEmpty;
    final display = title.isEmpty ? (line.value('display_name')?.toString() ?? tr('New line')) : title;

    // Product photo when the line's title is a product.
    final product = titleCol == null ? null : line.value(titleCol.name);
    final relation = titleCol == null ? null : lines.fields[titleCol.name]!['relation'];
    final productId = product is List && product.isNotEmpty && product.first is int ? product.first as int : null;
    final avatar = rpc != null && relation is String && relation.startsWith('product.')
        ? RecordAvatar(
            rpc: rpc!,
            model: relation,
            id: productId,
            imageField: 'image_128',
            text: display,
            size: 44,
            circle: false,
          )
        : null;

    final row = InkWell(
      onTap: () => onOpen(line),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: first ? null : Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            if (avatar != null) ...[avatar, const SizedBox(width: 12)],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    display,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (summary.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(summary, style: TextStyle(fontSize: 12, color: c.muted)),
                  ],
                  if (pending)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        tr('Not saved yet'),
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: scheme.primary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(amount.isEmpty || pending ? '—' : amount, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
    if (!editing || readonly || !lines.canDelete) return row;
    return Dismissible(
      key: ValueKey(line.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        color: scheme.errorContainer,
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        onRemove(line);
      },
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final col in lines.columns)
        if (lines.columnVisible(col, parentEnv)) col,
    ];
    final c = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Text(tr('No lines yet'), style: TextStyle(color: c.muted)),
          ),
        for (var i = 0; i < lines.items.length; i++) _line(context, lines.items[i], columns, i == 0),
        if (!readonly && lines.canCreate)
          InkWell(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.add, size: 20, color: Theme.of(context).colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    addLabel,
                    style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Result of the line editor.
sealed class LineEdit {
  const LineEdit();
}

class LineSaved extends LineEdit {
  final Map<String, dynamic> changes;

  const LineSaved(this.changes);
}

class LineRemoved extends LineEdit {
  const LineRemoved();
}

/// Bottom sheet that edits one line with the same field editors as forms,
/// applying the inline view's conditions (including `parent.*` ones).
Future<LineEdit?> showLineEditor(
  BuildContext context, {
  required OdooRpc rpc,
  required X2ManyLines lines,
  required LineRecord line,
  required Map<String, dynamic> parentEnv,
  required bool readonly,
  required String title,
  Map<String, dynamic> recordContext = const {},
}) {
  return showModalBottomSheet<LineEdit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _LineEditor(
      rpc: rpc,
      lines: lines,
      line: line,
      parentEnv: parentEnv,
      readonly: readonly,
      title: title,
      recordContext: recordContext,
    ),
  );
}

class _LineEditor extends StatefulWidget {
  final OdooRpc rpc;
  final X2ManyLines lines;
  final LineRecord line;
  final Map<String, dynamic> parentEnv;
  final bool readonly;
  final String title;
  final Map<String, dynamic> recordContext;

  const _LineEditor({
    required this.rpc,
    required this.lines,
    required this.line,
    required this.parentEnv,
    required this.readonly,
    required this.title,
    required this.recordContext,
  });

  @override
  State<_LineEditor> createState() => _LineEditorState();
}

class _LineEditorState extends State<_LineEditor> {
  /// Edits made in this sheet, on top of the line's existing changes.
  late final LineRecord _draft = LineRecord(
    id: widget.line.id,
    values: widget.line.values,
    changes: {...widget.line.changes},
    key: widget.line.key,
  );
  final Map<int, String> _tagNames = {};
  String? _error;

  X2ManyLines get _lines => widget.lines;

  bool _readonly(ArchField f, Map<String, dynamic> env) {
    final field = _lines.fields[f.name]!;
    if (widget.readonly || !editableTypes.contains(field['type'])) return true;
    final attr = f.attrs['readonly'];
    return attr != null ? evalModifier(attr, env) : field['readonly'] == true;
  }

  bool _required(ArchField f, Map<String, dynamic> env) {
    final attr = f.attrs['required'];
    return attr != null ? evalModifier(attr, env) : _lines.fields[f.name]?['required'] == true;
  }

  List<ArchField> _visible(Map<String, dynamic> env) => [
    for (final f in _lines.editorFields)
      if (!evalModifier(f.attrs['invisible'], env) && _lines.columnVisible(f, widget.parentEnv)) f,
  ];

  void _done() {
    final env = _lines.env(_draft, widget.parentEnv);
    final missing = [
      for (final f in _visible(env))
        if (_required(f, env) && _lines.fields[f.name]!['type'] != 'boolean')
          if (_draft.value(f.name) case final v when v == null || v == false || v == '')
            _labelOf(f, _lines.fields[f.name]),
    ];
    final invalid = [
      for (final f in _visible(env))
        if (_draft.value(f.name) is String &&
            const {'integer', 'float', 'monetary'}.contains(_lines.fields[f.name]!['type']))
          _labelOf(f, _lines.fields[f.name]),
    ];
    if (missing.isNotEmpty || invalid.isNotEmpty) {
      setState(
        () => _error = missing.isNotEmpty ? tr('Fill in: {fields}', {'fields': missing.join(isArabic ? '، ' : ', ')}) : tr('Not a number: {fields}', {'fields': invalid.join(isArabic ? '، ' : ', ')}),
      );
      return;
    }
    Navigator.of(context).pop(LineSaved(_draft.changes));
  }

  @override
  Widget build(BuildContext context) {
    final env = _lines.env(_draft, widget.parentEnv);
    final scheme = Theme.of(context).colorScheme;
    final visible = _visible(env);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(widget.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  for (final f in visible)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: _readonly(f, env)
                          ? InputDecorator(
                              decoration: InputDecoration(
                                labelText: _labelOf(f, _lines.fields[f.name]),
                                enabled: false,
                              ),
                              child: Text(() {
                                final text = formatFieldValue(_draft.value(f.name), _lines.fields[f.name]!);
                                return text.isEmpty ? '—' : text;
                              }()),
                            )
                          : FieldEditor(
                              rpc: widget.rpc,
                              name: f.name,
                              field: _lines.fields[f.name]!,
                              label: _labelOf(f, _lines.fields[f.name]),
                              required: _required(f, env),
                              value: _draft.value(f.name),
                              version: _draft.key,
                              recordContext: widget.recordContext,
                              domain: pickerDomain(f.attrs['domain'], _lines.fields[f.name]!['domain'], env),
                              tagNames: _tagNames,
                              onTagName: (id, name) => _tagNames[id] = name,
                              onChanged: (v) => setState(() {
                                _draft.changes[f.name] = v;
                                _error = null;
                              }),
                            ),
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: widget.readonly
                  ? FilledButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Close')))
                  : Row(
                      children: [
                        if (widget.line.id != null || widget.line.values.isNotEmpty || widget.line.changes.isNotEmpty)
                          if (_lines.canDelete)
                            IconButton(
                              tooltip: tr('Remove line'),
                              icon: Icon(Icons.delete_outline, color: scheme.error),
                              onPressed: () => Navigator.of(context).pop(const LineRemoved()),
                            ),
                        const Spacer(),
                        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: Text(tr('Cancel'))),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: _done, child: Text(tr('Done'))),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
