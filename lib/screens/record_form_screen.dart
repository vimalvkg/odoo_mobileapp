import 'package:flutter/material.dart';

import '../app_navigation.dart';
import '../odoo/expr.dart';
import '../odoo/format.dart';
import '../odoo/rpc.dart';
import '../odoo/view_arch.dart';
import '../widgets/error_view.dart';
import '../widgets/many2one_picker.dart';
import '../widgets/odoo_image.dart';
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
        final rows = await widget.rpc.read(widget.model, [id], [...names, if (imageField != null) imageField], context: widget.recordContext);
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
        children: [for (final n in _relatedNames[f.name]!) Chip(label: Text(n), visualDensity: VisualDensity.compact)],
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
    return Text(text.isEmpty ? '—' : text, style: text.isEmpty ? TextStyle(color: theme.colorScheme.outline) : null);
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
        final initial = value == null || value == false ? '' : value.toString();
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

  Widget _fieldRow(ArchField f, Map<String, dynamic> env) {
    final theme = Theme.of(context);
    if (_editing && !_isReadonly(f, env)) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _fieldEditor(f, _isRequired(f, env)),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_label(f), style: TextStyle(fontSize: 12, color: theme.colorScheme.outline)),
          const SizedBox(height: 2),
          _fieldView(f),
        ],
      ),
    );
  }

  List<Widget> _renderNodes(List<FormNode> nodes, Map<String, dynamic> env, int depth) {
    final theme = Theme.of(context);
    final out = <Widget>[];
    final loose = <Widget>[];

    void flushLoose() {
      if (loose.isEmpty) return;
      out.add(depth == 0 ? _section(null, List.of(loose)) : Column(children: List.of(loose)));
      loose.clear();
    }

    for (final node in nodes) {
      switch (node) {
        case FormFieldNode(:final field, :final isTitle):
          if (isTitle || !_fields.containsKey(field.name)) continue;
          if (_fields[field.name]!['type'] == 'binary') continue;
          if (evalModifier(field.attrs['invisible'], env)) continue;
          loose.add(_fieldRow(field, env));
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

  Widget _subheading(String title, ThemeData theme) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 2),
        child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
      );

  Widget _section(String? title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (title != null && title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _statusBar(ArchField f) {
    final field = _fields[f.name];
    if (field == null) return const SizedBox.shrink();
    final value = _value(f.name);
    final theme = Theme.of(context);
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
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          for (final (key, label) in steps)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Chip(
                label: Text(label),
                visualDensity: VisualDensity.compact,
                backgroundColor: pyEquals(key, value) ? theme.colorScheme.primary : null,
                labelStyle: pyEquals(key, value) ? TextStyle(color: theme.colorScheme.onPrimary) : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(FormArch arch, Map<String, dynamic> env) {
    final theme = Theme.of(context);
    final titleFields = [
      for (final f in _visibleFields(arch.body, env))
        if (arch.body.isNotEmpty && _isTitleField(arch.body, f.name)) f,
    ];
    final image = _imageField == null ? null : decodeOdooImage(_record[_imageField]);
    final heading = Row(
      children: [
        if (image != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: OdooImage(bytes: image, size: 56, fallback: const SizedBox(width: 56, height: 56)),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_editing)
                ...[for (final f in titleFields) _fieldRow(f, env)]
              else
                Text(
                  _id == null ? 'New' : (_value('display_name') ?? widget.title).toString(),
                  style: theme.textTheme.titleLarge,
                ),
            ],
          ),
        ),
      ],
    );
    final buttons = _editing || _id == null
        ? const <FormButton>[]
        : [for (final b in arch.buttons) if (!evalModifier(b.invisible, env)) b];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (arch.statusBar != null) _statusBar(arch.statusBar!),
        if (buttons.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final b in buttons)
                  b.primary
                      ? FilledButton(onPressed: _busy ? null : () => _runButton(b), child: Text(b.label))
                      : OutlinedButton(onPressed: _busy ? null : () => _runButton(b), child: Text(b.label)),
              ],
            ),
          ),
        Padding(padding: const EdgeInsets.only(bottom: 12), child: heading),
      ],
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
      body = const Center(child: CircularProgressIndicator());
    } else {
      final env = _env;
      body = RefreshIndicator(
        onRefresh: _editing ? () async {} : _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
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
        if (await _confirm('Discard your changes?', action: 'Discard') && mounted) {
          _edits.clear();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [
            if (arch != null && _editing) ...[
              IconButton(tooltip: 'Discard', icon: const Icon(Icons.close), onPressed: _busy ? null : _discard),
              IconButton(tooltip: 'Save', icon: const Icon(Icons.check), onPressed: _busy ? null : _save),
            ] else if (arch != null) ...[
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
      ),
    );
  }
}
