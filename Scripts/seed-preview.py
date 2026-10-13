#!/usr/bin/env python3
"""Seed synthetic v2 notes and record optional native CI runtime evidence."""
import json
import os
import plistlib
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

BUNDLE_ID = "com.joaocosta.Scraps"


def seed(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    texts = [
        ("A little space for your thoughts\nA thought worth keeping.\n\nQuick ideas, close by.", "yellow"),
        ("Today, at a glance\n☐ Pick up the book\n☑ Take a little walk\n☐ Call a friend", "blue"),
        ("Weekend ideas\n• Make something\n• Find a new café\n• Leave room for a little surprise", "pink"),
    ]
    for index, (text, color) in enumerate(texts):
        identifier = str(uuid.uuid5(uuid.NAMESPACE_URL, f"scraps-preview/{index}")).upper()
        date = datetime.fromtimestamp(time.time() - index * 3600, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        first_line_length = len(text.split("\n")[0].encode("utf-16-le")) // 2
        sticky = {
            "id": identifier, "text": text, "createdAt": date, "updatedAt": date,
            "floatsOnTop": True, "color": color, "isCollapsed": False,
            "appearsOnAllSpaces": False,
            "richText": {"runs": [{"location": 0, "length": first_line_length, "bold": True, "italic": False}]},
            "frame": {"x": 100 + index * 300, "y": 250, "width": 280, "height": 300},
        }
        destination = directory / f"{identifier}.json"
        temporary = destination.with_suffix(".tmp")
        temporary.write_text(json.dumps({"version": 2, "sticky": sticky}, ensure_ascii=False), encoding="utf-8")
        temporary.replace(destination)
    return len(texts)


def preview(mac_app, ios_app, output):
    output = Path(output).resolve()
    output.mkdir(parents=True, exist_ok=True)
    report = {"recordedAt": datetime.now(timezone.utc).isoformat(),
              "macOS": {"status": "unavailable"}, "iOS": {"status": "unavailable"}}
    log = []

    def run(arguments, timeout=45, check=True):
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=timeout)
        log.append({"command": [str(arg) for arg in arguments], "exitCode": result.returncode, "stdout": result.stdout, "stderr": result.stderr})
        if check and result.returncode:
            raise RuntimeError(result.stderr.strip() or f"Command exited {result.returncode}")
        return result.stdout

    if os.environ.get("CI", "").lower() != "true":
        report["reason"] = "Preview seeding is restricted to ephemeral CI runners."
    elif sys.platform != "darwin":
        report["reason"] = "Apple runtime tools are unavailable on this operating system."
    else:
        simulator = None
        owns_boot = False
        try:
            devices = json.loads(run(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
            candidates = [device for runtime, values in devices.items() if "iOS-27" in runtime
                          for device in values if device.get("isAvailable") and device["name"].startswith("iPhone")]
            if not candidates:
                report["iOS"]["reason"] = "No available iPhone simulator with an iOS 27 runtime."
            else:
                chosen = sorted(candidates, key=lambda device: device.get("state") != "Booted")[0]
                simulator = chosen["udid"]
                if chosen.get("state") != "Booted":
                    run(["xcrun", "simctl", "boot", simulator])
                    owns_boot = True
                run(["xcrun", "simctl", "bootstatus", simulator, "-b"], timeout=60)
                run(["xcrun", "simctl", "install", simulator, str(Path(ios_app).resolve())])
                container = Path(run(["xcrun", "simctl", "get_app_container", simulator, BUNDLE_ID, "data"]).strip())
                count = seed(container / "Library/Application Support" / BUNDLE_ID / "Stickies")
                launch = run(["xcrun", "simctl", "launch", "--terminate-running-process", simulator, BUNDLE_ID])
                time.sleep(3)
                screenshot = output / "ios-library.png"
                run(["xcrun", "simctl", "io", simulator, "screenshot", str(screenshot)])
                report["iOS"] = {"status": "captured", "device": chosen["name"], "simulator": simulator,
                                 "seededNotes": count, "launch": launch.strip(), "screenshot": screenshot.name}
        except Exception as error:
            report["iOS"] = {"status": "failed", "reason": str(error)}
        finally:
            if simulator and owns_boot:
                try:
                    run(["xcrun", "simctl", "shutdown", simulator], check=False)
                except (OSError, subprocess.TimeoutExpired) as error:
                    report["iOS"]["shutdownError"] = str(error)

        try:
            mac_app = Path(mac_app).resolve()
            with (mac_app / "Contents/Info.plist").open("rb") as stream:
                info = plistlib.load(stream)
            signing = subprocess.run(["codesign", "-d", "--entitlements", "-", str(mac_app)], capture_output=True, timeout=15)
            entitlement_bytes = signing.stdout + signing.stderr
            start = entitlement_bytes.find(b"<?xml")
            end = entitlement_bytes.find(b"</plist>")
            entitlements = plistlib.loads(entitlement_bytes[start:end + len(b"</plist>")]) if start >= 0 and end >= 0 else {}
            sandboxed = entitlements.get("com.apple.security.app-sandbox", False) is True
            # Let the app create its sandbox container and welcome note itself.
            # A manually created container could interfere with first launch.
            run(["open", "-n", str(mac_app)])
            time.sleep(3)
            inspection = output / "inspect-windows.swift"
            inspection.write_text('''import CoreGraphics
import Foundation
let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
let windows = (entries ?? []).filter { ($0[kCGWindowOwnerName as String] as? String) == "Scraps" }
let floating = windows.filter { ($0[kCGWindowLayer as String] as? Int) == 3 }
let report: [String: Any] = ["windowServerAvailable": entries != nil, "onScreenWindows": windows.count, "floatingWindows": floating.count]
let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
''')
            measured = json.loads(run(["xcrun", "swift", str(inspection)], timeout=60))
            report["macOS"] = {"status": "observed" if measured["floatingWindows"] > 0 else "not-visible",
                               "bundle": info["CFBundleIdentifier"], "sandboxed": sandboxed, **measured}
        except Exception as error:
            report["macOS"] = {"status": "failed", "reason": str(error)}

    (output / "runtime.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    (output / "commands.json").write_text(json.dumps(log, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    if len(sys.argv) == 5 and sys.argv[1] == "--preview":
        preview(*sys.argv[2:])
    elif len(sys.argv) == 2:
        if os.environ.get("CI", "").lower() != "true":
            raise SystemExit("Synthetic note seeding is restricted to ephemeral CI runners.")
        print(f"Seeded {seed(sys.argv[1])} synthetic preview notes.")
    else:
        raise SystemExit("Usage: seed-preview.py <notes-directory> | --preview <Mac app> <Simulator app> <output>")
