# logbook — Master Plan

*Version 1.1 · 8 November 2026 (added to-dos and time-blocking calendar) · status: planning, nothing built yet*

A private, native macOS app that replaces the daily Apple Notes log, and plans the day too: to-dos and a time-blocking calendar sit on the same timeline as what actually happened. You enter everything yourself. The app does the arithmetic, shows trends, runs live timers and nudges you at the right moments. It looks and behaves like an Apple app, and it is built so features can be added for years.

Research behind every decision here: [research/stack-and-architecture-report.md](research/stack-and-architecture-report.md).

---

## 1. Principles

1. **Faster than Notes, or it fails.** Logging a line must take no more effort than typing it into Notes today. Your shorthand stays the input language.
2. **The app does the maths.** You never type a total again: durations, daily totals, net calories and averages are all computed.
3. **Compare you with you.** Metrics are shown against your own 7- and 28-day baselines, not against generic targets or scores. No red/green moralising.
4. **Proactive, not noisy.** At most 3 insight cards a day and at most 2 unrequested notifications a day. Every insight can explain itself.
5. **Your history is sacred.** Local SQLite, daily backups, full JSON/CSV export, every imported row keeps its original text, and every import can be undone.
6. **Native, not imitated.** Real SwiftUI, Liquid Glass, Swift Charts and SF Symbols. No web view pretending to be a Mac app.
7. **Built to grow.** New metrics, detectors and screens slot in without rewriting the core.
8. **Plan, then compare.** Planned blocks and tasks sit beside what really happened, so the gap is visible and useful, never a guilt trip.

---

## 2. Stack (decided by research)

| Layer | Choice | Why |
|---|---|---|
| Language | **Swift 6.4** (Swift 6 language mode) | The only way to get real Liquid Glass, widgets, App Intents, and a path to iPhone/Watch; one language for everything |
| UI | **SwiftUI** (+ small AppKit bridges where needed) | Native sidebar, toolbar, materials, animation, keyboard handling |
| Charts | **Swift Charts** | Bar, line, area, range, rule and rectangle marks cover every chart planned; native look and accessibility |
| Storage | **SQLite via GRDB 7.12** + **SQLiteData 1.12** (Point-Free) | SQL `GROUP BY` and window functions for metrics; readable schema; online backup; CloudKit sync can be switched on later. SwiftData was rejected: no aggregate queries, open crash reports |
| Architecture | `@Observable` services in the SwiftUI Environment, pure logic in local Swift packages, swift-dependencies for injected clock/calendar | Simple, testable, easy for an AI assistant to extend. TCA is too much ceremony here |
| AI (optional) | **Apple Foundation Models**, on-device, free, offline | It only writes sentences around numbers Swift has already computed |
| Project | **Xcode 27.2 JSON project** (`project.xcproj`) edited only via `xcrun xcodeproj` | Built for coding agents; everything can be built, run and tested from the terminal |
| Tests | Swift Testing; swift-snapshot-testing for views | Date maths, attribution and the importer are the risky parts |
| Importer | Swift command-line target that reuses the app's model code | Same validation as the app; no second language |
| Signing | Ad-hoc ("Sign to Run Locally"); **no paid Apple account needed** until an iPhone app or iCloud sync | See §14 |

**Rejected:** Tauri (your earlier attempt), Electron, Flutter, React Native and Compose. None gets real Liquid Glass, and widgets and Shortcuts would need Swift anyway.

---

## 3. What you log → how the app stores it

Your current Notes format and where each line goes:

| You write today | Example | Stored as |
|---|---|---|
| Work block | `0945 - 1045 [1h] > study + exam` | `time_block` kind=work, start, end, label "study + exam", optional project/tag |
| Total work | `$ 6h 30m` | **Computed** from work blocks; your typed total is only used to check the import |
| Food | `pulao 250g - 408 / 8 / 0` | `food_log_entry` with kcal / protein g / caffeine mg **snapshotted**; linked to a `food` library item if one matches |
| Food without numbers | `Chicken roll`, `50rs puchka` | Entry flagged *needs values*; filled from the library or marked as an estimate (`~`) |
| Daily nutrition totals | `$ 1616 / 102 / 220` | **Computed** |
| Burn + steps | `burn - 373 / 11,773 steps` | `metric_sample` (active_kcal, steps) |
| Net calories | `$ 1243 / 102 / 220` | **Computed**: intake − logged burn, labelled honestly (logged burn is not total expenditure) |
| Nature's call | `nc -> 1550 - 1708 [1h 18m] [13m / 17m / 48m]` | `time_block` kind=nature_call; only the total is stored, the parts stay in `raw_text` |
| Sleep | `sleep -> 0045 - 0930 [8h 45m]` | `time_block` kind=sleep, crossing midnight handled |
| Estimates | `~1290 / 28 / 0` | `is_estimate = true` on the row; shown with a subtle `~` and down-weighted in insights |

### Core tables

| Table | Purpose | Key rules |
|---|---|---|
| `time_block` | Work, sleep, nature's call, and future custom kinds | Start/end stored as instants (UTC) plus time zone; `end = NULL` means a timer is running; `logical_day` fixed when written; optional `task_id` / `plan_block_id` link it to what was planned |
| `category` | Work projects/tags (e.g. "writing", "study", "coursework") | Colour + SF Symbol per category |
| `food` | Your **dictionary** of everything you eat (and smoke): name, aliases, serving, kcal / protein / carbs / fat / caffeine / nicotine per serving | Editing the dictionary never changes past days |
| `food_log_entry` | What you ate or smoked | Copies all six values at log time; quantity/multiplier; time consumed |
| `metric_definition` / `metric_sample` | Steps, burn, and **any metric you add later** (weight, mood, water, gym sets…) | Typed, unit-aware, sum/avg/max/last aggregation |
| `daily_facts` (SQL view) | One row per day: work min, sleep min, kcal, protein, caffeine, burn, steps, NC count/min | Feeds every chart and insight; computed, never stored |
| `goal` | Optional targets (protein, caffeine cap, work hours, bedtime…) | Unset by default |
| `import_batch`, `change_log` | Import provenance and audit history | Every import undoable; edits recorded |
| `insight_memory` | What was shown, dismissed or snoozed | Prevents repeat nagging |

Planning tables (`task_list`, `task`, `plan_block`, `plan_template`, `external_event`) are described in §9.

All rows use UUID keys and keep `source` (manual / timer / import), `raw_text` and `deleted_at` (soft delete).

### The day boundary (decided: calendar day, §16)

Your notes are grouped by calendar date, but your days don't follow the calendar. On 10 Oct you worked 01:00–03:30 and then slept 05:15–10:55; that 01:00 block is really the tail of 9 Oct. Two options:

- **A. Calendar day:** matches your notes exactly.
- **B. Personal day start** (e.g. 05:00): late-night work counts toward the day you were awake for, and sleep counts toward the day you wake up.

Whichever you pick is stored on each row when it's written, so changing the setting later never silently rewrites history.

---

## 4. Importing your history

**Source:** `daily-data-2026-08-24-to-2026-10-11.md` (7 weeks, 24 Aug–11 Oct). It contains your raw Notes text in fenced blocks, followed by calculated tables. **The remaining ~4 weeks (12 Oct–today) need locating**, probably still in Apple Notes (§16).

**Pipeline**
1. **Parse** each day's raw block line by line: date header, work lines (`HHMM - HHMM [dur] > label`), `$` totals, food lines, `burn`, `sleep ->`, `nc ->`, `~` estimates. Line numbers and original text are kept.
2. **Enrich** foods that have no numbers from the calculated nutrition tables already in the file, flagging them as estimates.
3. **Check**: recompute every duration and total and compare it with what you typed; mismatches become warnings, not silent fixes.
4. **Preview** in the app: per-day counts, warnings, unknown lines, new foods to add to the library.
5. **Apply** in one transaction under an `import_batch`. **Undo** removes the whole batch. Re-running is idempotent.
6. **Seed the food library** from every distinct food in the history (≈ your real menu: paneer 200 g, protein shake, coffee 50 ml + 2 tsp, Monster, Hell, Munch Max…).

The same parser also powers **"Paste from Notes"**: paste any day's raw note and it gets logged, so the missing weeks and any future Notes entries come in the same way.

---

## 5. Screens

Sidebar app (`NavigationSplitView`) with system Liquid Glass chrome. Keyboard-first; every action also has a menu item and a shortcut.

| Screen | What's on it |
|---|---|
| **Today** | 6 pinned hero metrics (work today, net kcal, protein, caffeine and nicotine in system now, last night's sleep), each with a one-line headline ("6 h 10 m, 40 m above your 4-week average") and a sparkline. Then **Up next** (the next planned block and today's top tasks), the **24-hour track** for today (plan ghosted behind actual), running timers, and up to 3 insight cards |
| **Calendar** | Day / week / month grid with two layers: **Plan** (time blocks you scheduled, outlined) and **Actual** (logged sleep, work and NC blocks, food markers, caffeine curve, live "now" line). Drag tasks in to time-block them; templates; optional Apple Calendar overlay. Week view adds sleep/wake range bars and stacked work bars (see §9) |
| **Tasks** | Inbox, Today, Upcoming, Someday, Done, and your lists; estimates vs actual time; drag a task onto the Calendar to block time for it (see §9) |
| **Work** | Total per day, per project/category, deep-work blocks (≥ 50 min), first-start time, longest focus streak, hours by time of day |
| **Food** | Day log with running totals; library; favourites and recent items; meals/templates; "copy yesterday"; protein and caffeine trends |
| **Sleep** | Duration, bedtime/wake ranges, midpoint, regularity, last 7/28 nights |
| **Body** | Burn, steps, NC frequency and duration (descriptive only) |
| **Trends** | Any metric over 7d / 28d / 3m / 1y / all, compare two metrics, simple correlations with confidence shown |
| **Review** | Weekly and monthly report pages: what changed, best days, consistency |
| **Dictionary / Library** | The food dictionary (full macros, caffeine, nicotine, aliases, favourites), categories, task lists, day/week templates, custom metrics, goals |
| **Import / Export** | Notes paste, file import with preview/undo, backups, JSON/CSV export |
| **Settings** | Day boundary, targets, notification controls, quiet hours, caffeine half-life, appearance, hotkeys |

### Always-available surfaces
- **Menu bar timer:** shows the running block live ("● study 1:12:40"). One click to stop, switch or start a block, plus quick add.
- **Quick Entry** (global hotkey, e.g. ⌥Space): one field that understands your shorthand (`0945-1045 study`, `pulao 250g`, `coffee`, `nc 1550-1708`, `sleep 0045-0930`, `burn 373 11773`, `t write deck ~45m fri`, `plan 1400-1600 deep work`) and shows a live parsed preview before saving.
- **Command palette (⌘K)** for every action and screen.
- **Close the day** sheet in the evening: lists unlogged gaps in the 24-hour track, missing burn/steps, and foods without values; offers to mark planned blocks done/skipped and to move unfinished tasks; then shows the day's summary and lets you **plan tomorrow** (stamp a template, drag in tasks).

---

## 6. Metrics catalogue

| Area | Metrics |
|---|---|
| Work | Total/day; vs 7d and 28d average; per category; deep-work blocks; first start; last end; fragmentation (block count); weekly total; streak of days ≥ your target |
| Food | kcal in; protein, carbs, fat (daily and 7-day average); caffeine and **nicotine** totals; **caffeine and nicotine in your system now and at your usual bedtime** (half-life models, defaults 5 h and 2 h, adjustable); last-caffeine time; foods logged; estimate share |
| Energy | Logged burn; steps; net kcal (intake − logged burn); 7-day averages |
| Sleep | Duration; onset; wake; midpoint; regularity (bedtime consistency, Sleep Regularity Index once there's enough data); naps |
| Nature's call | Count; total minutes; average duration; time-of-day pattern (descriptive only, neutral wording) |
| Planning | Planned vs actual work hours; plan adherence (% of planned minutes that happened); start-time drift; tasks completed, carried over, dropped; estimate accuracy (actual ÷ estimate) per list; overcommit (task estimates vs free planned time) |
| Logging | Days logged, completeness per field, current logging streak |

Every metric has a definition, a unit, an aggregation, and a "how is this calculated" popover.

---

## 7. Charts

| Chart | Used for |
|---|---|
| 24-hour lane track (rectangle marks) | Day view of sleep / work / NC with food markers; planned blocks drawn as ghosted outlines behind |
| Calendar grid (plan vs actual columns) | Day/week time blocking with plan and reality side by side |
| Planned vs actual bars | Work hours per day/week, with adherence % |
| Range bars (start→end per day) | Sleep window and work window across weeks: regularity at a glance |
| Stacked bars | Work per category per day/week |
| Bars + baseline band + rolling-average line | Any daily metric vs your 28-day typical range |
| Area curve | Caffeine in system across the day |
| Sparklines | Hero metric cards |
| Calendar heatmap | Year view for any metric |
| Scatter with trend line | Trends screen: metric vs metric (e.g. late caffeine vs next sleep) |

Rules (from Apple's HIG): a plain-language headline above every chart, detail on hover/selection, small and expanded versions look the same, explicit gaps for missing days (never zeros), one colour per category everywhere.

---

## 8. Timers

- A timer is a `time_block` with no end time, saved the instant you press start. Elapsed time is always `now − start`, so quitting, crashing or sleeping the Mac never loses time.
- One running block per kind (you can sleep-track while not working, etc.).
- Live counters use `Text(timerInterval:)`, so no ticking code is needed.
- **Forgotten-timer guard:** on wake or launch, a block running far longer than usual asks "Still going? / Stop at …".
- Retroactive entry is as quick as live timing; most of your logging today is retroactive.

---

## 9. Plan: to-dos and time blocking

Logging records what happened; planning decides what should happen. Both live on the same timeline, so every day can be read as **plan vs actual**.

### 9a. To-do lists
- **Lists** (e.g. "writing", "exams", "personal"), each optionally tied to a work category so time spent on its tasks counts toward that category.
- **Smart views:** Inbox, Today, Upcoming, Anytime, Someday, Done (a log of completed tasks).
- **Task fields:** title, notes, list, tags, priority (none / ! / !!), due date (deadline), scheduled day (when you intend to do it), estimate (minutes), checklist / subtasks, recurrence (daily, weekly, custom, or "after completion"), status (open / done / dropped).
- **Capture in your shorthand:** `t write SIH deck ~45m !! fri #horizon` → task, 45-min estimate, high priority, due Friday, in "horizon". Keyboard-first: ⌘N new, Space to complete, ⌘→ move to tomorrow, drag to reorder.
- **Doing a task:** "Start" on a task starts a work timer linked to it; stopping logs the time block with the task attached. Every task shows actual time vs its estimate.
- **No silent pile-up:** at Close the day, unfinished Today tasks are offered → tomorrow / pick a day / someday / drop.

### 9b. Calendar & time blocking
- **One Calendar screen** (it replaces a separate Timeline): Day, Week and Month, vertical hour grid starting at your day-start hour.
- **Two layers:** **Plan** (outlined, translucent blocks you scheduled) and **Actual** (solid blocks you logged: work, sleep, NC, plus food markers). Show plan only, actual only, or both side by side in each day column.
- **Time blocking:** drag a task from the sidebar onto the grid to create a block sized to its estimate; drag edges to resize (5-min snap, ⌥ for 1-min); ⌥-drag to duplicate; or type `1400-1600 deep work` straight into the grid or Quick Entry.
- **Plan block fields:** start, end, kind (work, sleep target, break, gym, custom), category, linked task(s), note, recurrence, template, status (planned / started / done / skipped / moved).
- **Plan → actual in one click:** when a planned block starts, a quiet notification says "Deep work · horizon starts now" with **Start** (starts the linked timer) and **Skip**. Afterwards, "Done as planned" creates the matching actual block (`source = plan`), so retroactive logging stays fast.
- **Templates:** save an "ideal day" or "ideal week" (e.g. sleep 01:00–09:00, deep work 10:00–13:00, gym 18:00) and stamp it onto any day or week; recurring blocks for routines.
- **Sleep target:** a recurring planned sleep window, compared with actual sleep and fed into sleep regularity.
- **Apple Calendar (optional, opt-in):** read events from chosen calendars through EventKit as a read-only layer (classes, exams, calls) so blocks don't collide. Write-back can come later. Calendar permission behaviour on an ad-hoc build is checked in the M0 spike.

### 9c. Planning metrics & insights
- Planned vs actual work hours (day and week), plan adherence, start-time drift, completion and carry-over counts, estimate accuracy per list, overcommit.
- Example insights: "You usually start planned deep work 35 min late", "Tasks in #horizon take 1.6× your estimate", "Tomorrow has 9 h of tasks but 5 h of free blocks".
- Same rules as every other insight: personal baselines, minimum-data gates, no guilt colouring.

### 9d. Data model additions (built 9 Nov 2026; `task` is `TodoTask` in Swift)

| Table | Key fields | Rules |
|---|---|---|
| `task_list` | name, colour, SF Symbol, `category_id?`, sort, `archived_at` | Lists can map to work categories |
| `task` | `list_id`, title, notes, priority, `due_date`, `scheduled_day`, `estimate_min`, `recurrence_rule`, `parent_task_id` (subtasks), status, `completed_at`, sort, provenance | A recurring task spawns its next instance on completion |
| `plan_block` | `start_utc`, `end_utc`, tz, `logical_day`, kind, `category_id`, `task_id?`, note, status, `template_id?`, `recurrence_rule`, provenance | Never merged with `time_block`: plan and reality stay separate rows |
| `plan_template` | name, scope (day / week), block definitions | Stamping a template creates ordinary `plan_block` rows |
| `external_event` | EventKit identifier, calendar, title, start, end, `last_synced` | Read-only cache; can be rebuilt any time |

Recurrence uses a subset of the iCalendar RRULE format, so it is standard and easy to test.

---

## 10. Proactive layer

### 10a. Insight engine (deterministic Swift; no AI needed) — built 9 Nov 2026
Each insight is a pluggable **detector** with a minimum-data gate, an effect size, a confidence level and a "why am I seeing this" explanation.

| Detector | Example | Needs |
|---|---|---|
| Baseline deviation | "Work today 2 h 10 m below your typical range" | 14 days |
| Trend | "Sleep onset has moved 50 min later over 2 weeks" | 28 days |
| Late caffeine | "Last caffeine 23:40 is within 6 h of your usual sleep time" (cutoff = your median sleep onset − 6 h) | 14 days |
| Caffeine vs sleep | "On days with caffeine after your cutoff, you slept 48 min less (moderate confidence)" | 8–10 days per group |
| Sleep vs work | "After < 6 h sleep, you average 1 h 40 m less work" | 8–10 days per group |
| Protein streak | "Protein ≥ target 5 days running" | goal set |
| Personal best | "Longest deep-work day in 6 weeks" | 28 days |
| Plan adherence | "You usually start planned deep work 35 min late" | 10 planned blocks |
| Estimate accuracy | "Tasks in #horizon take 1.6× your estimate" | 8 completed tasks with estimates |
| Overcommit | "Tomorrow has 9 h of tasks but 5 h of free blocks" | tasks with estimates |
| Data quality | "Burn missing 3 of last 7 days" | — |

Statistical safeguards: "not logged" ≠ zero; estimates down-weighted; false-discovery control on correlations; wording is always "on days when…", never "causes"; no medical claims.

### 10b. Notifications (local, all controllable) — built 9 Nov 2026 except missed-log and morning-plan
| Notification | When | Level |
|---|---|---|
| Forgotten timer | Block running far past normal | Active (Time Sensitive needs a paid-account entitlement) |
| Close the day | Your median sleep onset − 60 min | Active |
| Caffeine cutoff | 30 min before your personal cutoff, only if you're still drinking | Active |
| Missed log | A usual anchor (e.g. first work block) hasn't happened well past its usual time | Passive, max once/day |
| Planned block starting | At a planned block's start, only if no timer is running; Start / Skip actions | Active, opt-in per block or template |
| Task due | Morning of the due day, for tasks not yet scheduled into a block | Passive |
| Morning plan | Optional, before your usual first start: today's blocks and due tasks | Passive |
| Weekly review | Sunday (configurable) | Passive |
| Insight of the day | When a strong insight appears | Passive |

Planned-block and task-due reminders are ones you asked for, so they don't count toward the cap. Caps: max 2 unrequested notifications per day; never during a running sleep block; quiet hours; three ignored in a row → frequency halves and an inline "turn off" appears.

### 10c. On-device AI (built 9 Nov 2026: headline + sentence openings only; Swift inserts all numbers)
Apple Foundation Models writes the daily recap and weekly review prose **from facts Swift has already computed**. It cannot introduce numbers (validated); if it's unavailable or fails, built-in templates are used. Nothing leaves the Mac.

---

## 11. Design language — "premium, like Apple"

- **System first:** native sidebar, toolbar, inspector and sheets give Liquid Glass automatically. Custom glass only for the floating Quick Entry pill and menu bar panel.
- **Type:** SF Pro; SF Pro Rounded for hero numbers; tabular figures for every timer and number column.
- **Colour:** one semantic hue per domain, consistent everywhere (e.g. work = indigo, sleep = purple, food = orange, caffeine = brown, energy = green, NC = teal), adapted for light/dark and increased contrast. Neutral backgrounds; colour carries meaning, not decoration.
- **Motion:** spring transitions between day/week/month, numbers that count to new values, charts that morph rather than redraw; all respecting Reduce Motion.
- **Density:** generous spacing on Today; compact, information-dense tables in Library and Review.
- **Icon:** a custom app icon in Icon Composer (glass layers).
- **Checks:** both ends of the macOS 27 glass slider, Reduce Transparency, dark mode, VoiceOver labels on charts.

---

## 12. Personalisation & extensibility

- **Custom metrics** without code: add "weight (kg, last)", "water (ml, sum)" or "mood (1–5, avg)"; they automatically get logging, charts, baselines and insights.
- **Custom block kinds** beyond work/sleep/NC (gym, commute, reading…).
- **Pinned metrics** on Today, reorderable.
- **Day and week templates** for time blocking; task lists, tags and recurrence of your own.
- **Goals** per metric (optional, unset by default).
- **Shorthand aliases** ("cof" → coffee 50 ml + 2 tsp).
- **Detectors and notifications** are plug-ins: adding one = one file + its tests.
- **Code modules:** each feature is a local Swift package, so adding "Gym" or "Journal" later doesn't touch the core.

---

## 13. Code architecture

```
logbook/
  Logbook.xcodeproj/            JSON project — edit only via `xcrun xcodeproj`
  App/                          app entry, menu bar, windows, assets, icon
  Packages/
    LogbookCore/                types, interval maths, day attribution, metrics, insight detectors (pure, tested)
    LogbookPersistence/         schema, migrations, queries, daily_facts, backup/export
    LogbookImport/              shorthand parser, import plan, `logbook-import` CLI
    LogbookUI/                  design system + feature views with #Preview
  Fixtures/                     synthetic log snippets for golden tests
  Makefile                      build · run · test · install · screenshot
  CLAUDE.md                     commands, module map, rules for AI changes
  MASTER_PLAN.md                this file
```

Rules: no view does maths; all time comes from an injected clock/calendar; no concurrency escape hatches (`@unchecked Sendable`, `nonisolated(unsafe)`); every view has a `#Preview`; every bug fix gets a test; the schema dump (`schema.sql`) is regenerated by a test so it's always current.

---

## 14. Data safety, signing, platform limits

- **Storage:** `~/Library/Application Support/logbook/logbook.sqlite`.
- **Backups (built, 9 Nov 2026):** automatic daily snapshot (keep 30), manual JSON/CSV export, and a JSON restore that proves the round trip. Still to do: optional mirror of snapshots to iCloud Drive (never the live database).
- **Signing:** ad-hoc is enough for the whole Mac app: charts, menu bar, notifications, on-device AI, launch at login. Reading Apple Calendar through EventKit needs only a permission prompt, not a paid account (to confirm in M0).
- **Needs the $99/yr Apple Developer account** (not now): iCloud/CloudKit sync, an iPhone/Watch app beyond 7-day installs, and reliable desktop widgets.
- **HealthKit doesn't exist on the Mac.** Steps and burn stay manual for now. Later: import the iPhone Health export, or an iPhone Shortcut that drops daily JSON into iCloud Drive (free), or an iPhone companion (paid).

---

## 15. Roadmap

Each milestone ends with a working app you can use daily.

| # | Milestone | Done when |
|---|---|---|
| M0 | **Spike** (½ day) | Ad-hoc build launches; menu bar timer label updates live; notification permission, login item and Calendar (EventKit) permission survive a rebuild |
| M1 | **Foundation** | Project + packages + schema + day attribution + `daily_facts`; date-maths test matrix passes (midnight crossings, DST, missing days) |
| M2 | **Import history** | All 7 weeks (plus the missing 4 once found) imported with preview and undo; totals match your notes or the differences are explained; food library seeded |
| M3 | **Daily driver** | Today screen, Quick Entry with shorthand, live timers, menu bar, Close the day; **you stop using Notes** |
| M4 | **Food** | Library, favourites, meals, copy-yesterday, caffeine curve, protein tracking |
| M5 | **Charts & trends** | Calendar actual layer (day/week/month), Work/Sleep/Body screens, Trends, baselines |
| M6 | **Plan** | Tasks (lists, smart views, estimates, recurrence), Calendar plan layer with drag-to-block, templates, plan → actual in one click, plan tomorrow at Close the day, optional Apple Calendar overlay |
| M7 | **Proactive** | Insight engine + detectors (incl. planning), notifications with caps, weekly review |
| M8 | **Polish** | Full design pass, motion, icon, keyboard coverage, accessibility, settings, backups/export |
| M9 | **AI recap** | On-device daily recap and weekly review prose with template fallback |
| M10 | **Everywhere on the Mac** | Shortcuts/Spotlight actions (log, add task, start block), launch at login, custom metrics UI |
| Later | Widgets · iPhone/Watch quick log · Health import · iCloud sync · journal · gym log | Decide when ready; most need the paid account |

---

## 16. Decisions needed from you

1. ~~**Day boundary**~~ — decided 9 Nov 2026: **A, calendar day** (`DayBoundary.standard`). Sleep still counts toward the day you wake up.
2. **Missing weeks:** where are 12 Oct → today? — deferred 9 Nov 2026: you'll add the data later through the importer (format in [IMPORT_FORMAT.md](IMPORT_FORMAT.md)).
3. **What counts as "work":** today every `>` block counts (study, exams, calls, misc). Keep that, or tag some as non-work?
4. **Targets:** set any now (protein g, caffeine cap mg, work hours, sleep hours, bedtime), or leave them unset and let baselines do the work?
5. ~~**NC sub-durations**~~ — decided 9 Nov 2026: only the total (start → end) is stored; the parts stay in `raw_text`.
6. ~~**Project folder**~~ — decided: `kanishkpaul/logbook`.
7. **Paid Apple account:** confirm "not now" (everything up to M10 works without it).
8. **Existing to-dos and calendar:** where do your tasks and plans live today (Apple Reminders, Apple Calendar, Things, Notion, paper)? Import once, keep reading them, or start fresh?
9. **Apple Calendar overlay:** show your Apple Calendar events read-only on the Calendar, yes or no?

---

## 17. Risks (top 7)

| Risk | Mitigation |
|---|---|
| Wrong day attribution corrupts every metric | Fixed on write, per-kind rules, heavy tests, decision #1 above |
| Importer misreads messy lines | Preview, warnings, keep raw text, batch undo, golden tests from real lines |
| Menu bar label stops refreshing | Confirmed in M0 for `MenuBarExtra` + timer label; using `NSStatusItem` (verified) |
| Planning features make logging slower or the app cluttered | Logging paths stay untouched; Tasks and Calendar are their own screens; plan layer can be hidden; adherence never shown in red |
| Insights feel obvious or wrong | Data gates, confidence shown, few cards, dismiss memory |
| AI invents numbers | It never sees raw data or writes digits; validation + templates |
| New JSON Xcode project format has gaps | Only Apple's CLI edits it; fall back to classic project/XcodeGen if needed |
