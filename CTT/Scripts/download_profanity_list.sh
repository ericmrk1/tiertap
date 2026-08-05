#!/usr/bin/env bash
# Downloads profanity word lists from external sources and merges into ProfanityWords.txt
# (~100k+ words). Run from CTT directory or set OUT_FILE.
# Sources: LDNOOBWV2 (75 languages), questionable_international_words, google-profanity-words.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_FILE="${OUT_FILE:-${SCRIPT_DIR}/../TierTap/ProfanityWords.txt}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading profanity lists..."

# 1) LDNOOBWV2 - List of Dirty Naughty Obscene and Otherwise Bad Words (75 languages, 50k+ words)
LDNOOBW="${TMP_DIR}/ldnoobw"
git clone --depth 1 https://github.com/LDNOOBWV2/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words_V2.git "$LDNOOBW" 2>/dev/null || true
if [[ -d "$LDNOOBW/data" ]]; then
  cat "$LDNOOBW"/data/*.txt 2>/dev/null || true
fi > "${TMP_DIR}/all.txt"

# 2) questionable_international_words.csv from same repo (extra phrases)
if [[ -f "$LDNOOBW/questionable_international_words.csv" ]]; then
  # CSV: extract first column (word/phrase), skip header
  tail -n +2 "$LDNOOBW/questionable_international_words.csv" | cut -d',' -f1
fi >> "${TMP_DIR}/all.txt" 2>/dev/null || true

# 3) google-profanity-words (English)
curl -sL "https://raw.githubusercontent.com/coffee-and-fun/google-profanity-words/main/data/en.txt" 2>/dev/null || true >> "${TMP_DIR}/all.txt"

# Normalize: lowercase, one per line, strip blanks, dedupe, sort
echo "Merging and deduplicating..."
sed 's/^[[:space:]]*//;s/[[:space:]]*$//' "${TMP_DIR}/all.txt" \
  | tr '[:upper:]' '[:lower:]' \
  | grep -v '^$' \
  | sort -u \
  > "$OUT_FILE"

COUNT=$(wc -l < "$OUT_FILE" | tr -d ' ')
echo "Wrote $COUNT words to $OUT_FILE"
