# SwiftUI on SQLite Wins the Mac Logbook

The best stack for this app in November 2026 is **Swift 6.4 + SwiftUI for the whole UI, with a plain SQLite file managed by GRDB 7.12 as the store, and Point-Free's SQLiteData 1.12 as the SwiftUI query layer on top of GRDB**. The October 2026 design pass (SwiftUI + GRDB, SwiftData rejected) holds. Two refinements are worth adopting: use SQLiteData's `@FetchAll`/`@FetchOne` instead of a hand-rolled observation layer, and design the schema to CloudKit-sync rules from day one even though sync stays off. No web or cross-platform stack gets real Liquid Glass controls, and every one of them still needs Swift for widgets and App Intents. SwiftData still has no aggregate or group-by queries, which a metrics-and-charts app needs on every screen. The free/paid boundary is sharper than it looks. Everything in the core app runs ad-hoc signed with no Apple Developer Program membership: windows, charts, menu bar timers, local notifications, on-device Foundation Models, and backup/export. **CloudKit sync, a long-lived iPhone/Watch companion, push, and HealthKit on the phone all need the $99/yr membership**, and widgets are unreliable without at least a stable team identity. HealthKit data is not readable on the Mac at all. For CLI-driven AI development, Xcode 27.2 helps a lot: its new JSON project format and Apple's own `xcrun xcodeproj` CLI, both already on this machine, let an agent manage the project without third-party generators. Most of the effort will go into the data model (midnight-crossing blocks, fixed day attribution, snapshot nutrition, provenance), the import pipeline, and an insight engine in which Swift computes every number and the on-device LLM only phrases it.

*How to read this report: statements with a link are sourced. "Local check" means the research team verified it by running commands on this Mac on 2026-11-08. Statements marked **Inference** are design judgments from the research team, not sourced facts. Release years marked "year inferred" come from GitHub pages that omit the year.*

## Native SwiftUI on a plain SQLite file beats every alternative

### The UI layer: only SwiftUI gets Apple-grade chrome for free

The deciding requirement is "Apple-grade premium UI" on macOS 26/27, and here the alternatives are not close. In SwiftUI, standard toolbars, sidebars and controls pick up Liquid Glass automatically. At WWDC26, Apple said apps rebuilt for the 2027 releases adopt the refined glass automatically, follow the new system-wide Liquid Glass tint/transparency slider, and can mark custom glass "interactive" on macOS for smoother pointer response ([WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)). `NSGlassEffectView` is a **public** AppKit class from macOS 26 ([Apple docs](https://developer.apple.com/documentation/appkit/nsglasseffectview)). Web and cross-platform stacks can use it only as a backdrop behind their own drawn content.

The Tauri bridge, `tauri-plugin-liquid-glass`, is a community plugin at 0.1.6 with about 19 stars. It requires the macOS private-API flag ([docs.rs](https://docs.rs/tauri-plugin-liquid-glass); [ecosyste.ms](https://awesome.ecosyste.ms/projects/github.com%2Fhkandala%2Ftauri-plugin-liquid-glass)). Electron's equivalent puts glass *behind* the web content, and its variant and scrim methods carry a "DO NOT USE IN PROD" warning ([electron-liquid-glass README](https://app.unpkg.com/electron-liquid-glass@1.0.1/files/README.md)). Electron also needed its 40.0 release in January 2026 to fix excessive WindowServer GPU usage on Tahoe, which matters for an app meant to sit in the menu bar all day ([Electron 40 blog](https://www.electronjs.org/blog/electron-40-0)). Flutter's Liquid Glass tracking issue was still P3 in October 2026, and `cupertino_ui` 1.1.3 has no glass material ([issoh.co.jp, citing flutter/flutter #170310](https://www.issoh.co.jp/tech/details/16743/)). Compose's best attempt (Nucleus) uses native traffic lights and sidebar glass but draws everything else itself. Its own docs admit that the native and drawn layers must be kept in sync by hand ([Nucleus wiki](https://github.com/NucleusFramework/compose-macos-26-ui/wiki)).

The second disqualifier is structural. **Widgets and App Intents require Swift in every stack.** Tauri's widget plugin says the extension is built by Xcode as a separate project ([tauri-plugin-widgets](https://docs.rs/crate/tauri-plugin-widgets/0.3.0/source/README.md)). Flutter's widget packages say presentation "has to be written using Swift/SwiftUI" ([widget_kit_plugin](https://pub.dev/documentation/widget_kit_plugin/latest/)). Flutter has "no official App Intents integration and no committed plan" ([VGV, WWDC 2026 through a Flutter lens](https://verygood.ventures/blog/wwdc-2026-through-a-flutter-lens/)). A cross-platform choice therefore becomes a two-language project as soon as Spotlight logging, Shortcuts or a desktop widget is wanted. No non-Swift stack builds a watchOS app.

The cross-platform stacks do have real strengths: cross-OS reach, a deeper charting ecosystem, and the larger web corpus AI assistants have trained on. None of these matters much for a private, Mac-only app. The previously archived Tauri attempt fits this picture (Inference).

**Ranked recommendation and comparison**

| Rank | Stack | Liquid Glass / native controls | Widgets, App Intents, Watch | Charts | Footprint | AI-assistant fit | Verdict |
|---|---|---|---|---|---|---|---|
| 1 | **SwiftUI + SQLiteData 1.12 on GRDB 7.12** | Real, automatic, follows macOS 27 slider | Same project, same language | Swift Charts (Apple look, works in widgets) | Native, small | SQL migrations are legible; StructuredQueries DSL is less familiar, but `#sql` falls back to raw SQL | **Recommended** |
| 2 | SwiftUI + plain GRDB 7.12 (+ GRDBQuery 0.11 or a small `@Observable` wrapper) | Same | Same | Same | Same, fewer dependencies | Most legible: plain SQL and Codable structs | Conservative alternative; same file format, easy to switch either way |
| 3 | SwiftUI + SwiftData | Same | Same; built-in CloudKit (paid only) | No aggregates, so every chart is fetch-and-reduce | Same | Implicit schema, `VersionedSchema` ceremony, runtime-only crash feedback | Only for a much simpler, CloudKit-first app |
| 4 | SwiftUI + Core Data | Same | Same | SQL-pushed aggregates via `NSExpression` | Same | `.xcdatamodeld` XML and `perform {}` threading are error-prone for agents | No advantage here |
| 5 | Tauri 2 (WKWebView) | Window backdrop only; controls are imitations | Separate Swift/Xcode project | Web libraries (deepest ecosystem) | ~172 MB with six windows; ~8.6 MiB bundle | Strong for UI code, weak at native seams | Already tried and archived |
| 6 | Electron 40+ | Backdrop only; private-API knobs | Separate Swift project | Web libraries | ~409 MB with six windows; ~244 MiB bundle | Strong for UI code | Too heavy for an always-on menu bar app |
| 7 | Flutter 3.47 / RN-macOS 0.83 / Compose MP 1.11 | Imitation; no official glass | Separate Swift project | fl_chart / limited | JVM (Compose) or engine overhead | Mixed | Not suitable |

Memory and bundle figures are from one comparison ([Hopp on DEV](https://dev.to/gethopp/tauri-vs-electron-performance-bundle-size-and-the-real-trade-offs-1el4)). The react-native-macos and Compose versions are from [GitHub](https://github.com/microsoft/react-native-macos/releases/tag/react-native-macos%400.83.0) and the [Nucleus wiki](https://github.com/NucleusFramework/compose-macos-26-ui/wiki). The research found no rigorous 2026 benchmark covering all of these stacks.

Swift Charts covers every chart this app needs. Time-block Gantt rows come from `BarMark(xStart:xEnd:y:)` or `RectangleMark`, heatmaps from `RectangleMark` plus a gradient scale, and sparklines from axis-less `LineMark`s, with selection and scrolling since macOS 14. WWDC24 added vectorized plots for large datasets ([WWDC24 session 10155](https://developer.apple.com/videos/play/wwdc2024/10155/)). The research found no new Charts APIs at WWDC26 ([Swift with Majid recap](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/)). One low-confidence report mentions a regression with deeply branching chart content on OS 27 ([rabinarayanpatra.com](https://www.rabinarayanpatra.com/blogs/ios-27-for-developers)). That is one more reason to keep each chart's body simple and its data pre-aggregated.

### The data layer: SQL aggregates and a legible schema decide it

SwiftData improved at WWDC26: sectioned `@Query(sectionBy:)`, `@Attribute(.codable)`, `ResultsObserver` and `HistoryObserver` ([WWDC26 session 274](https://developer.apple.com/videos/play/wwdc2026/274/); [DEV summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)). It still has **no SQL-pushed sum/avg/min/max or group-by**. The documented workarounds are sort-plus-limit for min and max, or running a Core Data stack against the same file for anything else ([Blake Crosley, June 2026](https://blakecrosley.com/blog/swiftdata-performance-storage-engine); [Apple forums 832186](https://developer.apple.com/forums/thread/832186)). The new `.codable` attributes are opaque blobs that cannot be filtered or sorted and do not migrate when their shape changes. Model inheritance, the WWDC25 headline, has open crash reports on 26.x ([forums 802130](https://developer.apple.com/forums/thread/802130); [812212](https://developer.apple.com/forums/thread/812212); [800033](https://developer.apple.com/forums/thread/800033)). Point-Free's WWDC26 review adds that `sectionBy` only groups by stored `String` fields and that observation re-runs queries on unrelated property changes. Point-Free maintains a competing library, so treat that critique as biased ([Point-Free ep. 372](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)).

GRDB, by contrast, is mature and current. **v7.12.0 shipped 1 Nov 2026 (year inferred)** with a WAL snapshot-ordering fix and a `SharedValueObservation` deadlock fix, and the 7.x line has required Swift 6.1+ since 7.9.0 ([GRDB releases](https://github.com/groue/GRDB.swift/releases)). It gives append-only named migrations, `ValueObservation` as an async sequence, FTS5, WAL `DatabasePool`, Codable records and an online backup API ([GRDB README](https://raw.githubusercontent.com/groue/GRDB.swift/master/README.md)).

SQLiteData (formerly SharingGRDB) is a SwiftData-style layer over GRDB and is **MIT-licensed**. It provides `@Table` structs, `@FetchAll`/`@FetchOne` that work in views *and* in `@Observable` models, type-safe StructuredQueries with a raw `#sql` escape hatch, and a CKSyncEngine-based `SyncEngine` for CloudKit ([sqlite-data README](https://github.com/pointfreeco/sqlite-data)). It reached 1.0 around September 2025 ([Point-Free blog 187](https://www.pointfree.co/blog/posts/187-new-in-sqlitedata-migration-tool-for-cloudkit-sync)), and **1.12.1 shipped 9 Oct 2026 (year inferred)** with no breaking releases in its recent history ([releases](https://github.com/pointfreeco/sqlite-data/releases)). It pulls in roughly a dozen Point-Free packages, including StructuredQueries, which is still 0.x ([Package.swift](https://raw.githubusercontent.com/pointfreeco/sqlite-data/main/Package.swift)).

| Store | Aggregates for charts | Schema legibility for an AI agent | Backup / export | Future iPhone sync (paid) | Verdict |
|---|---|---|---|---|---|
| SQLiteData on GRDB | SQL `GROUP BY`, window functions; `@FetchAll` observes aggregate queries | SQL migrations + `@Table` structs | Single SQLite file; online backup / `VACUUM INTO`; readable by `sqlite3` | Built-in `SyncEngine` if schema follows its rules | **Primary** |
| Plain GRDB | Same | Best: SQL migrations + Codable structs | Same | Hand-write a CKSyncEngine delegate (large job) | Fallback |
| SwiftData | None; fetch-and-reduce or Core Data coexistence | Implicit; `VersionedSchema` + frozen old models | Z-prefixed Core Data tables; export via app code only | Built-in CloudKit, but optional relationships, no `.unique` | Reject |
| Core Data | `NSExpression` aggregates | XML model, verbose threading | Same Z-table opacity | `NSPersistentCloudKitContainer` | Reject |

**Verdict on the October 2026 design pass: it holds.** Its SwiftData rejection is well founded, for analytic and schema-evolution reasons rather than speed. At roughly 10–50 rows a day, every candidate is fast enough (Inference). The only addition is to put SQLiteData on top of GRDB and adopt its sync-compatible schema rules now. Those rules are **UUID primary keys** and **no UNIQUE constraints except on the primary key** ([Point-Free blog 187](https://www.pointfree.co/blog/posts/187-new-in-sqlitedata-migration-tool-for-cloudkit-sync); [sqlite-data PR #456](https://github.com/pointfreeco/sqlite-data/pull/456/files)). The database file and migrations are plain GRDB either way, so dropping SQLiteData later costs little (Inference).

## Version pins and a JSON project file make the CLI loop native

### What to pin

| Component | Pin | Evidence |
|---|---|---|
| macOS (dev and runtime) | 27.0.1 | Local check (`sw_vers`) |
| Xcode | 27.2, build 27B52 | Local check; 27.2 bundles Swift 6.4 and requires macOS 26.6+ ([Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)) |
| Swift toolchain | 6.4.2, Swift 6 language mode | Local check (`swift --version`) |
| Deployment target | macOS 27.0 | **Inference**: a single-machine app gains nothing from back-deploying and gets Foundation Models' runtime `contextSize` APIs |
| Project file | `project.xcproj` (JSON), edited only via `xcrun xcodeproj` | [Apple](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format); local check |
| GRDB.swift | `.upToNextMinor(from: "7.12.0")` | [GRDB releases](https://github.com/groue/GRDB.swift/releases) |
| SQLiteData | `.upToNextMinor(from: "1.12.1")` | [sqlite-data releases](https://github.com/pointfreeco/sqlite-data/releases) |
| Transitive: swift-structured-queries ≥ 0.39.1, swift-dependencies ≥ 1.9.0 | Lock via committed `Package.resolved` | [Package.swift](https://raw.githubusercontent.com/pointfreeco/sqlite-data/main/Package.swift) |
| GRDBQuery (only for the plain-GRDB route) | 0.11.0 | [GRDBQuery releases](https://github.com/groue/GRDBQuery/releases) |
| Tests | Swift Testing (bundled); XCTest only for UI tests | [Point-Free blog 146](https://pointfree.co/blog/posts/146-swift-testing-support-for-snapshottesting) |
| swift-snapshot-testing | 1.19.2 (confirm on GitHub before pinning) | [dev.co listing](https://dev.co/testing/open-source/swift-snapshot-testing) (third-party) |
| swift-parsing (optional, importer) | 0.15.2 | [swift-parsing](https://github.com/pointfreeco/swift-parsing) |
| XcodeGen (fallback only) | 2.46.0 | [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases) |

Pin to `upToNextMinor` and commit `Package.resolved`. GRDB shows why: 7.6.0 had a race on cancelled async accesses that 7.6.1 fixed ([newreleases](https://newreleases.io/project/github/groue/GRDB.swift/release/v7.6.0)). Read release notes before moving to a new minor.

### Project setup for an agent driving the CLI

Xcode 27.2 settles the project-generator question that XcodeGen and Tuist used to answer. Apple's documentation states that "in Xcode 27.2 and later, the default project configuration file is a smaller, hierarchical, self-describing JSON file with a `.xcproj` extension." It explicitly says the format "makes it easier for coding intelligence agents to edit" and reduces merge conflicts ([Apple](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)). The local check confirmed that `xcrun xcodeproj` is installed. Its subcommands are `init`, `setting`, `target`, `group`, `config` and `pkg`, and `target add` accepts `application`, `app-extension`, `tool`, `unit-test-bundle`, `watch-app` and full product-type identifiers. That covers the widget extension and iPhone/Watch targets later.

Artem Novichkov's October 2026 walkthrough documents the gotchas ([Artem Novichkov](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents)):

- `init` does not set `SWIFT_VERSION` or the deployment target.
- Add build phases *before* attaching a synchronized folder, or the exclusions break linking.
- Test targets need `TEST_HOST`, `BUNDLE_LOADER` and `ENABLE_TESTABILITY` wired by hand.
- `xcprojformatter --update` silently drops unknown keys, so a formatter diff exposes typos.
- Xcode's own MCP tools cannot add packages, link xcconfigs or edit build phases.

His rule for agents belongs verbatim in `CLAUDE.md`: never hand-edit the project file, create files on disk inside synchronized folders, and run a formatter check after every change. XcodeGen 2.46.0 supports synced folders and `.appex` embedding and is the fallback if this proves too low-level. It writes pbxproj, not JSON ([XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases)). Tuist's JSON support is still experimental ([tuist/XcodeProj 9.17.0](https://github.com/tuist/XcodeProj/releases/tag/9.17.0)), and its roadmap targets teams, so it is more than this project needs.

The layout should keep the Xcode project thin and put nearly all code in local Swift packages. The agent can then iterate with `swift build`/`swift test` and reach for `xcodebuild` only for app or extension integration (Inference, consistent with [Kadō's `Packages/KadoCore`](https://github.com/scastiel/kado/tree/main/Packages/KadoCore)):

```
Logbook/
  Logbook.xcodeproj/          project.xcproj (JSON) — edit only via `xcrun xcodeproj`
  App/                        synced folder: LogbookApp.swift, MenuBar, Assets, entitlements
  Packages/
    LogbookCore/              domain types, interval math, day attribution, aggregates, insights (nonisolated)
    LogbookPersistence/       schema, migrations, queries, backup/export
    LogbookImport/            parser + ImportPlan, and `logbook-import` executable
    LogbookUI/                feature views with #Preview (MainActor default isolation)
  Fixtures/                   anonymised snippets of the real Notes logs (golden tests)
  scripts/ or Makefile        build, run, test, screenshot, install
  CLAUDE.md (+ AGENTS.md symlink)
```

The CLI loop runs as follows (Inference, standard tools). Build with `xcodebuild -scheme Logbook -destination 'platform=macOS' -derivedDataPath build/DD build`. Launch with `open -n` on the built app. Test packages with `swift test --package-path Packages/LogbookCore`. Take screenshots with `screencapture`, which needs Screen Recording permission for the terminal. Two Apple tools sit on top of that. Xcode 27.2's `mcpbridge` (local check) exposes Xcode's MCP tools, and its RenderPreview tool can now render `#Preview`s to a chosen destination, so an agent can "see" a view without launching the app ([Xcode 27.2 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)). Third-party XcodeBuildMCP adds `build_run_macos`, though its screenshot tooling targets simulators ([setup guide](https://chriscalo.github.io/dev-skills/skills/apple-dev/xcodebuildmcp-setup)).

For concurrency, use Swift 6 mode with Approachable Concurrency and MainActor default isolation in UI targets, and nonisolated defaults in Core, Persistence and Import. In `Package.swift` that is `.defaultIsolation(MainActor.self)` plus the `NonisolatedNonsendingByDefault` and `InferIsolatedConformances` upcoming features ([Use Your Loaf](https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/)). The raw Xcode build-setting key names were not confirmed, so read them from `xcodebuild -showBuildSettings` before setting them. Expect two Xcode 27 source breaks: `@State` is now a macro with lazy initialization (TN3211), and SE-0508 changes init accessors. `PreviewProvider` is deprecated in favor of `#Preview` ([WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/); [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release), secondary).

`CLAUDE.md` should hold the exact commands, the module map and dependency direction, the concurrency policy (no `@unchecked Sendable` or `nonisolated(unsafe)` to silence errors), "a `#Preview` per view, a test per bug fix," and the signing rule: no iCloud or push entitlements. Kadō is a working precedent. It is a production SwiftUI habit app with a `CLAUDE.md`, `.claude/skills` workflows and dated plan documents ([Kadō CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)).

To install for yourself: build Release, quit the running copy, `ditto` it to `/Applications/Logbook.app`, and open it. Self-built apps carry no quarantine attribute, so Gatekeeper does not intervene ([Apple forums 740680](https://developer.apple.com/forums/thread/740680)). Launch-at-login uses `SMAppService.mainApp.register()` ([Apple](https://developer.apple.com/documentation/servicemanagement/smappservice)). Keep exactly one copy in `/Applications`, because stale copies are a known cause of login items that register but never launch ([forums 726826](https://developer.apple.com/forums/thread/726826); [777520](https://developer.apple.com/forums/thread/777520)).

## Free signing runs the core app; $99 buys sync, phones and safe widgets

### What works without a paid membership

Apple's TN3125 says: "Unlike Apple's other platforms, macOS doesn't require a provisioning profile to run third-party code." It also says that a Mac app using no restricted entitlements needs no profile at all ([TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)). "Sign to Run Locally" (ad-hoc, `codesign -s -`) is therefore enough for this app. The 7-day expiry of free provisioning profiles does not apply because there is no profile (Inference from TN3125). The line that matters is Apple's macOS capability table. Parsed from the page HTML, it shows **iCloud CloudKit, iCloud Documents and iCloud key-value storage unavailable to free "Apple Developer" accounts**, while App Groups and App Sandbox are available ([Apple: supported capabilities, macOS](https://developer.apple.com/help/account/reference/supported-capabilities-macos)). A second researcher could not read the checkmarks on the same page, but Apple's CloudKit setup guide also requires an active paid membership ([Enabling CloudKit](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app.md)). Apple DTS confirms that personal teams lack Push and iCloud ([forums 811929](https://developer.apple.com/forums/thread/811929)).

App Groups have a catch. On macOS 15 and later, an *ad-hoc* signed app that touches a group container gets a persistent privacy prompt. Apple DTS says a provisioning profile cannot fix that for ad-hoc apps ([forums 767604](https://developer.apple.com/forums/thread/767604)). macOS group IDs should also be Team-ID-prefixed rather than `group.`-prefixed ([forums 767581](https://developer.apple.com/forums/thread/767581); [758478](https://developer.apple.com/forums/thread/758478)). Desktop widgets and menu-bar Controls are sandboxed extensions that normally read the app's data through an App Group, so they are the first feature to hit the signing wall.

| Capability | Ad-hoc ("Sign to Run Locally") | Free Personal Team identity | Paid ADP ($99/yr) |
|---|---|---|---|
| SwiftUI, Liquid Glass, Swift Charts, `MenuBarExtra`, `TimelineView` | Works | Works | Works |
| Local notifications with actions | Works (Inference); permission may reset when the signature changes | Works; stable identity (Inference) | Works; Time Sensitive is a provisioned capability ([Apple](https://developer.apple.com/help/account/reference/supported-capabilities-macos)) |
| On-device Foundation Models | Should work on an Apple Intelligence–eligible Mac with AI enabled; no entitlement (Inference, untested ad-hoc) | Same | Same |
| Private Cloud Compute model (32K context) | No | No | Entitlement by application ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)) |
| App Intents → Shortcuts / Spotlight actions | Probably (unverified); install in `/Applications` | Probably | Yes |
| Login item (`SMAppService`) | Works; may need re-approval after rebuilds (unverified) | More stable (Inference) | Yes |
| App Groups → widgets, menu-bar Controls | **Persistent prompt on macOS 15+** ([DTS](https://developer.apple.com/forums/thread/767604)) | Plausible with a Team-ID group; unverified on macOS 27 | Reliable |
| CloudKit / iCloud Documents / KVS sync | No | No | Yes |
| Push / widget push | No | No | Yes |
| iPhone / Watch companion install | n/a | Profile expires after ~7 days ([forums 69248](https://developer.apple.com/forums/thread/69248)) | ~1-year profiles |
| HealthKit on the Mac | Not available at any tier | — | — |

**Inference: don't pay yet.** Ship the whole Mac app ad-hoc. Early on, run a half-day spike that signs with a free Personal Team "Apple Development" identity and checks three things: whether notification permission, the login item and a Team-ID App Group container survive rebuilds without prompts. Buy the membership when the iPhone/Watch companion becomes real, because that is the point where CloudKit sync, HealthKit on the phone and non-expiring installs all become necessary together. The cheapest sync path then is turning on SQLiteData's `SyncEngine`, which only works if the schema already follows its rules.

### HealthKit on the Mac is still a dead end

Apple DTS stated in September 2025 that "your app can't read or write HealthKit data on macOS as of today. isHealthDataAvailable() will return you false." A March 2026 follow-up in the same thread asking about macOS support went unanswered ([Apple forums 798780](https://developer.apple.com/forums/thread/798780)). HealthKit does not appear in Apple's macOS capability list ([Apple](https://developer.apple.com/help/account/reference/supported-capabilities-macos)), and post-WWDC26 macOS 27 recaps mention no Health app for the Mac ([TechRadar](https://techradar.com/computing/mac-os/macos-27-golden-gate-announced-at-wwdc-2026-heres-everything-you-need-to-know)). The macOS 27 SDK does annotate some new HealthKit symbols with macOS availability ([miniswift.run](https://miniswift.run/whats-new/healthkit/), secondary). Availability annotations do not mean live Health data exists on the Mac, so plan as though it does not.

There are three workarounds, in order of cost (Inference). The first is free: manual entry of steps and burn, which is what the Notes logs already do ("Burn – N kcal"), plus an optional importer for the iPhone Health app's "Export All Health Data" `export.zip`. The importer parses `StepCount`, `ActiveEnergyBurned` and `SleepAnalysis` records from `export.xml`, a route the forum thread itself suggests. The second is also free: a user-built iPhone Shortcut that writes daily Health samples as JSON to an iCloud Drive folder the Mac app watches. An unsandboxed Mac app needs no entitlement to read a plain iCloud Drive path. The third needs the paid tier: a native iPhone companion that reads HealthKit and syncs through CloudKit. A side benefit of a companion is that its Live Activities (say, a running work block) appear in the Tahoe menu bar automatically, with no Mac code ([WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)).

## Great logbooks compare you with yourself, not with a scoreboard

### Information architecture: a sparse Today, a baseline layer, and slow trends

The leading health apps have converged on three layers. Oura cut five tabs to **Today, Vitals and My Health**. Today has score shortcuts, a time-of-day-dependent highlight and a day timeline. Vitals shows each metric against the user's *personal baseline range*. My Health holds long-term trends and weekly, quarterly and yearly reports ([Oura blog](https://ouraring.com/blog/new-oura-app-experience/)). Oura's 2025 redesign went further toward "One Big Thing" and widened the overview window from one month to twelve ([9to5Google](https://9to5google.com/2025/10/20/oura-app-redesign/)). Apple Health's Summary runs **Pinned → Trends → Highlights** ([Apple Support](https://support.apple.com/en-ie/HT203037)). Apple's Sleep Score breaks into duration, bedtime consistency and interruptions ([AppleInsider](https://appleinsider.com/articles/25/09/12/how-sleep-score-works-on-apple-watch-with-watchos-26)). Apple's HIG says to keep charts simple with detail on demand, put a plain-language headline above each chart, prefer common chart types, and keep small and expanded versions of a chart visually continuous ([HIG: Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)).

**Inference for this app:** a `NavigationSplitView` sidebar (Today, Timeline, Food, Sleep, Work, Trends, Library, Import, Settings) with system chrome providing the Liquid Glass. Reserve custom `glassEffect` for one or two floating controls, such as a quick-log pill. Keep charts on standard backgrounds for legibility and test them at both ends of the macOS 27 glass slider and with Reduce Transparency. The Today canvas carries three to five pinned hero metrics: work today, net kcal, protein, caffeine now, last sleep. Each gets a one-sentence headline ("Worked 6 h 10 m, 40 m above your 4-week average") and a sparkline, followed by the 24-hour timeline, then at most three insight cards. Use one semantic colour per category everywhere, SF Pro with tabular figures for timers, and no red/green moralising. MacroFactor's target circles deliberately "never turn orange or red" ([MacroFactor](https://macrofactor.com/timeline-based-food-logger/)). Streaks capped its goals to stay uncluttered ([MacStories](https://www.macstories.net/?p=49979)). Exist's survey found correlations divisive, with complaints about "obvious correlations" ([Exist blog](https://exist.io/blog/post/use-cases/)). Insights should therefore be few and earned.

### Fast entry: keep the Notes shorthand as the input language

The user's Apple Notes shorthand (`0945 - 1045 [1h] > study`, `pulao 250g - 408 / 8 / 0`) is effectively a domain-specific language, and the fastest products show how to honour it. Things 3 puts a **system-wide Quick Entry on Ctrl+Space** ([Cultured Code](https://culturedcode.com/things/support/articles/2249437/)). Fantastical parses near-natural sentences and animates parsed tokens into fields *as you type*, but reviewers found its vocabulary brittle at the edges ([MacStories](https://www.macstories.net/news/preview-fantastical-upcoming-calendar-app-for-mac/)). MacroFactor's vendor-run Food Logging Speed Index counted **24 actions for four standard tasks versus 30–35 for the next-best apps**. Its speed came from reusing a food's last-logged serving and from raw-number Quick Add, the fastest method overall ([MacroFactor FLSI 2025](https://macrofactor.com/fastest-food-logger-2025/)). Its timeline logger adds copy, multi-paste to several days, and "To Today/To Tomorrow" ([MacroFactor](https://macrofactor.com/timeline-based-food-logger/)). Exist found that **69% of custom-tag users log once at the end of the day** ([Exist](https://exist.io/blog/post/use-cases/)), so retroactive batch entry matters as much as live capture.

**Inference:** build one global-hotkey capture field that accepts the shorthand (`0945-1045 study`, `pulao 250g`, `nc 1210 8m`, `sleep 0330-1015`, `coffee`) and shows a live parsed preview before commit. Food lines with explicit macros become Quick Add entries with a "save as food" offer. Name-plus-grams lines scale a library food and remember the last quantity. Add a ⌘K command palette, "copy yesterday's meals," and an evening **Close the day** sheet that lists unlogged gaps in the 24-hour track. Expose the same logging actions as App Intents (`LogFoodIntent`, `StartBlockIntent`) so they work from Shortcuts and from macOS 26+ Spotlight with parameters, which needs no extension ([WWDC25 session 275](https://developer.apple.com/videos/play/wwdc2025/275)). Apple's recommended test order is Shortcuts, then Spotlight, then Siri ([WWDC26 session 240](https://developer-rno.apple.com/cn/videos/play/wwdc2026/240/)). A global hotkey still needs Carbon or a package such as sindresorhus/KeyboardShortcuts (background knowledge; version not verified).

### Visualising blocks: lanes for the day, range bars for the week

Day views split into vertical hour-by-hour timelines (Structured, MacroFactor, Oura) and horizontal staged bands (Apple Sleep). The known failure mode is density. Reviewers say Structured's column collapses into "an unreadable ribbon of colour" when a dozen 15-minute blocks stack up, and it has no monthly view ([Makerstack](https://makerstack.co/reviews/structured-review/)). MacroFactor answers with density controls: spacious or dense, **Hide Empty Hours**, collapsed icon rows, and per-hour macro summaries ([MacroFactor](https://macrofactor.com/timeline-based-food-logger/)). **Inference:** render the day as a 24-hour track starting at the user's day-start hour, with separate lanes for sleep, work and nature's call blocks, food as point markers carrying hourly subtotals, and a caffeine-remaining curve overlaid. A live "now" `RuleMark` is driven by `TimelineView`. Week and month views use Apple-Sleep-style range bars (start→end per day), which make regularity visible at a glance, plus stacked work-hours bars. A year view can be a calendar heatmap, though the research found no evidence on how effective heatmaps are for personal logs.

### Metrics that matter

**Inference**, grounded in the baseline pattern above: the useful daily KPIs are work total vs its 7- and 28-day averages; deep-work blocks of 50 minutes or more; first-block start time; kcal in, logged burn and net; protein vs target as a 7-day average; caffeine total and *estimated caffeine remaining at your usual bedtime*; sleep duration plus onset and midpoint consistency; steps; and nature's-call count and minutes as descriptive trends only. Two numbers need honest labels. "Net calories" is intake minus *logged active* burn, not energy balance. MacroFactor's expenditure model needs a weight trend, and under-logged intake biases it ([MacroFactor help](https://help.macrofactorapp.com/dashboard/expenditure)), so the app should never project weight change. Caffeine-in-system is a model estimate: dedicated apps default to about a 5-hour half-life and let users adjust it ([Unbuzz](https://apps.apple.com/app/id6757951639); [HalfCup, 2–10 h](https://apps.apple.com/app/id6756392479)).

## Swift computes every number and the model only narrates

### Borrow the vendors' gates, then add real statistics

No vendor publishes its full insight formulas, but their visible gates are consistent:

- Bearable shows a correlation only after **at least 3 days with a factor and 3 without** ([Bearable](https://bearable.app/support/tips/what-are-factors/)).
- WHOOP needs **at least 5 "yes" and 5 "no" answers within 90 days**, recommends tracking fewer than 10 behaviours, and openly warns about confounding ([WHOOP Journal](https://www.whoop.com/thelocker/the-whoop-journal/); [WHOOP monthly assessment](https://whoop.com/eu/en/thelocker/monthly-performance-assessment-now-features-enhanced-recovery-analysis)).
- Exist reports **strength and confidence separately**, so a strong finding backed by little data looks tentative ([Exist KB](https://kb.exist.io/article/37-what-are-correlations)).
- Apple Health Trends compare the **last 90 days against the last 365** and need 180 days of data ([Apple Support](https://apple.co/36ggRsf)).
- Apple Vitals sends one gentle notification only when **two or more** metrics are outliers on the same night ([BGR](https://bgr.com/tech/watchos-11-everything-you-need-to-know-about-apples-new-vitals-app/)).
- MacroFactor's V3 expenditure model pauses when more than 3 of 7 days are missing and damps day-to-day updates by about 35% compared with V2 ([MacroFactor V3](https://macrofactor.com/expenditure-v3/)).

The statistical caution is real. Self-tracking series are autocorrelated, so ordinary tests that assume independent days overstate significance ([Tang & Landes, arXiv 1904.01622](https://arxiv.org/abs/1904.01622v2)). Associations from personal logs are hypotheses to test with a self-experiment, not causal findings ([Daza 2018](https://statsof1.netlify.com/2018_daza_latexversion.pdf)). Two domain findings are strong enough to build on. **Caffeine taken 6 hours before bedtime cut objectively measured sleep by more than an hour**, and participants did not notice ([Drake et al. 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3805807/)). In 60,977 UK Biobank participants, **sleep regularity predicted mortality more strongly than duration**: a 1-SD higher Sleep Regularity Index came with a 20% lower hazard. The authors note it may be a marker rather than a cause ([Windred et al. 2024](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10782489/)).

**Inference: the engine design.** Every threshold here is a tunable default, not a validated number.

- **Detector shape.** Each insight is a pluggable `InsightDetector` with an id, version, required metrics, a minimum-valid-days gate and an `evaluate(context) → [InsightCandidate]` function. Each candidate carries a de-duplication subject key, kind (anomaly, trend, correlation, streak, data-quality), standardised effect size, confidence (from n, coverage and interval width), actionability, a list of pre-formatted facts, a structured explanation, and a `medicalSensitivity` flag.
- **Pipeline.** A data-quality pass first: coverage per metric, `~` estimates down-weighted, and "not logged" kept distinct from zero, which is the main source of spurious findings in manual logs. Then run detectors, gate, apply Benjamini-Hochberg FDR at 10% across correlation candidates, score, suppress via a memory table, cap at three cards a day and one per subject, and route each card to a card, a notification or the weekly digest.
- **Statistics.**
  - Baselines: a 28-day median with MAD. Robust z = (x − median)/(1.4826·MAD), flagged at |z| ≥ 2 on two of the last three days or a single |z| ≥ 3, and only after 14 valid days.
  - Trends: 7-day vs 28-day means, the Apple Trends idea shortened to fit 7–11 weeks of history, with Theil-Sen slopes. Report a trend only when it clears both a practical threshold (sleep ±30 min, work ±45 min) and a noise threshold.
  - Correlations: a short pre-registered list of lagged pairs (late caffeine → next sleep; sleep on night t → work on day t+1). Compare with and without the factor, with 8–10 days per group (stricter than WHOOP's 5+5), and report a median difference with a block-bootstrap interval.
  - Wording: "on days when…", never "causes". A promising pattern gets an offer to run a two-week self-experiment.
- **Memory.** A table of `(detectorID, subjectKey, lastShown, timesShown, timesDismissed, snoozedUntil, feedback)`. A dismissal suppresses a card for 14 days unless the effect grows by half. "Wrong" feedback flags the underlying data for review. Store the detector version with each shown insight so threshold changes don't re-fire old cards.
- **Explanations.** "Why am I seeing this" is rendered from the explanation struct, not from the LLM.

Domain specifics, also Inference. Anchor the caffeine cutoff to the user's *personal median sleep onset* minus 6 hours, following Drake 2013, rather than a clock-time "4 pm" rule. For a 03:30 sleeper that cutoff is about 21:30. Compute SRI from logged sleep blocks once at least 5 consecutive valid day-pairs exist, but never cite the mortality finding as a personal risk. Nature's-call metrics stay descriptive, never push, and carry neutral "a clinician is the right person to ask" copy.

### Notification policy follows the HIG's interruption levels

Apple's HIG reserves **Time Sensitive for things relevant now or within an hour**, warns that people turn off all notifications from apps that over-interrupt, and notes that Passive and Active notifications do not break through Focus ([HIG: Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md)). The research is mixed. ML-timed delivery raised receptivity by up to 36–40% over random timing in one study ([Mishra et al.](https://cs.dartmouth.edu/dfk/research/mishra-receptivity/mishra-receptivity.pdf)), while a stress-app study found frequency did not clearly hurt engagement ([PMC5207732](https://pmc.ncbi.nlm.nih.gov/articles/PMC5207732)).

**Inference:** at most two proactive pushes a day beyond reminders the user scheduled. Use Passive for insights and the weekly review, Active for opted-in reminders, and Time Sensitive only for a forgotten running timer, with "Stop now / Stop at… / Still going" actions. Fire the close-out reminder at the user's median sleep onset minus 60 minutes, not at midnight. Send missed-log nudges at most once a day, after a usual anchor time has passed by P75 + 60 minutes. Never send during a running sleep block. After three consecutive ignored dismissals of a type, halve its frequency and offer an inline "turn off." All of this runs locally through `UNUserNotificationCenter`. A resident menu bar app makes the scheduling reliable.

### The on-device LLM is a copywriter, never an analyst

Foundation Models gives free, offline access to Apple's ~3B on-device model through `LanguageModelSession`, `@Generable` structured output and `Tool` calling. At WWDC26 Apple rebuilt the model and showed `contextSize` returning **8,192** in sample code, while Apple's context-window documentation still says **4,096 tokens per session**. That budget covers instructions, schemas, tool I/O and output ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [Apple: Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md)). Read `contextSize` at runtime rather than hard-coding either figure. Apple's guidance is to keep prompts to three paragraphs or fewer, offer no more than 3–5 tools, and skip tools entirely when the data is always needed: put it in the prompt instead ([Apple](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md)). The model needs an Apple Intelligence–eligible Mac with Apple Intelligence switched on. Unavailability reasons include `deviceNotEligible`, `appleIntelligenceNotEnabled` and `modelNotReady` ([Kodeco](https://www.kodeco.com/53631607-getting-started-with-apples-foundation-models)). macOS 27 also ships an `fm` CLI (`respond`, `chat`, `token-count`, `serve`), which is handy for iterating on prompts from the terminal ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)).

**Inference: the narrate-only pattern.**

1. The deterministic engine selects 5–12 facts, roughly 300–800 tokens. Each fact has an id, a pre-formatted value string ("6 h 40 m", "−52 min vs your 28-day median"), a direction and a confidence label. Raw logs never reach the model.
2. The model returns a `@Generable DailyRecap { headline; points: [RecapPoint(factID, phrasing)] }`, with `@Guide(.maximumCount(3))` on the points.
3. Swift validates the output. It rejects unknown fact ids, any digits in the free text, and banned words (diagnose, disease, causes, should, risk). It then interpolates the verified value strings into the phrasing.
4. On a second failure, Swift uses template strings. The same templates are the permanent fallback when the model is unavailable, so every card and notification works with no LLM.

Cache output on a hash of the fact sheet plus the prompt version, and use one fresh session per summary. The WWDC26 `LanguageModel` protocol also lets a session be backed by local MLX models or by Anthropic and Google packages ([WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)). That is an escape hatch if the on-device model's prose disappoints. Cloud backends conflict with "private," though, and the PCC model needs an entitlement this setup cannot get.

## Fix the day when you write it and snapshot every food

### Architecture: plain SwiftUI, injected time, pure packages

The 2026 consensus for a solo developer is plain SwiftUI. `@Observable` services are injected through the Environment, and business logic lives in pure structs that take an injected `Calendar`. Kadō shows this at production quality: "lightweight MVVM," view models only where state is shared, no Combine, no third-party DI ([Kadō CLAUDE.md](https://github.com/scastiel/kado/blob/main/CLAUDE.md)). TCA 2.0 was a private beta for Point-Free subscribers as of April 2026, and the latest public tag is 1.26.2 ([Point-Free blog 206](https://www.pointfree.co/blog/posts/206-beta-preview-composablearchitecture-2-0); [TCA releases](https://github.com/pointfreeco/swift-composable-architecture/releases)). Its ceremony is not worth it for a timer-and-CRUD app (Inference). SQLiteData configures its database through swift-dependencies, which also provides overridable `date`, `calendar`, `timeZone`, `uuid` and clock values ([swift-dependencies](https://github.com/pointfreeco/swift-dependencies/tree/main/Sources/Dependencies/DependencyValues)). One dependency system therefore covers both persistence and deterministic tests.

### Data model: instants, attribution, snapshots, provenance

Kadō's `DayBoundary` gives the core rule. A record's logical day is resolved against a user day-start hour and **fixed when the record is written**, because "bucketing on read instead would silently rewrite history" whenever the setting changes. Kadō also handles zones whose DST transition falls at midnight ([Kadō DayBoundary.swift](https://github.com/scastiel/kado/blob/main/Packages/KadoCore/Sources/KadoCore/Services/DayBoundary.swift)). Dayflow, a 7,400-star macOS timeline app on GRDB, does the same with a fixed 4 AM boundary and a `yyyy-MM-dd` day key stored next to start and end instants ([Dayflow StorageDateHelpers.swift](https://github.com/JerryZLiu/Dayflow/blob/main/Dayflow/Dayflow/Core/Recording/StorageDateHelpers.swift)).

**Inference: the recommended schema** (UUID primary keys throughout, for sync readiness):

| Table | Key fields | Rules |
|---|---|---|
| `time_block` | `kind` (work, sleep, nature_call, custom), `category_id`, `start_utc`, `end_utc` (NULL = running), `tz_identifier`, `logical_day` (text, fixed on write), `note`, `source` (manual, timer, import), `is_estimate`, `import_batch_id`, `raw_text`, `created_at`, `updated_at`, `deleted_at` | Attribution is per kind: work → day of start; sleep → day of wake. Durations come from instants, never wall-clock subtraction (DST days run 23 or 25 hours). |
| `food` | name, aliases, serving size + unit, kcal / protein g / caffeine mg per serving, `archived_at` | Library editing never touches history |
| `food_log_entry` | `food_id?`, quantity or multiplier, **snapshotted** name, kcal, protein, caffeine, `consumed_at`, `logical_day`, provenance fields | Typed-macro shorthand becomes an entry with explicit totals and an optional library link |
| `metric_definition` / `metric_sample` | name, unit, value type, aggregation (sum, avg, max, last), builtin flag / definition id, logical day, value, `is_estimate`, source | Narrow typed EAV for steps, burn and future custom metrics; stays SQL-aggregatable |
| `daily_facts` (SQL view) | one row per logical day: work min, sleep min, kcal in, protein, caffeine, burn, steps, nature's-call count and minutes, estimate flag | Feeds every chart and every detector; computed, not stored |
| `import_batch`, `change_log`, `insight_memory` | batch metadata; trigger-written before/after JSON; detector suppression state | Undo, audit, notification fatigue |

Two functions must be kept apart and both tested. **Attribution** decides which logical day a block's total counts toward. Under a 4 AM day start, a 2250–0000 work block and a 0100–0330 block both belong to the previous day. **Clipping** splits a block into the calendar windows it spans, for drawing timelines and for "hours on date X" questions. Use SQL for `GROUP BY logical_day`, window functions for rolling averages and gaps-and-islands streaks, and aligned per-day vectors for correlations, which are then computed in Swift because SQLite has no `CORR`. Generate the full calendar range and left-join actual data so that missing days show as explicit gaps instead of zeros. SQLiteData's Reminders example shows the mechanics: raw-SQL migrations through `DatabaseMigrator`, FTS5 search and triggers for derived behaviour ([Schema.swift](https://github.com/pointfreeco/sqlite-data/blob/main/Examples/Reminders/Schema.swift)).

### Timers derive from stored start dates

A timer is a `time_block` row whose `end_utc` is NULL, written the moment the user presses start. Elapsed time is always `now − start`, so quitting, crashing and sleeping the machine all take care of themselves. TomatoBar takes the same approach: it recomputes from a stored `finishTime` because "ticks can be missed during the machine sleep" ([TomatoBar Timer.swift](https://github.com/ivoronin/TomatoBar/blob/main/TomatoBar/Timer.swift)). `Text(timerInterval:)` and `Text(_, style: .timer)` render self-updating text with no app-side ticking ([Apple docs](https://developer.apple.com/documentation/swiftui/text/datestyle/timer)).

The menu bar label is the one fragile spot. Forum reports describe SwiftUI timers in a `MenuBarExtra` label that don't refresh, and an open menu blocking the run loop ([forums 726369](https://developer.apple.com/forums/thread/726369); [720625](https://developer.apple.com/forums/thread/720625)). TomatoBar sidesteps this with an `NSStatusItem` title updated once a second. **Inference:** try `MenuBarExtra(.window)` with `Text(timerInterval:)` in the label first, keep an `NSStatusItem` fallback ready, and verify on macOS 27. On launch and on `NSWorkspace.didWakeNotification`, look for open blocks longer than the 95th percentile for their kind (or a hard cap) and ask "Still running?"

There is a schema tension (Inference). The natural way to enforce "one running block per kind" is a partial UNIQUE index, but SQLiteData's CloudKit rules forbid non-primary-key UNIQUE constraints. If sync readiness matters, enforce the rule in the write path or with a `BEFORE INSERT` trigger instead.

### Import pipeline: parse, plan, preview, apply, undo

The 7–11 weeks of Notes-derived markdown should go through a Swift executable in the same workspace (`logbook-import`), not a Python script. That way the import writes through the same model, validation and migrations as the app, and Swift Testing can cover it with golden files. Python is defensible only as a throwaway pre-cleaner that emits JSON for a Swift `Codable` path (Inference).

The grammar follows the existing shorthand. Date headings set context. Block lines are `HHMM - HHMM [dur] > label`. Food lines are `name [qty unit] - kcal / protein / caffeine`. Sleep and nature's-call lines use `sleep ->` and `nc ->` prefixes, nature's-call lines sometimes carrying a bracketed sub-duration triplet. Burn lines read `Burn - N kcal`, and a `~` prefix marks an estimate. The bracketed duration is redundant with start and end, so use it as a check and flag mismatches. When end is earlier than start, infer a midnight crossing (Inference, from the engineering notes).

The pipeline has five steps:

1. `parse(text) → [ParsedLine | ParseIssue]`, keeping line numbers and `raw_text`.
2. `plan(parsed, db) → ImportPlan`: inserts, likely duplicates keyed on day, kind and times, and new library foods.
3. A preview UI with per-day counts, warnings and unknown lines.
4. Apply in a single transaction stamped with `import_batch_id`.
5. Undo by deleting or soft-deleting every row with that batch id.

Use deterministic UUIDs (for example UUIDv5 from date plus line content) so that re-runs are idempotent (Inference). Swift Regex handles per-line classification fine at this size, despite documented performance problems on large inputs ([Swift forums](https://forums.swift.org/t/slow-regex-performance/75768)). swift-parsing 0.15.2 composes neatly for the time, duration and macro-triplet pieces ([swift-parsing](https://github.com/pointfreeco/swift-parsing)). Keep the original markdown untouched in the repo or a backup.

### Backup and export

**Inference, built on GRDB's online backup API** ([GRDB README](https://raw.githubusercontent.com/groue/GRDB.swift/master/README.md)): take a daily `VACUUM INTO` or GRDB-backup snapshot to `~/Library/Application Support/<bundle-id>/Backups/`, keep N copies, and optionally mirror the snapshots (never the live database) to an iCloud Drive folder. Add a manual JSON export (one array per table, ISO-8601 dates, a schema version) with a matching import that proves the round trip, plus a per-table CSV export. Commit a `schema.sql` dump regenerated by a test, so the AI assistant always sees the current schema. Never keep the live SQLite file with its `-wal` and `-shm` files inside a synced folder.

### Testing the dangerous parts

Inject `Calendar`, `TimeZone`, "now" and clocks everywhere. Kadō's `TestCalendar` provides a ready template: a fixed UTC reference, Paris for 23- and 25-hour days, and Havana for a DST transition at midnight. Its instant builder traps on wall times that don't exist, so mistakes in test setup fail loudly ([Kadō TestCalendar.swift](https://github.com/scastiel/kado/blob/main/KadoTests/Helpers/TestCalendar.swift)).

The test matrix (Inference):

- blocks of 2250–0000, 0100–0330 and 2300–0700 under day starts of 0 and 4;
- blocks spanning spring-forward and fall-back;
- a block started in one time zone and ended in another;
- weeks with missing days, and different `firstWeekday` settings;
- food snapshots staying unchanged after a library edit;
- one golden import test per shorthand variant;
- import → undo → identical database;
- a property test that clipped per-day durations always sum to the block's total.

Snapshot tests catch visual regressions the agent cannot otherwise see. Re-record them deliberately after OS updates.

### Open-source code worth studying

There is no mature open-source Mac logbook combining time blocks, food and sleep. Searches for Swift food and sleep loggers turn up only small or abandoned repositories ([e.g. caloryn](https://github.com/VaggelisKa/caloryn)). The useful approach is to borrow parts from several projects. Stars and last-push dates below were checked via the GitHub API on 2026-11-08.

| Repo | Stars / last push | Borrow |
|---|---|---|
| [scastiel/kado](https://github.com/scastiel/kado) | 190 / 2026-10-15 | `DayBoundary`, DST test calendars, backup/CSV round-trip tests, `CLAUDE.md` + `.claude/skills` workflow, local core package |
| [JerryZLiu/Dayflow](https://github.com/JerryZLiu/Dayflow) | 7,401 / 2026-11-03 | macOS timeline on GRDB, 4 AM day key, weekly rollups, AI daily brief |
| [pointfreeco/sqlite-data](https://github.com/pointfreeco/sqlite-data) examples | 1,960 / 2026-11-06 | `@Table` schema, SQL migrations, triggers, FTS5, tests, CloudKit demo |
| [ivoronin/TomatoBar](https://github.com/ivoronin/TomatoBar) | 3,586 / 2026-05-29 | Seven-file menu bar timer; stored finish time; `NSStatusItem` title |
| [exelban/stats](https://github.com/exelban/stats) / [jordanbaird/Ice](https://github.com/jordanbaird/Ice) | 43,216 / 29,982 | Mature menu bar apps; status-item and AppKit interop |
| [Dimillian/IceCubesApp](https://github.com/Dimillian/IceCubesApp) | 7,104 / 2026-10-13 | Large `@Observable` + Environment app with feature packages |
| [jordibruin/Swift-Charts-Examples](https://github.com/jordibruin/Swift-Charts-Examples) | 2,449 / 2025-05-25 | Catalogue of chart types |
| [pointfreeco/swift-parsing](https://github.com/pointfreeco/swift-parsing) / [swift-dependencies](https://github.com/pointfreeco/swift-dependencies) / [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) | 1,001 / 2,202 / 4,390 | Importer parsers, injected time, view and plan snapshots |
| [ActivityWatch/activitywatch](https://github.com/ActivityWatch/activitywatch) | 19,551 (Python/Rust) | Event-in-bucket interval model, for comparison |

### A build order that keeps the app usable at every step

**Inference.** Work in this order:

1. A one-day spike: signing identity, notification persistence, the login item, and `MenuBarExtra` label refresh on macOS 27.
2. Core and persistence: schema, attribution, `daily_facts`, tests.
3. The importer, with preview and undo, run against the real 7–11 weeks. This also tests the day-start hour against actual sleep times.
4. Today, timeline and quick entry, plus the menu bar timer.
5. Trends and charts.
6. Deterministic insights and the notification policy.
7. LLM narration.
8. App Intents and Spotlight.
9. Widgets, only after the App Group spike passes.
10. The paid membership, sync and the iPhone/Watch companion.

Each step ships a usable app, and the importer comes early because real data exposes model mistakes faster than fixtures.

## Thirteen risks with mitigations, and seven questions still open

| Risk | Why it matters | Mitigation |
|---|---|---|
| App Group prompt for ad-hoc apps | Widgets and Controls break or nag ([DTS](https://developer.apple.com/forums/thread/767604)) | Defer widgets; spike Personal Team + Team-ID group; fall back to menu bar + notifications; or pay |
| Signature changes on every rebuild | Notification, TCC and login-item approvals may reset (unverified) | Stable signing identity; a single `/Applications` install path; test early |
| `MenuBarExtra` label stops refreshing | The live timer is a headline feature ([forums 726369](https://developer.apple.com/forums/thread/726369)) | `Text(timerInterval:)` first; `NSStatusItem` fallback |
| Wrong day attribution | Silent, compounding errors in every metric | Fix `logical_day` on write; per-kind rules; explicit recompute migration; DST test matrix |
| Live SQLite inside iCloud Drive or Dropbox | Torn WAL states, conflict copies | Live DB in Application Support; sync only snapshots |
| Point-Free dependency fan-out; StructuredQueries 0.x churn | Slower builds, API breaks | `upToNextMinor` pins, committed `Package.resolved`; plain GRDB remains a cheap exit |
| Sync rules adopted too late | Later CloudKit migration pain | UUID keys and no non-PK UNIQUE from day one; enforce "one running block" in code or a trigger |
| AI-generated concurrency workarounds | Hidden data races | Per-module isolation defaults; ban `@unchecked Sendable` and `nonisolated(unsafe)` in `CLAUDE.md` |
| JSON `.xcproj` is new (format package v0.1.0) | Tooling gaps ([InfoQ](https://www.infoq.com/news/2026/10/xcode-json-project-format/)) | Use only `xcrun xcodeproj` and the formatter; `xcodebuild -convert-project pbxproj` or XcodeGen as fallback |
| LLM invents or miscomputes numbers | Erodes trust | Fact-ID schema, digit ban, validation, template fallback |
| Spurious correlations | "Obvious" or false insights erode trust ([Exist](https://exist.io/blog/post/use-cases/)) | Gates, FDR, replication on the last 28 days, a whitelist of plausible pairs, strength vs confidence in the UI |
| Importer misparses messy lines | Corrupted history | Dry-run preview, batch undo, golden tests from real lines, keep `raw_text` |
| Snapshot tests drift across OS updates | False failures | Tolerances; deliberate re-recording after upgrades |

| Open question | Why it matters | How to resolve |
|---|---|---|
| Does a free Personal Team identity give prompt-free Team-ID App Groups and stable permissions on macOS 27? | Decides whether widgets need the $99 | Half-day spike on this Mac |
| What day-start hour fits this user's real sleep? | A 03:30 onset straddles a 4 AM boundary | Histogram sleep onsets from the imported logs before fixing the rule |
| Is the on-device context 4,096 or 8,192 tokens on this Mac? | Sizes the fact sheet | Read `SystemLanguageModel.contextSize` at runtime |
| Do App Intents and Spotlight actions register for an ad-hoc app? | Fast-entry path | Install to `/Applications`, test Shortcuts → Spotlight |
| Will Apple ever expose HealthKit on the Mac? | Steps and burn automation | Watch macOS 27.x release notes; meanwhile use export.xml or a Shortcuts bridge |
| Has macOS 27 fixed `MenuBarExtra` label refresh and the SwiftData inheritance crashes? | Affects the fallback choices | Empirical check; the research found no confirmation |
| What caffeine half-life default should be used? | Bedtime-caffeine estimate | Keep the 5 h default user-adjustable; the research found no primary pharmacology source |

## Conclusion

The stack question turned out to be the easy part. Every serious signal points to SwiftUI, and the October design pass was right to choose SQLite over SwiftData, because a logbook is an analytics app wearing a journaling app's clothes. Two choices will decide whether the app is still trustworthy in five years. The first is the decision to **fix a record's logical day when it is written** and to **snapshot nutrition onto each food entry**. The second is the discipline that **Swift computes every number while the LLM only phrases it**. Both are cheap now and expensive to retrofit.

The paid-account boundary also reframes the roadmap. The $99 membership is not a quality upgrade for the Mac app. It is the entry ticket to the iPhone/Watch world: CloudKit sync, HealthKit on the phone and non-expiring installs. Build sync-ready now and pay on the day the companion starts. On the tooling side, Xcode 27.2's JSON project format and `xcrun xcodeproj` mean that, for the first time, an AI assistant can manage a native Mac project from the command line with Apple's own tools. The previous Tauri attempt was archived partly to escape native tooling friction, and that reason has largely gone away.
