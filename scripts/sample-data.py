#!/usr/bin/env python3
"""Fill Firestore with fake sessions so the stats screen has something to show.

Generates sessions for the activity types in seed/activities.json over the past
N days (ending yesterday, so it never collides with a running timer). Each
activity gets its own typical amount per day and a trend up or down, so the
lines on the chart differ. Sessions within a day never overlap.

Sample sessions are tagged `sample: true`. Every run first deletes all existing
sample sessions, so re-running replaces them; `--delete` only deletes.
Your real sessions are never touched.

Usage:
  scripts/sample-data.py you@example.com            # 30 days
  scripts/sample-data.py you@example.com --days 120
  scripts/sample-data.py you@example.com --delete   # remove sample data
"""

import argparse
import datetime as dt
import getpass
import json
import plistlib
import random
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLIST = ROOT / "ios/ActivityTimers/GoogleService-Info.plist"


def request(url, body, token=None, headers=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req) as resp:
            return json.load(resp)
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        try:
            detail = json.loads(detail)["error"]["message"]
        except Exception:
            pass
        sys.exit(f"Request failed ({e.code}): {detail}")


def sign_in(config, email):
    password = getpass.getpass(f"Password for {email}: ")
    auth = request(
        "https://identitytoolkit.googleapis.com/v1/accounts:signInWithPassword"
        f"?key={config['API_KEY']}",
        {"email": email, "password": password, "returnSecureToken": True},
        headers={"X-Ios-Bundle-Identifier": config["BUNDLE_ID"]},
    )
    return auth["idToken"], auth["localId"]


def ts(d):
    return d.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def generate(type_ids, days, rng):
    """Returns [(doc_id, type_id, start, end)] in local time."""
    # Per-activity personality: typical minutes/day, how often it happens, and a
    # trend (multiplier goes from 1-trend at the start to 1+trend at the end).
    profiles = {
        t: {
            "minutes": rng.uniform(20, 110),
            "chance": rng.uniform(0.45, 0.95),
            "trend": rng.uniform(-0.7, 0.7),
        }
        for t in type_ids
    }
    today = dt.datetime.now().astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    sessions = []
    for i in range(days):
        day = today - dt.timedelta(days=days - i)
        progress = i / max(days - 1, 1)  # 0 at the oldest day, 1 at yesterday
        weekend = day.weekday() >= 5

        chunks = []  # (type_id, minutes)
        for t, p in profiles.items():
            if rng.random() > p["chance"]:
                continue
            factor = 1 + p["trend"] * (2 * progress - 1)
            if weekend:
                factor *= rng.uniform(0.6, 1.5)
            total = max(5, p["minutes"] * factor * rng.uniform(0.5, 1.5))
            parts = rng.randint(1, 3)
            for _ in range(parts):
                chunks.append((t, total / parts))
        rng.shuffle(chunks)

        # Lay the chunks out through the day, 7:00 to midnight, with gaps.
        cursor = day + dt.timedelta(hours=7, minutes=rng.randint(0, 90))
        day_end = day + dt.timedelta(hours=23, minutes=59)
        for n, (t, minutes) in enumerate(chunks):
            start = cursor
            end = start + dt.timedelta(minutes=minutes)
            if end > day_end:
                break
            sessions.append((f"sample-{day:%Y%m%d}-{n:02d}", t, start, end))
            cursor = end + dt.timedelta(minutes=rng.randint(5, 120))
    return sessions


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("email")
    parser.add_argument("--days", type=int, default=30)
    parser.add_argument("--seed", type=int, default=1, help="random seed (same seed = same data)")
    parser.add_argument("--delete", action="store_true", help="only delete existing sample sessions")
    parser.add_argument("--activities", default=str(ROOT / "seed/activities.json"))
    args = parser.parse_args()

    config = plistlib.loads(PLIST.read_bytes())
    project = config["PROJECT_ID"]
    token, uid = sign_in(config, args.email)

    root = f"projects/{project}/databases/(default)/documents"
    api = f"https://firestore.googleapis.com/v1/{root}"
    user_doc = f"{root}/users/{uid}"

    def batch_write(writes):
        # `:commit` (not `:batchWrite`, which rejects end-user credentials) is what
        # the client SDKs use, so it's checked against firestore.rules.
        for i in range(0, len(writes), 500):  # Firestore's per-commit limit
            request(f"{api}:commit", {"writes": writes[i:i + 500]}, token)

    # Delete existing sample sessions.
    found = request(
        f"https://firestore.googleapis.com/v1/{user_doc}:runQuery",
        {"structuredQuery": {
            "from": [{"collectionId": "sessions"}],
            "where": {"fieldFilter": {
                "field": {"fieldPath": "sample"}, "op": "EQUAL", "value": {"booleanValue": True},
            }},
            "select": {"fields": [{"fieldPath": "__name__"}]},
        }},
        token,
    )
    old = [r["document"]["name"] for r in found if "document" in r]
    batch_write([{"delete": name} for name in old])
    print(f"Deleted {len(old)} existing sample sessions.")
    if args.delete:
        return

    type_ids = [t["id"] for t in json.loads(Path(args.activities).read_text())["activityTypes"]]
    sessions = generate(type_ids, args.days, random.Random(args.seed))
    batch_write([
        {"update": {
            "name": f"{user_doc}/sessions/{doc_id}",
            "fields": {
                "activityTypeId": {"stringValue": t},
                "startedAt": {"timestampValue": ts(start)},
                "endedAt": {"timestampValue": ts(end)},
                "sample": {"booleanValue": True},
            },
        }}
        for doc_id, t, start, end in sessions
    ])
    print(f"Wrote {len(sessions)} sample sessions over {args.days} days for users/{uid}.")


if __name__ == "__main__":
    main()
