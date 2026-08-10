# TierTap — MVP v1.0

## Setup in Xcode

1. **Open** `TierTap.xcodeproj` in Xcode (14.2+ / 15+)
2. **Select your Team** — in all targets:
   - `TierTap` → Signing & Capabilities → Team
   - `CasinoTimerWidget` → Signing & Capabilities → Team
   - `TierTap Watch App` → Signing & Capabilities → Team
3. **Set your Bundle IDs** if needed (app: `com.app.tiertap`, widget: `com.app.tiertap.CasinoTimerWidget`, watch: `com.app.tiertap.watchkitapp`)
4. **App Group (for Watch sync):** Add the **App Groups** capability to both **TierTap** and **TierTap Watch App** targets, and create/select the group: `group.com.app.tiertap`. This lets the Watch and iPhone share session data (live session, history, and “requiring more info” cash-outs).
5. **Build & Run** on a real device (Live Activities require physical hardware).

> ⚠️ Live Activities (lock screen timer) require a **real iPhone** running iOS 16.2+.
> The simulator does not support Live Activities.

---

## Testing in the Simulator (on your Mac)

### iPhone app (TierTap)

1. Open **TierTap.xcodeproj** in Xcode.
2. In the toolbar, set the **scheme** to **TierTap** (not CasinoTimerWidget).
3. Set the **destination** to an iPhone simulator (e.g. **iPhone 16** or **iPhone 15**).
4. Press **⌘R** (or **Product → Run**).
5. The app launches in the simulator. You can:
   - Check in, run a live session, add buy-ins, close out, view history, and complete “incomplete” sessions.
   - **Live Activity** (lock screen timer) will not appear in the simulator; that only works on a real device.

### Watch app (TierTap Watch App)

1. In Xcode, set the **scheme** to **TierTap Watch App**.
2. Set the **destination** to a **Watch** simulator.  
   - If you don’t see one: **Xcode → Window → Devices and Simulators → Simulators** and ensure you have a watchOS simulator (e.g. **Apple Watch Series 10 - 46mm**). Xcode usually installs these with the watchOS SDK.
3. Press **⌘R**.
4. The Watch app runs in the Watch simulator. You can start a session, add buy-ins, and cash out (saved as “requiring more info”).

**Linking iPhone and Watch simulators (see timer on Watch started on iPhone)**

1. **Pair the simulators** (one-time):
   - **Xcode → Window → Devices and Simulators → Simulators** tab.
   - Select an **iPhone** simulator (e.g. iPhone 16).
   - Use **“Pair with Watch”** or the **+** under paired simulators to add an **Apple Watch** simulator (e.g. Apple Watch Series 10) so it appears as paired with that iPhone.

2. **Install the Watch app on the Watch simulator** (do this first):
   - In Xcode, set the **scheme** to **TierTap Watch App** (not TierTap).
   - Set the **destination** to your **Watch** simulator (e.g. **Apple Watch Series 10 - 46mm**).
   - Press **⌘R**.  
   - The Watch simulator will boot (and the paired iPhone simulator may open). The **TierTap** Watch app is now installed on the Watch. You can stop the run (⌘.) after it launches.
   - This step is needed because running only the iPhone app (TierTap scheme) often does not auto-install the Watch app on the Watch simulator.

3. **Run the iPhone app and see the timer on the Watch**:
   - Set the **scheme** back to **TierTap**, destination **iPhone** (e.g. iPhone 16).
   - Press **⌘R**. TierTap runs on the iPhone simulator.
   - On the **iPhone simulator**: TierTap → **Check In** → start a session.
   - On the **Watch simulator**: open the **TierTap** app (home screen). You should see the **same live session** (timer, add buy-in, cash out) if **App Group** (`group.com.app.tiertap`) is added to both targets.

**Syncing iPhone and Watch in Simulator:**  
Data is shared via the **App Group** (`group.com.app.tiertap`). Add that capability to **both** TierTap and TierTap Watch App targets. Then:

- Run the **iPhone** app (with a paired Watch), start a session, then open the **Watch** app on the Watch simulator: you should see the same live session on the Watch.
- Or run the **Watch** app alone (TierTap Watch App scheme), start a session and cash out; run the **iPhone** app and open **History** to see the “Incomplete” session and **Complete session**.

## Features
- ✅ Check In with game, casino, starting tier, buy-in (under 15 seconds)  
- ✅ Live session timer with real-time HH:MM:SS display  
- ✅ Lock screen Live Activity timer (iPhone + Dynamic Island support)  
- ✅ Add buy-ins mid-session with timestamps  
- ✅ Closeout with cash out, avg bet actual/rated, ending tier  
- ✅ Auto-calculates: Win/Loss, Tier Points Earned, Tiers/Hour, Tiers per $100 Rated Bet-Hour  
- ✅ Historical session backfill  
- ✅ Session history with full audit view; **status** (Complete vs Incomplete) for each session  
- ✅ **Apple Watch app:** Start session, add buy-ins, cash out (saved as “requiring more info”); complete those sessions later on iPhone  
- ✅ Dark mode, portrait-optimized UI  

## Architecture
```
TierTap/
├── Models/       Session.swift (with SessionStatus), GamesList.swift
├── ViewModels/   SessionStore.swift (App Group UserDefaults, watch closeout API)
├── Views/        SwiftUI screens + CompleteSessionView (finish Watch cash-outs)
└── LiveActivity/ TimerActivityAttributes.swift, LiveActivityManager.swift

CasinoTimerWidget/   ← Widget extension for lock screen
├── CasinoTimerWidgetBundle.swift
└── CasinoTimerLiveActivity.swift

TierTap Watch App/   ← watchOS companion
├── TierTapWatchApp.swift
└── Views/   WatchContentView, WatchStartView, WatchLiveView, WatchCashOutView
```
