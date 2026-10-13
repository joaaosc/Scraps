#!/usr/bin/env python3
"""Check native bundle resources, effective entitlements and intent metadata."""
import argparse
import json
import plistlib
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("bundle", type=Path)
parser.add_argument("--release", action="store_true", help="Reject debugging entitlements")
parser.add_argument("--distribution", action="store_true", help="Require an Apple Distribution signature")
args = parser.parse_args()
bundle = args.bundle
is_mac = (bundle / "Contents").is_dir()
contents = bundle / "Contents" if is_mac else bundle
resources = contents / "Resources" if is_mac else contents


def require(condition, message):
    if not condition:
        raise SystemExit(message)


with (contents / "Info.plist").open("rb") as stream:
    info = plistlib.load(stream)
require(info.get("CFBundleIdentifier") == "com.joaocosta.Scraps", "Unexpected bundle identifier")
icon = info.get("CFBundleIconName") if is_mac else info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {}).get("CFBundleIconName")
require(icon == "AppIcon", "Missing app icon")
require(info.get("ITSAppUsesNonExemptEncryption") is False, "Missing export-compliance declaration")
require(set(info.get("CFBundleLocalizations", [])) >= {"en", "pt-BR"}, "Missing declared languages")
for language in ("en", "pt-BR"):
    for table in ("Localizable.strings", "AppShortcuts.strings"):
        require((resources / f"{language}.lproj" / table).is_file(), f"Missing {language}/{table}")
privacy_files = list(contents.rglob("PrivacyInfo.xcprivacy"))
require(privacy_files, "Missing privacy manifest")
with (resources / "PrivacyInfo.xcprivacy").open("rb") as stream:
    privacy = plistlib.load(stream)
require(privacy.get("NSPrivacyTracking") is False, "Unexpected tracking declaration")
require(privacy.get("NSPrivacyCollectedDataTypes") == [], "Unexpected collected-data declaration")
reasons = {item["NSPrivacyAccessedAPIType"]: item["NSPrivacyAccessedAPITypeReasons"] for item in privacy.get("NSPrivacyAccessedAPITypes", [])}
require(reasons.get("NSPrivacyAccessedAPICategoryUserDefaults") == ["CA92.1"], "Missing UserDefaults required reason")
metadata = resources / "Metadata.appintents/extract.actionsdata"
require(metadata.exists(), "Missing App Intents metadata; use a clean build")
data = json.loads(metadata.read_text())
serialized = json.dumps(data)
require("StickyActionEntity" in serialized or "StickyAction" in serialized, "Missing action entity")
require("OpenStickyActionIntent" in serialized, "Missing action opening intent")
require("NewStickyIntent" in serialized and "ShowStickiesIntent" in serialized, "Missing shortcut intents")
require("com.joaocosta.Scraps.edit" in info.get("NSUserActivityTypes", []), "Missing Handoff declaration")
require(any("scraps" in item.get("CFBundleURLSchemes", []) for item in info.get("CFBundleURLTypes", [])), "Missing note URL scheme")
require(list(contents.rglob("default.metallib")), "Missing compiled Metal shader library")
widget = contents / "PlugIns/ScrapsWidgets.appex"
widget_contents = widget / "Contents" if is_mac else widget
require(widget_contents.is_dir(), "Missing embedded widget extension")
with (widget_contents / "Info.plist").open("rb") as stream:
    widget_info = plistlib.load(stream)
require(widget_info.get("CFBundleIdentifier") == "com.joaocosta.Scraps.widgets", "Unexpected widget identifier")
require(widget_info.get("CFBundleVersion") == info.get("CFBundleVersion"), "Widget build does not match app")
require(widget_info.get("CFBundleShortVersionString") == info.get("CFBundleShortVersionString"), "Widget version does not match app")
require(widget_info.get("NSExtension", {}).get("NSExtensionPointIdentifier") == "com.apple.widgetkit-extension", "Missing WidgetKit declaration")
widget_resources = widget_contents / "Resources" if is_mac else widget_contents
for language in ("en", "pt-BR"):
    require((widget_resources / f"{language}.lproj/Localizable.strings").is_file(), f"Missing widget language {language}")
require((widget_resources / "PrivacyInfo.xcprivacy").is_file(), "Missing widget privacy manifest")
if not is_mac:
    require("remote-notification" in info.get("UIBackgroundModes", []), "Missing background CloudKit notifications")

if is_mac or args.distribution:
    signature = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(bundle)], check=True, capture_output=True)
    entitlements = plistlib.loads(signature.stdout)
    if is_mac:
        require(entitlements.get("com.apple.security.app-sandbox") is True, "Mac product is not sandboxed")
    require("iCloud.com.joaocosta.Scraps" in entitlements.get("com.apple.developer.icloud-container-identifiers", []), "Missing private CloudKit container")
    require("CloudKit" in entitlements.get("com.apple.developer.icloud-services", []), "Missing CloudKit entitlement")
    require(entitlements.get("com.apple.developer.icloud-container-environment") == ("Production" if args.release or args.distribution else "Development"), "Unexpected CloudKit environment")
    push_key = "com.apple.developer.aps-environment" if is_mac else "aps-environment"
    require(entitlements.get(push_key) == ("production" if args.release or args.distribution else "development"), "Unexpected push environment")
    groups = entitlements.get("com.apple.security.application-groups", [])
    require(any(group.endswith(".com.joaocosta.Scraps") for group in groups), "Missing app group")
    widget_signature = subprocess.run(["codesign", "-d", "--entitlements", "-", "--xml", str(widget)], check=True, capture_output=True)
    widget_entitlements = plistlib.loads(widget_signature.stdout)
    require(set(groups) & set(widget_entitlements.get("com.apple.security.application-groups", [])), "App and widgets do not share a group")
    if is_mac:
        require(widget_entitlements.get("com.apple.security.app-sandbox") is True, "Widget is not sandboxed")
    if args.release or args.distribution:
        require(not widget_entitlements.get("com.apple.security.get-task-allow") and not widget_entitlements.get("get-task-allow"), "Release widget permits debugging")
        require(not entitlements.get("com.apple.security.get-task-allow") and not entitlements.get("get-task-allow"), "Release product permits debugging")
    if args.distribution:
        details = subprocess.run(["codesign", "-d", "--verbose=4", str(bundle)], check=True, capture_output=True, text=True)
        require("Authority=Apple Distribution:" in details.stderr, "Missing Apple Distribution signature")
print("Privacy, languages, icon, widgets, Metal, CloudKit entitlements and action metadata verified.")
