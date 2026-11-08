# Apple platform frameworks for a native SwiftUI macOS personal logbook app (as of Nov 2026: macOS 26 Tahoe / macOS 27, Xcode 27, Swift 6.4)

Research method note: Apple's developer documentation pages (developer.apple.com/documentation/...) are JavaScript-rendered and could NOT be read by the fetch tool. WWDC session pages (which include transcripts and code) were readable and are the main primary sources here. Where a claim rests on long-standing, well-known API facts that I could not re-verify this session, it is placed under "Inferences" or explicitly labelled "(prior knowledge, not re-verified)". Several 2026 facts come from secondary blogs and are labelled as such.

Context facts: Swift 6.4 ships inside Xcode 27 — [byteiota](https://byteiota.com/swift-64-wwdc-2026-upgrade/) (secondary); macOS 27 was announced at WWDC 2026 under the name "Golden Gate" — [TechRadar](https://techradar.com/computing/mac-os/macos-27-golden-gate-announced-at-wwdc-2026-heres-everything-you-need-to-know); a macOS 27.2 beta was reported shortly after a 27.x release — [BornCity](https://borncity.com/news/macos-27-2-beta-apple-startet-testphase-zwei-tage-nach-release/) (secondary, German).

## Liquid Glass: SwiftUI APIs on macOS 26/27, WWDC26 additions, HIG best practices

### Takeaway
Liquid Glass arrived with the OS 26 generation (macOS 26 Tahoe) via `glassEffect(_:in:)`, `GlassEffectContainer`, and `.glass` / `.glassProminent` button styles; standard toolbars, sidebars and controls adopt it automatically when built with the 26+ SDK. WWDC26 (macOS 27) added no big new glass API surface — it refined the look automatically, added a system-wide Liquid Glass tint/transparency slider, smoother pointer response for "interactive" glass on Mac, and new toolbar-control APIs (overflow menu, visibility priority, pinned items).

### Cited Findings
- Liquid Glass was introduced at WWDC25 as a new system-wide design language across iOS 26, macOS Tahoe 26, etc. — [Apple Newsroom, June 2025](https://www.apple.com/newsroom/2025/06/apple-introduces-a-delightful-and-elegant-new-software-design/)
- WWDC26 "What's new in SwiftUI" (session 269): apps adopt the updated Liquid Glass appearance on the 2027 releases automatically when rebuilt; glass responds to the new Liquid Glass slider that adjusts its tint; custom Liquid Glass elements can be marked "interactive" on iOS **and macOS** so they respond more fluidly to clicks and the mouse pointer (session does not name a new modifier — consistent with the existing `.interactive()` on `Glass`) — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)
- WWDC26 adds `@Environment(\.appearsActive)` usage to dim content when a window is inactive (iPadOS now matches macOS's inactive-window dimming) — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)
- WWDC26 menu bar change: Mac/iPad menu bars show a minimal set of icons by default; opt an item into an icon with `.labelStyle(.titleAndIcon)` inside `CommandMenu` — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)
- WWDC26 toolbar APIs: `ToolbarItemGroup { }.visibilityPriority(.high)`, `ToolbarOverflowMenu { }`, `ToolbarItem(placement: .topBarPinnedTrailing)`, `.toolbarMinimizeBehavior(.onScrollDown, for: .navigationBar)` (the latter two are iOS-flavoured placements; macOS applicability not stated) — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/); also listed by [Swift with Majid](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/)
- Other WWDC26 SwiftUI items useful to this app: `Tab(role: .prominent)`; reorderable containers via `.reorderable()` on `ForEach` + `.reorderContainer(for:)` (works with `List`, lazy stacks/grids); `.swipeActionsContainer()` to enable swipe actions outside `List`; `confirmationDialog(_:item:)` and `alert(_:item:)` item-binding; `@State` is now a macro with lazy one-time initialization of classes (back-deployed to iOS 17/macOS 14 — source-breaking if `@State` has a default and is assigned in `init`, see TN3211); `ContentBuilder` unifies builders to reduce "unable to type-check" errors when building with Xcode 27 — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)
- Press coverage: macOS 27 adds a Liquid Glass customization slider (tint/transparency), restores a uniform toolbar look on macOS, and standardizes window corner radius across apps — [Cult of Mac](https://www.cultofmac.com/news/liquid-glass-changes-ios-27-macos-27); [AppleMagazine](https://applemagazine.com/macos-27-liquid-glass/) (both secondary)
- Core API shape (OS 26+): `.glassEffect(.regular.tint(.blue).interactive(), in: .capsule)`; `Glass` variants `.regular`, `.clear`, `.identity`; `GlassEffectContainer(spacing:)` to group/merge nearby glass shapes; `glassEffectID(_:in:)` for morphing; `glassEffectUnion(id:namespace:)`; `glassEffectTransition(_:)`; `.buttonStyle(.glass)` / `.buttonStyle(.glassProminent)` — Apple doc page [Applying Liquid Glass to custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) (page title confirmed; body not renderable by fetch tool, so signatures are prior knowledge, not re-verified)
- Best practice (from Apple guidance as commonly summarized): use glass for the navigation/control layer floating above content, not for content itself; avoid glass-on-glass; group effects in a `GlassEffectContainer` (glass cannot sample other glass); limit simultaneous effects for performance; test with Reduce Transparency — same source as above (prior knowledge, not re-verified against HIG text)

### Inferences
- For this app: rely on system chrome (`NavigationSplitView` sidebar, `.toolbar`, `.inspector`) to get Liquid Glass for free; reserve custom `glassEffect` for a few floating controls (e.g., a floating "Start block" pill or the quick-log HUD), and keep charts/data on opaque or standard material backgrounds for legibility.
- Because WWDC26 made the glass look user-tunable (slider) and auto-refreshed, avoid hard-coding assumptions about glass translucency/contrast; test both slider extremes plus Reduce Transparency and Increase Contrast.
- None of the Liquid Glass APIs require entitlements or a paid account.

### Gaps
- Could not read HIG "Materials"/"Liquid Glass" pages verbatim (JS-rendered); no direct HIG quotes.
- Whether WWDC26 added any new `Glass` variants or modifiers (beyond automatic refresh + interactive pointer behavior) is not confirmed; session 269 named none.
- Whether `.topBarPinnedTrailing` / `toolbarMinimizeBehavior` apply on macOS is not stated.

## Swift Charts: capabilities, macOS 27 additions, timeline/Gantt, heatmaps, sparklines

### Takeaway
Swift Charts on macOS covers everything this app needs: time-block timelines via `RectangleMark`/`BarMark` with start–end ranges, heatmaps via `RectangleMark` + color scale, sparklines via a stripped `LineMark` chart, scrolling (`chartScrollableAxes`), selection (`chartXSelection`), and annotations. Vectorized/function plots (`LinePlot`, `AreaPlot`, `RectanglePlot`…) arrived at WWDC24 and `Chart3D`/`SurfacePlot` at WWDC25 (OS 26). I found no evidence of new Swift Charts APIs at WWDC26 (OS 27).

### Cited Findings
- WWDC24 session 10155 "Swift Charts: Vectorized and function plots" introduced `LinePlot` (plot a function, including parametric and piecewise with `.nan` gaps) and `AreaPlot` (area between functions, bounded sampling domain), plus vectorized plot APIs such as `RectanglePlot` that process large collections efficiently and style via key paths without per-element iteration — [WWDC24 session 10155](https://developer.apple.com/videos/play/wwdc2024/10155/?time=61); [WWDC Notes summary](https://wwdcnotes.com/documentation/wwdc24-10155-swift-charts-vectorized-and-function-plots/)
- WWDC25 introduced `Chart3D { }` and `SurfacePlot` for 3D charts on iOS 26, macOS 26 and visionOS 26 — [DEV Community guide to Chart3D](https://dev.to/arshtechpro/wwdc-2025-swift-charts-3d-a-complete-guide-to-3d-data-visualization-40nc) (secondary)
- WWDC26 SwiftUI session 269 does not cover Charts; WWDC26 searches surfaced no Swift Charts session or new Charts APIs — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/); [Swift with Majid WWDC26 recap](https://swiftwithmajid.com/2026/06/08/what-is-new-in-swiftui-after-wwdc26/) (no Charts mentioned)
- One iOS 27 developer overview mentions a regression in Swift Charts with deeply branching chart content (unverified context) — [rabinarayanpatra.com](https://www.rabinarayanpatra.com/blogs/ios-27-for-developers) (secondary, low confidence)
- Baseline API availability (prior knowledge, not re-verified this session): `BarMark/LineMark/PointMark/AreaMark/RuleMark/RectangleMark` and `.annotation` = iOS 16/macOS 13; `SectorMark`, `chartXSelection`, `chartScrollableAxes`, `chartXVisibleDomain`, `chartScrollPosition` = iOS 17/macOS 14; vectorized/function plots = iOS 18/macOS 15 (WWDC24); `Chart3D`/`SurfacePlot` = OS 26 — [Swift Charts docs](https://developer.apple.com/documentation/charts)

### Inferences
- Timeline/Gantt for blocks (work, sleep, nature's call): `BarMark(xStart: .value("Start", block.start), xEnd: .value("End", block.end), y: .value("Kind", block.kind))` or `RectangleMark(xStart:xEnd:yStart:yEnd:)`; colour by `foregroundStyle(by: .value("Kind", ...))`. A "today" `RuleMark` at `Date.now` driven by `TimelineView(.periodic(from:by:))` gives a live "now" line.
- Heatmap (e.g., caffeine by hour × weekday, or a GitHub-style calendar of steps): `RectangleMark(x:y:)` with `.foregroundStyle(by:)` and `chartForegroundStyleScale(range: Gradient(...))`; for large datasets use `RectanglePlot` (OS 15+).
- Sparklines: a small `Chart { LineMark/AreaMark }` with `.chartXAxis(.hidden)`, `.chartYAxis(.hidden)`, `.chartLegend(.hidden)`; cheap enough for menu bar and widgets (Charts render in WidgetKit).
- Chart3D is unnecessary for this app; skip it.
- No entitlements/paid account needed for Charts.

### Gaps
- Could not confirm via Apple docs whether OS 27 added any Charts symbols (doc pages not renderable); recommend checking the Xcode 27 SDK diff / release notes.

## Foundation Models framework: on-device LLM on macOS 26/27, guided generation, tools, context limits, WWDC26 updates

### Takeaway
Foundation Models (introduced macOS 26) gives free, offline access to Apple's on-device ~3B model with `LanguageModelSession`, `@Generable` structured output, and `Tool` calling — well suited to turning a day's structured stats into short insights/nudges. WWDC26 (macOS 27) rebuilt the on-device model (better logic/tool calling, image input), showed a context size of 8,192 tokens in sample code (docs/other sources still say 4,096 — read `contextSize` at runtime), added a 32K-token Private Cloud Compute model (needs an entitlement — likely impractical without a paid account), a `LanguageModel` protocol for third-party/local models, dynamic profiles, built-in tools, usage reporting, and an `fm` CLI on macOS 27. On-device use needs an Apple Intelligence–capable Apple silicon Mac with Apple Intelligence turned on.

### Cited Findings
- WWDC26 session 241: on-device model "rebuilt from the ground up", better at logic and tool calling; sample shows `SystemLanguageModel().contextSize` → `8192`; `model.tokenCount(for:)`; context-size and token-counting APIs were added in iOS 26.4 (and aligned releases); speaker advises adapting to the hardware the app runs on — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- Conflict on on-device context window: Apple docs still list 4,096 tokens per session (per a blog reading the docs during beta 1), while session code shows 8,192; a secondary guide says 4,096 on macOS 26.0 and 8,192 on macOS 27 on newer devices — [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/); [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [dmarketertayeeb.com](https://dmarketertayeeb.com/blog/apple-foundation-models-macos-27-local-ai/) (secondary)
- Image input: `Attachment(...)` inside the prompt builder accepts `NSImage`, `UIImage`, `CGImage`, Core Image, CVPixelBuffer, file URLs — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- `PrivateCloudComputeLanguageModel`: larger server model, 32,000-token context, reasoning via `ContextOptions(reasoningLevel: .light / .deep)`; no API keys or account setup; no cloud cost for developers under 2M first-time downloads; users have daily limits (higher with iCloud+); **requires an entitlement** — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/). The entitlement is `com.apple.developer.private-cloud-compute`, obtained through an application process; free-tier cost eligibility tied to App Store Small Business Program — [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/) (secondary)
- New `LanguageModel` protocol: `LanguageModelSession` can be backed by `SystemLanguageModel`, `PrivateCloudComputeLanguageModel`, open-source `CoreAILanguageModel` / `MLXLanguageModel` (local models on Apple silicon), and Anthropic/Google Swift packages (which need auth + per-token billing; store OAuth tokens in Keychain) — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); package names `ClaudeForFoundationModels`/`ClaudeLanguageModel` and Firebase `GeminiLanguageModel` per [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/) (secondary)
- Tool calling: custom tools conform to `Tool` with `description`, `@Generable struct Arguments`, `call(arguments:)`; new built-in tools `BarcodeReaderTool`, `OCRTool`, and a Spotlight-backed search tool for local RAG (named `SpotlightSearchTool` per secondary source) — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- `LanguageModelSession.DynamicProfile` (switch instructions/tools/model/options while keeping history); `response.usage` with input/output/cached/reasoning token counts; Evaluations framework integrating with Swift Testing; Foundation Models instrument in Xcode 27 — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- macOS 27 ships an `fm` CLI (`respond`, `chat`, `token-count`, `schema`, `serve`, `available`, `quota-usage`; `fm serve` exposes a local OpenAI-compatible endpoint) — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); subcommand list from [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- Core framework being open-sourced (can run where Swift runs); `foundation-models-utilities` package updated between OS releases — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- WWDC26 session 241 does not describe changes to `@Generable` itself — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/)
- Most OS 27 Foundation Models APIs were marked Beta during the summer betas — [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- Availability: check `SystemLanguageModel.default.availability`; unavailable reasons include `deviceNotEligible`, `appleIntelligenceNotEnabled`, `modelNotReady`; user must enable Apple Intelligence — [Kodeco](https://www.kodeco.com/53631607-getting-started-with-apples-foundation-models); [DEV Community fallback guide](https://dev.to/arshtechpro/how-to-fall-back-gracefully-when-apple-intelligence-isnt-available-48j). Requires an Apple silicon (M-series) Mac — [levelup.gitconnected](https://levelup.gitconnected.com/integrating-apples-on-device-llm-a-step-by-step-guide-to-foundation-models-47d84a7a347a) (secondary); macOS VMs often can't run it (same source family, secondary)

### Inferences
- On-device `SystemLanguageModel` needs no entitlement, so it should work in an ad-hoc / "Sign to Run Locally" build on an eligible Mac (no source found explicitly testing ad-hoc signing — see Gaps).
- Fit for "daily insights/nudges": pre-compute stats in Swift (totals, deltas vs. 7-day average, streaks) and pass a compact summary (a few hundred tokens) with `@Generable struct Insight { headline; body; severity; suggestedAction }`. Use tool calling (e.g., `getDayStats(date:)`, `getWeeklyTrend(metric:)`) only if summaries exceed the budget. Never let the model do arithmetic; it should narrate pre-computed numbers. Always have a deterministic, rule-based fallback for when `availability != .available`.
- PCC model is effectively off the table for an unpaid, non-distributed app (entitlement application + App Store-oriented cost terms).
- `fm serve` on macOS 27 is an alternative integration path (local HTTP) for scripts/extensions outside the app.

### Gaps
- Definitive on-device context size per Mac/OS (4,096 vs 8,192) — conflicting sources; must read `contextSize` at runtime.
- Official Mac hardware floor (M1?) and Apple Intelligence language/region requirements not confirmed from Apple docs this session.
- Whether the PCC entitlement can be granted to a free (non-ADP) account — not stated anywhere found.
- Exact rate limits/daily quotas not published.

## HealthKit on macOS: availability, entitlements, alternatives

### Takeaway
As of the latest authoritative statement found (Apple DTS, Sept 2025), apps cannot read or write HealthKit data on macOS — `HKHealthStore.isHealthDataAvailable()` returns `false` — and there is no Health app on Mac. WWDC26 coverage found no announcement of HealthKit data access or a Health app on macOS 27. Plan on an iPhone companion (HealthKit on iPhone → shared store via CloudKit/iCloud) or Health export files; note HealthKit itself needs a paid-account entitlement on iOS.

### Cited Findings
- Apple DTS engineer (Ziqiao Chen, Sept 2025): "your app can't read or write HealthKit data on macOS as of today. isHealthDataAvailable() will return you false" — [Apple Developer Forums thread 798780](https://developer.apple.com/forums/thread/798780)
- Same thread, Mar 2026: a developer notes HealthKit documentation lists only iOS, visionOS, and watchOS, asks if macOS support is coming — no answer — [Apple Developer Forums thread 798780](https://developer.apple.com/forums/thread/798780)
- Community workaround in that thread: export Health data from iPhone and read it on the Mac (as CDA/XML) — [Apple Developer Forums thread 798780](https://developer.apple.com/forums/thread/798780) (user suggestion, not Apple)
- A third-party SDK-diff site lists 17 of 19 new HealthKit symbols in the "iOS & macOS 27 SDK" tagged with macOS availability (menopause category types, `HKWorkoutZone*` types) — [miniswift.run](https://miniswift.run/whats-new/healthkit/) (secondary; API availability annotations do not imply that live Health data is available on Mac)
- Pre-WWDC26 wishlists hoped for a Health app on Mac; post-keynote macOS 27 recaps found mention no Mac Health app — [9to5Mac wishlist (May 2026)](https://9to5mac.com/2026/05/29/hopes-for-wwdc-2026-health-for-mac-wallet-everywhere-and-other-os-27-dreams/); [TechRadar macOS 27 recap](https://techradar.com/computing/mac-os/macos-27-golden-gate-announced-at-wwdc-2026-heres-everything-you-need-to-know)
- Mac Observer: macOS still has no built-in Health app; suggested workaround is exporting iPhone data to the Mac — [Mac Observer](https://www.macobserver.com/macos/best-software/personal-health-software-for-mac/)
- HealthKit is not listed among macOS capabilities on Apple's supported-capabilities page — [Apple: Supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos)

### Inferences
- Direct HealthKit reads of steps/active energy/sleep on Mac: treat as **not available** on macOS 26/27 for planning purposes; if Apple ever enables it, it would require the HealthKit entitlement, which (on iOS) requires a provisioning profile — i.e., paid membership is very likely required (prior knowledge, not re-verified).
- Practical options for this app:
  1. Manual entry + optional import of the iPhone Health app's "Export All Health Data" `export.zip` (`export.xml`, plus CDA) — parse `HKQuantityTypeIdentifierStepCount`, `ActiveEnergyBurned`, `HKCategoryTypeIdentifierSleepAnalysis` records. Free, no entitlements.
  2. A user-built Shortcuts automation on iPhone ("Find Health Samples" → write JSON to iCloud Drive) that the Mac app reads. Free; iCloud Drive file access from an ad-hoc Mac app works via a user-selected folder (security-scoped bookmark) if sandboxed, or directly if not.
  3. A native iPhone companion reading HealthKit and syncing via CloudKit — requires paid membership (HealthKit + iCloud/CloudKit entitlements need provisioning; free Personal Team device builds also expire after 7 days — prior knowledge, not re-verified).

### Gaps
- No Apple primary source found confirming or denying HealthKit data access on macOS 27 specifically; macOS 27 release notes not readable.
- A German report mentions macOS 27.2 beta "Health analysis features" without clarity whether Mac-side — [BornCity](https://borncity.com/news/macos-27-2-beta-apple-startet-testphase-zwei-tage-nach-release/) — unresolved.

## MenuBarExtra, TimelineView, Text(timerInterval:), sleep/wake correctness

### Takeaway
`MenuBarExtra` with `.menuBarExtraStyle(.window)` (macOS 13+) is the standard way to build a menu bar timer popover; the label itself can show a live count via `Text(timerInterval:)` or `TimelineView`. Store absolute start `Date`s (never accumulate ticks) so timers stay correct across sleep/wake. No entitlements needed.

### Cited Findings
- WWDC26 adds menu-bar-related SwiftUI changes: minimal icons by default in app menus, `.labelStyle(.titleAndIcon)` to opt in — [WWDC26 session 269](https://developer.apple.com/videos/play/wwdc2026/269/)
- macOS 26 lets app Controls (WidgetKit `ControlWidget`) sit directly in the menu bar; demo used a coffee-tracker control to update a log from the menu bar — [WWDC25 "What's new in widgets" (278)](https://developer.apple.com/videos/play/wwdc2025/278/)
- API facts (prior knowledge, not re-verified this session; Apple doc pages not renderable): `MenuBarExtra(_:systemImage:content:)` and `MenuBarExtra(isInserted:content:label:)` — macOS 13; `.menuBarExtraStyle(.window | .menu)` — macOS 13; `Text(timerInterval: start...end, countsDown: false)` — iOS 16/macOS 13; `Text(_:style: .timer)` and `Text(.currentDate, format: .timer(countingUpIn:))`-style formats — iOS 16+/macOS 13+ (format variants vary by OS); `TimelineView(.periodic(from:by:))` — macOS 12 — [MenuBarExtra docs](https://developer.apple.com/documentation/swiftui/menubarextra); [Text(timerInterval:) docs](https://developer.apple.com/documentation/swiftui/text/init(timerinterval:pausetime:countsdown:showshours:))

### Inferences
- Model a running block as `{start: Date, end: Date?}`; display elapsed = `now - start`. `Text(timerInterval:)` self-updates without app timers and survives sleep because it's date-based. For the menu bar label, `Text(timerInterval:)` inside `MenuBarExtra`'s label is the lightest option; if custom formatting is needed, `TimelineView(.periodic(from: .now, by: 1))`.
- Observe `NSWorkspace.didWakeNotification` / `willSleepNotification` to re-sync anything using `Timer` (e.g., notifications scheduling, pomodoro-style limits). Use `ContinuousClock`/wall-clock Dates rather than `Timer` counts.
- Consider `NSApplication.ActivationPolicy.accessory` (LSUIElement) if the app should run primarily as a menu bar app, with a main window opened on demand via `openWindow`.
- Menu-bar Controls (ControlWidget) are a WidgetKit extension → subject to the extension signing/sandbox caveats in the WidgetKit section.

### Gaps
- Could not re-verify exact availability of the `.timer` `Date.FormatStyle` variants from Apple docs.

## WidgetKit on macOS (desktop widgets), Live Activities on Mac, Controls

### Takeaway
macOS 26 desktop/Notification Center widgets render with clear-glass or tinted presentations (use `widgetRenderingMode` / `widgetAccentedRenderingMode`); Controls can live in Control Center and directly in the macOS menu bar; iPhone Live Activities show up in the Tahoe menu bar automatically (iOS 18+ iPhone, no code). There is no Mac-native Live Activity API — a Mac app's own "live" timer should be a MenuBarExtra. Widgets/Controls are app extensions that must share data with the app (App Group) — the main friction point for an unpaid/ad-hoc build.

### Cited Findings
- Live Activities from a paired iPhone appear in the macOS Tahoe menu bar (leading + trailing views together); clicking shows the lock-screen presentation and launches the app via iPhone Mirroring; iPhone must run iOS 18+; no code changes required — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- macOS 26 widgets: desktop and Notification Center widgets can use clear glass or tinted presentations; content rendered in accented mode, background replaced by glass/tint; read `@Environment(\.widgetRenderingMode)` (`.fullColor` vs `.accented`); `widgetAccentedRenderingMode(_:)` on `Image` with `.accented`, `.desaturated`, `.accentedDesaturated`, `.fullColor` — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- Controls on macOS 26: apps built with the macOS SDK, Catalyst, or iOS apps on Apple silicon can provide controls; placeable in Control Center (small/medium/large) and directly in the menu bar — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- Widget reload mechanisms: `TimelineReloadPolicy` (budgeted), `WidgetCenter.shared.reloadAllTimelines()` / `reloadTimelines(ofKind:)` from the running app (not budgeted), and APNs widget push via `WidgetPushHandler` + `.pushHandler(...)` (requires Push Notifications entitlement + server) — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- `RelevanceConfiguration` relevance widgets are a watchOS 26 Smart Stack feature — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)
- On macOS Sequoia+ a widget/app using an iOS-style `group.` App Group ID triggers "would like to access data from other apps" prompts and can break; Apple DTS guidance is to prefix the group ID with the Team ID (`<TEAMID>.something`) on macOS; Mac App Store apps may keep `group.` IDs if registered to the team — [Forums 763826](https://developer.apple.com/forums/thread/763826); [Forums 767581](https://developer.apple.com/forums/thread/767581); [Forums 758358](https://developer.apple.com/forums/thread/758358)
- A macOS widget with an app group set exited immediately on Sequoia beta until the group ID was changed to the team-prefixed form; multiplatform targets can't easily use team-prefixed groups, so devs split macOS targets or swap entitlements via `CODE_SIGN_ENTITLEMENTS` — [Forums 758478](https://developer.apple.com/forums/thread/758478); [Forums 763093](https://developer.apple.com/forums/thread/763093)
- Widgets not showing on macOS is a recurring forum topic — [Forums 751747](https://developer.apple.com/forums/thread/751747)

### Inferences
- WidgetKit extensions on macOS must be sandboxed (prior knowledge, not re-verified). A sandboxed widget cannot read the main app's container, so data sharing needs an App Group container (`<TEAMID>.com.you.logbook`). With a free Apple Account Personal Team, Xcode does assign a team ID, so a team-prefixed group is plausible; with pure ad-hoc ("Sign to Run Locally", no team) there is no team ID → expect group-container prompts or failures. **Flag: reliable widgets/Controls likely need at least a free Personal Team signing identity, and are most reliable with a paid account.**
- Workarounds if App Groups are troublesome: (a) widget reads data via App Intents/`AppEntity` queries is not possible without shared storage either; (b) have the main app write a tiny JSON snapshot into the group container only; (c) skip widgets and use MenuBarExtra + notifications, which need no extension.
- Avoid widget push (needs APNs + server + paid account). Use `WidgetCenter.reloadTimelines` from the app whenever a log is saved, plus timeline entries for "elapsed time" using `Text(timerInterval:)` (widgets render date-relative text live).
- Live Activities: only relevant if a future iPhone companion exists; then its Live Activity (e.g., running work block) would appear in the Mac menu bar for free.

### Gaps
- No source found that tests widget/Control registration under free Personal Team vs. ad-hoc signing on macOS 26/27.
- Apple's supported-capabilities page checkmarks (ADP vs free "Apple Developer" vs Developer ID) for App Groups could not be read — fetch returned rows without column checkmarks — [Apple supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos).
- No WWDC26 widget-specific changes for macOS were found.

## App Intents: Shortcuts, Spotlight actions (Tahoe), interactive snippets, quick logging via Spotlight/Siri

### Takeaway
App Intents is the extensibility backbone: an `AppIntent` like `LogFoodIntent(name:calories:protein:caffeine:)` or `StartBlockIntent(kind:)` becomes available in Shortcuts, in macOS 26 Spotlight (which can run app actions with parameters directly), to Siri, and as interactive snippets (OS 26). WWDC26 (OS 27) pushes App Intents further into Apple-Intelligence Siri via App Schemas/domains. App Intents itself needs no special entitlement (prior knowledge), making it the best free extensibility path.

### Cited Findings
- WWDC25 "Get to know App Intents" (session 275) and "Design interactive snippets" (281) cover OS 26 App Intents, including Spotlight on Mac and interactive snippets — [WWDC25 session 275](https://developer.apple.com/videos/play/wwdc2025/275); [WWDC25 session 281](https://developer.apple.com/videos/play/wwdc2025/281)
- Interactive snippets appear in Spotlight, Siri, and Shortcuts; interactivity updates by calling the static reload method on the snippet intent — [WWDC Notes 281](https://wwdcnotes.com/documentation/wwdc25-281-design-interactive-snippets/); [DEV Community snippets guide](https://dev.to/arshtechpro/wwd-2025-interactive-snippets-guide-for-ios-developers-4ln6) (secondary)
- WWDC26: a session on bringing apps to Siri via App Intents, made more capable by Apple Intelligence in the 27 releases; conforming intents to App Schemas/App Schema domains makes actions executable by Siri through natural language; recommended testing order: Shortcuts → Spotlight → Siri — [WWDC26 session 240](https://developer-rno.apple.com/cn/videos/play/wwdc2026/240/) (via search summary; page content not fetched directly)
- iOS 27: App Intents let users act in third-party apps directly through Siri or Spotlight without opening the app — [Braze WWDC26 roundup](https://www.braze.com/resources/articles/2026-wwdc-ios-27-updates) (secondary)
- macOS 27 rebuilt Spotlight search (press coverage) — [TechRadar](https://techradar.com/computing/mac-os/macos-27-golden-gate-announced-at-wwdc-2026-heres-everything-you-need-to-know)

### Inferences
- Define `AppEntity` types (FoodItem, BlockKind) + `AppShortcutsProvider` phrases ("Log coffee in Logbook"); with parameters, macOS 26+ Spotlight can run "Log Food" with fields filled from the Spotlight action UI — ideal quick-logging path that requires no extension.
- Interactive snippets (OS 26) can return a mini confirmation UI (e.g., "Logged 80 mg caffeine — Undo").
- Siri/Apple-Intelligence App Schema domains may not cover a custom logbook domain; generic `AppIntent`s with App Shortcuts phrases still work. Siri capability on macOS for App Shortcuts historically needed no entitlement (prior knowledge, not re-verified); the legacy SiriKit "Siri" capability is different and needs provisioning.
- App Intents run in-process (or via an App Intents extension); sharing data with an extension again raises the App Group issue — prefer in-app intents (`openAppWhenRun = false` intents run by launching the app in the background).

### Gaps
- Could not read WWDC26 "Discover new capabilities in the App Intents framework" session content; specific OS 27 App Intents APIs (e.g., new snippet or Spotlight APIs on macOS 27) are unverified.
- Whether App Intents / Spotlight actions work under pure ad-hoc signing (vs. development-team signing) is not documented in sources found; Spotlight indexing of intents is generally tied to the app being registered with LaunchServices (installed in /Applications) — unverified.

## UserNotifications for local scheduled reminders in an ad-hoc signed app; actionable notifications

### Takeaway
Local notifications (`UNUserNotificationCenter` with `UNCalendarNotificationTrigger` / `UNTimeIntervalNotificationTrigger`, plus `UNNotificationCategory` actions such as "Log water" / "End block") need no entitlement and no paid account; only remote push and Time Sensitive interruption level need capabilities. The key gotcha for ad-hoc builds is that notification authorization is tied to the bundle ID + code signature, so re-signing can reset permissions.

### Cited Findings
- Push Notifications and Time Sensitive Notifications are listed as capabilities on Apple's macOS supported-capabilities page (i.e., provisioned capabilities) — [Apple supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos) (tier checkmarks not readable)
- WWDC25 guidance: for urgent alerts use a User Notification; widget pushes are opportunistic — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)

### Inferences
- Local `UNNotificationRequest`s with actionable categories (`UNNotificationAction`, `UNTextInputNotificationAction` for quick calorie entry) work in a non-sandboxed or sandboxed, locally signed app without a paid account (prior knowledge, not re-verified this session). Use `.timeSensitive` interruption level only if the entitlement is available; otherwise `.active`.
- System limit of 64 pending local notifications per app (prior knowledge) — schedule rolling windows (e.g., next 48h) and reschedule on app launch/wake.
- "Proactive" nudges (e.g., "No food logged since 1pm", "caffeine after 3pm") are best computed in-app (on wake, on log save, via a background `NSBackgroundActivityScheduler`) and delivered as local notifications; a menu-bar app staying resident makes this reliable. Text can come from Foundation Models with deterministic fallback.
- Ad-hoc signature changes on every rebuild can make macOS treat the app as new for TCC/notification permission; signing consistently with a stable identity (free Personal Team "Apple Development" cert or a self-signed cert) avoids repeated prompts.

### Gaps
- No primary source found this session explicitly confirming local notifications in ad-hoc-signed macOS apps; based on prior knowledge.
- Could not confirm whether Time Sensitive is available to free accounts.

## App Sandbox, App Groups, and what needs a paid Apple Developer Program account

### Takeaway
For a private, non-distributed Mac app: Liquid Glass, Charts, MenuBarExtra, local notifications, on-device Foundation Models, and in-app App Intents need no paid account. Features that rely on extensions (widgets, Controls), shared containers (App Groups), push, CloudKit/iCloud sync, HealthKit (iPhone), and PCC are where provisioning/paid membership becomes necessary or at least much more reliable.

### Cited Findings
- Apple's macOS capabilities reference distinguishes ADP (paid; can distribute on App Store), Developer ID, and "Apple Developer" (free; agreed to Developer Agreement, can't distribute) columns; capabilities listed include App Groups, App Sandbox, Push notifications, iCloud (CloudKit, documents, KVS), Time Sensitive Notifications — [Apple supported capabilities (macOS)](https://developer.apple.com/help/account/reference/supported-capabilities-macos) (per-column checkmarks not readable)
- macOS App Group IDs should be Team-ID-prefixed to avoid Sequoia+ access prompts; `group.` IDs are OK only for Mac App Store apps registered to the team — [Forums 767581](https://developer.apple.com/forums/thread/767581); [Forums 758358](https://developer.apple.com/forums/thread/758358)
- Changing an App Group ID moves the container location, requiring data migration — [Golden Hill Software](https://www.goldenhillsoftware.com/2024/06/migration-step-in-next-beta-of-unread-for-macos/)
- PCC model needs entitlement `com.apple.developer.private-cloud-compute` (application process) — [WWDC26 session 241](https://developer.apple.com/videos/play/wwdc2026/241/); [ivanmagda.dev](https://ivanmagda.dev/posts/wwdc26-foundation-models-year-two/)
- Widget push requires Push Notifications entitlement on the widget extension — [WWDC25 session 278](https://developer.apple.com/videos/play/wwdc2025/278/)

### Inferences (feature matrix — verify before committing)
| Feature | Paid account needed? | Notes |
|---|---|---|
| Liquid Glass, SwiftUI, Charts, MenuBarExtra, TimelineView | No | Pure frameworks |
| Local notifications + actions | No | Time Sensitive level likely needs capability |
| Foundation Models (on-device) | No | Needs Apple Intelligence–eligible Apple silicon Mac + AI enabled |
| Foundation Models PCC model | Very likely yes | Entitlement by application |
| App Intents (in-app), Shortcuts, Spotlight actions | Probably no | Install in /Applications for indexing; unverified for ad-hoc |
| WidgetKit desktop widgets / menu-bar Controls | Free Personal Team probably sufficient; ad-hoc unreliable | Needs sandboxed extension + Team-ID App Group |
| App Groups | Team ID required (free Personal Team has one) | Provisioning-profile behavior on macOS unverified for free tier |
| iCloud/CloudKit sync (Mac ↔ iPhone) | Yes | Requires provisioned iCloud container |
| Push / widget push | Yes | APNs |
| HealthKit (iPhone companion) | Yes for practical use | Free Personal Team iOS builds expire after 7 days (prior knowledge) |
| HealthKit on Mac | N/A | Not supported as of latest Apple statement |
- Simplest data architecture for an unpaid build: a single non-sandboxed (or sandboxed) app with SwiftData/SQLite in Application Support, MenuBarExtra as the "always-on" surface, App Intents for Shortcuts/Spotlight, local notifications — and widgets as an optional add-on once signing with a team ID is in place.

### Gaps
- Could not render Apple's capability table checkmarks to confirm which capabilities the free "Apple Developer" tier gets on macOS.
- No source found on behavior of macOS App Group containers for apps signed "to run locally" (no team) on macOS 26/27.
