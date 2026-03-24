Already partly there (so the “gap” is smaller than it sounds)
A (programs): Loyalty program is inferred from casino name keywords for charts like “Tier Points by Loyalty Program,” not stored per session as program + property + city.
AddE (share controls): Analytics image sharing has toggles (including win/loss); text sharing supports includeWinLoss.
J (CSV): Session CSV export is already in Settings.
Easy wins (not implemented / incomplete, low “qualifications” bar)
B) Trips + trip dashboard (local-first)
There’s no Trip entity or grouping. A local-only model (name + dates, optional tripId on Session) plus one summary screen (hours, tier points, tiers/hour, “best” property) is straightforward and doesn’t need backend.
B) Time-window chips (7 / 30 / 90 days)
Analytics uses custom from/to date pickers. Adding preset buttons that set those ranges is small UI work.
A) First-class session tags: program, property, city
Today everything rides on one casino string. Adding optional structured fields (and maybe a bundled static list of “programs” for pickers) makes rollups comparable and filterable without needing casino partnerships—users pick or you default from rules.
A) “Where do I earn tiers fastest?” as built-in charts
The data (tiers/hour, tiers per $100 rated bet-hour) already exists on sessions; the AI prompts mention ranking by program/property/game. A deterministic breakdown (tables in Analytics) avoids model reliance and is still easy.
C) Rated vs actual — structured “gap” + simple “pattern” detector
You already chart rated − actual where both exist. Still missing: per-session gap summary row, rolling/average gap by property/game without AI, and a gentle rule-based flag (e.g. consistently negative gap over N sessions)—all from existing fields.
C) “Estimated” vs “confirmed” rated bet
A single enum/bool on Session + closeout toggle is a small schema + UI change and unlocks confidence tagging in analytics/shares.
E) Share “templates” + privacy tweaks
You have phrase libraries and toggles. Named modes (facts-only vs spicier tone) = routing phrases / suppressing flourish. Hide casino name = string redaction in SessionShareFormatter + matching image cards. Default win/loss OFF in share sheets is a one-line default change if you want privacy-first out of the box.
D) “Recently used” casinos & games
Favorites exist; recency from Session history (last N unique casinos/games) at the top of pickers is pure client logic.
G) Mood vs how you played
Cross mood with tiers/hour, duration, gap, tier points in a small analytics section—no new inputs if you’re happy with current mood granularity.
G) Safety resources link
Optional link in Settings or after certain moods (plain URL, opt-in)—minimal scope.
H) “High volatility session” heuristic + copy
Rule-based flag from rebuys/add-ons, session length, bet vs buy-in—no ML. Actual push “nudges” need notifications permission and policy thought; in-session or post-sessional labels stay easy.
H) Educational overlays
You already have StrategyDatabase-style content; linking overlays from game pickers is mostly navigation/copy.
I) TapPoints as a visible layer
Tap Level already scores engagement-like behavior; surfacing a “points this week / streak” narrative (even if it’s the same formula sliced differently) is mostly UI unless you want a separate economy.
J) “Trip summary” PDF
CSV exists; PDF = format the same aggregates (local render). Slightly more work than CSV but still self-contained.
Usually not “easy without qualifications” (called out on purpose)
Share links → landing / coming soon → needs web + routing, not just the app.
Community handles, field-level privacy, leaderboards → schema, abuse, and product policy even if Supabase is there.
Referrals, partner perks, “official” program rules → ops, compliance, or partnerships depending on how you frame them.
Live stop-loss / break notifications → doable technically, but framing and App Store / responsible-gambling expectations merit a deliberate pass—not a casual toggle.
Bottom line: The biggest “easy and high leverage” gaps vs your list are Trips (local), 7/30/90 presets, structured program/property/city (or program + city at minimum), native (non-AI) rated/actual rollups + confidence flag, share templates + hide-venue + safer defaults, and recently-used pickers. Those tighten the product story without opening new external dependencies.
