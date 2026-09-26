#!/usr/bin/env python3
"""Uploads an .aab to the Play Console's app bundle library, without
touching any release track.

Play Console itself doesn't expose "just upload, don't release" as an
action - every path through the UI attaches a bundle to a track. The Play
Developer API does support it though: open an edit, upload the bundle,
commit the edit, and stop there. The result shows up under Release > App
bundle explorer and nowhere else - nothing goes out to testers or
production until it's promoted to a track by hand, whenever that's wanted.

Needs:
  GOOGLE_PLAY_PACKAGE_NAME             e.g. dev.ayushya.noo
  GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH  path to a service account key file

The Play Developer API can't create an app's first release - Google
requires at least one manual upload through the Play Console web UI (to
any track) before it'll accept API calls for that app at all.

  python3 tool/upload_play_bundle.py path/to/app-release.aab
"""
import os
import sys

from google.oauth2 import service_account
from googleapiclient.discovery import build

SCOPES = ["https://www.googleapis.com/auth/androidpublisher"]


def main(bundle_path):
    package_name = os.environ["GOOGLE_PLAY_PACKAGE_NAME"]
    key_path = os.environ["GOOGLE_PLAY_SERVICE_ACCOUNT_JSON_PATH"]
    creds = service_account.Credentials.from_service_account_file(
        key_path, scopes=SCOPES
    )
    service = build("androidpublisher", "v3", credentials=creds)

    edit_id = service.edits().insert(body={}, packageName=package_name).execute()["id"]

    bundle = (
        service.edits()
        .bundles()
        .upload(editId=edit_id, packageName=package_name, media_body=bundle_path)
        .execute()
    )
    print("Uploaded versionCode %s" % bundle["versionCode"])

    service.edits().commit(editId=edit_id, packageName=package_name).execute()
    print(
        "Committed - visible under Release > App bundle explorer in Play "
        "Console. Not attached to any track, so nothing goes out to "
        "testers or production until it's promoted by hand."
    )


if __name__ == "__main__":
    main(sys.argv[1])
