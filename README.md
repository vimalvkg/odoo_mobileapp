# Tailorline Mobile

Dynamic mobile client for any Odoo 19 Community database. Sign in with
server, database, username and password; the app reads the database's
installed apps, menus and views and renders them as native screens (app grid,
lists, forms), like the Odoo Enterprise mobile app. Anything not rendered
natively opens in Odoo's web client inside the app.

See [Tailorline_Mobile_FRS.md](Tailorline_Mobile_FRS.md) for requirements,
scope and status.

## Layout

| Path | Purpose |
|---|---|
| `lib/odoo_client.dart` | Odoo JSON-RPC auth (`/web/session/authenticate`, `/web/session/destroy`) |
| `lib/session_store.dart` | Persisted session and last-used login details |
| `lib/odoo/rpc.dart` | JSON-RPC client: `call_kw`, menus, actions, `get_views`, buttons |
| `lib/odoo/view_arch.dart` | Parses list/kanban/search/form view archs |
| `lib/odoo/expr.dart`, `domain.dart` | Safe evaluator for view modifiers, domains and contexts |
| `lib/navigation_policy.dart` | Decides which WebView links stay in-app, open externally, or mean "signed out" |
| `lib/screens/` | Splash, login, home (apps), action, record list, record form, web view |
| `test/` | Unit tests for the pure logic above |

## Running

```sh
flutter pub get
flutter test
flutter run            # on a connected Android device
flutter build apk      # sideloadable APK
```

Sign in with your Odoo server (e.g. `yourshop.example.com` or
`192.168.1.20:8069`), database name, username and password.
