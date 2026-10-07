# /// script
# requires-python = ">=3.12"
# dependencies = ["garminconnect", "curl_cffi"]
# ///
"""Create Garmin login tokens in ~/.garminconnect. Run this once, in a terminal.

The password is typed here and is not saved. What gets saved is a login token.
Never commit ~/.garminconnect, and never paste the token into the app or into git.
"""
import getpass
from pathlib import Path

from garminconnect import Garmin

dest = Path.home() / ".garminconnect"
email = input("Garmin email: ").strip()
password = getpass.getpass("Garmin password: ")
Garmin(email, password).login(str(dest))
print(f"Saved tokens in {dest}")
print("ScaleBar and `garmin_push.py` read that folder. They never see the password.")
