#!/usr/bin/env python3
"""
Regenerate TierTap/TierTap/Airports.json from OurAirports (public domain).

  python3 Scripts/build_airports_json.py

Source: https://ourairports.com/data/airports.csv
"""
from __future__ import annotations

import csv
import json
import sys
from pathlib import Path
from urllib.request import urlopen

URL = "https://ourairports.com/data/airports.csv"
DEFAULT_OUT = Path(__file__).resolve().parent.parent / "TierTap" / "Airports.json"


def norm_code(s: str | None) -> str:
    return (s or "").strip().upper()


def main() -> None:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_OUT
    rows: list[dict] = []
    with urlopen(URL, timeout=300) as r:
        content = r.read().decode("utf-8", errors="replace")
    reader = csv.DictReader(content.splitlines())
    for row in reader:
        if row.get("type") == "closed":
            continue
        try:
            lat = float(row["latitude_deg"])
            lon = float(row["longitude_deg"])
        except (ValueError, KeyError):
            continue
        if lat == 0 and lon == 0:
            continue
        name = (row.get("name") or "").strip()
        if not name:
            continue
        iata = norm_code(row.get("iata_code") or "")
        if iata and len(iata) != 3:
            iata = ""
        gps = norm_code(row.get("gps_code") or "")
        ident = norm_code(row.get("ident") or "")
        icao = ""
        if len(gps) == 4 and gps.isalnum():
            icao = gps
        elif len(ident) == 4 and ident.isalnum():
            icao = ident
        elif gps:
            icao = gps
        elif ident:
            icao = ident
        if not icao and not iata:
            continue
        city = (row.get("municipality") or "").strip()
        if not city:
            ir = str(row.get("iso_region") or "").strip()
            city = ir.replace("-", " / ") if ir else (row.get("iso_country") or "Unknown")
        rows.append(
            {
                "id": row.get("id") or "",
                "iata": iata,
                "icao": icao,
                "name": name,
                "city": city,
                "country": (row.get("iso_country") or "").strip().upper(),
                "latitude": lat,
                "longitude": lon,
            }
        )
    rows.sort(key=lambda x: (x["city"].casefold(), x["icao"], x["iata"]))
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("w", encoding="utf-8") as f:
        json.dump(rows, f, separators=(",", ":"), ensure_ascii=False)
    print(len(rows), "airports ->", out, f"({out.stat().st_size / (1024 * 1024):.2f} MiB)")


if __name__ == "__main__":
    main()
