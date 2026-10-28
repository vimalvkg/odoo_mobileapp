# Tailorline Mobile

Flutter mobile client for the Tailorline tailor management system on Odoo 19
Community. A native shell (login, session, error handling) wraps the Odoo web
client in a WebView, so every installed module — including the custom
`vm_tailor_*` addons — works without per-screen native code.

See [Tailorline_Mobile_FRS.md](Tailorline_Mobile_FRS.md) for requirements,
scope and status.

## Layout

| Path | Purpose |
|---|---|
| `lib/odoo_client.dart` | Odoo JSON-RPC auth (`/web/session/authenticate`, `/web/session/destroy`) |
| `lib/session_store.dart` | Persisted session and last-used login details |
| `lib/navigation_policy.dart` | Decides which WebView links stay in-app, open externally, or mean "signed out" |
| `lib/screens/` | Splash, login and WebView screens |
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
