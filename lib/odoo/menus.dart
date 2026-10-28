/// A node of Odoo's menu tree, as returned by `ir.ui.menu.load_web_menus`.
/// Top-level nodes are the installed apps shown on the home screen.
class OdooMenu {
  final int id;
  final String name;
  final int? actionId;
  final String? actionModel;

  /// `module,path/to/icon.png` or a font-awesome spec; see [iconData].
  final String? webIcon;

  /// Base64 icon (optionally a `data:` URI) uploaded with the app.
  final String? iconData;
  final List<OdooMenu> children;

  const OdooMenu({
    required this.id,
    required this.name,
    this.actionId,
    this.actionModel,
    this.webIcon,
    this.iconData,
    this.children = const [],
  });

  /// This menu if it opens something, else its first descendant that does —
  /// what Odoo opens when you tap an app.
  OdooMenu? get firstAction {
    if (actionId != null) return this;
    for (final child in children) {
      final found = child.firstAction;
      if (found != null) return found;
    }
    return null;
  }

  /// Every menu under this one that opens something, with its path for search
  /// results ("Sales / Orders / Quotations").
  Iterable<(OdooMenu, String)> actionsWithPath([String prefix = '']) sync* {
    final path = prefix.isEmpty ? name : '$prefix / $name';
    if (actionId != null) yield (this, path);
    for (final child in children) {
      yield* child.actionsWithPath(path);
    }
  }
}

List<OdooMenu> parseMenus(dynamic raw) {
  if (raw is! Map) return [];
  final byId = <String, Map<dynamic, dynamic>>{
    for (final e in raw.entries)
      if (e.value is Map) e.key.toString(): e.value as Map<dynamic, dynamic>,
  };

  OdooMenu build(Map<dynamic, dynamic> m) {
    final action = m['actionID'];
    String? text(dynamic v) => v is String && v.isNotEmpty ? v : null;
    return OdooMenu(
      id: m['id'] is int ? m['id'] as int : 0,
      name: m['name']?.toString() ?? '',
      actionId: action is int ? action : null,
      actionModel: text(m['actionModel']),
      webIcon: text(m['webIcon']),
      iconData: text(m['webIconData']),
      children: [
        for (final c in (m['children'] as List? ?? const []))
          if (byId[c.toString()] case final child?) build(child),
      ],
    );
  }

  final root = byId['root'];
  if (root == null) return [];
  return build(root).children;
}
