# M0 spike — checklist and results

Goal (master plan §15): an ad-hoc build launches; the menu bar timer label updates live; notification permission, login item and Calendar (EventKit) permission survive a rebuild.

The app is currently the spike: a window with one row per check, and a `MenuBarExtra`. Every launch writes the current statuses to `~/Library/Application Support/logbook/spike-status.json` (`make spike-status` prints it).

## Results so far (9 Nov 2026)

| Check | Result |
|---|---|
| Ad-hoc signed build (`Signature=adhoc`, no team) launches from the CLI | ✅ |
| Calendar usage string present in the generated Info.plist | ✅ |
| Live database opens and migrates at `~/Library/Application Support/logbook/logbook.sqlite` | ✅ `ok (11 tables)` |
| Menu bar label counts live (`Text(timerInterval:)` in `MenuBarExtra` label) | ⏳ not verified: screen was locked during the run |
| Notification permission survives a rebuild | ⏳ needs a grant first |
| Login item survives a rebuild | ⏳ needs a grant first |
| Calendar full access survives a rebuild | ⏳ needs a grant first |

## Manual steps

1. `make run`. In the window:
   - Notifications → **Request**, allow. **Send test** should show a banner.
   - Login item → **Toggle**. If it says `requiresApproval`, open **Settings…** and allow Logbook.
   - Calendar → **Request**, allow. The row should show a calendar count.
   - Timer → **Start**. Close the window and watch the menu bar: "● study 0:00:0x" should keep counting. Open the panel from the menu bar and check it counts there too.
2. `make spike-status` → all three should read `authorized` / `enabled` / `fullAccess`.
3. Change any source file (or just `touch App/LogbookApp.swift`), `make run` again, then `make spike-status`. Compare `binaryBuiltAt` (new) with the three statuses (should be unchanged).
4. Repeat 2–3 with `make install` (the `/Applications` copy), since the login item should only ever point at that one.

## If something fails

- **Menu bar label freezes:** fall back to an `NSStatusItem` whose title is set once a second from the stored start instant (research report, TomatoBar pattern).
- **Permissions reset on every rebuild:** the ad-hoc cdhash changes per build. Try signing with a free Personal Team "Apple Development" identity (stable Team ID), then re-run steps 1–3.
- **Status item missing entirely:** check System Settings → Menu Bar for a per-app toggle, and whether the notch is hiding it.
