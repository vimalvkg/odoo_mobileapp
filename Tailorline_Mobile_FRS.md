# Tailorline Mobile App — Functional Requirements Specification

| | |
|---|---|
| **Document** | Functional Requirements Specification |
| **Product** | Tailorline Mobile (Odoo 19 Community mobile client) |
| **Status** | Phase 1 (App Shell) implemented; Phase 2+ planned |
| **Date** | 2026-10-28 |

## 1. Purpose

Tailorline Mobile is a native mobile app for the tailor management system built on Odoo 19 Community (`vm_tailor_*` addon suite). It gives staff a phone-based alternative to the existing web portal, in the spirit of Odoo Enterprise's mobile app — but for Community edition plus this business's custom addons, which the official Enterprise app does not support.

## 2. Background

Odoo Enterprise's mobile app is, architecturally, a native shell wrapping a WebView that loads Odoo's own OWL web client — it is "dynamic" (works with any installed module, including custom ones) because it defers rendering to the server-driven web client rather than hand-coding native screens per model. That approach is not available on Community edition.

Three architectures were evaluated for replicating this:

| Approach | Description | Verdict |
|---|---|---|
| **A. Pure WebView wrapper** | Native shell (login, session) + WebView loading the existing Odoo portal | Fastest to build (~3–5 days); works for every module automatically, including future ones |
| **B. Hybrid** | WebView wrapper + hand-built native screens for the highest-traffic workflows (job cards, payments, WhatsApp) | Best user experience; 2–4 weeks depending on screen count; requires ongoing maintenance as workflows change |
| **C. Full native dynamic renderer** | Reimplement Odoo's view-engine logic natively (menus, `get_views`, `fields_get`, `search_read`, ACL-aware rendering for arbitrary models) | Matches Enterprise's generality exactly, but is a multi-month effort — not pursued |

**Decision:** build Approach A first as a working foundation, then layer native screens from Approach B onto it for the highest-value workflows.

## 3. Scope

### 3.1 In scope — Phase 1 (implemented)
- Generic connection to any Odoo 19 server (not hardcoded to one deployment) — server URL, database, username, password
- Session-based authentication against Odoo's `/web/session/authenticate` endpoint
- Persistent session (auto-resume on app relaunch without re-entering credentials)
- WebView rendering of the existing Odoo portal/backend, inheriting all server-side ACL and `ir.rule` enforcement automatically — no duplicated authorization logic on the client
- Native app shell: splash screen, login screen, app bar with reload, drawer with reload/sign out
- Error handling: no network connection, server unreachable, invalid credentials, generic failure — each with a distinct, actionable message
- Android native build (APK), sideloadable or installable via `flutter run`

### 3.2 In scope — Phase 2 (planned, not yet built)
Native (non-WebView) screens for the highest-frequency staff workflows, backed by JSON API endpoints wrapping the existing portal controllers:
- Job card list + detail + stage actions
- Payment collection (advance/balance)
- WhatsApp send (reuses existing `whatsapp_url` compute already built into `tailor_order.py`)
- Family order list + detail
- Push notifications for order-stage changes (requires a notification backend — not yet designed)

### 3.3 Out of scope
- Approach C (full dynamic native renderer) — not justified by current team size/timeline
- Offline mode / local data caching — no requirement identified yet
- iOS App Store distribution — blocked on Apple Developer Program enrollment and Mac build access (see §6)

## 4. Functional Requirements

| ID | Requirement | Status |
|---|---|---|
| FR-1 | User can enter server URL, database name, username, and password to connect to any Odoo 19 instance | Done |
| FR-2 | App authenticates via `/web/session/authenticate` and distinguishes invalid credentials, no network, and server-unreachable failures with distinct messages | Done |
| FR-3 | On successful login, the session cookie is persisted locally and injected into the WebView automatically | Done |
| FR-4 | On relaunch, a saved session resumes directly into the portal without re-login | Done |
| FR-5 | WebView loads `/web`, which Odoo itself routes correctly for both portal users (→ `/my`) and internal users (→ backend) | Done |
| FR-6 | User can manually reload the current page and sign out from a drawer menu | Done |
| FR-7 | App detects loss of connectivity before attempting network calls and shows a dedicated retry screen | Done |
| FR-8 | Native job card list/detail screens with stage actions | Planned |
| FR-9 | Native payment collection screen | Planned |
| FR-10 | Native WhatsApp send action | Planned |
| FR-11 | Push notification on order stage change | Planned — needs backend design |

## 5. Non-Functional Requirements

- **Security:** no credentials or tokens are stored in source control or logs; session cookie is the only persisted secret, stored via platform-secure local storage (`shared_preferences`, backed by Android's encrypted prefs / iOS Keychain-backed storage where applicable)
- **Compatibility:** must work against any Odoo 19 Community deployment with the `vm_tailor_*` addons installed, not just this business's own server
- **Authorization:** client performs no authorization logic of its own — all ACL/`ir.rule` enforcement is delegated to the Odoo server, consistent with the web portal's existing security model
- **Platform:** Android and iOS native apps (Flutter); no Linux/Windows/macOS desktop targets required

## 6. Platform Support & Known Constraints

| Platform | Status | Notes |
|---|---|---|
| **Android** | Working | Builds and installs via `flutter run` or sideloaded APK. Local emulator testing is not available in the current dev environment (no hardware virtualization exposed, and this Flutter/emulator version no longer supports ARM-on-x86 software translation) — verified instead via browser-based auth testing plus a real-device sideload path |
| **iOS** | Blocked | Building and signing an iOS app requires Xcode, which only runs on macOS. The current dev environment is Linux-only. Needs either a physical Mac or a cloud build service (e.g. Codemagic) plus an Apple Developer account before iOS work can start |
| **Web (browser)** | UI-preview only | Flutter can run the same codebase in a browser for layout/UI checks, but full login cannot be tested there: browsers block the session-cookie read (`Set-Cookie` is never exposed to page JavaScript) and Odoo's `/web/session/authenticate` route sends no CORS headers, so the real authentication flow only works in a true native app, not a browser |

## 7. Open Questions for Phase 2 Planning

- Which workflows are highest-priority for native screens — job cards, payments, WhatsApp, or something else?
- Is push notification infrastructure (FCM/APNs + an Odoo-side trigger) in scope, or deferred further?
- Target timeline and whether a physical Android device / Mac will be made available for proper device testing going forward
