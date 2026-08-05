#!/usr/bin/env python3
"""
Translate only TierTap User Guide strings in Strings.json (cells where locale still equals English).

  cd CTT && scripts/.venv/bin/python scripts/tiertap_translate_user_guide_l10n.py [--throttle 0.05]

Requires: pip install deep-translator (same venv as tiertap_translate_l10n.py)
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from collections import defaultdict
from pathlib import Path

CTT = Path(__file__).resolve().parent.parent
STRINGS_JSON = CTT / "TierTap" / "Localization" / "Strings.json"
TIER_TAP = CTT / "TierTap"

LANG_MAP = {
    "zh-Hans": "zh-CN",
    "ja": "ja",
    "ko": "ko",
    "vi": "vi",
    "es": "es",
    "ar": "ar",
    "he": "iw",
    "de": "de",
    "fr": "fr",
    "hi": "hi",
}


def ui_key(english: str) -> str:
    h = hashlib.sha256(english.encode("utf-8")).hexdigest()[:24]
    return f"ui.{h}"


def user_guide_english_strings() -> set[str]:
    found: set[str] = set()
    paths = [
        TIER_TAP / "Views/UserGuideContent.swift",
        TIER_TAP / "Views/UserGuideView.swift",
    ]
    patterns = [
        re.compile(r'\bloc\(\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'L10n\.tr\(\s*"((?:\\.|[^"\\])*)"\s*,'),
        re.compile(r'L10nText\(\s*"((?:\\.|[^"\\])*)"\s*\)'),
    ]
    for path in paths:
        if not path.exists():
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
                if s.strip():
                    found.add(s)
    return found


def translate_with_retries(translator, text: str, attempts: int = 4) -> str:
    delay = 1.5
    last_exc: Exception | None = None
    for i in range(attempts):
        try:
            out = translator.translate(text)
            return (out or text).strip()
        except Exception as e:
            last_exc = e
            if i < attempts - 1:
                time.sleep(delay)
                delay = min(delay * 2, 30)
    print(f"  failed: {last_exc}", flush=True)
    return text


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--throttle", type=float, default=0.05, help="Seconds after each API call")
    args = parser.parse_args()

    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print(
            "Install: python3 -m venv scripts/.venv && scripts/.venv/bin/pip install deep-translator",
            file=sys.stderr,
        )
        raise SystemExit(1)

    english_set = user_guide_english_strings()
    guide_keys = {ui_key(s) for s in english_set}
    print(f"User guide English strings: {len(english_set)} → {len(guide_keys)} keys", flush=True)

    data: dict[str, dict[str, str]] = json.loads(STRINGS_JSON.read_text(encoding="utf-8"))

    translators = {
        catalog: GoogleTranslator(source="en", target=gcode)
        for catalog, gcode in LANG_MAP.items()
    }

    # (catalog_code, english) -> [ui keys that need this cell filled]
    groups: dict[tuple[str, str], list[str]] = defaultdict(list)
    for key in guide_keys:
        row = data.get(key)
        if not row:
            continue
        en = (row.get("en") or "").strip()
        if not en:
            continue
        for catalog_code in LANG_MAP:
            cur = row.get(catalog_code)
            if cur is None or cur == en:
                groups[(catalog_code, en)].append(key)

    jobs = list(groups.items())
    print(f"User guide translation jobs: {len(jobs)} (cells)", flush=True)

    for idx, ((catalog_code, en), keys) in enumerate(jobs):
        translator = translators[catalog_code]
        translated = translate_with_retries(translator, en)
        for k in keys:
            data[k][catalog_code] = translated
        if args.throttle:
            time.sleep(args.throttle)
        if (idx + 1) % 40 == 0:
            STRINGS_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
            print(f"checkpoint {idx + 1}/{len(jobs)}", flush=True)

    STRINGS_JSON.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {STRINGS_JSON}", flush=True)


if __name__ == "__main__":
    main()
