#!/usr/bin/env python3
"""Validate the shipped translations and Siri phrases without launching the app."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STRING = r'"(?:[^"\\]|\\.)*"'
ENTRY = re.compile(rf'({STRING})\s*=\s*({STRING})\s*;')
SPACE = re.compile(r'(?:\s+|/\*.*?\*/|//[^\n]*)*', re.DOTALL)
FORMAT = re.compile(r'%(?!%)(?:\d+\$)?(?:[-+ #0]*\d*(?:\.\d+)?)(?:hh|h|ll|l|z|t|j)?[@diuoxXfFeEgGaAcCsSp]')


def read_strings(path):
    source = path.read_text(encoding="utf-8")
    entries = {}
    position = 0
    while position < len(source):
        position = SPACE.match(source, position).end()
        if position == len(source):
            break
        entry = ENTRY.match(source, position)
        assert entry, f"Malformed .strings entry at {path}:{source[:position].count(chr(10)) + 1}"
        key, value = (json.loads(part) for part in entry.groups())
        assert key not in entries, f"Duplicate translation key in {path}: {key}"
        entries[key] = value
        position = entry.end()
    return entries


def placeholders(value):
    return sorted(re.sub(r'^%\d+\$', '%', part) for part in FORMAT.findall(value))


resources = sorted(ROOT.glob("App/*/Resources/en.lproj/Localizable.strings"))
resources += sorted(ROOT.glob("Packages/StickyKit/Sources/*/Resources/en.lproj/Localizable.strings"))
assert resources, "Missing English fallback resources"
count = 0
for fallback in resources:
    reference = read_strings(fallback)
    assert reference, f"Empty English resources: {fallback}"
    for translated in sorted(fallback.parent.parent.glob("*.lproj/Localizable.strings")):
        entries = read_strings(translated)
        assert entries.keys() == reference.keys(), f"Translation keys differ in {translated}"
        for key, value in entries.items():
            assert value.strip(), f"Empty translation in {translated}: {key}"
            assert placeholders(value) == placeholders(reference[key]), f"Format placeholders differ in {translated}: {key}"
        count += 1

for target in ("Scraps", "ScrapsMobile"):
    resource_root = ROOT / "App" / target / "Resources"
    fallback = read_strings(resource_root / "en.lproj/AppShortcuts.strings")
    for path in sorted(resource_root.glob("*.lproj/AppShortcuts.strings")):
        entries = read_strings(path)
        assert entries.keys() == fallback.keys(), f"Siri phrase keys differ in {path}"
        assert len(entries) == 4, f"Expected four Siri phrases in {path}"
        for key, phrase in entries.items():
            assert key.count("${applicationName}") == phrase.count("${applicationName}") == 1, f"Missing app-name token in {path}: {key}"
    for locale in ("en", "pt-BR"):
        assert (resource_root / f"{locale}.lproj/AppShortcuts.strings").is_file()

print(f"Validated {count} localization tables and Siri phrases for both app targets.")
