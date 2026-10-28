import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_navigation.dart';
import '../contact_actions.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../theme.dart';
import '../widgets/error_view.dart';
import '../widgets/many2one_picker.dart';
import '../widgets/odoo_image.dart';
import '../widgets/skeleton.dart';
import 'record_list_screen.dart';
import 'webview_screen.dart';

/// Field types the app can edit; others are shown read-only.
const _editableTypes = {
  'char', 'text', 'integer', 'float', 'monetary', 'boolean', 'selection', 'date', 'datetime', 'many2one',
};

/// One record of any model, laid out from its form view: statusbar, header
/// buttons, title, groups and notebook pages. Supports viewing, editing,
/// creating and deleting; anything beyond that opens in the web client.
class RecordFormScreen extends StatefulWidget {
  final OdooRpc rpc;
  final String model;

  /// Null to create a new record.
  final int? recordId;
  final int? formViewId;
  final Map<String, dynamic> recordContext;
  final String title;
  final Widget? drawer;

  const RecordFormScreen({
    super.key,
    required this.rpc,
    required this.model,
    this.recordId,
    this.formViewId,
    this.recordContext = const {},
    required this.title,
    this.drawer,
  });

  @override
  State<RecordFormScreen> createState() => _RecordFormScreenState();
}

class _RecordFormScreenState extends State<RecordFormScreen> {
  int? _id;
  Map<String, Map<String, dynamic>> _fields = {};
  FormArch? _arch;
  Map<String, dynamic> _record = {};
  final Map<String, dynamic> _edits = {};
  Map<String, List<String>> _relatedNames = {};
  String? _imageField;

  Object? _error;
  bool _editing = false;
  bool _busy = false;

  /// Bumped when edits are discarded so text fields rebuild with the saved
  /// values.
  int _formVersion = 0;

  /// Selected tab per notebook, keyed by its page titles.
  final Map<String, int> _selectedPage = {};

  @override
  void initState() {
    super.initState();
    _id = widget.recordId;
    _editing = _id == null;
    _load();
  }

  Future<void> _load() async {
    try {
      final views = await widget.rpc.getViews(
        widget.model,
        [
          [widget.formViewId ?? false, 'form'],
        ],
        context: widget.recordContext,
      );
      final archXml = views.archs['form'];
      if (archXml == null) throw const OdooException('This model has no form view.');
      final arch = parseFormArch(archXml);
      final fields = views.fields;

      // Binary fields can be megabytes; only fetch a small avatar if any.
      final names = [
        for (final n in arch.fieldNames)
          if (fields.containsKey(n) && fields[n]!['type'] != 'binary') n,
        if (fields.containsKey('display_name')) 'display_name',
      ];
      final hasImage = arch.fieldNames.any((n) => fields[n]?['type'] == 'binary' && n.startsWith('image'));
      final imageField = hasImage && fields.containsKey('image_128') ? 'image_128' : null;

      final Map<String, dynamic> record;
      final id = _id;
      if (id != null) {
        final rows = await widget.rpc.read(widget.model, [id], [...names, ?imageField], context: widget.recordContext);
        if (rows.isEmpty) throw const OdooException("This record doesn't exist or you can't access it.");
        record = rows.first;
      } else {
        final defaults = await widget.rpc.callKw(widget.model, 'default_get',
            args: [names], context: widget.recordContext);
        record = defaults is Map ? Map<String, dynamic>.from(defaults) : {};
        await _resolveMany2oneDefaults(record, fields);
      }

      final relatedNames = await _loadRelatedNames(record, fields, arch);
      if (!mounted) return;
      setState(() {
        _fields = fields;
        _arch = arch;
        _record = record;
        _relatedNames = relatedNames;
        _imageField = imageField;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (e is OdooException && e.isSessionExpired) {
        endSession(notice: sessionEndedNotice);
        return;
      }
      if (_arch == null) {
        setState(() => _error = e);
      } else {
        handleRpcError(context, e);
      }
    }
  }

  /// `default_get` returns bare ids for many2one; `read` returns `[id, name]`.
  Future<void> _resolveMany2oneDefaults(Map<String, dynamic> record, Map<String, Map<String, dynamic>> fields) async {
    for (final entry in record.entries.toList()) {
      final field = fields[entry.key];
      if (field?['type'] == 'many2one' && entry.value is int) {
        try {
          final rows = await widget.rpc.read(field!['relation'] as String, [entry.value as int], ['display_name']);
          record[entry.key] = rows.isEmpty ? false : [entry.value, rows.first['display_name']];
        } on OdooException {
          record[entry.key] = [entry.value, '#${entry.value}'];
        }
      } else if (field?['type'] == 'one2many' || field?['type'] == 'many2many') {
        // Defaults here are write commands, not ids; start empty.
        if (entry.value is List && (entry.value as List).any((v) => v is! int)) record[entry.key] = <int>[];
      }
    }
  }

  /// Names for x2many values (tags, lines), shown as chips.
  Future<Map<String, List<String>>> _loadRelatedNames(
      Map<String, dynamic> record, Map<String, Map<String, dynamic>> fields, FormArch arch) async {
    final result = <String, List<String>>{};
    await Future.wait([
      for (final name in arch.fieldNames)
        if ((fields[name]?['type'] == 'many2many' || fields[name]?['type'] == 'one2many') &&
            record[name] is List &&
            (record[name] as List).isNotEmpty)
          () async {
            final ids = (record[name] as List).whereType<int>().take(20).toList();
            try {
              final rows = await widget.rpc.read(fields[name]!['relation'] as String, ids, ['display_name']);
              result[name] = [for (final r in rows) r['display_name']?.toString() ?? ''];
            } on OdooException {
              // No access to the related model: fall back to the count.
            }
          }(),
    ]);
    return result;
  }

  dynamic _value(String name) => _edits.containsKey(name) ? _edits[name] : _record[name];

  /// Values as Odoo's modifier expressions see them (many2one = id).
  Map<String, dynamic> get _env {
    final env = <String, dynamic>{...widget.rpc.evalEnv};
    for (final name in {..._record.keys, ..._edits.keys}) {
      final v = _value(name);
      env[name] = v is List && _fields[name]?['type'] == 'many2one' ? (v.isEmpty ? false : v.first) : v;
    }
    env['id'] = _id ?? false;
    env['context'] = {...widget.rpc.userContext, ...widget.recordContext};
    return env;
  }

  bool _isReadonly(ArchField f, Map<String, dynamic> env) {
    final field = _fields[f.name]!;
    if (!_editable(field)) return true;
    final attr = f.attrs['readonly'];
    if (attr != null) return evalModifier(attr, env);
    return field['readonly'] == true;
  }

  bool _editable(Map<String, dynamic> field) => _editableTypes.contains(field['type']);

  bool _isRequired(ArchField f, Map<String, dynamic> env) {
    final attr = f.attrs['required'];
    if (attr != null) return evalModifier(attr, env);
    return _fields[f.name]?['required'] == true;
  }

  String _label(ArchField f) => f.label ?? _fields[f.name]?['string']?.toString() ?? f.name;

  Iterable<ArchField> _visibleFields(List<FormNode> nodes, Map<String, dynamic> env) sync* {
    for (final node in nodes) {
      switch (node) {
        case FormFieldNode(:final field):
          if (_fields.containsKey(field.name) && !evalModifier(field.attrs['invisible'], env)) yield field;
        case FormGroupNode(:final invisible, :final children):
          if (!evalModifier(invisible, env)) yield* _visibleFields(children, env);
        case FormSeparatorNode():
          break;
      }
    }
  }

  Future<void> _save() async {
    final arch = _arch!;
    final env = _env;
    final missing = <String>[];
    final invalid = <String>[];
    final writable = <String>{};
    for (final f in _visibleFields(arch.body, env)) {
      final type = _fields[f.name]!['type'];
      final v = _value(f.name);
      if (_isRequired(f, env) && type != 'boolean' && (v == null || v == false || v == '')) missing.add(_label(f));
      if (v is String && (type == 'integer' || type == 'float' || type == 'monetary')) invalid.add(_label(f));
      if (!_isReadonly(f, env)) writable.add(f.name);
    }
    if (missing.isNotEmpty || invalid.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(missing.isNotEmpty ? 'Fill in: ${missing.join(', ')}' : 'Not a number: ${invalid.join(', ')}'),
      ));
      return;
    }

    // On create, also send defaults for fields the user could have edited.
    final source = _id == null
        ? {for (final e in _record.entries) if (writable.contains(e.key)) e.key: e.value, ..._edits}
        : _edits;
    final vals = <String, dynamic>{
      for (final e in source.entries)
        if (_fields[e.key] != null && _editable(_fields[e.key]!))
          e.key: e.value is List && _fields[e.key]!['type'] == 'many2one' ? (e.value as List).first : e.value,
    };

    setState(() => _busy = true);
    try {
      final id = _id;
      if (id == null) {
        final created = await widget.rpc.callKw(widget.model, 'create', args: [vals], context: widget.recordContext);
        _id = created is List ? created.first as int : created as int;
      } else if (vals.isNotEmpty) {
        await widget.rpc.callKw(widget.model, 'write', args: [[id], vals], context: widget.recordContext);
      }
      _edits.clear();
      _editing = false;
      _formVersion++;
      HapticFeedback.mediumImpact();
      await _load();
    } catch (e) {
      if (mounted) handleRpcError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _discard() {
    if (_id == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _edits.clear();
      _editing = false;
      _formVersion++;
    });
  }

  Future<bool> _confirm(String message, {String action = 'OK'}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: Text(action)),
        ],
      ),
    );
    return ok == true;
  }

  void _openInWeb() {
    final id = _id;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => WebViewScreen(
        session: widget.rpc.session,
        path: id == null ? '/odoo/${widget.model}/new' : '/odoo/${widget.model}/$id',
        title: widget.title,
      ),
    ));
  }

  Future<void> _runButton(FormButton button) async {
    final id = _id;
    if (id == null) return;
    if (button.confirm != null && !await _confirm(button.confirm!)) return;
    if (!mounted) return;

    if (button.type == 'action') {
      // Action buttons mostly open wizards; let the web client run them.
      _openInWeb();
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await widget.rpc.callButton(widget.model, button.name, [id],
          context: {...widget.recordContext, 'active_id': id, 'active_ids': [id], 'active_model': widget.model});
      if (!mounted) return;
      final type = result is Map ? result['type'] : null;
      if (type != null && type != 'ir.actions.act_window_close') {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('This step continues in the web version.')));
        _openInWeb();
      }
      await _load();
    } catch (e) {
      if (mounted) handleRpcError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final id = _id;
    if (id == null || !await _confirm('Delete this record?', action: 'Delete')) return;
    try {
      await widget.rpc.callKw(widget.model, 'unlink', args: [[id]], context: widget.recordContext);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) handleRpcError(context, e);
    }
  }

  // ---- Field widgets ----

  Widget _fieldView(ArchField f) {
    final field = _fields[f.name]!;
    final type = field['type'];
    final value = _value(f.name);
    final theme = Theme.of(context);

    if (type == 'many2many' && _relatedNames[f.name] != null) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final n in _relatedNames[f.name]!)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: colorFor(n).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(n, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorFor(n))),
            ),
        ],
      );
    }
    if (type == 'one2many' && value is List && value.isNotEmpty) {
      final names = _relatedNames[f.name] ?? const <String>[];
      return InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => RecordListScreen(
            rpc: widget.rpc,
            model: field['relation'] as String,
            title: _label(f),
            domain: [
              ['id', 'in', value],
            ],
          ),
        )),
        child: Row(
          children: [
            Expanded(
              child: Text(
                names.isEmpty ? formatFieldValue(value, field) : names.join('\n'),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.chevron_right, color: theme.colorScheme.outline),
          ],
        ),
      );
    }
    if (type == 'boolean') {
      return Align(
        alignment: Alignment.centerLeft,
        child: Icon(value == true ? Icons.check_box : Icons.check_box_outline_blank, color: theme.colorScheme.primary),
      );
    }
    final text = formatFieldValue(value, field);
    if (text.isEmpty) return Text('—', style: TextStyle(color: theme.colorScheme.outline));
    final label = Text(
      text,
      style: TextStyle(
        fontSize: 15,
        fontWeight: type == 'monetary' ? FontWeight.w700 : FontWeight.w500,
        color: type == 'many2one' ? theme.colorScheme.primary : null,
      ),
    );
    final kind = type == 'char' ? contactKindOf(f.name, f.widget) : null;
    if (kind == null) return label;
    return Row(
      children: [
        Expanded(child: label),
        ContactButtons(kind: kind, value: text),
      ],
    );
  }

  /// First visible phone/email value, for the header's quick actions.
  String? _contactValue(Iterable<ArchField> visible, ContactKind kind) {
    for (final f in visible) {
      if (_fields[f.name]?['type'] != 'char' || contactKindOf(f.name, f.widget) != kind) continue;
      final v = _value(f.name);
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  /// The record's own address, when its model has address fields.
  String? get _address {
    String part(String name) {
      final v = _record[name];
      if (v is String) return v.trim();
      if (v is List && v.length > 1) return v[1].toString();
      return '';
    }

    if (!_fields.containsKey('street') && !_fields.containsKey('city')) return null;
    final parts = [for (final n in const ['street', 'street2', 'city', 'state_id', 'zip', 'country_id']) part(n)]
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(', ');
  }

  Widget _quickActions(Iterable<ArchField> visible) {
    final phone = _contactValue(visible, ContactKind.phone);
    final email = _contactValue(visible, ContactKind.email);
    final address = _address;
    final actions = [
      if (phone != null) ...[
        (Icons.call_outlined, 'Call', () => callPhone(context, phone)),
        (Icons.chat_outlined, 'WhatsApp', () => whatsApp(context, phone)),
      ],
      if (email != null) (Icons.mail_outline, 'Email', () => sendEmail(context, email)),
      if (address != null) (Icons.map_outlined, 'Map', () => openMap(context, address)),
    ];
    if (actions.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final (icon, label, onTap) in actions)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(icon, size: 20, color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _fieldEditor(ArchField f, bool required) {
    final field = _fields[f.name]!;
    final type = field['type'] as String;
    final value = _value(f.name);
    final label = _label(f) + (required ? ' *' : '');
    final key = ValueKey('${f.name}-$_formVersion');

    switch (type) {
      case 'boolean':
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value == true,
          onChanged: (v) => setState(() => _edits[f.name] = v),
        );
      case 'selection':
        final options = [
          for (final o in (field['selection'] as List? ?? const []))
            if (o is List && o.length > 1) (o[0], o[1].toString()),
        ];
        return DropdownButtonFormField<Object>(
          key: ValueKey('${f.name}-$_formVersion-$value'),
          initialValue: options.any((o) => o.$1 == value) ? value as Object : null,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            if (!required) const DropdownMenuItem<Object>(value: false, child: Text('—')),
            for (final (k, v) in options) DropdownMenuItem<Object>(value: k as Object, child: Text(v)),
          ],
          onChanged: (v) => setState(() => _edits[f.name] = v ?? false),
        );
      case 'many2one':
        final text = formatFieldValue(value, field);
        return _tapField(label, text, Icons.arrow_drop_down, () async {
          final picked = await showMany2onePicker(
            context,
            rpc: widget.rpc,
            model: field['relation'] as String,
            title: _label(f),
            allowClear: !required,
            recordContext: widget.recordContext,
          );
          if (picked != null && mounted) setState(() => _edits[f.name] = picked);
        });
      case 'date':
      case 'datetime':
        final isDate = type == 'date';
        final current = isDate ? parseOdooDate(value) : parseOdooDateTime(value);
        return _tapField(label, formatFieldValue(value, field), Icons.calendar_today, () async {
          final now = DateTime.now();
          final day = await showDatePicker(
            context: context,
            initialDate: current ?? now,
            firstDate: DateTime(1900),
            lastDate: DateTime(2200),
          );
          if (day == null || !mounted) return;
          if (isDate) {
            setState(() => _edits[f.name] = serializeOdooDate(day));
            return;
          }
          final time = await showTimePicker(
            context: context,
            initialTime: TimeOfDay.fromDateTime(current ?? now),
          );
          if (time == null) return;
          final local = DateTime(day.year, day.month, day.day, time.hour, time.minute);
          setState(() => _edits[f.name] = serializeOdooDateTime(local));
        }, onClear: required || value == false || value == null ? null : () => setState(() => _edits[f.name] = false));
      default:
        final numeric = type == 'integer' || type == 'float' || type == 'monetary';
        final initial = value == null || value == false
            ? ''
            : (value is double && value == value.truncateToDouble() ? value.toInt().toString() : value.toString());
        return TextFormField(
          key: key,
          initialValue: initial,
          minLines: type == 'text' ? 2 : 1,
          maxLines: type == 'text' ? 6 : 1,
          keyboardType: numeric
              ? TextInputType.numberWithOptions(decimal: type != 'integer', signed: true)
              : (type == 'text' ? TextInputType.multiline : TextInputType.text),
          decoration: InputDecoration(labelText: label),
          onChanged: (raw) {
            final t = raw.trim();
            if (!numeric) {
              _edits[f.name] = raw.isEmpty ? false : raw;
            } else if (t.isEmpty) {
              _edits[f.name] = type == 'integer' ? 0 : 0.0;
            } else {
              final cleaned = t.replaceAll(',', '');
              // Keep unparsable input as text so save can flag it.
              _edits[f.name] = (type == 'integer' ? int.tryParse(cleaned) : double.tryParse(cleaned)) ?? raw;
            }
          },
        );
    }
  }

  Widget _tapField(String label, String text, IconData icon, VoidCallback onTap, {VoidCallback? onClear}) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: onClear != null
              ? IconButton(icon: const Icon(Icons.clear), tooltip: 'Clear', onPressed: onClear)
              : Icon(icon),
        ),
        isEmpty: text.isEmpty,
        child: Text(text),
      ),
    );
  }

  /// Long text reads better full width; everything else is label | value.
  bool _isWide(ArchField f) {
    final type = _fields[f.name]?['type'];
    return type == 'html' || type == 'text' || type == 'one2many' || f.attrs['nolabel'] == '1';
  }

  Widget _fieldRow(ArchField f, Map<String, dynamic> env) {
    final scheme = Theme.of(context).colorScheme;
    if (_editing && !_isReadonly(f, env)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: _fieldEditor(f, _isRequired(f, env)),
      );
    }
    final label = Text(_label(f), style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant));
    if (_isWide(f)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [label, const SizedBox(height: 4), _fieldView(f)],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Padding(padding: const EdgeInsets.only(top: 1), child: label)),
          const SizedBox(width: 12),
          Expanded(flex: 3, child: _fieldView(f)),
        ],
      ),
    );
  }

  /// Rows separated by hairlines, as in a settings list.
  List<Widget> _divided(List<Widget> rows) => [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0 && !_editing) const Divider(height: 1),
          rows[i],
        ],
      ];

  List<Widget> _renderNodes(List<FormNode> nodes, Map<String, dynamic> env, int depth) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    final loose = <Widget>[];

    void flushLoose() {
      if (loose.isEmpty) return;
      out.add(depth == 0 ? _section(null, List.of(loose)) : Column(children: List.of(loose)));
      loose.clear();
    }

    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      switch (node) {
        case FormFieldNode(:final field, :final isTitle):
          if (isTitle || !_fields.containsKey(field.name)) continue;
          if (_fields[field.name]!['type'] == 'binary') continue;
          if (evalModifier(field.attrs['invisible'], env)) continue;
          loose.add(_fieldRow(field, env));
        case FormGroupNode(isPage: true):
          // A run of pages is a notebook: show it as tabs.
          final pages = <FormGroupNode>[];
          while (i < nodes.length && nodes[i] is FormGroupNode && (nodes[i] as FormGroupNode).isPage) {
            final page = nodes[i] as FormGroupNode;
            if (!evalModifier(page.invisible, env)) pages.add(page);
            i++;
          }
          i--;
          final rendered = [
            for (final p in pages) (p.title ?? '', _renderNodes(p.children, env, depth + 1)),
          ].where((p) => p.$2.isNotEmpty).toList();
          if (rendered.isEmpty) continue;
          flushLoose();
          out.add(_notebook(rendered));
        case FormGroupNode(:final title, :final invisible, :final children):
          if (evalModifier(invisible, env)) continue;
          final kids = _renderNodes(children, env, depth + 1);
          if (kids.isEmpty) continue;
          if (depth == 0) {
            flushLoose();
            out.add(_section(title, kids));
          } else {
            if (title != null && title.isNotEmpty) loose.add(_subheading(title, theme));
            loose.addAll(kids);
          }
        case FormSeparatorNode(:final title):
          loose.add(_subheading(title, theme));
      }
    }
    flushLoose();
    return out;
  }

  Widget _notebook(List<(String, List<Widget>)> pages) {
    final key = pages.map((p) => p.$1).join('|');
    final selected = (_selectedPage[key] ?? 0).clamp(0, pages.length - 1);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pages.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Row(
                  children: [
                    for (var i = 0; i < pages.length; i++)
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => setState(() => _selectedPage[key] = i),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                color: i == selected ? scheme.primary : Colors.transparent,
                                width: 2.5,
                              ),
                            ),
                          ),
                          child: Text(
                            pages[i].$1,
                            style: TextStyle(
                              fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                              color: i == selected ? scheme.primary : scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Text(pages.first.$1, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            if (pages.length > 1) const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _divided(pages[selected].$2),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _subheading(String title, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          title.toUpperCase(),
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _section(String? title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null && title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ..._divided(children),
            ],
          ),
        ),
      ),
    );
  }

  /// Odoo's statusbar as a row of steps: done, current, upcoming.
  Widget _statusBar(ArchField f) {
    final field = _fields[f.name];
    if (field == null) return const SizedBox.shrink();
    final value = _value(f.name);
    final scheme = Theme.of(context).colorScheme;
    final List<(Object?, String)> steps;
    if (field['type'] == 'selection') {
      final visible = f.attrs['statusbar_visible']?.split(',').map((s) => s.trim()).toSet();
      steps = [
        for (final o in (field['selection'] as List? ?? const []))
          if (o is List && o.length > 1 && (visible == null || visible.contains(o[0]) || o[0] == value))
            (o[0], o[1].toString()),
      ];
    } else {
      final text = formatFieldValue(value, field);
      steps = text.isEmpty ? [] : [(value, text)];
    }
    if (steps.isEmpty) return const SizedBox.shrink();
    final current = steps.indexWhere((s) => pyEquals(s.$1, value));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            if (i > 0) Icon(Icons.chevron_right, size: 18, color: scheme.outlineVariant),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: i == current
                    ? scheme.primary
                    : (i < current ? scheme.primaryContainer : scheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (i < current) ...[
                    Icon(Icons.check, size: 14, color: scheme.onPrimaryContainer),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    steps[i].$2,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: i == current
                          ? scheme.onPrimary
                          : (i < current ? scheme.onPrimaryContainer : scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _header(FormArch arch, Map<String, dynamic> env) {
    final scheme = Theme.of(context).colorScheme;
    final titleFields = [
      for (final f in _visibleFields(arch.body, env))
        if (_isTitleField(arch.body, f.name)) f,
    ];
    final image = _imageField == null ? null : decodeOdooImage(_record[_imageField]);
    final title = _id == null ? 'New ${widget.title}' : (_value('display_name') ?? widget.title).toString();
    final buttons = _editing || _id == null
        ? const <FormButton>[]
        : [for (final b in arch.buttons) if (!evalModifier(b.invisible, env)) b];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editing && titleFields.isNotEmpty)
                for (final f in titleFields) _fieldRow(f, env)
              else
                Row(
                  children: [
                    if (image != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: OdooImage(
                          bytes: image,
                          size: 56,
                          fallback: LetterAvatar(text: title, size: 56),
                        ),
                      )
                    else
                      LetterAvatar(text: title, size: 56),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, height: 1.25),
                      ),
                    ),
                  ],
                ),
              if (!_editing && _id != null) _quickActions(_visibleFields(arch.body, env)),
              if (arch.statusBar != null) ...[
                const SizedBox(height: 14),
                _statusBar(arch.statusBar!),
              ],
              if (buttons.isNotEmpty) ...[
                const SizedBox(height: 14),
                Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.5)),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final b in buttons)
                      b.primary
                          ? FilledButton(
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: _busy ? null : () => _runButton(b),
                              child: Text(b.label),
                            )
                          : OutlinedButton(
                              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                              onPressed: _busy ? null : () => _runButton(b),
                              child: Text(b.label),
                            ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  bool _isTitleField(List<FormNode> nodes, String name) {
    for (final node in nodes) {
      switch (node) {
        case FormFieldNode(:final field, :final isTitle):
          if (isTitle && field.name == name) return true;
        case FormGroupNode(:final children):
          if (_isTitleField(children, name)) return true;
        case FormSeparatorNode():
          break;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final arch = _arch;
    final Widget body;
    if (_error != null) {
      body = ErrorView.fromError(_error!, onRetry: () {
        setState(() => _error = null);
        _load();
      });
    } else if (arch == null) {
      body = ListView(
        padding: const EdgeInsets.all(16),
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Skeleton(width: 56, height: 56, radius: 14),
                  SizedBox(width: 14),
                  Expanded(child: Skeleton(height: 20)),
                ],
              ),
            ),
          ),
          SizedBox(height: 12),
          Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                children: [
                  _SkeletonRow(),
                  _SkeletonRow(),
                  _SkeletonRow(),
                  _SkeletonRow(),
                  _SkeletonRow(),
                  _SkeletonRow(),
                ],
              ),
            ),
          ),
        ],
      );
    } else {
      final env = _env;
      body = RefreshIndicator(
        onRefresh: _editing ? () async {} : _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _header(arch, env),
            ..._renderNodes(arch.body, env, 0),
          ],
        ),
      );
    }

    return PopScope(
      canPop: !_editing || _edits.isEmpty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirm('Discard your changes?', action: 'Discard') && context.mounted) {
          _edits.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (arch != null && !_editing) ...[
              if (arch.canEdit)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => setState(() => _editing = true),
                ),
              PopupMenuButton<String>(
                onSelected: (choice) {
                  if (choice == 'web') _openInWeb();
                  if (choice == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'web', child: Text('Open in web')),
                  if (arch.canDelete) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ],
          bottom: _busy
              ? const PreferredSize(preferredSize: Size.fromHeight(2), child: LinearProgressIndicator(minHeight: 2))
              : null,
        ),
        drawer: widget.drawer,
        body: body,
        bottomNavigationBar: arch != null && _editing
            ? SafeArea(
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(onPressed: _busy ? null : _discard, child: const Text('Discard')),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(onPressed: _busy ? null : _save, child: const Text('Save')),
                      ),
                    ],
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.only(bottom: 18),
        child: Row(
          children: [
            Expanded(flex: 2, child: Skeleton(height: 12)),
            SizedBox(width: 24),
            Expanded(flex: 3, child: Skeleton(height: 14)),
          ],
        ),
      );
}
