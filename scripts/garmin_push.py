# /// script
# requires-python = ">=3.12"
# dependencies = ["garminconnect", "curl_cffi"]
# ///
"""Push one saved weigh-in to Garmin Connect: weight and BMI only.

usage: uv run scripts/garmin_push.py --db ~/health/health.db --push 2026-10-07T09:36:56

Reads tokens from ~/.garminconnect. Create them with scripts/garmin_login.py.
Fat, water, muscle, bone and BMR are not uploaded.
"""
import argparse, datetime as dt, json, sqlite3, sys
from pathlib import Path

TOKENS = Path.home() / ".garminconnect"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", required=True)
    ap.add_argument("--push", required=True, metavar="ISO_TS")
    a = ap.parse_args()
    if not TOKENS.is_dir() or not any(TOKENS.iterdir()):
        sys.exit(
            "No Garmin credentials in ~/.garminconnect.\n"
            "In a terminal, from this repo: uv run scripts/garmin_login.py\n"
            "That asks for your email and password and saves a token on this Mac. "
            "Do not commit that folder."
        )
    con = sqlite3.connect(a.db, timeout=30)
    row = con.execute(
        "select weight_kg, bmi, garmin_pushed_at from weighin where ts=?", (a.push,)
    ).fetchone()
    if not row:
        sys.exit(f"no weigh-in at {a.push}")
    weight, bmi, pushed = row
    if pushed:
        print(f"already pushed at {pushed}")
        return
    from garminconnect import Garmin
    g = Garmin()
    g.login(str(TOKENS))
    g.add_body_composition(a.push, weight=weight, bmi=bmi)
    fields = json.dumps({"weight": weight, "bmi": bmi})
    con.execute(
        "update weighin set garmin_pushed_at=?, garmin_fields=? where ts=?",
        (dt.datetime.now().isoformat(timespec="seconds"), fields, a.push),
    )
    con.commit()
    print("pushed to Garmin:", fields)

if __name__ == "__main__":
    main()
