# TierTap — MVP v1.0

## Setup in Xcode

1. **Open** `TierTap.xcodeproj` in Xcode (14.2+ / 15+)
2. **Select your Team** — in both targets:
   - `TierTap` → Signing & Capabilities → Team
   - `CasinoTimerWidget` → Signing & Capabilities → Team
3. **Set your Bundle IDs** if needed (default: `com.app.tiertap` / `com.app.tiertap.CasinoTimerWidget`)
4. **Build & Run** on a real device (Live Activities require physical hardware)

**Simulator:** Use the **TierTap** scheme (not CasinoTimerWidget) when running in the simulator. A shared scheme is included that launches only the main app and avoids the "Failed to show Widget" / "Failed to get descriptors for extensionBundleID" error.

> ⚠️ Live Activities (lock screen timer) require a **real iPhone** running iOS 16.2+.
> The simulator does not support Live Activities.

## Features
- ✅ Check In with game, casino, starting tier, buy-in (under 15 seconds)  
- ✅ Live session timer with real-time HH:MM:SS display  
- ✅ Lock screen Live Activity timer (iPhone + Dynamic Island support)  
- ✅ Add buy-ins mid-session with timestamps  
- ✅ Closeout with cash out, avg bet actual/rated, ending tier  
- ✅ Auto-calculates: Win/Loss, Tier Points Earned, Tiers/Hour, Tiers per $100 Rated Bet-Hour  
- ✅ Historical session backfill  
- ✅ Session history with full audit view  
- ✅ Dark mode, portrait-optimized UI  

## Architecture
```
TierTap/
├── Models/       Session.swift, GamesList.swift
├── ViewModels/   SessionStore.swift
├── Views/        7 SwiftUI screens + shared components
└── LiveActivity/ TimerActivityAttributes.swift, LiveActivityManager.swift

CasinoTimerWidget/   ← Widget extension for lock screen
├── CasinoTimerWidgetBundle.swift
└── CasinoTimerLiveActivity.swift
```
