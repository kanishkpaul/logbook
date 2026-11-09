# logbook — notes for Claude

Private, single-user native macOS logbook (work blocks, food with kcal/protein/caffeine, burn/steps, nature's-call blocks, sleep) with to-do lists and a time-blocking calendar (plan vs actual). Personal use only; never distributed.

**Read first:** `docs/MASTER_PLAN.md` (what we're building and in what order) and `docs/research/stack-and-architecture-report.md` (why).

## Status
M3 daily driver and M4 food built, plus backups/export pulled forward from M8: daily `VACUUM INTO` snapshots (keep 30) in `<data>/Backups`, JSON export that restores exactly (round-trip tested), CSV export, Backups & Export screen, CLI `backup`/`export-json`/`export-csv`/`restore`. M4: meals (`meal x = a + b`), copy yesterday, favourites/recents quick-add, 7-day macro averages, caffeine/nicotine at usual bedtime (median sleep onset). M0 permission-survival checks still need the user's clicks. Decisions: calendar day (`DayBoundary.standard`); NC stores only the total; every `>` block is work; no targets (baselines only). M5 charts & trends built: Calendar (day/week/month), Work, Sleep, Body, Trends; `HistoryPresenter`/`CalendarPresenter` are pure and tested; `Stats` in Core (rolling mean, typical range = IQR, correlation with n≥8, linear fit) and `DayPart` (per-day clipping for grids). M6 plan built: v5 schema (`task_list`, `task` as `TodoTask`, `plan_block`, `plan_template`, `time_block.task_id/plan_block_id`), `Recurrence` (RRULE subset + `AFTER;`), `PlanShorthand` (`t …`, `plan …`), Tasks screen, plan ghosts, Up next, Close-the-day planning, templates. Not built (waiting on decisions #8/#9): importing existing to-dos, Apple Calendar overlay, drag-to-block. M7 proactive built: `InsightEngine` + 10 detectors in Core (`Detectors.swift`; add one = one struct + tests), BH at q=0.1 over correlation p-values (seeded permutation tests), memory in `insight_memory` (v6 adds dismissal), wording rules in `InsightText` (tested on every detector title); weekly Review (template prose); `NotificationPlanner` (pure, tested: cap 2 unrequested/day, quiet in usual sleep and running sleep, back-off after 3 ignored) + app `NotificationScheduler`. M8 polish built: generated icon (`make icon`, `tools/make-icon.swift`), `AppRouter` + ⌘K `CommandPalette` + Go/Timer menus (⌘1–⌘0, ⌥⌘W/S/N, ⌘., ⇧⌘D, ⌘L, ⌘K), welcome card, `Domain.other` lane, AX chart descriptors, Reduce Motion, open at login, backup mirror to iCloud Drive. M9 built: `RecapFact`/`RecapPrompt`/`RecapValidator`/`RecapTemplate` in Core; `RecapWriter` + `OnDeviceRecapModel` (Foundation Models, `@Generable`) in UI. Learned on macOS 27.0.1: regex `@Guide`s throw UnsupportedGuide, and the model ignores `{value}` placeholders, so it writes only a headline and neutral sentence openings; Swift appends value + comparison. Live check: `LIVE_AI=1 swift test --package-path Packages/LogbookUI --filter liveOnDeviceModel`. M10 built: App Intents in `App/Intents/LogbookIntents.swift` (Log anything via QuickEntry, Start/Stop timer, Add task, Log food with `FoodEntity`, Today so far) + `LogbookShortcuts` phrases; the store is injected with `AppDependencyManager` / `@AppDependency`; intent types can't be `nonisolated` (property wrappers). Custom metrics: `LogStore+Metrics`, `Metrics.spec(for:)`, Library › Metrics, `custom.<key>` in insights. Roadmap M0–M10 is built; open: decisions #8/#9, missed-log/morning-plan nudges, widgets/iPhone (paid account). Other open decisions are in master plan §16. Don't build past them without asking.

## Commands
- `make test` — `swift test` for Core, Persistence, Import and UI (fast; use this most).
- New tables must be added to `DataExport.restoreOrder` (parents before children) so JSON restore satisfies foreign keys.
- `make render` — renders key views on synthetic data to `build/shots/*.png` (ImageRenderer can't draw AppKit text fields/forms/buttons; those show as blanks). Prefer this to screen captures: the user's desktop may show private apps.
- `make demo DIR=/tmp/logbook-demo` — runs the app on a scratch data folder (`LOGBOOK_DATA_DIR`), never the real log. Seed it with `logbook-import apply … --db $DIR/logbook.sqlite`.
- `make build` / `make run` — xcodebuild Debug into `build/DD`, then open.
- `make format-check` — after every `xcrun xcodeproj` change.
- `make schema` — regenerate `Packages/LogbookPersistence/schema.sql`.
- `make install` — Release to `/Applications/Logbook.app` (one fixed path).
- `make spike-status` — what the M0 spike recorded on last launch.
- `make import-preview FILE=…` / `make import-apply FILE=…` / `make import-batches` — the importer against the live DB (`ARGS="--db path"` for another DB). Undo: `swift run --package-path Packages/LogbookImport logbook-import undo <batch-id>`.
- xcodebuild needs `-skipMacroValidation` (package macros); the Makefile passes it.

## Module map (dependencies point down)
- `App/` (synced folder, MainActor default): `LogbookApp` (AppDelegate owns store + models), `MenuBar/` (`StatusItemController` — NSStatusItem; **don't use `MenuBarExtra` with a timer label**: it layout-loops on macOS 27 — and `QuickEntryPanel` + Carbon `GlobalHotKey` with fallbacks), `Diagnostics/` (permissions, DB status, writes spike-status.json).
- `Packages/LogbookImport`: the shorthand everywhere: `ShorthandParser` (pure; values grammar kcal/protein/caffeine/nicotine + tags `c f p caf nic`), `FoodResolver` (dictionary rules shared by import and Quick Entry), `ImportPlanner` → `Importer.apply/undo`, `QuickEntry` (interpret → preview → commit, timer commands), `NutritionInput`, and the `logbook-import` executable. Depends on Core and Persistence. Fixtures are synthetic only.
- `Packages/LogbookUI`: `Today/` (`TodayModel` observes `LogStore.observe`; `TodayPresenter` is pure and tested and does all presentation maths via Core; views only lay out `TodayState`), `Dictionary/`, `Shell/` (Root, Import, Settings, MenuBarPanel, `PreviewSupport` synthetic data). MainActor default. Depends on Core, Persistence, Import.
- `Packages/LogbookPersistence`: `Schema` (append-only migrations, triggers, views), `@Table` records, `LogStore` (the only write path; applies attribution on write; its pure `…Row` builders let callers batch rows in one transaction), `AppDatabase`. Depends on Core, GRDB, SQLiteData. Record memberwise inits are internal: build rows through `LogStore`.
- `Packages/LogbookCore`: pure value types and maths, no dependencies.
- SQL is snake_case; Swift is camelCase via `@Column("...")`. Dates are UTC text `yyyy-MM-dd HH:mm:ss.SSS`, UUIDs lowercase text.
- Migrations name their own tables explicitly (v1 once read a shared list and broke when the list grew). A new table that holds logged data gets `installChangeLogTriggers` in its own migration and is listed in `Schema.auditedTables` (for reference). Altering an audited table means calling `installChangeLogTriggers` again in that migration.

## Stack (decided)
- Swift 6.4, Swift 6 language mode. SwiftUI + Swift Charts. macOS 27 deployment target.
- SQLite via GRDB `upToNextMinor(from: "7.12.0")` + SQLiteData `upToNextMinor(from: "1.12.1")`. Commit `Package.resolved`.
- No SwiftData, no Core Data, no web views, no second language (the importer is Swift too).
- Ad-hoc signing. **No iCloud/CloudKit/push entitlements** (they need a paid account).

## Project rules
- The Xcode project is the JSON `project.xcproj`. **Never hand-edit it**; use `xcrun xcodeproj` only, then run the formatter check. Create source files on disk inside synchronized folders.
- Nearly all code lives in local packages under `Packages/` (Core, Persistence, Import, UI). App target stays thin.
- Core / Persistence / Import: nonisolated defaults. UI and App: MainActor default isolation + Approachable Concurrency.
- Never silence concurrency errors with `@unchecked Sendable` or `nonisolated(unsafe)`.
- Views never do maths. All time comes from injected clock / calendar / time zone.
- Durations come from instants, never wall-clock subtraction. `logical_day` is fixed on write.
- Food log entries snapshot nutrition values; editing the library never changes history.
- "Not logged" is not zero. Estimates (`~`) carry `is_estimate`.
- UUID primary keys; no UNIQUE constraints other than the primary key (keeps CloudKit sync possible later).
- Every view has a `#Preview`; every bug fix gets a test; `schema.sql` is regenerated by a test.
- The LLM (Foundation Models) never computes or writes numbers; it only phrases precomputed facts.
- Insights: wording "on days when…", never "causes"; no medical claims.

## Privacy
Real personal log data never gets committed. Test fixtures use anonymised or synthetic snippets. The live database lives in `~/Library/Application Support/logbook/`.

## Planning rules
- `plan_block` (what was planned) and `time_block` (what happened) are separate tables; never merge them. Links go through `time_block.plan_block_id` / `task_id`.
- Recurrence is an iCalendar RRULE subset, tested like date maths.
- Apple Calendar (EventKit) is read-only and cached in `external_event`; never write to the user's calendars without an explicit feature for it.
