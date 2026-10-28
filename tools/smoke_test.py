#!/usr/bin/env python3
"""Read-only smoke test of the server calls the mobile app makes.

Walks the same flow as the app against a real Odoo server: database list,
login, session info, installed apps (menus), and for every app its action,
views (list/kanban, search, form), a page of records and one record read.
Nothing is created, written or deleted.

Usage:
    python3 tools/smoke_test.py https://yourserver.example.com DB LOGIN
The password is read from the ODOO_PASSWORD environment variable or prompted.
"""

import getpass
import http.cookiejar
import json
import os
import sys
import urllib.request
import xml.etree.ElementTree as ET

TRUE = {"1", "True", "true"}


class Client:
    def __init__(self, server):
        self.server = server.rstrip("/")
        self.jar = http.cookiejar.CookieJar()
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(self.jar))
        self.context = {}

    def post(self, path, params):
        body = json.dumps({"jsonrpc": "2.0", "method": "call", "params": params}).encode()
        req = urllib.request.Request(self.server + path, body, {"Content-Type": "application/json"})
        with self.opener.open(req, timeout=60) as resp:
            data = json.loads(resp.read().decode())
        if data.get("error"):
            err = data["error"].get("data") or {}
            raise RuntimeError(f"{err.get('name', '')}: {err.get('message') or data['error'].get('message')}")
        return data.get("result")

    def call_kw(self, model, method, args=(), kwargs=None, context=None):
        kwargs = dict(kwargs or {})
        kwargs["context"] = {**self.context, **(context or {})}
        return self.post(f"/web/dataset/call_kw/{model}/{method}",
                         {"model": model, "method": method, "args": list(args), "kwargs": kwargs})


def card_fields(arch):
    """Same rules as parseCardFields in lib/odoo/view_arch.dart."""
    out, seen = [], set()

    def walk(el):
        for child in el:
            if child.tag == "field":
                name = child.get("name")
                hidden = (child.get("invisible") in TRUE or child.get("column_invisible") in TRUE
                          or child.get("optional") == "hide" or child.get("widget") == "handle")
                if name and not hidden and name not in seen:
                    seen.add(name)
                    out.append(name)
            elif child.tag not in ("header", "control", "button"):
                walk(child)

    walk(ET.fromstring(arch))
    return out


def form_fields(arch):
    """Top-level field names of a form (not inside relational sub-views)."""
    names = set()

    def walk(el):
        for child in el:
            if child.tag == "field":
                if child.get("name"):
                    names.add(child.get("name"))
            else:
                walk(child)

    walk(ET.fromstring(arch))
    return names


def walk_menus(menus, menu_id, path=""):
    m = menus[str(menu_id)]
    full = f"{path} / {m['name']}" if path else m["name"]
    if m.get("actionID"):
        yield m, full
    for child in m.get("children", []):
        if str(child) in menus:
            yield from walk_menus(menus, child, full)


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    server, db, login = sys.argv[1:]
    password = os.environ.get("ODOO_PASSWORD") or getpass.getpass("Password: ")
    c = Client(server)
    ok = fail = 0

    def check(label, fn):
        nonlocal ok, fail
        try:
            result = fn()
            ok += 1
            print(f"  OK    {label}" + (f" — {result}" if result else ""))
            return True
        except Exception as e:  # noqa: BLE001 - report every failure and keep going
            fail += 1
            print(f"  FAIL  {label} — {e}")
            return False

    print(f"Server {c.server}")
    check("database list", lambda: c.post("/web/database/list", {}))
    if not check("authenticate", lambda: c.post("/web/session/authenticate",
                                                {"db": db, "login": login, "password": password}).get("uid")):
        sys.exit(1)

    info = c.post("/web/session/get_session_info", {})
    c.context = dict(info.get("user_context") or {})
    companies = info.get("user_companies") or {}
    if isinstance(companies.get("current_company"), int):
        c.context["allowed_company_ids"] = [companies["current_company"]]
    print(f"  OK    session info — {info.get('name')} (uid {info.get('uid')}), "
          f"server {info.get('server_version')}")

    menus = c.call_kw("ir.ui.menu", "load_web_menus", [False])
    apps = [menus[str(i)] for i in menus["root"]["children"] if str(i) in menus]
    print(f"  OK    menus — {len(apps)} apps: {', '.join(a['name'] for a in apps)}")

    for app in apps:
        first = next(walk_menus(menus, app["id"]), None)
        print(f"\n[{app['name']}] icon: {'data' if app.get('webIconData') else app.get('webIcon') or 'none'}")
        if not first:
            print("  --    no menu with an action")
            continue
        menu, path = first
        try:
            action = c.post("/web/action/load", {"action_id": menu["actionID"], "context": c.context})
        except Exception as e:  # noqa: BLE001
            fail += 1
            print(f"  FAIL  action for {path} — {e}")
            continue
        model = action.get("res_model")
        if action.get("type") != "ir.actions.act_window" or not model:
            print(f"  --    {path}: {action.get('type')} → web client fallback")
            continue
        views = [[v[0], "list" if v[1] == "tree" else v[1]] for v in action.get("views") or []]
        types = [v[1] for v in views]
        print(f"  ..    {path}: {model}, views {types}, domain {action.get('domain')!r}")
        if views and types[0] == "form" or action.get("res_id"):
            print("  --    opens a form directly")
        card = "list" if "list" in types else ("kanban" if "kanban" in types else None)
        if not card:
            print("  --    no list/kanban → web client fallback")
            continue
        ids = {t: i for i, t in views}
        state = {}

        def load_views():
            res = c.call_kw(model, "get_views",
                            [[[ids.get(card) or False, card], [ids.get("search") or False, "search"],
                              [ids.get("form") or False, "form"]]],
                            {"options": {"toolbar": False, "load_filters": False}})
            info_ = res["models"][model]
            state["fields"] = info_["fields"] if isinstance(info_.get("fields"), dict) else info_
            state["archs"] = {k: v["arch"] for k, v in res["views"].items()}
            state["cards"] = [f for f in card_fields(state["archs"][card]) if f in state["fields"]]
            return f"{len(state['fields'])} fields, card fields {state['cards'][:6]}"

        if not check("get_views", load_views):
            continue

        def search():
            domain = action.get("domain")
            domain = domain if isinstance(domain, list) else []
            rows = c.call_kw(model, "search_read", [],
                             {"domain": domain, "fields": ["display_name"] + state["cards"], "limit": 5})
            state["rows"] = rows
            return f"{len(rows)} records, first: {rows[0]['display_name'] if rows else '-'}"

        if not check("search_read", search) or not state["rows"]:
            continue

        def read_form():
            names = [n for n in form_fields(state["archs"]["form"])
                     if n in state["fields"] and state["fields"][n]["type"] != "binary"]
            rec = c.call_kw(model, "read", [[state["rows"][0]["id"]]], {"fields": names})
            return f"{len(names)} fields read"

        check("read form record", read_form)

    print(f"\n{ok} OK, {fail} failed")
    sys.exit(1 if fail else 0)


if __name__ == "__main__":
    main()
