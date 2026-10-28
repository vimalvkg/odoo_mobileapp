import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import 'field_editor.dart';

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
  });

  Widget _line(BuildContext context, LineRecord line, List<ArchField> columns) {
    final scheme = Theme.of(context).colorScheme;
    if (line.isSection || line.isNote) {
      final text = line.value('name')?.toString() ?? line.value('display_name')?.toString() ?? '';
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
        child: Text(
          text,
          style: line.isSection
              ? const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)
              : TextStyle(fontStyle: FontStyle.italic, color: scheme.onSurfaceVariant),
        ),
      );
    }

    ArchField? titleCol;
    ArchField? amountCol;
    for (final c in columns) {
      final type = lines.fields[c.name]!['type'];
      if (titleCol == null && (type == 'many2one' || type == 'char' || type == 'text')) titleCol = c;
      if (type == 'monetary') amountCol = c;
    }
    final title = titleCol == null ? '' : formatFieldValue(line.value(titleCol.name), lines.fields[titleCol.name]!);
    final amount = amountCol == null ? '' : formatFieldValue(line.value(amountCol.name), lines.fields[amountCol.name]!);
    final details = [
      for (final c in columns)
        if (c != titleCol && c != amountCol && c.name != 'name')
          // Zero and empty values (e.g. "Disc.%: 0.00") are noise on a card.
          if (formatFieldValue(line.value(c.name), lines.fields[c.name]!) case final v
              when v.isNotEmpty && v != 'No' && line.value(c.name) != 0)
            '${_labelOf(c, lines.fields[c.name])}: $v',
    ];

    final card = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: line.id == null || line.changes.isNotEmpty
            ? scheme.primaryContainer.withValues(alpha: 0.35)
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onOpen(line),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.isEmpty ? (line.value('display_name')?.toString() ?? 'New line') : title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (details.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(details.join('  ·  '), style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                amount.isEmpty && (line.id == null || line.changes.isNotEmpty) ? '—' : amount,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
    if (!editing || readonly || !lines.canDelete) return card;
    return Dismissible(
      key: ValueKey(line.key),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      onDismissed: (_) {
        HapticFeedback.mediumImpact();
        onRemove(line);
      },
      child: card,
    );
  }

  @override
  Widget build(BuildContext context) {
    final columns = [
      for (final c in lines.columns)
        if (lines.columnVisible(c, parentEnv)) c,
    ];
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (lines.items.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text('No lines yet', style: TextStyle(color: scheme.outline)),
          ),
        for (final line in lines.items) _line(context, line, columns),
        if (!readonly && lines.canCreate)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: Text(addLabel)),
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
        () => _error = missing.isNotEmpty ? 'Fill in: ${missing.join(', ')}' : 'Not a number: ${invalid.join(', ')}',
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
                  ? FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))
                  : Row(
                      children: [
                        if (widget.line.id != null || widget.line.values.isNotEmpty || widget.line.changes.isNotEmpty)
                          if (_lines.canDelete)
                            IconButton(
                              tooltip: 'Remove line',
                              icon: Icon(Icons.delete_outline, color: scheme.error),
                              onPressed: () => Navigator.of(context).pop(const LineRemoved()),
                            ),
                        const Spacer(),
                        OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                        const SizedBox(width: 12),
                        FilledButton(onPressed: _done, child: const Text('Done')),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
