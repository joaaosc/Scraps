#!/usr/bin/env python3
"""Check the built Mac bundle's privacy declarations and Spotlight metadata."""
import json
import plistlib
import sys
from pathlib import Path

bundle = Path(sys.argv[1])
contents = bundle / "Contents"
with (contents / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
assert info["CFBundleIdentifier"] == "com.joaocosta.Scraps"
assert info["CFBundleIconName"] == "AppIcon"
privacy_files = list(contents.rglob("PrivacyInfo.xcprivacy"))
assert privacy_files, "Missing privacy manifest"
with privacy_files[0].open("rb") as stream:
    privacy = plistlib.load(stream)
assert privacy["NSPrivacyTracking"] is False
assert privacy["NSPrivacyCollectedDataTypes"] == []
metadata = contents / "Resources/Metadata.appintents/extract.actionsdata"
assert metadata.exists(), "Missing App Intents metadata; use a clean build"
data = json.loads(metadata.read_text())
serialized = json.dumps(data)
assert "StickyActionEntity" in serialized or "StickyAction" in serialized, "Missing action entity"
assert "OpenStickyActionIntent" in serialized, "Missing action opening intent"
assert "NewStickyIntent" in serialized and "ShowStickiesIntent" in serialized
print("Privacy, icon and action metadata are present.")
