import 'package:xml/xml.dart';

/// A `<field>` from a view arch with its attributes (`widget`, `string`,
/// `invisible`, `readonly`, `required`, ...).
class ArchField {
  final String name;
  final Map<String, String> attrs;

  /// Inline views of a relational field (`list`, `form`, `kanban`), as XML.
  final Map<String, String> subviews;

  const ArchField(this.name, this.attrs, [this.subviews = const {}]);

  String? get widget => attrs['widget'];
  String? get label => attrs['string'];
}

Map<String, String> _attrs(XmlElement el) => {for (final a in el.attributes) a.name.local: a.value};

bool _isTrue(String? v) {
  final s = v?.trim();
  return s == '1' || s == 'True' || s == 'true';
}

bool _isFalse(String? v) {
  final s = v?.trim();
  return s == '0' || s == 'False' || s == 'false';
}

/// Whether the view's root allows an operation (`create="0"` disables it).
bool archAllows(String arch, String operation) =>
    !_isFalse(XmlDocument.parse(arch).rootElement.getAttribute(operation));

/// Fields shown by a list or kanban view, in order, minus hidden columns and
/// sub-views nested inside relational fields.
List<ArchField> parseCardFields(String arch) {
  final seen = <String>{};
  final out = <ArchField>[];
  void walk(XmlElement el) {
    for (final child in el.childElements) {
      final tag = child.name.local;
      if (tag == 'field') {
        final name = child.getAttribute('name');
        final hidden = _isTrue(child.getAttribute('invisible')) ||
            _isTrue(child.getAttribute('column_invisible')) ||
            child.getAttribute('optional') == 'hide' ||
            child.getAttribute('widget') == 'handle';
        if (name != null && !hidden && seen.add(name)) out.add(ArchField(name, _attrs(child)));
      } else if (tag != 'header' && tag != 'control' && tag != 'button') {
        walk(child);
      }
    }
  }

  walk(XmlDocument.parse(arch).rootElement);
  return out;
}

class SearchFilter {
  final String name;
  final String label;
  final String domain;

  /// Filters in the same group are OR-ed, groups are AND-ed (as in Odoo).
  final int group;

  const SearchFilter(this.name, this.label, this.domain, this.group);
}

/// The predefined filters of a search view that have a domain. Group-by and
/// date-range filters are skipped.
List<SearchFilter> parseSearchFilters(String arch) {
  final out = <SearchFilter>[];
  var group = 0;
  void walk(XmlElement el) {
    for (final child in el.childElements) {
      final tag = child.name.local;
      if (tag == 'separator') {
        group++;
      } else if (tag == 'group') {
        group++;
        walk(child);
        group++;
      } else if (tag == 'filter') {
        final name = child.getAttribute('name');
        final domain = child.getAttribute('domain');
        if (name != null && domain != null && !_isTrue(child.getAttribute('invisible'))) {
          out.add(SearchFilter(name, child.getAttribute('string') ?? name, domain, group));
        }
      }
    }
  }

  walk(XmlDocument.parse(arch).rootElement);
  return out;
}

sealed class FormNode {
  const FormNode();
}

class FormFieldNode extends FormNode {
  final ArchField field;

  /// Inside the `oe_title` block: rendered as the record's heading.
  final bool isTitle;

  /// Inside a `<group>`. Odoo only labels grouped fields; fields placed
  /// directly in a page or the sheet (lines, notes) show without a label.
  final bool inGroup;

  const FormFieldNode(this.field, {this.isTitle = false, this.inGroup = true});
}

/// A `<group>` or notebook `<page>`.
class FormGroupNode extends FormNode {
  final String? title;
  final String? invisible;
  final bool isPage;
  final List<FormNode> children;

  const FormGroupNode({this.title, this.invisible, this.isPage = false, required this.children});
}

class FormSeparatorNode extends FormNode {
  final String title;

  const FormSeparatorNode(this.title);
}

class FormButton {
  final String name;

  /// `object` (a model method) or `action` (an ir.actions record id).
  final String type;
  final String label;
  final String? invisible;
  final String? confirm;
  final bool primary;

  const FormButton({
    required this.name,
    required this.type,
    required this.label,
    this.invisible,
    this.confirm,
    this.primary = false,
  });
}

class FormArch {
  final List<FormButton> buttons;
  final ArchField? statusBar;
  final List<FormNode> body;

  /// Every field the view declares, visible or not; modifiers may refer to
  /// the hidden ones, so they must all be read.
  final Set<String> fieldNames;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  const FormArch({
    required this.buttons,
    required this.statusBar,
    required this.body,
    required this.fieldNames,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
  });
}

/// Python `or` of two optional conditions.
String? _anyOf(String? a, String? b) {
  final x = a?.trim() ?? '';
  final y = b?.trim() ?? '';
  if (x.isEmpty) return y.isEmpty ? null : y;
  if (y.isEmpty) return x;
  return '($x) or ($y)';
}

const _skippedFormTags = {'button', 'label', 'widget', 'chatter', 'img', 'footer', 'templates', 'script', 'i'};

FormArch parseFormArch(String arch) {
  final root = XmlDocument.parse(arch).rootElement;
  final buttons = <FormButton>[];
  final fieldNames = <String>{};
  ArchField? statusBar;

  void collectHeader(XmlElement header) {
    for (final el in header.childElements) {
      if (el.name.local == 'button') {
        final name = el.getAttribute('name');
        final type = el.getAttribute('type');
        final label = el.getAttribute('string') ?? '';
        if (name == null || (type != 'object' && type != 'action') || label.isEmpty) continue;
        if (_isTrue(el.getAttribute('invisible'))) continue;
        final cls = el.getAttribute('class') ?? '';
        buttons.add(FormButton(
          name: name,
          type: type!,
          label: label,
          invisible: el.getAttribute('invisible'),
          confirm: el.getAttribute('confirm'),
          primary: cls.contains('oe_highlight') || cls.contains('btn-primary'),
        ));
      } else if (el.name.local == 'field') {
        final name = el.getAttribute('name');
        if (name == null) continue;
        fieldNames.add(name);
        if (el.getAttribute('widget') == 'statusbar' && !_isTrue(el.getAttribute('invisible'))) {
          statusBar = ArchField(name, _attrs(el));
        }
      } else {
        collectHeader(el);
      }
    }
  }

  void collectNames(XmlElement el) {
    for (final child in el.childElements) {
      if (child.name.local != 'field') {
        collectNames(child);
      } else if (child.getAttribute('name') case final name?) {
        fieldNames.add(name);
      }
    }
  }

  /// [hiddenIf] is the `invisible` condition inherited from wrapping
  /// elements (`div`, `span`, ...), which Odoo applies to everything inside.
  List<FormNode> walk(XmlElement el, bool inTitle, String? hiddenIf, [bool inGroup = false]) {
    final nodes = <FormNode>[];
    for (final child in el.childElements) {
      final tag = child.name.local;
      final cls = child.getAttribute('class') ?? '';
      if (tag == 'field') {
        final name = child.getAttribute('name');
        if (name == null) continue;
        fieldNames.add(name);
        if (!_isTrue(child.getAttribute('invisible'))) {
          final attrs = _attrs(child);
          final invisible = _anyOf(hiddenIf, attrs['invisible']);
          if (invisible != null) attrs['invisible'] = invisible;
          final subviews = {
            for (final sub in child.childElements)
              if (const {'list', 'tree', 'form', 'kanban'}.contains(sub.name.local))
                sub.name.local == 'tree' ? 'list' : sub.name.local: sub.toXmlString(),
          };
          nodes.add(FormFieldNode(ArchField(name, attrs, subviews), isTitle: inTitle, inGroup: inGroup));
        }
        // Fields nested inside a relational field belong to its sub-view.
      } else if (_isTrue(child.getAttribute('invisible'))) {
        continue;
      } else if (tag == 'header') {
        collectHeader(child);
      } else if (tag == 'group' || tag == 'page') {
        final kids = walk(child, inTitle, null, tag == 'group');
        if (kids.isNotEmpty) {
          nodes.add(FormGroupNode(
            title: child.getAttribute('string'),
            invisible: _anyOf(hiddenIf, child.getAttribute('invisible')),
            isPage: tag == 'page',
            children: kids,
          ));
        }
      } else if (tag == 'separator') {
        final title = child.getAttribute('string');
        if (title != null && title.isNotEmpty) nodes.add(FormSeparatorNode(title));
      } else if (RegExp(r'\balert\b').hasMatch(cls)) {
        // Warning banners ("another contact has this Tax ID") mix text with
        // helper fields that only make sense inside the banner. Not shown,
        // but their fields are still read: modifiers elsewhere may use them.
        collectNames(child);
      } else if (_skippedFormTags.contains(tag) ||
          cls.contains('oe_button_box') ||
          cls.contains('oe_chatter') ||
          child.getAttribute('name') == 'button_box') {
        continue;
      } else {
        nodes.addAll(walk(
          child,
          inTitle || cls.contains('oe_title'),
          _anyOf(hiddenIf, child.getAttribute('invisible')),
          inGroup,
        ));
      }
    }
    return nodes;
  }

  final body = walk(root, false, null);
  return FormArch(
    buttons: buttons,
    statusBar: statusBar,
    body: body,
    fieldNames: fieldNames,
    canCreate: !_isFalse(root.getAttribute('create')),
    canEdit: !_isFalse(root.getAttribute('edit')),
    canDelete: !_isFalse(root.getAttribute('delete')),
  );
}

/// Every field of a form body, in layout order, with its own conditions.
List<ArchField> formFields(List<FormNode> nodes) => [
      for (final node in nodes)
        ...switch (node) {
          FormFieldNode(:final field) => [field],
          FormGroupNode(:final children) => formFields(children),
          FormSeparatorNode() => const <ArchField>[],
        },
    ];

/// Every field a list view declares, hidden ones included (line conditions
/// often depend on hidden columns), excluding nested sub-views.
Set<String> archFieldNames(String arch) {
  final names = <String>{};
  void walk(XmlElement el) {
    for (final child in el.childElements) {
      if (child.name.local != 'field') {
        walk(child);
      } else if (child.getAttribute('name') case final name?) {
        names.add(name);
      }
    }
  }

  walk(XmlDocument.parse(arch).rootElement);
  return names;
}
