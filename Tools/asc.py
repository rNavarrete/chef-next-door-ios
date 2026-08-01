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
# "Friends and family". Testers belong to the group, not to a build — adding
# somebody once is permanent, and a release only has to hand the build over.
#
# Apple has an attribute for true auto-distribution, `hasAccessToAllBuilds`,
# but it is create-only and applies to *internal* groups (App Store Connect
# users). These testers are external email invitees, so every build still has
# to be handed to the group explicitly. That is the one call below.
GROUP_ID = "7527a524-723e-4274-b46c-f678d49459f4"
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
    call("POST", f"/v1/betaGroups/{GROUP_ID}/relationships/builds",
         {"data": [{"type": "builds", "id": b["id"]}]})
    members = call("GET", f"/v1/betaGroups/{GROUP_ID}/betaTesters")["data"]
    print(f"given to the group ({len(members)} testers):",
          ", ".join(t["attributes"]["email"] for t in members))

    # The step that was missing for six builds. Uploading, processing and
    # attaching testers all succeed without it, and the build appears in
    # TestFlight with an Install button — which then fails with "Your request
    # couldn't be completed". Nothing anywhere says the build was never
    # released; `externalBuildState` sits at READY_FOR_BETA_SUBMISSION and you
    # have to go looking for it.
    #
    # Builds 2 through 7 were all uploaded this way. Testers stayed on build 1.
    detail = call("GET", f"/v1/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
    if detail.get("externalBuildState") == "READY_FOR_BETA_SUBMISSION":
        try:
            r = call("POST", "/v1/betaAppReviewSubmissions",
                     {"data": {"type": "betaAppReviewSubmissions",
                               "relationships": {"build": {"data": {"type": "builds", "id": b["id"]}}}}})
            print("submitted for external testing:",
                  r["data"]["attributes"]["betaReviewState"])
        except urllib.error.HTTPError:
            print("!! submission refused — testers will NOT be able to install")
            raise
    else:
        print("external state:", detail.get("externalBuildState"))

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
