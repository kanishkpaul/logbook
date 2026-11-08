# Engineering patterns for a private macOS SwiftUI daily logbook (as of Nov 2026)

Method note: repo stars, last-push dates, licences and file contents below were pulled live from the GitHub API (`gh api`) on 2026-11-08. "Last push" = `pushed_at`, which is any branch push, not necessarily a release. Anything not checked that way is marked UNVERIFIED.

## 1. Open-source SwiftUI/Swift apps worth studying

### Takeaway
There is no mature, open-source macOS "daily logbook" that does time blocks + food + sleep together. The useful approach is to borrow pieces: Kadō (day boundaries, DST-safe tests, AI-assisted workflow), Point-Free's SQLiteData examples (SQL schema, triggers, observation), Dayflow (macOS timeline app on GRDB with a 4 AM day boundary), and TomatoBar/mater (menu bar timers). Open-source nutrition and sleep loggers in Swift are almost all small or abandoned.

### Cited Findings

**Repos verified on 2026-11-08 (stars / last push / licence)**

| Repo | Stars | Last push | What to borrow |
|---|---|---|---|
| [scastiel/kado](https://github.com/scastiel/kado): habit tracker (iOS) | 190 | 2026-10-15 | `DayBoundary` "logical day" type, DST test calendars, MVVM-lite rules, `CLAUDE.md` + `.claude/skills` for AI-assisted dev, local `Packages/KadoCore` |
| [pointfreeco/sqlite-data](https://github.com/pointfreeco/sqlite-data): SwiftData replacement on GRDB | 1,960 | 2026-11-06 (v1.12.1, 2026-10-09) | `Examples/Reminders`, `SyncUps`, `CaseStudies`, `CloudKitDemo`, with tests |
| [pointfreeco/syncups](https://github.com/pointfreeco/syncups): Scrumdinger rebuilt | 345 | 2026-06-11 | Modern SwiftUI + dependencies + tests |
| [pointfreeco/swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) | 15,007 | 2026-11-05 (latest 1.x tag 1.26.2, 2026-08-28) | TCA reference |
| [pointfreeco/swift-dependencies](https://github.com/pointfreeco/swift-dependencies) | 2,202 | 2026-10-30 | Built-in `date`, `calendar`, `timeZone`, `uuid`, `continuousClock` deps |
| [pointfreeco/swift-parsing](https://github.com/pointfreeco/swift-parsing) | 1,001 | 2026-10-23 (0.15.2, 2026-09-02) | Composable parsers for the markdown import |
| [pointfreeco/swift-clocks](https://github.com/pointfreeco/swift-clocks) | 350 | 2026-10-15 | `TestClock` / `ImmediateClock` |
| [pointfreeco/swift-structured-queries](https://github.com/pointfreeco/swift-structured-queries) | 368 | 2026-10-03 | Type-safe SQL used by SQLiteData |
| [pointfreeco/isowords](https://github.com/pointfreeco/isowords) | 3,008 | 2026-11-05 | Large TCA app split into many SPM modules |
| [groue/GRDB.swift](https://github.com/groue/GRDB.swift) | 8,727 | 2026-11-05 | SQLite toolkit: migrations, ValueObservation |
| [JerryZLiu/Dayflow](https://github.com/JerryZLiu/Dayflow): macOS automatic work journal / time tracker | 7,401 | 2026-11-03 | Local-first macOS timeline on GRDB, 4 AM day boundary, weekly and daily-brief views, AI summaries |
| [ivoronin/TomatoBar](https://github.com/ivoronin/TomatoBar): menu bar Pomodoro | 3,586 | 2026-05-29 | Small (7 Swift files) menu bar timer that computes from `finishTime`, so it survives machine sleep |
| [jasonlong/mater](https://github.com/jasonlong/mater): menu bar Pomodoro | 600 | 2026-10-01 | MIT; another small menu bar timer (architecture not inspected) |
| [michaelvillar/timer-app](https://github.com/michaelvillar/timer-app) | 2,719 | 2026-05-04 | Simple Mac timer UI |
| [exelban/stats](https://github.com/exelban/stats): menu bar system monitor | 43,216 | 2026-11-07 | Mature menu bar app with modules and a widget per module |
| [jordanbaird/Ice](https://github.com/jordanbaird/Ice): menu bar manager | 29,982 | 2026-10-06 | Advanced NSStatusItem/AppKit interop |
| [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp): Mastodon client | 7,104 | 2026-10-13 | Large SwiftUI app with `@Observable` + Environment ("MV") and feature packages |
| [nalexn/clean-architecture-swiftui](https://github.com/nalexn/clean-architecture-swiftui) | 6,604 | 2025-07-14 | Clean Architecture + SwiftData + DI sample (now slower-moving) |
| [jordibruin/Swift-Charts-Examples](https://github.com/jordibruin/Swift-Charts-Examples) | 2,449 | 2025-05-25 | Catalogue of Swift Charts chart types |
| [apple/sample-food-truck](https://github.com/apple/sample-food-truck) | 1,852 | 2023-08-18 (stale) | Swift Charts usage, multiplatform navigation (WWDC22) |
| [apple/sample-backyard-birds](https://github.com/apple/sample-backyard-birds) | 614 | 2023-12-11 (stale) | SwiftData sample (WWDC23) |
| [HabitRPG/habitica-ios](https://github.com/HabitRPG/habitica-ios) | 859 | 2026-11-07 | Long-lived production habit app, mostly UIKit-era |
| [ActivityWatch/activitywatch](https://github.com/ActivityWatch/activitywatch) | 19,551 | 2026-11-06 | Python/Rust, not Swift: event/bucket data model for time tracking (heartbeat events in buckets) |
| [openfoodfacts/openfoodfacts-ios](https://github.com/openfoodfacts/openfoodfacts-ios) | 380 | 2023-09-05, **archived** | Legacy only |
| [openfoodfacts/openfoodfacts-swift](https://github.com/openfoodfacts/openfoodfacts-swift): Swift SDK | 70 | 2026-11-04 | Optional barcode/nutrient lookup |
| [banghuazhao/longevity-master](https://github.com/banghuazhao/longevity-master): habit app | 17 | 2026-11-07 | Small; README says SwiftUI + GRDB (GitHub description says SQLiteData); CC BY-NC licence |
| [danielkuhlwein/strength-training](https://github.com/danielkuhlwein/strength-training) | 17 | 2026-11-05 | Small SwiftUI workout logger with iCloud (not inspected) |
| [toggl-open-source/toggldesktop](https://github.com/toggl-open-source/toggldesktop) | 1,867 | 2023-06-22, **archived**, C++ | Historical only |

- GitHub searches for Swift calorie or food-log apps return only tiny repos, mostly abandoned or prototypes: KAJU-Calorie-Counter (38★, 2023), NutriScan (22★, 2025-05), caloryn (3★), onigiri (5★). Sleep tracker searches likewise: twilight (7★), maby (25★, 2024). Journaling: locallog (51★, macOS, 2026-05). None is a strong reference. — GitHub search via `gh search repos`, 2026-11-08 (e.g. [VaggelisKa/caloryn](https://github.com/VaggelisKa/caloryn), [carlbarenbrug/locallog](https://github.com/carlbarenbrug/locallog))
- Kadō: "SwiftUI, `@Observable`, SwiftData, CloudKit, WidgetKit, App Intents — no cross-platform layer, no third-party dependencies". It ports Loop Habit Tracker's score as an exponential moving average and exports to JSON/CSV. — [kado README](https://github.com/scastiel/kado)
- Kadō ships a `CLAUDE.md` with explicit architecture rules for Claude Code and a `.claude/skills/conductor` workflow (plan/research/build/done). It also has dated plan docs under `docs/plans/` (e.g. `docs/plans/2026-08/day-start-hour/`). — [kado CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)
- Kadō's test suite has DST, day-boundary and backup tests: `DayBoundaryTests`, `LogicalDayWriteTests`, `BackupRoundTripTests`, `CSVRoundTripTests`, `KadoSchemaTests`, `CloudKitShapeTests`. — [kado KadoTests](https://github.com/scastiel/kado/tree/main/KadoTests)
- Dayflow uses GRDB (plus Sentry, PostHog, Sparkle) and buckets days with `getDayInfoFor4AMBoundary()`, which returns a `yyyy-MM-dd` day key plus start/end instants. — [Dayflow StorageDateHelpers.swift](https://github.com/JerryZLiu/Dayflow/blob/main/Dayflow/Dayflow/Core/Recording/StorageDateHelpers.swift); [Dayflow Package.resolved](https://github.com/JerryZLiu/Dayflow)
- The SQLiteData Reminders example defines `@Table` structs with raw-SQL migrations via GRDB `DatabaseMigrator`, foreign-key indexes, an FTS5 virtual table for search, and `createTemporaryTrigger` triggers for derived behaviour. — [sqlite-data Examples/Reminders/Schema.swift](https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift)

### Inferences
- For this app, the closest analogues are Kadō (logical day, tests, AI-dev workflow), Dayflow (macOS, GRDB, day timeline, weekly rollups) and TomatoBar (menu bar timer). Food logging is better learned from data-model principles (section 3) than from any repo.
- Kadō is iOS 18-only, but its domain core is in a local package (`Packages/KadoCore`), so its patterns transfer directly to macOS.

### Gaps
- Did not inspect the internal architecture of Dayflow, IceCubesApp, mater, stats or Ice beyond file layout and dependencies.
- No well-maintained open-source Swift nutrition logger with a food library and serving multipliers was found. Dedicated sleep or quantified-self Mac apps were also not found.
- Point-Free's SyncUps/Reminders do not model time intervals crossing midnight.

## 2. App architecture options in 2026

### Takeaway
For a solo developer working with an AI assistant, the 2026 consensus is plain SwiftUI: `@Observable` models and services injected through the Environment, with business logic in pure, Calendar-injected structs inside a local Swift package. Kadō shows this working at production quality. Point-Free's swift-dependencies and SQLiteData add testability without TCA's weight. TCA 2.0 was still beta-only (private, Point-Free Max) as of the latest information found, so a new project should not depend on it.

### Cited Findings
- Kadō rules: "Lightweight MVVM". ViewModels (`@Observable`) are used "only for views that mutate state outside of `@Query`-driven updates or share state across multiple views". Otherwise logic goes into "a free struct with injected `Calendar`" (pattern: `CompletionToggler`). Services are protocol-defined and injected via SwiftUI `Environment`; "No third-party DI framework". `@Entry` is used for `@MainActor` `@Observable` services. — [kado CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)
- Kadō bans Combine "unless there's no alternative" and keeps "Zero third-party dependencies for v0.x". — [kado CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)
- Thomas Ricouard (IceCubesApp author) wrote "SwiftUI in 2025: Forget MVVM". Per a secondhand Reddit summary, it argues for lightweight view structs and Environment-injected services over per-view ViewModels. Critics reply that these services are effectively view models under another name. (Article text paywalled, not read directly.) — [r/SwiftUI discussion](https://reddit.birdcat.cafe/r/SwiftUI/comments/1l1ki00/swiftui_in_2025_forget_mvvm)
- TCA 2.0 "beta preview" was announced 2026-04-01 as a private beta for Point-Free Max subscribers. It replaces reducers with an `@Feature` macro and adds `store.addTask`/`store.modify`, `onMount`/`onDismount` and automatic bindings via `$store`. It ships `ComposableArchitecture2` alongside a deprecated `ComposableArchitecture1` shim, so features can migrate one at a time. Version 1.25 added a `ComposableArchitecture2Deprecations` SwiftPM trait. — [Point-Free blog #206](https://www.pointfree.co/blog/posts/206-beta-preview-composablearchitecture-2-0); see also [Point-Free blog #200](https://www.pointfree.co/blog/posts/200-the-point-free-way-tca-2-0-sneak-peek-a-giveaway-q-a-and-more)
- No general-availability 2.0 tag appears on GitHub. The latest TCA releases are 1.26.x (1.26.0 on 2026-06-09, 1.26.2 on 2026-08-28) plus a 1.23.3 backport on 2026-09-18. — [TCA releases](https://github.com/pointfreeco/swift-composable-architecture/releases)
- swift-dependencies ships built-in dependency values for `Calendar`, `Clocks`, `Date`, `Locale`, `TimeZone`, `UUID`, `NotificationCenter`, `MainQueue`/`MainRunLoop` and more. — [swift-dependencies Sources/Dependencies/DependencyValues](https://github.com/pointfreeco/swift-dependencies/tree/main/Sources/Dependencies/DependencyValues)
- SQLiteData is configured with `prepareDependencies { $0.defaultDatabase = ... }` at app start, so it relies on swift-dependencies. Its `@FetchAll`/`@FetchOne` work in views and in `@Observable` models, unlike SwiftData's view-bound `@Query`. — [sqlite-data README](https://github.com/pointfreeco/sqlite-data)
- Modularisation examples: Kadō keeps domain services in a local package (`Packages/KadoCore/Sources/KadoCore/...`, e.g. `Services/DayBoundary.swift`). isowords and IceCubesApp split features into SPM modules. — [kado tree](https://github.com/scastiel/kado/tree/main/Packages/KadoCore); [isowords](https://github.com/pointfreeco/isowords)

### Inferences
- Recommended shape: an `App` target plus local packages, roughly `LogbookCore` (pure domain types, interval math, day attribution, aggregates, insights), `LogbookPersistence` (schema, migrations, queries), `LogbookImport` (parser, import plan) and `LogbookUI` (feature views). Pure packages build and test fast with `swift test`, which helps an AI agent iterate.
- A Kadō-style `CLAUDE.md` with explicit rules (no Combine, inject Calendar, where logic lives, how to test DST) is a useful way to constrain an AI assistant.
- TCA's exhaustive testing is valuable but adds ceremony. For a single-user CRUD + timer app, `@Observable` + swift-dependencies captures most of the testability benefit.

### Gaps
- Could not read Ricouard's article directly. No primary source was found that benchmarks MV vs MVVM vs TCA for solo developers; the claims above are opinions.
- TCA 2.0 OS and Swift version requirements were not stated in the beta post.

## 3. Data modelling

### Takeaway
Store instants as UTC `Date`s plus the IANA timezone at capture time, and fix each record's "logical day" when it is written, not when it is read. Kadō documents why: bucketing on read rewrites history when the user changes the day-start setting. Persistence options in 2026 are SwiftData (improved at WWDC26 with sectioned queries, `ResultsObserver` and `HistoryObserver`), and GRDB/SQLiteData. SQLiteData fits better here: you get SQL aggregates for charts, triggers for audit and soft-delete, and testable plain structs.

### Cited Findings
- Kadō's `DayBoundary` resolves a "logical day" given a user `startHour` (e.g. 4, so the day runs `[04:00, next 04:00)`). It is applied at exactly two points: reading (the reference date for calculators) and writing (the date stamped on a new record). "Because the day is fixed when the record is created, changing the setting later cannot move anything already logged. Bucketing on read instead would silently rewrite history." It also handles zones whose DST transition is at midnight (America/Havana, America/Santiago). — [kado DayBoundary.swift](https://github.com/scastiel/kado/blob/main/Packages/KadoCore/Sources/KadoCore/Services/DayBoundary.swift)
- Dayflow uses a fixed 4 AM boundary and stores a string day key (`yyyy-MM-dd`) alongside start/end instants. — [Dayflow StorageDateHelpers.swift](https://github.com/JerryZLiu/Dayflow/blob/main/Dayflow/Dayflow/Core/Recording/StorageDateHelpers.swift)
- ActivityWatch stores time as events (timestamp + duration + data) grouped into buckets per source. This is a generic interval-event model. — [ActivityWatch repo](https://github.com/ActivityWatch/activitywatch) (data-model detail from project docs, not fetched this session: UNVERIFIED detail)
- WWDC26 SwiftData additions:
  - `@Query(sort:, sectionBy:)` for sectioned results.
  - `@Attribute(.codable)` for opaque Codable blobs. These cannot be used in predicates or sorts and do not trigger migrations.
  - `ResultsObserver`, for observing fetches outside views.
  - `HistoryObserver`, an `eventCounter` plus `ModelContext.fetchHistory`, with author filtering.

  Source: [dev.to WWDC26 SwiftData summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5) and [Apple session 274](https://developer.apple.com/videos/play/wwdc2026/274). This is a secondary summary; the article itself notes a naming discrepancy (`ModelResultsObserver`) to check against the SDK.
- Fatbobman's SwiftData guidance:
  - Prefer basic property types.
  - Be cautious with custom Codable properties.
  - Avoid `@Attribute(.unique)`; make properties optional or defaulted (a CloudKit constraint).
  - For heavier needs, consider GRDB/SQLite.swift or `CKSyncEngine`.

  r/swift commenters add that SwiftData types are not Sendable (painful under Swift 6) and are hard to unit test. — [fatbobman: Key Considerations Before Using SwiftData](https://fatbobman.com/en/posts/key-considerations-before-using-swiftdata/); [r/swift thread](https://red.127.pp.ua/r/swift/comments/1j9jaz0/key_considerations_before_using_swiftdata)
- SQLiteData supports CloudKit sync and CloudKit sharing on top of GRDB, with `@Table` structs and `@FetchAll`/`@FetchOne`. It was formerly SharingGRDB, now deprecated in its favour. — [sqlite-data README](https://github.com/pointfreeco/sqlite-data); [Point-Free blog #168](https://www.pointfree.co/blog/posts/168-sharinggrdb-a-swiftdata-alternative)
- SQLiteData's Reminders example puts date logic in SQL (`date(dueDate) < date(now)`), uses FTS5 for search, and uses temporary triggers for derived updates. That is the mechanism for `updatedAt`, audit rows or soft-delete cascades. — [Reminders Schema.swift](https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift)
- Kadō has a `CloudKitShapeTests` test and archives habits rather than deleting them (`ArchivedHabitsView`). — [kado tree](https://github.com/scastiel/kado)

### Inferences (recommended model, synthesised)
- **TimeBlock** (`id`, `kind`: work/sleep/bathroom/custom, `categoryID`, `startUTC`, `endUTC?` where nil means running, `tzIdentifier`, `logicalDay` as a `yyyy-MM-dd` text key fixed on write, `note`, `source`: manual/timer/import, `isEstimate`, `importBatchID?`, `createdAt`, `updatedAt`, `deletedAt?`).
  - Day attribution is a per-kind rule. Work uses the logical day of the start under a configurable day-start hour, so 2250–0000 and 0100–0330 both land on the previous day with a 4 AM boundary. Sleep uses the wake day (the logical day of `end`).
  - Store the attributed day, as Kadō does, so changing the rule later does not silently move history. Provide an explicit "recompute attribution" migration instead.
  - For per-day totals that must split at midnight (e.g. "hours worked on calendar date X"), compute the overlap at query time by clipping intervals to day windows. Keep this separate from attribution.
- **Food library vs log.** `Food` (name, aliases, `servingSize`+unit, kcal/protein/caffeine per serving, `archivedAt`). `FoodLogEntry` (`foodID?`, `multiplier` or grams, plus *snapshotted* kcal/protein/caffeine and name at log time). Editing a library food then never rewrites past days. Shorthand lines like "pulao 250g - 408 / 8 / 0" become entries with explicit totals and an optional library link.
- **Daily summaries.** Derive these with SQL `GROUP BY logicalDay`. Cache only if profiling shows a need, keyed by day and invalidated by triggers. Store user-entered day-level values (Burn kcal, steps) as rows, not as summaries.
- **Custom metrics.** A typed hybrid. `MetricDefinition` (id, name, unit, valueType: number/duration/bool/interval, aggregation: sum/avg/max/last, `isBuiltin`) plus `MetricSample` (definitionID, logicalDay, instant?, numeric value, `isEstimate`, source). This is narrow EAV with typed numeric values, so it stays SQL-aggregatable. Use JSON only for unqueried extras; WWDC26 `.codable` blobs likewise cannot be queried.
- **Provenance.** Every row gets `source`, `importBatchID`, `isEstimate` (for "~" values) and an optional `rawText` (the original markdown line).
- **Soft delete and audit.** Add a `deletedAt` column and filter it everywhere through a base query. Add an append-only `ChangeLog` table (table, rowID, op, before/after JSON, at) written by triggers. On SwiftData, `HistoryObserver`/`fetchHistory` covers part of this.
- **Timezone/DST.** Never store wall-clock-only times. Keep `tzIdentifier` per block so travel days render correctly. Compute durations from instants (`end - start`), not from wall-clock subtraction; DST days are 23 or 25 hours long.

### Gaps
- No authoritative source was found comparing EAV vs typed tables vs JSON specifically for SwiftData/SQLite personal-tracking apps; the recommendation above is reasoned, not sourced.
- Did not verify SQLiteData's own docs on soft delete; the trigger approach is inferred from its trigger APIs.

## 4. Timers (start/stop, menu bar, survival across quit, sleep and crashes)

### Takeaway
Persist the running block (a `TimeBlock` with `endUTC = nil` and `startUTC` set) in the database the moment the user presses start. The UI derives elapsed time from `now - start`. It never accumulates ticks, so quit, crash and machine sleep are handled automatically. For display, use `Text(timerInterval:)` / `Text(date, style: .timer)` or `TimelineView(.periodic)`. The menu bar label needs care because SwiftUI timers inside `MenuBarExtra` have known update issues.

### Cited Findings
- TomatoBar stores `finishTime = Date().addingTimeInterval(...)` and recomputes the remaining time on each `DispatchSourceTimer` tick as `finishTime.timeIntervalSince(Date())`. A code comment notes "Ticks can be missed during the machine sleep", and it handles the overrun on wake. — [TomatoBar Timer.swift](https://github.com/ivoronin/TomatoBar/blob/main/TomatoBar/Timer.swift)
- TomatoBar updates the menu bar title through an `NSStatusItem` wrapper (`TBStatusItem.shared.setTitle`), not a SwiftUI `MenuBarExtra` label. — [TomatoBar Timer.swift](https://github.com/ivoronin/TomatoBar/blob/main/TomatoBar/Timer.swift)
- Apple Developer Forums report that a SwiftUI timer attached to a `MenuBarExtra` label does not refresh, and that an open menu can block the run loop. Suggested fixes: move the scene and content into separate `Scene`/`View` structs, drive the timer from a dedicated observable object, and use `.common` run-loop mode. — [Forums 726369](https://developer.apple.com/forums/thread/726369); [Forums 720625](https://developer.apple.com/forums/thread/720625)
- `Text.DateStyle.timer` and `Text(timerInterval:)` give self-updating text without app-side ticking. — [Apple docs: Text.DateStyle.timer](https://developer.apple.com/documentation/swiftui/text/datestyle/timer); [Forums 756971](https://developer.apple.com/forums/thread/756971) (reports a countdown bug and a workaround)
- Kadō has a `TimerLogSheet` and uses ActivityKit Live Activities, which take a start date and let the system render the timer. — [kado tree](https://github.com/scastiel/kado); [kado CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)

### Inferences
- Single source of truth: one "active block" row per kind, enforced with a partial unique index (`WHERE endUTC IS NULL AND deletedAt IS NULL`). The main window and menu bar both observe it through `@FetchOne` or `ResultsObserver`, so they stay in sync without app-level messaging.
- On launch, query for open blocks. If one is "suspiciously long" (e.g. over 16 hours, or across a sleep/wake gap), prompt the user to set the real end.
- Listen to `NSWorkspace.willSleepNotification` / `didWakeNotification` (UNVERIFIED in this session; standard AppKit API) to offer "you were away X minutes, keep or trim?". Do not adjust a stored counter, because there isn't one.
- For a menu bar title showing mm:ss, an `NSStatusItem` updated by a once-per-second timer (as in TomatoBar) is the battle-tested route. `MenuBarExtra` with `TimelineView` inside the label is cleaner, but verify it on the target macOS version.

### Gaps
- No primary 2026 source was found confirming whether `MenuBarExtra` label refresh issues are fixed in macOS 26/27.
- Did not verify `TimelineView` energy behaviour in menu bar labels.

## 5. Import parsers for the messy markdown log

### Takeaway
At 50–80 days of input, performance is irrelevant; pick for clarity and error reporting. Swift Regex/RegexBuilder handles per-line classification well. swift-parsing (v0.15.x, active) composes well for structured pieces like times, durations and the `kcal / protein / caffeine` triplet. Either way, use a two-phase pipeline: parse into an "import plan", show a dry-run diff, then commit as a reversible batch.

### Cited Findings
- swift-parsing describes itself as "A library for turning nebulous data into well-structured data, with a focus on composition, performance, generality, and ergonomics". 1,001★, release 0.15.2 on 2026-09-02. — [swift-parsing](https://github.com/pointfreeco/swift-parsing)
- Swift Regex has documented performance problems: construction cost inside loops, and roughly 10× slower than Java in one forum benchmark even on Swift 6.1.2, attributed to retain/release overhead. These matter for large inputs, not an 80-day log. — [Forums: Slow regex performance](https://forums.swift.org/t/slow-regex-performance/75768); [Forums: Regex initializer is painfully slow](https://forums.swift.org/t/regex-initializer-is-painfully-slow/79841)
- swift-parsing can also be slow in naive use: an HTML lexer took 14.8 s vs 77 ms hand-written, dominated by `Substring.distance`. Using UTF8View parsers is the usual fix. — [swift-parsing discussion #321](https://github.com/pointfreeco/swift-parsing/discussions/321)
- Kadō has import round-trip tests (`BackupImporterTests`, `BackupRoundTripTests`, `CSVReaderTests`) as a model for import correctness tests. — [kado KadoTests](https://github.com/scastiel/kado/tree/main/KadoTests)

### Inferences (design synthesised for this log format)
- **Grammar.** Treat each line as a list item; context comes from date headings.
  - Time block: `HHMM - HHMM [dur] > label`.
  - Food: `name [qty unit] - kcal / protein / caffeine`.
  - Sleep: `sleep -> HHMM - HHMM [dur]`.
  - Nature's call: `nc -> HHMM - HHMM [dur] [a / b / c]`, where the bracket triplet is sub-durations.
  - Burn: `Burn - N kcal`.
  - `~` prefix on any number sets `isEstimate`.
- **Validation.** The bracketed `[1h]` / `[8h 45m]` is redundant with start–end. Use it to validate: flag a mismatch rather than trusting either. Infer a midnight crossing when end < start.
- **Pipeline.**
  1. `parse(text) -> [ParsedLine]` (each with source line number and `rawText`, or a `ParseIssue`).
  2. `plan(parsed, existingDB) -> ImportPlan` (inserts, likely duplicates by `(logicalDay, kind, start, end)` or `(logicalDay, normalisedFoodName, kcal)`, unmatched foods to create in the library).
  3. A preview UI showing per-day counts, warnings and unknown lines.
  4. `apply(plan)` in one transaction, stamping `importBatchID`.
  5. Undo = delete (or soft-delete) `WHERE importBatchID = ?`.
- Keep the importer in a pure package with golden-file tests: input markdown snippet in, expected `ImportPlan` out. Ask the AI assistant to grow fixtures from real messy lines.

### Gaps
- Found no published Swift project that parses this exact shorthand style. No direct head-to-head comparison of RegexBuilder vs swift-parsing ergonomics on small inputs was found.

## 6. Charts engineering

### Takeaway
Swift Charts covers week, month and year views of daily totals easily, because the data is only hundreds of points. Do aggregation in SQL or the domain layer (daily rows), let Charts bucket by `unit: .weekOfYear`/`.month` or pre-bucket yourself, and make gaps explicit rather than letting lines interpolate. Vectorized plots (WWDC24) are only needed for thousands of marks.

### Cited Findings
- WWDC24 "Swift Charts: Vectorized and function plots" (session 10155) recommends vectorized plots (e.g. `RectanglePlot`, `LinePlot`, `AreaPlot`) for larger datasets styled uniformly. Its guidance: group data by style, use key paths, store computed values as stored properties, and drop imperceptible styling. Mark-based charts remain better for small, individually styled data. — [Apple WWDC24 10155](https://developer.apple.com/videos/play/wwdc2024/10155/); [WWDC Notes](https://wwdcnotes.com/documentation/wwdc24-10155-swift-charts-vectorized-and-function-plots/)
- Swift Charts examples catalogue (2,449★) and Apple's Food Truck sample show chart types and the date-unit APIs. — [Swift-Charts-Examples](https://github.com/jordibruin/Swift-Charts-Examples); [sample-food-truck](https://github.com/apple/sample-food-truck)
- Dayflow ships weekly views (`Views/UI/Weekly/Sections`, `Core/Weekly`) built on a day-keyed GRDB store, a real-world precedent for weekly rollups from day keys. — [Dayflow repo](https://github.com/JerryZLiu/Dayflow)
- WWDC26 SwiftData `sectionBy:` gives grouped fetches, but aggregation still happens in Swift. SQL `GROUP BY` via GRDB/SQLiteData aggregates in the database. — [dev.to WWDC26 SwiftData](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5); [sqlite-data README](https://github.com/pointfreeco/sqlite-data)

### Inferences
- **`DailyFacts`.** Build one query or view returning one row per logical day: work minutes, sleep minutes, kcal in, protein, caffeine, burn, steps, nc count/minutes, and an `estimate` flag. Every chart and insight reads from it.
- **Weekly and monthly series.** Generate the full calendar range of days with an injected Calendar (`firstWeekday` matters) and left-join actuals, so missing days are explicit `nil`. Render gaps as breaks (separate series segments) or zero bars, consistently.
- **Charting midnight-crossing data.** Sleep/work timelines (Gantt-style `BarMark(xStart:xEnd:y:)`) need clipping into the day windows they span, while totals use attribution. Keep both functions in the core package with tests.
- **Insights.** Rolling averages, streaks and correlations (e.g. caffeine after 4 PM vs sleep duration) are pure functions over `[DailyFacts]`. That makes them easy to test and easy for an AI assistant to extend.

### Gaps
- No 2026 source quantifies Swift Charts performance thresholds; the "over 1,000 points" rule of thumb seen online is not Apple's.

## 7. Testing strategy for date math and aggregates

### Takeaway
Inject `Calendar`, `TimeZone`, "now" and clocks everywhere. Pin tests to fixed calendars (UTC plus DST-transition zones) and fixed reference dates. Kadō's `TestCalendar` is a ready-made template. swift-dependencies and swift-clocks provide `date`, `calendar`, `timeZone` and `TestClock` for timer and model tests.

### Cited Findings
- Kadō's `TestCalendar` has a Gregorian UTC calendar, a fixed Monday reference date (2026-04-13 12:00 UTC) and `day(offset)` helpers. It adds `paris` (2026-03-29 has 23 hours, 2026-10-25 has 25) and `havana` (DST at midnight on 2026-03-08, which "Paris can't catch"). Its instant builder traps on non-existent wall times so test-authoring mistakes fail loudly. — [kado TestCalendar.swift](https://github.com/scastiel/kado/blob/main/KadoTests/Helpers/TestCalendar.swift)
- Kadō's `DayBoundary` takes an injected `Calendar` "so tests can pin to UTC for determinism and to a DST-crossing zone", and clamps `startHour` read from UserDefaults. — [kado DayBoundary.swift](https://github.com/scastiel/kado/blob/main/Packages/KadoCore/Sources/KadoCore/Services/DayBoundary.swift)
- swift-dependencies provides overridable `Date`, `Calendar`, `TimeZone`, `Locale`, `UUID` and clock dependencies. swift-clocks provides test clocks for Swift concurrency. — [swift-dependencies DependencyValues](https://github.com/pointfreeco/swift-dependencies/tree/main/Sources/Dependencies/DependencyValues); [swift-clocks](https://github.com/pointfreeco/swift-clocks)
- SQLiteData's examples ship test targets (`RemindersTests`, `SyncUpTests`, `CaseStudiesTests`). Since the database is a dependency, tests can use an in-memory database with seeded rows. — [sqlite-data Examples](https://github.com/pointfreeco/sqlite-data/tree/main/Examples)
- Point-Free's swift-snapshot-testing (4,390★, last push 2026-10-21) and swift-custom-dump (894★, 2026-08-28) help with readable diffs of parsed import plans and aggregate structures. — [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing); [swift-custom-dump](https://github.com/pointfreeco/swift-custom-dump)

### Inferences
- **Test matrix for this app.**
  - Blocks: 2250–0000, 0100–0330 and 2300–0700 sleep, each under day-start hours 0 and 4.
  - DST: blocks spanning spring-forward and fall-back (duration from instants, not wall time).
  - Timezone travel: a block started in one zone and ended in another.
  - Aggregates: weeks with missing days, and different `firstWeekday` values.
  - Food: snapshot immutability after a library edit.
  - Import: a golden test per shorthand variant, including "~", mismatched bracket durations, and unknown lines.
  - Import reversibility: import, undo, then confirm the DB is identical.
- Use property-style tests (random intervals; check that the sum of clipped per-day durations equals the total duration) to catch off-by-one errors at boundaries.

### Gaps
- Did not locate a Swift Testing-specific write-up (parameterised `@Test(arguments:)` for date matrices) from the suggested authors (Sundell, Donny Wals, objc.io) in this session. The suggested-author coverage is thin overall: only fatbobman was directly sourced.
