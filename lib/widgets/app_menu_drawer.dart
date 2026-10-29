import 'package:flutter/material.dart';

import '../l10n.dart';
import '../odoo/menus.dart';
import '../odoo/rpc.dart';
import '../screens/action_screen.dart';
import 'odoo_image.dart';

/// The open app's menu tree, like the menu bar of Odoo's web client.
class AppMenuDrawer extends StatelessWidget {
  final OdooRpc rpc;
  final OdooMenu app;
  final int? currentMenuId;

  const AppMenuDrawer({super.key, required this.rpc, required this.app, this.currentMenuId});

  void _open(BuildContext context, OdooMenu menu) {
    final navigator = Navigator.of(context);
    navigator.pop();
    if (menu.id == currentMenuId) return;
    navigator.pushReplacement(MaterialPageRoute(
      builder: (_) => ActionScreen(rpc: rpc, actionId: menu.actionId!, title: menu.name, app: app, menuId: menu.id),
    ));
  }

  List<Widget> _items(BuildContext context, List<OdooMenu> menus, int depth) {
    final theme = Theme.of(context);
    return [
      for (final menu in menus) ...[
        if (menu.actionId != null)
          ListTile(
            contentPadding: EdgeInsetsDirectional.only(start: 16.0 + depth * 16, end: 16),
            title: Text(menu.name),
            selected: menu.id == currentMenuId,
            onTap: () => _open(context, menu),
          )
        else if (menu.children.isNotEmpty)
          Padding(
            padding: EdgeInsetsDirectional.fromSTEB(16.0 + depth * 16, 16, 16, 4),
            child: Text(
              menu.name.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline, letterSpacing: 0.8),
            ),
          ),
        ..._items(context, menu.children, menu.actionId != null ? depth + 1 : depth),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  AppIcon(app: app, serverUrl: rpc.session.serverUrl, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(app.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.apps),
              title: Text(tr('All apps')),
              onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
            ),
            const Divider(),
            ..._items(context, app.children, 0),
          ],
        ),
      ),
    );
  }
}
