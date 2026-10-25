#!/usr/bin/env python3
"""Checks that every L("...") key in the Swift sources is translated into every app language.

Usage: scripts/localization.py check      exit 1 on missing or stale keys
       scripts/localization.py keys       print the keys found in the sources
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "NotiForward"
CATALOG = SOURCES / "Resources" / "Localizable.xcstrings"
LANGUAGES = ["en", "zh-Hans", "zh-Hant", "ja", "ko", "de", "fr", "es", "it", "pt-BR"]

# L("text") and L("text \(value)"); interpolations become %@ in the catalog key.
CALL = re.compile(r'\bL\("((?:[^"\\]|\\.|\\\((?:[^()]|\([^()]*\))*\))*)"\)')
INTERPOLATION = re.compile(r'\\\((?:[^()]|\([^()]*\))*\)')


def source_keys():
    keys = set()
    for path in SOURCES.rglob("*.swift"):
        for match in CALL.finditer(path.read_text()):
            keys.add(INTERPOLATION.sub("%@", match.group(1)).replace('\\"', '"'))
    return keys


def check():
    strings = json.loads(CATALOG.read_text())["strings"]
    keys = source_keys()
    problems = []
    for key in sorted(keys):
        localizations = strings.get(key, {}).get("localizations", {})
        missing = [lang for lang in LANGUAGES if lang != "en"
                   and localizations.get(lang, {}).get("stringUnit", {}).get("state") != "translated"]
        if key not in strings:
            problems.append(f"missing key: {key!r}")
        elif missing:
            problems.append(f"untranslated {key!r}: {', '.join(missing)}")
        else:
            for lang in LANGUAGES[1:]:
                value = localizations[lang]["stringUnit"]["value"]
                if key.count("%@") != value.count("%@"):
                    problems.append(f"placeholder mismatch {key!r} [{lang}]: {value!r}")
    for key in sorted(set(strings) - keys):
        problems.append(f"stale key: {key!r}")
    for problem in problems:
        print(f"  ✗ {problem}")
    if problems:
        return 1
    print(f"  {len(keys)} strings × {len(LANGUAGES)} languages OK")
    return 0


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else "check"
    if command == "keys":
        print("\n".join(sorted(source_keys())))
    else:
        sys.exit(check())
