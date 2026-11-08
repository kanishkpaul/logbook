# Persistence and Sync for a Private, Single-User SwiftUI macOS Logbook (as of 2026-11-08)

Scope: SwiftData vs GRDB vs Core Data vs Point-Free SQLiteData, plus sync and backup/export, for a personal, ad-hoc-signed macOS 27 app (Xcode 27.2, Swift 6.4) that logs time blocks, foods/macros, steps, sleep, and charts multi-week aggregates. Data scale is small: roughly 10–50 rows/day, so tens of thousands of rows after several years.

Dating convention: GitHub release pages show "DD Mon" without a year. Years below are inferred from ordering and from a dated mirror (CocoaPods lists GRDB 7.10.0 as 2026-02-15). They are marked "(year inferred)" where that applies.

---

## Q1. State of SwiftData in 2025–2026: is it mature enough for this app?

### Takeaway
SwiftData got incremental additions in 2025 and 2026, not a fix for its core gaps. WWDC25 added model inheritance; WWDC26 added `@Query(sectionBy:)`, `@Attribute(.codable)`, `ResultsObserver`, and `HistoryObserver`. It still has **no aggregate or group-by queries**. Inheritance has open crash reports, and observation re-fetches more often than it needs to. It is usable for simple CRUD, but this app is analytics-heavy, needs an export and backup story, and will have an AI assistant evolving the schema. That makes SwiftData the weakest fit here. The October 2026 rejection of SwiftData holds up.

### Cited Findings
- **WWDC26 ("What's new in SwiftData", session 274)** introduced four things: sectioned fetches via `@Query(sectionBy:)`, `@Attribute(.codable)` for Codable types you don't own, `ResultsObserver` (Query-style fetching outside SwiftUI), and `HistoryObserver` (an observable `eventCounter` that ticks on new persistent-history transactions). — [Apple WWDC26 session 274](https://developer.apple.com/videos/play/wwdc2026/274/); [DEV Community summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)
- `.codable` attributes are stored as opaque blobs. They cannot be used in predicates or sort descriptors, and changes to the Codable type's shape do not trigger migrations, so your Codable implementation has to handle compatibility. A class property without `.codable` crashes at launch ("Class property within Persisted Struct/Enum is not supported"). — [DEV Community summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)
- `ResultsObserver` and `HistoryObserver` require you to store an `ObservationTracking.Token`. `HistoryObserver` filters by author, which lets a server-sync loop avoid echoing its own changes. — [DEV Community summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)
- **Point-Free's critique (Episode #372, 2026-07-13).** This is a biased source: Point-Free maintains the competing SQLiteData. Their points:
  - `sectionBy` only works on `String` fields stored directly on the model. It cannot group by relationships, computed properties, or optional chains, grouping by a first-letter key path crashes at runtime, and query changes do not animate.
  - `.codable` fields cannot be filtered, sorted, or sectioned.
  - Observation is not minimal: updating an unobserved property every second re-ran a query that only observed a different property, and `propertiesToFetch` did not help.
  - Relationships must be optional because of CloudKit's requirements.
  - Model inheritance (WWDC25) uses single-table inheritance.
  — [Point-Free ep. 372](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)
- Point-Free said WWDC25 brought little to SwiftData beyond model inheritance. — [Point-Free ep. 372 via search snippet](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)
- **No native aggregates.** SwiftData has no equivalent of Core Data's SQL-pushed sum, avg, min, and max. The suggested workarounds are:
  - for min or max, fetch sorted with `fetchLimit = 1`;
  - for real aggregates, run a Core Data stack against the same store file ("coexistence"), which requires persistent history tracking enabled on the Core Data side.

  The same source names `fetchCount(_:)` and `fetchIdentifiers(_:)` as the cheap non-materializing reads. `@Model` objects are not `Sendable`: you pass a `PersistentIdentifier` across actors and re-fetch on the other side. — [Blake Crosley, "SwiftData Performance Is a Storage Problem", 2026-06-15, summarizing WWDC26 SwiftData Group Lab 8017](https://blakecrosley.com/blog/swiftdata-performance-storage-engine)
- The aggregate-query gap has been tracked since launch (FB12292503 cited by the community). An Apple Developer Forums thread asking for aggregates in SwiftData points back to Core Data `NSExpression`. — [Apple Dev Forums thread 832186](https://developer.apple.com/forums/thread/832186); [Use Your Loaf, SwiftData Expressions](https://useyourloaf.com/blog/swiftdata-expressions/)
- **Inheritance bugs (iOS/macOS 26.x), from forum user reports:**
  - A subclass insert crashes with a fatalError in BackingData.swift. — [thread 802130](https://developer.apple.com/forums/thread/802130)
  - Inheritance combined with an optional many-to-one relationship and CloudKit gives a "Could not cast value of type 'SwiftData.PersistentIdentifier'" crash on the second save, still reported on 26.3. Removing subclassing avoids it. — [thread 812212](https://developer.apple.com/forums/thread/812212)
  - "Never access a full future backing data" fatal error. An Apple engineer called it a known issue with materializing a relationship to a superclass. — [thread 800033](https://developer.apple.com/forums/thread/800033)
- **Migration and concurrency criticism.** SwiftData crashes when the schema is incompatible and no migration is supplied, and `ModelContext` is not `Sendable`. — [everything-wrong-with-swiftdata (nikolaydubina)](https://awesome.ecosyste.ms/projects/github.com%2Fnikolaydubina%2Feverything-wrong-with-swiftdata). A 2026 guide says Core Data's migration tooling is more mature for apps with multiple shipped releases. — [3nsofts 2026 guide](https://3nsofts-site.pages.dev/insights/swiftdata-vs-core-data-production-ios-2026). These sources disagree on whether SwiftData's actor model resolves the sendability problems.
- Fatbobman's weekly covered WWDC26 ("AI Watched It for You — Now What?", #140). I found no dedicated 2026 Fatbobman article on SwiftData migration or concurrency. — [Fatbobman's Swift Weekly #140](https://weekly.fatbobman.com/p/fatbobmans-swift-weekly-140)

### Inferences
- For this app, the decisive SwiftData weakness is the **lack of SQL aggregation and group-by**, not raw speed. At this data size, in-memory reduction would be fast enough, so performance doesn't decide it. The issues that do matter:
  - every chart has to materialize `@Model` objects on the main context, or set up a background `ModelActor` and pass identifiers around;
  - the store is a Core Data-managed SQLite file with Z-prefixed tables (`ZFOODENTRY`, `Z_PK`, and so on), so exporting or inspecting it with external tools is awkward.
- **Schema evolution with an AI assistant.** SwiftData's schema is implicit in `@Model` classes. Non-trivial changes need `VersionedSchema` plus `SchemaMigrationPlan` with frozen copies of old models. That is more ceremony, and easier for an LLM to get subtly wrong (a forgotten version, or edited old models), than an append-only list of SQL migrations.
- Inheritance, the main WWDC25 feature, is a poor fit for modeling different entry kinds (work, sleep, bathroom blocks) given the open crash reports. Separate tables or a `kind` enum column is safer under any stack.
- SwiftData's built-in CloudKit sync (through `ModelConfiguration`) would be its main draw for a future iPhone/Watch companion. The paid-account requirement (Q5) applies to it just as much, so it gives SwiftData no advantage for an ad-hoc-signed app.

### Gaps
- I could not open Apple's official SwiftData release notes for OS 27 to confirm bug fixes, enum or compound predicate improvements (one roundup mentioned them, unconfirmed), or new aggregate APIs. No aggregate API turned up in any WWDC26 coverage.
- No measured benchmarks for SwiftData vs GRDB at about 50k rows were found. The Crosley post explicitly gives no numbers.
- I did not verify whether the inheritance crashes are fixed in macOS 27.0.x.

---

## Q2. GRDB: current version, Swift 6, ValueObservation, migrations, FTS5, backup, SwiftUI integration

### Takeaway
GRDB is mature and actively maintained. The latest release is **v7.12.0, 2026-11-01 (year inferred)**. The 7.x line was built for Swift 6 concurrency, and since v7.9.0 it requires Swift 6.1+ and Xcode 16.3+. It provides SQL migrations, `ValueObservation`, FTS5, WAL `DatabasePool`, Codable records, SQL interpolation, an online backup API, and optional SQLCipher. Its SwiftUI companion, GRDBQuery, works but moves slowly: latest is 0.11.0.

### Cited Findings
- **Recent releases** — [GRDB releases page](https://github.com/groue/GRDB.swift/releases)

  | Version | Date | Notes |
  |---|---|---|
  | **v7.12.0** | 01 Nov 2026 (year inferred) | Works around an SQLite WAL snapshot ordering bug; supports Strings containing NUL; supports statement recompilation after schema column changes; fixes a SharedValueObservation deadlock |
  | v7.11.1 | 18 Jun | Migration registration is O(1) in DEBUG |
  | v7.11.0 | 01 Jun | UPSERT fix for WITHOUT ROWID tables; option to disable change filtering in TransactionObserver |
  | v7.10.0 | 15 Feb | Android, Linux, and Windows support; UPSERT column configuration; easier SQLCipher setup via SPM |
  | v7.9.0 | 13 Dec | **Breaking:** requires Swift 6.1+ / Xcode 16.3+; FTS5 cancellation fix |
  | v7.8.0 | 02 Oct | Merged migrations |
  | v7.7.0 | 23 Sep | Xcode 26 support; Persistable Database Views |

  Xcode 27 is not mentioned explicitly in any release note.
- CocoaPods lists 7.10.0 as released 2026-02-15. A Mintlify changelog mirror says 2025-02-15, which looks like a typo. — [CocoaPods](https://cocoapods.org/pods/NewGRDB.swift); [Mintlify changelog](https://www.mintlify.com/groue/GRDB.swift/resources/changelog)
- GRDB 7.0.0 shipped in January 2025, aimed at Swift 6 concurrency. 7.6.0 had a race condition on cancelled async accesses, fixed in 7.6.1. — [mjtsai 2025-01-28](https://mjtsai.com/blog/?p=46562); [newreleases v7.6.0](https://newreleases.io/project/github/groue/GRDB.swift/release/v7.6.0)
- **README feature list:**
  - ValueObservation ("Get notifications when database values are modified"), usable as `for try await` over `observation.values(in:)`, with Combine and RxSwift adapters
  - Migrations
  - Full-Text Search (FTS5)
  - DatabasePool, which opens in WAL mode and allows concurrent access
  - Codable records, with complex properties stored as JSON
  - SQL interpolation (`execute(literal:)`)
  - Backup ("Dump the content of a database to another")
  - SQLCipher encryption
  - the system SQLite by default, with a guide for custom SQLite builds

  — [GRDB README](https://raw.githubusercontent.com/groue/GRDB.swift/master/README.md)
- **GRDBQuery** (SwiftUI companion) releases: 0.11.0, the latest (15 Mar, year likely 2025), adds `QueryableOptions.assertNoFailure`. 0.10.0 depends on GRDB 7. 0.9.0 added `DatabaseContext`. — [GRDBQuery releases](https://github.com/groue/GRDBQuery/releases)

### Inferences
- GRDB's API surface is plain SQL plus Swift records. Each migration is a named, append-only `registerMigration("v3-add-caffeine") { db in ... }` block, which makes schema evolution very legible to an AI coding assistant: it can read the migration list, the current schema (`sqlite3 db .schema`), and the record structs. This is the main qualitative advantage over SwiftData.
- Backup is built in (online backup API). `VACUUM INTO` (an SQLite feature since 3.27) also gives a consistent single-file snapshot while the app runs. Both make "copy the .sqlite file" a real backup strategy. (From prior knowledge of SQLite and GRDB; the backup section of the README was not quoted in this session.)
- For aggregates (daily totals, weekly averages, streaks via window functions or CTEs, correlations computed from per-day vectors), SQL `GROUP BY date(start)` with `SUM`/`AVG` is natural, and the system SQLite on macOS 27 supports window functions. At this data scale, computing in Swift would also be fine. SQL wins on clarity and reuse (the same queries work in `sqlite3` or Datasette), not on speed.
- GRDBQuery's slower release pace (no release found since 0.11.0) is a mild risk. SQLiteData's `@FetchAll` and `@FetchOne` (Q3) is the more actively developed SwiftUI layer over GRDB.

### Gaps
- Release years are inferred from ordering. The GitHub page omits years.
- I did not confirm the exact minimum macOS version for GRDB 7.12 (the README "Requirements" line was not captured) or the system SQLite version shipped in macOS 27.

---

## Q3. Point-Free SQLiteData (formerly SharingGRDB): version, features, maturity, licensing, risks

### Takeaway
SQLiteData is a SwiftData-style layer on top of GRDB plus Point-Free's StructuredQueries. It offers `@Table` models, `@FetchAll`/`@FetchOne` property wrappers, type-safe SQL, and a CKSyncEngine-based `SyncEngine` for CloudKit sync and sharing. It is MIT-licensed and post-1.0: **1.0 shipped around mid-September 2025**, and the latest release is **1.12.1 (2026-10-09, year inferred)**. It ships often, with about 12 minor releases in roughly 13 months. CloudKit sync imposes schema rules: globally unique (UUID) primary keys, and no UNIQUE constraints except on the primary key.

### Cited Findings
- README: "a fast, lightweight replacement for SwiftData, powered by SQL and supporting CloudKit synchronization." It has `@Table` (analogous to `@Model`), `@FetchAll`/`@FetchOne` (analogous to `@Query`) with ordering, filtering, and counting, automatic observation from SwiftUI, UIKit, and `@Observable` models, StructuredQueries type-safe queries plus the `#sql` macro, and `SyncEngine` for CloudKit sync including sharing. **License: MIT.** About 2.0k GitHub stars. Built on GRDB. — [sqlite-data README](https://github.com/pointfreeco/sqlite-data)
- **Releases** (latest first) — [sqlite-data releases](https://github.com/pointfreeco/sqlite-data/releases)
  - **1.12.1** (09 Oct): visionOS fix; CloudKit sync docs link
  - 1.12.0 (31 Aug): user-defined collations
  - 1.11.2 (29 Aug): StructuredQueries 0.38 support
  - 1.11.1 (28 Aug): fixes resolution of the shared CloudKit database for shared records
  - 1.11.0 (19 Aug): `ColumnCoding` trait; NUL strings; `@Fetch*` uses SwiftUI `@State` where possible; statement caching; faster String, Date, and UUID coding
  - 1.10.0 (11 Aug): `@FetchOne` auto-observes primary-keyed records; `StrictDecoding` trait
  - 1.9.0 (03 Aug): raised OS and StructuredQueries floors
  - 1.8.x (27–29 Jul): `@FetchAll(sectionBy:)`; CloudKit metadata suspension handling

  None of these is labeled breaking.
- 1.6.1 (23 Mar) fixed a CloudKit migration bug with NULL DEFAULT columns, modification-timestamp caching, and date drift during sync. It also added preview support for CloudKit apps and `SyncEngine.isSynchronizing`. — [search summary of release notes](https://gh.r-mj.com/pointfreeco/sqlite-data/releases)
- **Package.swift (main branch):**
  - swift-tools-version 6.4
  - platforms iOS 16 / macOS 13 / tvOS 16 / watchOS 9
  - deps: GRDB.swift `from: 7.6.0`, swift-structured-queries `from: 0.39.1`, swift-dependencies 1.9.0, swift-sharing 2.3.0, swift-perception 2.0.0, swift-issue-reporting 2.1.0, swift-collections, swift-clocks, swift-concurrency-extras, swift-custom-dump, swift-snapshot-testing, swift-tagged, swift-docc-plugin

  — [Package.swift](https://raw.githubusercontent.com/pointfreeco/sqlite-data/main/Package.swift)
- **History:**
  - "SharingGRDB: A SwiftData alternative" (renamed SQLiteData) — [Point-Free blog 168](https://pointfree.co/blog/posts/168-sharinggrdb-a-swiftdata-alternative)
  - CloudKit private alpha — [blog 179](https://www.pointfree.co/blog/posts/179-a-swiftdata-alternative-with-sqlite-cloudkit-private-alpha)
  - Public beta on a `cloudkit` branch; the posts said most apps enable sync "with a few lines of code" but may need schema tweaks — [blog 181](https://www.pointfree.co/blog/posts/181-a-swiftdata-alternative-with-sqlite-cloudkit-public-beta)
  - 1.0 shipped about three weeks before 2025-10-08 — [blog 187, 2025-10-08](https://www.pointfree.co/blog/posts/187-new-in-sqlitedata-migration-tool-for-cloudkit-sync)
  - The SyncEngine design is covered in the episode series — [ep. 341 "CloudKit Sync: The SyncEngine"](https://www.pointfree.co/episodes/ep341-cloudkit-sync-the-syncengine)
- **CloudKit schema rules:**
  - All synced tables need globally unique primary keys (UUID); integer autoincrement IDs are incompatible. — [blog 187](https://www.pointfree.co/blog/posts/187-new-in-sqlitedata-migration-tool-for-cloudkit-sync)
  - Tables cannot have UNIQUE constraints on columns other than the primary key; the suggested workaround is to make that column the primary key. — [sqlite-data PR #456 docs](https://github.com/pointfreeco/sqlite-data/pull/456/files)
  - 1.1 added `SyncEngine.migratePrimaryKeys(db, tables:)`, which converts Int primary keys to UUIDs using SQLite's 12-step table-alteration procedure and recreates indices and triggers. — [blog 187](https://www.pointfree.co/blog/posts/187-new-in-sqlitedata-migration-tool-for-cloudkit-sync)
- Point-Free says SQLiteData supports most of the WWDC26 SwiftData features out of the box, and covered domain modeling in ep. 373. This is a vendor claim. — [Point-Free ep. 372](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)

### Inferences
- SQLiteData is a superset of the October design pass's GRDB pick, not a rival to it. The database is a plain SQLite file managed by GRDB `DatabaseMigrator` migrations, so every GRDB tool (raw SQL, backup, `ValueObservation`) stays available. What it adds is SwiftData-like view ergonomics (`@FetchAll` in views) and a ready-made CloudKit path for a future iPhone/Watch companion.
- **Risks:**
  - Dependency fan-out: about 12 Point-Free packages plus macros, which slows clean builds, and macro-plugin trust prompts in Xcode.
  - Fast release cadence: StructuredQueries is still 0.x (0.39), so its API can change between minors.
  - A single vendor maintains it.
  - The schema-design rules for sync (UUID keys, no secondary UNIQUE) should be adopted from day one if sync is ever wanted, even if sync stays off.
- Licensing is a non-issue (MIT), as it is for GRDB.
- **AI-assistant friendliness:** StructuredQueries' macro-generated query DSL is less familiar to LLMs than raw GRDB or SQL. However, SQLiteData accepts raw SQL through `#sql`, so an assistant can fall back to SQL.

### Gaps
- Release years on the GitHub page are inferred. 1.12.1 is assumed to be October 2026 because 1.0 was September 2025 and 1.6.1 was March 2026.
- The released 1.12.1 manifest might differ from main (swift-tools 6.4 on main). Exact platform floors for 1.12.1 were not confirmed; 1.9.0 "raised floors" without stating values in the notes.
- No independent adoption metrics beyond the star count. No third-party production post-mortems found.

---

## Q4. Core Data in 2026: still worth it?

### Takeaway
Core Data is still Apple's most capable first-party option. It has SQL-pushed aggregates via `NSExpression`/`NSExpressionDescription`, mature migration tooling, and `NSPersistentCloudKitContainer`. For a new Swift 6 SwiftUI app, though, it has the most ceremony and the least modern concurrency story, and it shares SwiftData's opaque Z-table store format. Its main role in 2026 is as a fallback underneath SwiftData for aggregates.

### Cited Findings
- SwiftData developers who need aggregates are told to use Core Data `NSExpression`, or to run a Core Data stack against the same store ("coexistence", WWDC23 session 10189), which needs persistent history tracking. — [Crosley 2026-06-15](https://blakecrosley.com/blog/swiftdata-performance-storage-engine); [Apple Dev Forums 832186](https://developer.apple.com/forums/thread/832186)
- A 2026 comparison says Core Data's migration tooling is more mature for apps with several shipped release cycles. — [3nsofts 2026](https://3nsofts-site.pages.dev/insights/swiftdata-vs-core-data-production-ios-2026)
- WAL has been the default Core Data SQLite journal mode since iOS 7 and OS X Mavericks (Apple QA1809). — [Crosley 2026-06-15](https://blakecrosley.com/blog/swiftdata-performance-storage-engine)

### Inferences
- `NSPersistentCloudKitContainer` needs the same CloudKit entitlement as everything else (Q5), so it gives no sync advantage for an unpaid, ad-hoc-signed app.
- `NSManagedObject` and context threading under Swift 6 strict concurrency mean `perform {}` blocks and `NSManagedObjectID` hand-offs everywhere. That's workable but verbose, and an AI assistant is more likely to create data races or main-thread misuse than with GRDB's value-type records.
- **Verdict:** I found no reason to pick Core Data over GRDB or SQLiteData for this app.

### Gaps
- No 2026 Apple announcements specific to Core Data were found. WWDC26 coverage focused on SwiftData.

---

## Q5. Sync options and requirements for an ad-hoc-signed personal app

### Takeaway
**CloudKit, iCloud Documents, and iCloud key-value storage all require a paid Apple Developer Program (ADP) membership or a Developer ID-signed app. They are not available to free "Apple Developer" accounts.** That rules out SwiftData/Core Data CloudKit sync, `CKSyncEngine`, and SQLiteData `SyncEngine` until the user pays the $99/yr. App Groups *are* available on the free tier. For now the realistic options are: no sync, or file-based backup/export copies placed in an iCloud Drive or Dropbox folder.

### Cited Findings
- **Apple's macOS supported-capabilities table** (rows parsed from the page HTML), with columns ADP / Developer ID / free "Apple Developer":

  | Capability | ADP | Developer ID | Free "Apple Developer" |
  |---|---|---|---|
  | iCloud: CloudKit | yes | yes | **no** |
  | iCloud: iCloud documents | yes | yes | **no** |
  | iCloud: iCloud key-value storage | yes | yes | **no** |
  | App groups | yes | yes | yes |
  | App Sandbox | yes | yes | yes |

  The page defines "Apple Developer" as free Apple Account holders who accepted the Developer Agreement and "can't distribute apps". — [Apple: Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos)
- Apple's CloudKit docs tell you to verify an active ADP membership with admin permissions before adding the iCloud capability. — [Apple: Enabling CloudKit in your app](https://developer.apple.com/documentation/cloudkit/enabling-cloudkit-in-your-app.md)
- Apple DTS on the forums: push notifications and iCloud capabilities are part of ADP membership. — [Apple Dev Forums 811929](https://developer.apple.com/forums/thread/811929). Hacking with Swift forums: "You must have paid account for that." — [HWS forum](https://www.hackingwithswift.com/forums/100-days-of-swiftui/day-58-syncing-swiftdata-with-cloudkit-icloud-capability-not-available-in-xcode/26870). A Reddit comment claiming free testing is possible is unverified and contradicted by Apple's table.
- **CKSyncEngine** (WWDC23 session 10188):
  - wraps common sync logic for private and shared CloudKit databases;
  - the app hands it pending changes and receives remote changes;
  - it batches sends and listens for push notifications, so the Remote Notifications capability is needed;
  - the app must persist the engine's state serialization and initialize the engine at launch.

  — [WWDC23 10188](https://developer.apple.com/videos/play/wwdc2023/10188/); [WWDC Notes](https://wwdcnotes.com/notes/wwdc23/10188)
- SQLiteData's `SyncEngine` is built on CKSyncEngine and supports CloudKit sharing. — [sqlite-data README](https://github.com/pointfreeco/sqlite-data); [ep. 341](https://www.pointfree.co/episodes/ep341-cloudkit-sync-the-syncengine)

### Inferences
- **Without ADP:** No first-party Apple sync. Ad-hoc signing cannot carry iCloud entitlements, and an iPhone or Watch companion can't be installed long-term anyway: free-team provisioning profiles expire after about 7 days, which is prior knowledge, not verified this session. The iPhone/Watch plan therefore effectively *implies* buying ADP. Plan for the paid tier when the companion app happens, not before.
- **File-based fallback:** A non-sandboxed, ad-hoc-signed Mac app can write ordinary files anywhere the user can, including `~/Library/Mobile Documents/com~apple~CloudDocs/` (the user's iCloud Drive folder), with no entitlement. That makes it fine for *periodic snapshot backups and exports*. **Do not keep the live SQLite database (with its -wal/-shm files) in iCloud Drive or Dropbox.** File-sync services can upload torn or partial WAL states and create conflict copies. This is a well-known SQLite caveat, not sourced in this session.
- **Stay sync-ready.** If the user later buys ADP, the cheapest path to iPhone/Watch sync is SQLiteData `SyncEngine`, provided the schema already uses UUID primary keys and has no non-PK UNIQUE constraints. With plain GRDB you would write a CKSyncEngine delegate yourself, a substantial project. SwiftData's built-in CloudKit is the other path, but it carries all the Q1 limitations.

### Gaps
- I didn't confirm whether a *Developer ID* certificate without ADP is possible. It is not: Developer ID requires ADP (prior knowledge, not re-verified).
- I didn't confirm the current CloudKit quota limits for personal private-database use (irrelevant at this data size).

---

## Q6. Backup/export strategies, and how easily an AI assistant can reason about the schema

### Takeaway
SQLite-file stacks (GRDB/SQLiteData) give the best backup and export story: a consistent single-file snapshot (`VACUUM INTO` or the online backup API), schema readable with `sqlite3 .schema`, and trivial CSV/JSON export with SQL or Codable. SwiftData and Core Data stores are SQLite too, but use Z-prefixed tables and metadata, so exports have to go through app code.

### Cited Findings
- GRDB provides an online backup API ("Dump the content of a database to another") and Codable record support for JSON round-tripping. — [GRDB README](https://raw.githubusercontent.com/groue/GRDB.swift/master/README.md)
- SwiftData `.codable` attributes are opaque blobs that don't migrate with type changes. That's a hazard for long-lived data and exports. — [DEV Community WWDC26 summary](https://dev.to/arshtechpro/wwdc-2026-whats-new-in-swiftdata-sectioned-queries-codable-attributes-and-observers-2ao5)

### Inferences
- **Recommended backup design** (GRDB/SQLiteData):
  1. Write an automatic daily snapshot `logbook-YYYY-MM-DD.sqlite` via `VACUUM INTO` or GRDB backup to `~/Library/Application Support/<app>/Backups/`, keep N copies, and optionally mirror to an iCloud Drive folder.
  2. Offer a manual "Export JSON" (one array per table, ISO-8601 dates, schema-version field) and "Export CSV per table".
  3. Offer "Import JSON" to restore and to prove the export round-trips.
  4. Time Machine already covers `~/Library/Application Support`.
- **Data modeling for decades of data:** Store instants as UTC (ISO-8601 TEXT or Unix seconds) plus the entry's local `tz` identifier. Daily totals bucket by *local* calendar day, and sleep and work blocks cross midnight. Keep derived daily totals as SQL views, or compute them on the fly; don't store them, which avoids drift. Use INTEGER for calories and mg caffeine, and REAL for grams of protein.
- **AI-assistant legibility, ranked:** (1) plain GRDB with SQL migrations, (2) SQLiteData (`@Table` structs plus SQL migrations, a slightly unfamiliar query DSL), (3) Core Data (.xcdatamodeld XML is hard for an LLM to edit safely), (4) SwiftData (implicit schema, VersionedSchema ceremony, runtime-only crash feedback). A `schema.sql` dump checked into the repo and regenerated by a test makes the current schema obvious to an assistant under either SQL option.

### Gaps
- Exact current GRDB backup method signatures were not quoted this session (README truncated). Check `DatabaseReader.backup(to:)` in the GRDB docs.

---

## Q7. Aggregation and analytics: SQL vs in-memory Swift

### Takeaway
At this scale (roughly 10^4–10^5 rows over years), performance is irrelevant for every candidate. Even fetching everything and reducing in Swift is well under 100 ms (an inference, unbenchmarked). The real criteria are expressiveness and reuse. SQL (GROUP BY, window functions for rolling averages and streaks, CTEs) in GRDB/SQLiteData is concise, testable, and inspectable outside the app. SwiftData can't express aggregates at all, so every chart means hand-written fetch-and-reduce code.

### Cited Findings
- SwiftData has no SQL-pushed aggregate functions. The workarounds are sort-plus-limit for min/max and Core Data coexistence for the rest. — [Crosley 2026-06-15](https://blakecrosley.com/blog/swiftdata-performance-storage-engine)
- SwiftData observation re-runs queries on unrelated property changes, per Point-Free (a biased source). That adds churn to chart views that observe large ranges. — [Point-Free ep. 372](https://www.pointfree.co/episodes/ep372-wwdc26-swiftdata)
- SQLiteData's `@FetchAll`/`@FetchOne` can observe arbitrary SQL query results, including aggregates and counts, and refresh views automatically. — [sqlite-data README](https://github.com/pointfreeco/sqlite-data)

### Inferences
- Correlations (for example caffeine vs sleep duration) are best done in SQL to produce aligned per-day vectors, followed by a Pearson or Spearman calculation in Swift. SQLite has no built-in CORR. Streaks are the classic "gaps and islands" window-function query.
- Swift Charts consumes `[DailySummary]` structs regardless of storage, so a `daily_summary` SQL view mapped to a Codable struct is the cleanest seam.

### Gaps
- No benchmarks found for any of the stacks at this scale; I found none, and none are needed.

---

## Overall recommendation (for the report writer)

**Primary:** **SQLiteData 1.12.1** (Point-Free, MIT) on **GRDB 7.12.0**.
- Use UUID primary keys, no non-PK UNIQUE constraints, and SQL migrations through `DatabaseMigrator`.
- Leave CloudKit `SyncEngine` **off** until the user joins the paid Apple Developer Program, which an iPhone/Watch companion effectively requires anyway.

**Conservative alternative:** plain **GRDB 7.12.0** with **GRDBQuery 0.11.0**, or a small `@Observable` wrapper over `ValueObservation`. This avoids about 12 Point-Free dependencies and the 0.x StructuredQueries DSL, at the cost of writing sync yourself later.

**Reject:** SwiftData (no aggregates, inheritance crashes, opaque migrations and store) and Core Data (ceremony, no advantage here).

**On the October 2026 design pass:** Its GRDB recommendation and SwiftData rejection are sound for the reasons above. The one critique is that it should consider SQLiteData as the SwiftUI layer over GRDB, and adopt the sync-compatible schema rules now.

**Suggested SPM pins:**
- `.package(url: "https://github.com/pointfreeco/sqlite-data", .upToNextMinor(from: "1.12.1"))`
- `.package(url: "https://github.com/groue/GRDB.swift", .upToNextMinor(from: "7.12.0"))`
- Commit `Package.resolved`. Re-check the 7.6.0 → 7.6.1 lesson: avoid floating onto fresh minors without reading the release notes.
