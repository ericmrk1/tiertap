# Scripts

## download_profanity_list.sh

Populates `TierTap/ProfanityWords.txt` with a large profanity word list (~50k–100k+ words) by downloading from:

- **LDNOOBWV2** – [List of Dirty Naughty Obscene and Otherwise Bad Words](https://github.com/LDNOOBWV2/List-of-Dirty-Naughty-Obscene-and-Otherwise-Bad-Words_V2) (75 languages)
- **questionable_international_words.csv** from the same repo
- **google-profanity-words** – [English list](https://github.com/coffee-and-fun/google-profanity-words)

Run from the `CTT` directory (or set `OUT_FILE` to your target path):

```bash
cd CTT
chmod +x Scripts/download_profanity_list.sh
./Scripts/download_profanity_list.sh
```

Requires: `git`, `curl`. The app uses this file to replace profane words with `###` when posting comments to the community feed.
