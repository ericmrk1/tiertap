#!/usr/bin/env python3
"""
Replace static SwiftUI strings with L10nText / LocalizedLabel / localizedNavigationTitle.
Run from CTT:  python3 scripts/tiertap_apply_l10n.py
Then:         python3 scripts/tiertap_extract_l10n.py
"""
from __future__ import annotations

import re
from pathlib import Path

CTT = Path(__file__).resolve().parent.parent
TIER_TAP = CTT / "TierTap"
WATCH_APP = CTT / "TierTap Watch App"


def transform(s: str) -> str:
    # Label("Title", systemImage: "icon")
    s = re.sub(
        r'Label\(\s*"((?:\\.|[^"])*)"\s*,\s*systemImage:\s*"([^"]+)"\s*\)',
        r'LocalizedLabel(title: "\1", systemImage: "\2")',
        s,
    )

    # .navigationTitle("Title")
    s = re.sub(
        r'\.navigationTitle\(\s*"((?:\\.|[^"])*)"\s*\)',
        r'.localizedNavigationTitle("\1")',
        s,
    )

    def text_repl(m: re.Match[str]) -> str:
        inner = m.group(1)
        if "\\(" in inner:
            return m.group(0)
        return f'L10nText("{inner}")'

    s = re.sub(r'Text\(\s*"((?:\\.|[^"])*)"\s*\)', text_repl, s)
    return s


def main() -> None:
    roots = [TIER_TAP]
    if WATCH_APP.exists():
        roots.append(WATCH_APP)
    for root in roots:
        for path in sorted(root.rglob("*.swift")):
            if "Localization" in path.parts:
                continue
            orig = path.read_text(encoding="utf-8")
            new = transform(orig)
            if new != orig:
                path.write_text(new, encoding="utf-8")
                print("updated", path.relative_to(CTT))


if __name__ == "__main__":
    main()
