#!/usr/bin/env python3
"""Resolve build-setting placeholders for validation signatures."""
import argparse
import plistlib
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('source', type=Path)
parser.add_argument('destination', type=Path)
parser.add_argument('--configuration', choices=('Debug', 'Release'), required=True)
parser.add_argument('--team', required=True)
args = parser.parse_args()
settings = {
    'DEVELOPMENT_TEAM': args.team,
    'ICLOUD_ENVIRONMENT': 'Production' if args.configuration == 'Release' else 'Development',
    'APS_ENVIRONMENT': 'production' if args.configuration == 'Release' else 'development',
}

def resolve(value):
    if isinstance(value, str):
        for key, replacement in settings.items():
            value = value.replace(f'$({key})', replacement)
        if '$(' in value:
            raise SystemExit(f'Unresolved build setting: {value}')
        return value
    if isinstance(value, list):
        return [resolve(item) for item in value]
    if isinstance(value, dict):
        return {key: resolve(item) for key, item in value.items()}
    return value

args.destination.parent.mkdir(parents=True, exist_ok=True)
args.destination.write_bytes(plistlib.dumps(resolve(plistlib.loads(args.source.read_bytes()))))
