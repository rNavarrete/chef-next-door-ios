"""Minimal App Store Connect API client, for the parts `altool` cannot do.

    python3 -m venv .venv && .venv/bin/pip install pyjwt cryptography
    .venv/bin/python Tools/asc.py status          # what is uploaded, and its state
    .venv/bin/python Tools/asc.py release 7       # attach testers to build 7

`altool` uploads an .ipa and stops there. It cannot tell you whether Apple
finished processing, and it cannot attach a build to testers — so every release
otherwise ends with a wait of unknown length followed by clicking through App
Store Connect.

## The key

Reads `~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8` to sign a
short-lived JWT. The .p8 never leaves this process and is never printed. The
Key ID and Issuer ID below are identifiers rather than secrets — they are
useless without the file, which is why they can live in the repo and it cannot.

Lived in a temp directory for seven builds and was deleted twice by whatever
prunes that directory, each time mid-release.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

KEY_ID = "YJRRK6UG6G"
ISSUER = "516f516d-e06d-4cdb-95b4-d8b13c741629"
APP_ID = "6795673262"
KEY_PATH = os.path.expanduser(f"~/.appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8")
BASE = "https://api.appstoreconnect.apple.com"


def token() -> str:
    now = int(time.time())
    with open(KEY_PATH) as f:
        private = f.read()
    return jwt.encode(
        {"iss": ISSUER, "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
        private,
        algorithm="ES256",
        headers={"kid": KEY_ID, "typ": "JWT"},
    )


def call(method: str, path: str, body=None):
    req = urllib.request.Request(
        f"{BASE}{path}",
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {token()}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code} on {method} {path}\n{e.read().decode()}", file=sys.stderr)
        raise


def builds():
    return call("GET", f"/v1/builds?filter[app]={APP_ID}&limit=10&sort=-version")["data"]


def find(version: str):
    for b in builds():
        if b["attributes"]["version"] == version:
            return b
    return None


def cmd_status():
    for b in builds():
        a = b["attributes"]
        print(f"  build {a['version']:>2}  {a['processingState']:<10} expires {(a.get('expirationDate') or '')[:10]}")


def cmd_wait(version: str, timeout_s: int = 900):
    """Apple takes five to fifteen minutes. Worth waiting rather than guessing."""
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        b = find(version)
        state = b["attributes"]["processingState"] if b else "absent"
        if state == "VALID":
            print(f"build {version} VALID ({b['id']})")
            return b
        print(f"  {state}…")
        time.sleep(15)
    raise SystemExit(f"build {version} not ready after {timeout_s}s")


def cmd_release(version: str, notes: str | None = None):
    b = cmd_wait(version)
    testers = call("GET", "/v1/betaTesters?limit=50")["data"]
    call("POST", f"/v1/builds/{b['id']}/relationships/individualTesters",
         {"data": [{"type": "betaTesters", "id": t["id"]} for t in testers]})
    print("attached:", ", ".join(t["attributes"]["email"] for t in testers))

    if notes:
        for loc in call("GET", f"/v1/builds/{b['id']}/betaBuildLocalizations")["data"]:
            call("PATCH", f"/v1/betaBuildLocalizations/{loc['id']}",
                 {"data": {"type": "betaBuildLocalizations", "id": loc["id"],
                           "attributes": {"whatsNew": notes}}})
        print(f"notes set ({len(notes)} chars)")


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] == "status":
        cmd_status()
    elif sys.argv[1] == "wait":
        cmd_wait(sys.argv[2])
    elif sys.argv[1] == "release":
        notes = open(sys.argv[3]).read() if len(sys.argv) > 3 else None
        cmd_release(sys.argv[2], notes)
    else:
        raise SystemExit(__doc__)
