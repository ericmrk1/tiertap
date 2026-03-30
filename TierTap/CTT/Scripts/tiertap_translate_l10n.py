#!/usr/bin/env python3
"""
Machine-translate Strings.json: fills any locale column that still matches English.

  cd CTT && python3 -m venv scripts/.venv && scripts/.venv/bin/pip install deep-translator
  scripts/.venv/bin/python -u scripts/tiertap_translate_l10n.py [--throttle 0.05]

Dedupes identical (target language, English source) so shared phrases translate once.
Safe to re-run: skips cells where translation already differs from English.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from collections import defaultdict
from pathlib import Path

CTT = Path(__file__).resolve().parent.parent
STRINGS_JSON = CTT / "TierTap" / "Localization" / "Strings.json"

LANG_MAP = {
    "zh-Hans": "zh-CN",
    "ja": "ja",
    "vi": "vi",
    "es": "es",
    "ar": "ar",
    "he": "iw",
    "de": "de",
    "fr": "fr",
    "hi": "hi",
}


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


def write_json(data: dict, path: Path) -> None:
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--throttle", type=float, default=0.05, help="Seconds after each API call")
    args = parser.parse_args()

    try:
        from deep_translator import GoogleTranslator
    except ImportError:
        print("Install: python3 -m venv scripts/.venv && scripts/.venv/bin/pip install deep-translator", file=sys.stderr)
        raise SystemExit(1)

    translators = {
        catalog: GoogleTranslator(source="en", target=gcode)
        for catalog, gcode in LANG_MAP.items()
    }

    data: dict[str, dict[str, str]] = json.loads(STRINGS_JSON.read_text(encoding="utf-8"))

    # (catalog_code, english) -> [ui keys that need this cell filled]
    groups: dict[tuple[str, str], list[str]] = defaultdict(list)
    for key, row in data.items():
        en = (row.get("en") or "").strip()
        if not en:
            continue
        for catalog_code in LANG_MAP:
            cur = row.get(catalog_code)
            if cur is None or cur == en:
                groups[(catalog_code, en)].append(key)

    jobs = list(groups.items())
    print(f"Unique translation jobs: {len(jobs)} (covers {sum(len(v) for _, v in jobs)} cells)", flush=True)

    for idx, ((catalog_code, en), keys) in enumerate(jobs):
        translator = translators[catalog_code]
        translated = translate_with_retries(translator, en)
        for k in keys:
            data[k][catalog_code] = translated
        if args.throttle:
            time.sleep(args.throttle)
        if (idx + 1) % 25 == 0:
            write_json(data, STRINGS_JSON)
            print(f"checkpoint {idx + 1}/{len(jobs)}", flush=True)

    write_json(data, STRINGS_JSON)
    print(f"Wrote {STRINGS_JSON}", flush=True)


if __name__ == "__main__":
    main()
