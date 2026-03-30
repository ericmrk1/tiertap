#!/usr/bin/env python3
"""
Extract unique UI string literals from TierTap Swift sources and build
TierTap/Localization/Strings.json (hash keys -> per-locale strings).

Usage (from CTT):
  python3 scripts/tiertap_extract_l10n.py

Locales match AppLanguage.catalogCode in TierTapLocalization.swift.
"""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

CTT = Path(__file__).resolve().parent.parent
TIER_TAP = CTT / "TierTap"
WATCH_APP = CTT / "TierTap Watch App"
OUT_JSON = TIER_TAP / "Localization" / "Strings.json"

# Must match AppLanguage.catalogCode values
LANG_ORDER = [
    "en",
    "zh-Hans",
    "ja",
    "vi",
    "es",
    "ar",
    "he",
    "de",
    "fr",
    "hi",
]


def ui_key(english: str) -> str:
    h = hashlib.sha256(english.encode("utf-8")).hexdigest()[:24]
    return f"ui.{h}"


def extract_literals(roots: list[Path]) -> list[str]:
    patterns = [
        re.compile(r'Text\(\s*"((?:\\.|[^"\\])*)"\s*[,)]'),
        re.compile(r'Label\(\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'navigationTitle\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
        re.compile(r'navigationBarTitle\(\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'Button\(\s*"((?:\\.|[^"\\])*)"\s*[,)]'),
        re.compile(r'\.alert\(\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'placeholder:\s*"((?:\\.|[^"\\])*)"\s*'),
        re.compile(r'title:\s*"((?:\\.|[^"\\])*)"\s*[,)]\s*systemImage:'),
        re.compile(r'Section\(\s*header:\s*\{\s*Text\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
        re.compile(r'L10nText\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
        re.compile(r'LocalizedLabel\(\s*title:\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'\.localizedNavigationTitle\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    ]
    found: set[str] = set()
    for root in roots:
        if not root.exists():
            continue
        for path in sorted(root.rglob("*.swift")):
            if "Localization" in path.parts:
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            for pat in patterns:
                for m in pat.finditer(text):
                    s = (
                        m.group(1)
                        .replace(r"\"", '"')
                        .replace(r"\\", "\\")
                        .replace(r"\n", "\n")
                        .replace(r"\t", "\t")
                    )
                    if "\\(" in s:
                        continue
                    if not s.strip():
                        continue
                    if len(s) > 800:
                        continue
                    found.add(s)
    return sorted(found)


def main() -> None:
    roots = [TIER_TAP]
    if WATCH_APP.exists():
        roots.append(WATCH_APP)
    literals = extract_literals(roots)
    table: dict[str, dict[str, str]] = {}
    for en in literals:
        row = {lang: en for lang in LANG_ORDER}
        table[ui_key(en)] = row
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(table, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {OUT_JSON} with {len(table)} keys from {len(literals)} unique literals")


if __name__ == "__main__":
    main()
