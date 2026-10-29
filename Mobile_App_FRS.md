# ERP Mobile — Functional Requirements Specification

| | |
|---|---|
| **Document** | Functional Requirements Specification |
| **Product** | ERP Mobile — dynamic mobile client for Odoo 19 Community |
| **Status** | Phase 1 (shell), Phase 1.1 (WebView UX) and Phase 2 (dynamic native screens) implemented; device testing pending |
| **Date** | 2026-10-28 |

## 1. Purpose

A mobile app for **any Odoo 19 Community database**, comparable to the Odoo Enterprise mobile app. The user connects with server URL, database, username and password; the app then builds its screens from what is **installed in that database** — apps, menus, list/form views, filters and buttons — instead of hard-coding screens for specific modules. Standard modules (Sales, CRM, Inventory, Contacts, …) and custom modules work the same way, with no app update needed when modules are installed or changed.

## 2. Background and approach

The Enterprise app is a native shell around Odoo's web client. Three approaches were evaluated:

| Approach | Description | Verdict |
|---|---|---|
| **A. Pure WebView wrapper** | Native login/session + WebView of the Odoo web client | Built in Phase 1; kept as the fallback for anything not rendered natively |
| **B. Hand-built native screens** | Native screens coded per workflow/module | Rejected: not dynamic — every module needs app code |
| **C. Dynamic native renderer** | Read menus, actions and views from the server (`load_web_menus`, `/web/action/load`, `get_views`) and render them natively | **Chosen** for Phase 2: matches the "screens depend on installed modules" requirement |

**Decision:** the app renders window actions (list + form) natively and dynamically (C). Everything Odoo's web client does that the native renderer does not yet cover — dashboards, Discuss, calendar/pivot/graph views, wizards, settings, reports — opens in the embedded web client (A), using the same session.

## 3. Architecture

| Layer | Files | Responsibility |
|---|---|---|
| Auth & session | `odoo_client.dart`, `session_store.dart` | `/web/session/authenticate`, database list, persisted session |
| RPC | `odoo/rpc.dart` | JSON-RPC (`call_kw`, `get_session_info`, `load_web_menus`, `/web/action/load`, `get_views`, `call_button`) with the session cookie; maps Odoo errors, detects expired sessions and rotated session ids |
| View engine | `odoo/view_arch.dart`, `odoo/expr.dart`, `odoo/domain.dart`, `odoo/format.dart` | Parse list/kanban/form/search archs; evaluate modifiers (`invisible="state != 'draft'"`), action domains and contexts (safe Python-subset evaluator); domain normalization; value formatting |
| Screens | `screens/home_screen.dart`, `action_screen.dart`, `record_list_screen.dart`, `record_form_screen.dart`, `webview_screen.dart` | Home app grid → action → native list/form, or web fallback |

All data access goes through the same endpoints the Odoo web client uses, so **access rights, record rules and field groups are enforced by the server**; the app has no authorization logic of its own.

## 4. Screens

| Screen | Behaviour |
|---|---|
| **Splash** | Resumes a saved session straight to Home, else Login |
| **Login** | Server, database, username, password. Database can be picked from the server's list (`/web/database/list`) when the server allows it. Remembers server/database/username (never the password); password show/hide |
| **Home** | Grid of installed apps (top-level menus) with their icons; search across apps and all menus ("Sales / Orders / Quotations"); account sheet with user, server, database, company, *Open web version* and *Sign out* |
| **App drawer** | The open app's menu tree (sections and items), *All apps* back to Home |
| **Record list** | Cards built from the action's list view (kanban if no list): title, up to 3 detail fields, amount, status badge. Search (`display_name ilike`), the search view's predefined filters (with `search_default_*` defaults, OR within a group, AND across groups), infinite scroll, pull to refresh, *New* button (respects `create="0"`), *Open in web* |
| **Record form** | Built from the form view: statusbar, header buttons (with `invisible` modifiers and `confirm`), title/avatar, groups and notebook pages as sections; `invisible`/`readonly`/`required` modifiers evaluated live; many2many as chips, one2many as a tappable list that opens the related records. Edit / save / discard, create (with `default_get`), delete (respects `edit`/`delete` attributes), *Open in web* |
| **Web view** | Any server path in the embedded web client with the same session; Android back walks page history; WhatsApp/phone/email/other-site links open in external apps; reaching `/web/login` returns to the native login |

## 5. Functional Requirements

| ID | Requirement | Status |
|---|---|---|
| FR-1 | Connect to any Odoo 19 server with server URL, database, username, password | Done |
| FR-2 | Distinct messages for invalid credentials, no network, server unreachable | Done |
| FR-3 | Persist the session cookie; inject it into the WebView | Done |
| FR-4 | Resume a saved session on relaunch without re-login | Done |
| FR-5 | Embedded web client for screens not rendered natively | Done |
| FR-6 | Sign out ends the server session and clears WebView cookies | Done |
| FR-7 | Detect missing connectivity and show a retry screen | Done |
| FR-12 | Android back navigates WebView history | Done |
| FR-13 | External links (WhatsApp, `tel:`, `mailto:`, other sites) open in the matching app | Done |
| FR-14 | Expired session anywhere (RPC or WebView) returns to native login with a notice | Done |
| FR-16 | Login prefilled with last server/database/username; database picker from server list | Done |
| FR-20 | Home shows the apps installed in the connected database, with icons, built dynamically from its menus | Done |
| FR-21 | Search apps and menus from Home | Done |
| FR-22 | Opening a menu loads its action; window actions render as native list/form, other action types open in the web client | Done |
| FR-23 | Native list of any model, columns taken from its list/kanban view; search, predefined filters, paging, pull to refresh | Done |
| FR-24 | Native form of any model laid out from its form view, with modifiers evaluated against the record | Done |
| FR-25 | Edit and save simple fields: text, numbers, boolean, selection, date, datetime, many2one (search picker) | Done |
| FR-26 | Create and delete records, honouring the view's `create`/`edit`/`delete` attributes | Done |
| FR-27 | Run form header buttons (`type="object"`); actions/wizards they return continue in the web client | Done |
| FR-28 | Open the same record or action in the web client from any native screen | Done |
| FR-33 | Company branding from the connected database: public company logo on login/lock screens, `res.company.primary_color` re-themes the app (remembered per server+database) | Done |
| FR-34 | Record photos (`avatar_128`/`image_128`) in lists, form header and profile, when the model has them | Done |
| FR-35 | Swipe on list cards: contact (call/WhatsApp/email) when the record has phone/email fields; archive with undo when the model has `active` | Done |
| FR-36 | Phone/email/URL fields get one-tap actions; form header quick actions (call, WhatsApp, email, map from address fields) | Done |
| FR-37 | Bottom navigation: Apps, Activities, Discuss, Profile — Activities/Discuss only when `mail` is installed | Done |
| FR-38 | My Activities: the user's `mail.activity` grouped overdue/today/upcoming, open the record, mark done (swipe or tap); summary card and badge | Done |
| FR-39 | Recent menus on Home, remembered per server+database | Done |
| FR-40 | Quick unlock with fingerprint/face/screen lock (on-device only), appearance (auto/light/dark), loading skeletons, haptics | Done |
| FR-18 | File/photo upload from the WebView | Planned |
| FR-19 | Download/share PDF reports | Planned |
| FR-29 | Run onchange while editing (live computed fields/defaults) | Planned |
| FR-30 | Edit one2many lines natively (e.g. order lines): line cards from the field's inline list view, add/edit in a line editor built from its inline form (or list columns) with `parent.*` conditions, swipe to remove; saved as Odoo x2many commands so the server computes prices, taxes and totals | Done |
| FR-41 | Many2many tags editable (add/remove chips); record pickers respect the field's domain | Done |
| FR-42 | Live onchange while editing lines (unit price, taxes, subtotal shown before saving) | Planned — today computed on Save |
| FR-43 | Language follows the user's Odoo language (`res.users.lang`): Odoo data comes translated by the server, the app's own text in English or Arabic, right-to-left layout for Arabic (and other RTL languages). Profile → Language lists the languages installed in the database and saves the choice to the user's Odoo preferences; English/Arabic toggle on the sign-in screen | Done |
| FR-31 | Native wizards (`target="new"` actions), kanban grouping, calendar | Planned — today via web client |
| FR-32 | Push notifications (Discuss, activities) | Planned — needs server-side design |

## 6. Known limitations (current release)

- **Onchange is not run** while editing, so computed fields and dependent defaults update only after saving (the server recomputes on save).
- **Line prices/taxes/subtotals** are computed by Odoo when the record is saved (no live onchange yet).
- **Modifiers and domains** use a safe Python subset. Expressions with functions such as `context_today()` or `relativedelta` can't be evaluated on the device: such modifiers are treated as false (field shown), such search filters are hidden, and an action domain that can't be evaluated is dropped with a visible notice (server-side record rules still apply).
- **Binary fields** other than the record avatar are not loaded.
- Web fallback URLs use Odoo 17+/19 routes (`/odoo/action-<id>`, `/odoo/<model>/<id>`).

## 7. Non-Functional Requirements

- **Security:** no credentials in source or logs; only the session cookie and non-secret login details are persisted. All authorization is enforced by the Odoo server. Cleartext HTTP is permitted so LAN servers work; production servers should use HTTPS.
- **Compatibility:** any Odoo 19 Community database, any combination of standard and custom modules. Fallbacks exist for Odoo 16–18 response shapes (`get_views`, menus route, `tree` → `list`).
- **Platform:** Android and iOS (Flutter).

## 8. Platform Support & Known Constraints

| Platform | Status | Notes |
|---|---|---|
| **Android** | Working (Phase 1); Phase 2 needs device verification | Builds via `flutter run` / APK |
| **iOS** | Blocked | Needs macOS/Xcode (or a cloud build service) and an Apple Developer account |
| **Web (browser)** | UI-preview only | Browsers hide `Set-Cookie` and Odoo sends no CORS headers, so login only works in the native app |

## 9. Testing

- Unit tests (`flutter test`): expression evaluator, domain handling, arch parsing (list/search/form), menu tree, value formatting, navigation policy, auth helpers.
- Manual test plan against an Odoo 19 Community database with Contacts, Sales, CRM, Inventory and a custom module: open each app, list/search/filter, open/edit/save/create/delete a record, run a header button, open a wizard (falls back to web), sign out, expire the session on the server.

## 10. Open Questions

- Priority order for FR-29 (onchange), FR-30 (line editing), FR-31 (wizards) vs FR-18/19 (uploads, reports)?
- App name/branding: the product name is neutral ("ERP Mobile" launcher label, set in `lib/theme.dart`); the home screen shows the connected company's name. Company logo and colours to be supplied.
- Push notifications: in scope, and with which provider (FCM/APNs)?
