# Cross-platform / non-Swift stacks vs native SwiftUI for a premium Mac-only logbook app (as of Nov 2026)

Research date: 2026-11-08. About 17 tool calls. Items marked **[background knowledge, not verified this session]** come from the researcher's prior knowledge (cutoff mid-2026) and were not re-checked against a live source. Treat them as likely, not confirmed.

Bottom line for the report writer: no non-Swift stack matches SwiftUI on this app's main requirement, an Apple-grade macOS 26/27 look, and none can avoid Swift for widgets or App Intents. The best a web or cross-platform stack can do is a real native glass *backdrop* (window level) with web or Skia content drawn on top that imitates Apple controls. Every Liquid Glass bridge found is a small (tens of stars, 0.x version) community package, often using undocumented private parameters. The real wins for cross-platform stacks (cross-OS reach, more web training data for AI assistants, hot reload) count for little in a private, Mac-only, never-published app. The user has also already archived one Tauri attempt.

---

## 1. Can any web/cross-platform stack get true Liquid Glass / native materials and controls on macOS 26/27? What looks "off"?

### Takeaway
Only window-level glass is achievable. Tauri and Electron can put a real `NSGlassEffectView` behind a transparent web view, and Compose (via the Nucleus library) can use native traffic lights and sidebar glass. Every control, sidebar row, toolbar item, sheet, menu, and chart inside the window is still drawn by HTML/CSS or Skia/Impeller as an imitation. Flutter's own Cupertino library has no Liquid Glass at all as of Oct 2026. In SwiftUI the system gives you all of this automatically (standard controls, toolbars, sidebars, inspectors) plus `glassEffect` for custom views.

### Cited Findings

**Apple platform API (baseline)**
- `NSGlassEffectView` is a **public** AppKit class, available macOS 26.0+, described as "A view that embeds its content view in a dynamic glass effect." Public properties: `contentView`, `cornerRadius`, `tintColor`, `style`, `effectIsInteractive`. A related `NSGlassEffectContainerView` merges nearby glass views — [Apple Developer docs: NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview)
  - Conflict note: the community Tauri and Electron wrappers below describe `NSGlassEffectView` as a "private" API. Apple's docs show the class itself is public in the macOS 26 SDK. The *extra* knobs those wrappers expose (numbered variants, scrim, subdued) are the undocumented/private parts.
- The Apple "Adopting Liquid Glass" page did not render through the fetch tool, so I could not quote it — [Apple: Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass). **[background knowledge, not verified this session]** Apple's guidance is that standard SwiftUI/AppKit controls, toolbars, sidebars, and sheets pick up Liquid Glass automatically when rebuilt with the 26 SDK, and that SwiftUI `glassEffect(_:in:)`, `GlassEffectContainer`, and `.buttonStyle(.glass)` cover custom views.
- macOS 27 (WWDC June 2026) adds a system Settings slider that moves Liquid Glass from very clear to fully tinted. iOS 27 has the same control — [Very Good Ventures, "WWDC 2026, Through a Flutter Lens" (Jun 12, 2026)](https://verygood.ventures/blog/wwdc-2026-through-a-flutter-lens/). Inference: native apps follow this user setting for free. Imitation glass drawn in CSS or shaders will not unless someone wires it up by hand.

**Tauri 2**
- `tauri-plugin-liquid-glass` (community, not official): uses `NSGlassEffectView` on macOS 26+ and falls back to `NSVisualEffectView`. It needs a transparent window and the macOS private-API flag in `tauri.conf.json`. The docs list 24 material variants, marked experimental. Latest release 0.1.6 (Dec 18, 2025). About 19 GitHub stars and 1 open issue, last pushed Dec 2025 — [docs.rs tauri-plugin-liquid-glass](https://docs.rs/tauri-plugin-liquid-glass); [awesome.ecosyste.ms listing](https://awesome.ecosyste.ms/projects/github.com%2Fhkandala%2Ftauri-plugin-liquid-glass)
- A forum commenter who prefers Tauri over Electron still lists "outdated theming and several widgets" among Tauri's gaps (anecdotal) — [blendit.bsd.cafe comment](https://blendit.bsd.cafe/comment/1209460)

**Electron**
- `electron-liquid-glass` (community npm package): inserts `NSGlassEffectView` instances **behind** the web content ("not over it") and falls back to `NSVisualEffectView`. It requires macOS 26+, Electron 30+, Node 22+, `transparent: true`, and `vibrancy` left unset, because setting it "will override the liquid glass effect and cause blurriness." The `unstable_setVariant` / `unstable_setScrim` / `unstable_setSubdued` methods use private APIs and carry the warning "DO NOT USE IN PROD." Removing and updating views is still an unchecked roadmap item. Only variants 0–15 and 19 are described as working — [electron-liquid-glass README (unpkg)](https://app.unpkg.com/electron-liquid-glass@1.0.1/files/README.md); [pkgstats](https://www.pkgstats.com/pkg:electron-liquid-glass)
- Electron 40.0.0 (Jan 13, 2026; Chromium 144, Node 24.11.1) shipped macOS 26 fixes for "excessive WindowServer GPU usage on macOS Tahoe 26," high CPU usage with the input tag on macOS 26, and trafficLightPosition with `customButtonsOnHover` — [Electron 40.0.0 blog](https://www.electronjs.org/blog/electron-40-0). Inference: Electron was still fixing basic Tahoe compatibility bugs months after macOS 26 shipped.

**Flutter (macOS desktop)**
- Official status: tracking issue flutter/flutter #170310 (opened Jun 10, 2025) was still P3 on Oct 18, 2026. In June 2025 the team said Apple's 26-series design would not be built into Cupertino for now and contributions would not be accepted. `cupertino_ui` 1.0.0 (Aug 12, 2026) moved the existing Cupertino code out of core and added no glass. `cupertino_ui` 1.1.3 (Oct 14, 2026) still has no glass material. A Sep 9, 2026 Flutter blog post said official Liquid Glass work is "in progress" with community package authors. Community PRs #13162/#13163 (Oct 8, 2026) to merge liquid_glass_widgets into a `liquid_glass` branch are unmerged, and the author noted the code does not compile yet — [issoh.co.jp article, updated Oct 18, 2026](https://www.issoh.co.jp/tech/details/16743/) (secondary source, but it cites issue and PR numbers)
- Community packages: `liquid_glass_widgets` 1.13.0 (shader-based, premium mode Impeller-only, "avoid on scrolling surfaces"); `liquid_glass_renderer` 0.2.0-dev.4 (experimental, max 16 shapes, not updated in about 11 months, lists macOS); `cupertino_liquid_glass` (BackdropFilter blur, no refraction); `native_liquid_glass` (iOS-only UiKitView, 1–2 platform views per screen) — [issoh.co.jp](https://www.issoh.co.jp/tech/details/16743/); [pub.dev cupertino_liquid_glass](https://pub.dev/documentation/cupertino_liquid_glass/0.6.0/)
- `macos_glass` 0.1.4: System Settings-style window, sidebar, glass toolbar capsules, menus, sheets. Its "glass" is made from backdrop blur, tint, top sheen, hairline edge, and soft shadow (an imitation), on top of a native sidebar-blur window material via `macos_window_utils`. 1 like, 187 downloads — [pub.dev macos_glass](https://pub.dev/packages/macos_glass)
- Community view (anecdotal): a Reddit commenter said real Liquid Glass is "impossible to implement with the current Flutter engine," and a Mastodon user said its edge reflections and background distortion are "very hard or nearly impossible to imitate correctly" — [r/FlutterDev thread](https://r.enesgenc.dev/r/FlutterDev/comments/1l7h2mc/will_customers_demand_liquid_glass_on_apple/mx1105p/?context=3); [polymaths.social post](https://polymaths.social/@kytta/statuses/01K6Z48VCCQMXJMH4H9NKNN0P0)

**React Native macOS / Expo**
- react-native-macos 0.83.0 is the latest official release (tagged "Latest," Sep 30, year not shown on the page but context implies 2026). It syncs with React Native 0.83.10, and its release notes do not mention macOS 26, Liquid Glass, Fabric, or Expo. The 0.81 line was still being patched in April 2026, including a CVE dependency bump and an SPM macOS support backport — [react-native-macos 0.83.0 release](https://github.com/microsoft/react-native-macos/releases/tag/react-native-macos%400.83.0); [PR #2931](https://github.com/microsoft/react-native-macos/pull/2931); [PR #2916](https://github.com/microsoft/react-native-macos/pull/2916)
- A devbytes article argues React Native is better placed than Flutter for Liquid Glass because it uses native components (iOS-focused opinion) — [devbytes](https://devbytes.co.in/news/how-ios-26s-liquid-glass-ui-is-a-challenge-for-flutter)

**Kotlin Compose Multiplatform**
- The Nucleus "Compose Macos UI" library ports the macOS 26 style to Compose. On macOS, the traffic lights (native AppKit), the large macOS 26 corner radius (via a hidden `NSToolbar`), the sidebar glass region, and SF Symbol icons are native. Everything else is Compose-drawn. Its docs note that native surfaces "follow `MacosTheme` rather than the OS appearance." Sidebar items "always render the Lucide vector even on macOS" because `SidebarItem.icon` takes an `ImageVector`. `titleBarHeight` must be kept in sync by hand because "the native layer and the visible toolbar are drawn separately." It patches the JVM for the macOS 26 SDK and pulls a GraalVM 25 JDK for installers. Badges list Compose Multiplatform 1.11.1 and Kotlin 2.4.10 — [NucleusFramework/compose-macos-26-ui wiki](https://github.com/NucleusFramework/compose-macos-26-ui/wiki); [klibs.io](https://klibs.io/project/NucleusFramework/compose-macos-26-ui)
- Compose Desktop runs on the JVM (JDK 11+). Native (non-JVM) Compose on macOS was described as "still very experimental" in an older Kotlin Slack thread (date not current) — [Kotlin compatibility docs](https://kotlinlang.org/docs/multiplatform/compose-compatibility-and-versioning.html); [kotlinlang Slack archive](https://slack-chats.kotlinlang.org/t/10377512/right-now-compose-for-ios-really-means-ios-only-and-not-also?t=v2)

### Inferences
- **What looks "off" in web stacks (Tauri/Electron):** the window background can be real glass, but sidebar selection pills, toolbar capsules, segmented controls, popovers, context menus drawn in HTML, scroll physics/rubber-banding inside the web view, focus rings, text rendering and kerning in CSS versus native SF Pro optical sizing, and spring animations all have to be hand-imitated. Interactive glass (`effectIsInteractive`, morphing between glass shapes with `GlassEffectContainer`) and the macOS 27 transparency slider are not available to HTML elements.
- **Flutter:** everything is Skia/Impeller-drawn, so even with `macos_ui` or `macos_glass` the controls are look-alikes. There is no official Liquid Glass and no committed date. Refraction-quality shaders are Impeller-only and the docs advise against them on scrolling surfaces.
- **RN macOS:** in principle the closest of the cross-platform options, since it maps to AppKit views. But I found no evidence of Liquid Glass-specific work in react-native-macos release notes, and the macOS fork trails upstream RN. Expo's macOS support is not first-class (see Gaps).
- **Compose:** the most thoughtful attempt (native chrome plus Compose content), but it is a single community project on a JVM runtime with acknowledged seams.
- **SwiftUI:** gets the real thing by default, including future macOS 27/28 refinements, with no extra work.

### Gaps
- Could not fetch Apple's "Adopting Liquid Glass" page or the HIG Materials page text (JS-rendered). Claims about automatic adoption are from background knowledge.
- No side-by-side screenshot comparisons of Tauri/Electron glass versus native SwiftUI were found.
- No evidence either way on whether react-native-macos exposes `NSGlassEffectView` or SwiftUI glass components. Expo's macOS status was not confirmed.

---

## 2. Charting: web libraries / fl_chart / Compose vs Swift Charts

### Takeaway
No charting sources were fetched this session (tool budget). Based on background knowledge: web charting (ECharts, visx/D3, uPlot, Observable Plot, Recharts) is the deepest and most flexible ecosystem and the one AI assistants know best. Swift Charts is the only option whose output looks like Apple's Health/Fitness/Screen Time charts by default and works unchanged in widgets and on watchOS.

### Cited Findings
- No sourced findings gathered this session for charting.

### Inferences
- **[background knowledge, not verified this session]** Swift Charts (macOS 13+) offers declarative marks (bar, line, area, point, rule, sector/pie since macOS 14), scrolling and selection APIs (macOS 14+), accessibility and audio graphs built in, system fonts and colors, and matching animations. It also runs inside WidgetKit and on watchOS, which no web or Flutter chart library can do. Its weaknesses: less customization than D3/visx, some performance limits with very large point counts, and fewer exotic chart types. For a personal logbook (days to years of points), volume is not a concern.
- **[background knowledge, not verified this session]** Web: ECharts and uPlot handle large datasets and many chart types; visx/D3 and Observable Plot give full control. Making them look like Apple charts (SF Pro, rounded bar caps, Health-style ranges, haptics-free selection, native tooltips) is manual styling work. Flutter's `fl_chart` is capable but has its own look. Compose has fewer mature chart libraries (e.g., Vico, mostly Android-oriented).
- For "beautiful like Apple" with the least effort, Swift Charts wins. For maximum chart variety, web libraries win.

### Gaps
- No 2026 benchmarks or quality comparisons were retrieved. The report writer should treat this section as lower-confidence or rely on another researcher's charting notes.

---

## 3. Menu bar timers, notifications, global hotkeys, local DB, widgets, App Intents/Shortcuts

### Takeaway
Menu bar timers, notifications, hotkeys, and SQLite are all doable in Tauri and Electron. **WidgetKit widgets and App Intents require Swift in every stack**: Flutter and Tauri plugins only bridge data to a separately built Swift/SwiftUI extension. Any cross-platform choice therefore becomes a two-language project as soon as widgets or Shortcuts are wanted.

### Cited Findings
- **Tauri menu bar timer:** a developer reports that replacing the whole tray menu every tick works on macOS but is unreliable on Windows. The recommended approach is to keep a handle to one menu item and update its text — [tauri-apps discussion #11134](https://github.com/orgs/tauri-apps/discussions/11134). Menu-bar popover apps use the `tray-icon` feature plus `tauri-plugin-positioner`, with a borderless transparent always-on-top window under the icon — [DEV: Complete guide to a macOS menu bar app with Tauri v2](https://dev.to/hiyoyok/complete-guide-to-building-a-macos-menu-bar-app-with-tauri-v2-aji); [DEV: "what nobody tells you"](https://dev.to/hiyoyok/building-a-menubar-app-with-tauri-v2-what-nobody-tells-you-2nae)
- **Widgets, Tauri:** `tauri-plugin-widgets` 0.3.0 states that the widget extension is built by Xcode and included in the bundle. Tauri doesn't generate an `.xcodeproj`, so the extension is a separate Xcode project that reads JSON and renders SwiftUI views. The Tauri CLI can scaffold `src-tauri/macos-widget/`. App and widget share data through an App Group — [docs.rs tauri-plugin-widgets README](https://docs.rs/crate/tauri-plugin-widgets/0.3.0/source/README.md)
- **Widgets, Flutter:** `widgets_kit` says you cannot write the widget in Flutter. The widget is native code, though a Flutter widget can be rendered to an image. `widget_kit_plugin` says presentation logic "has to be written using Swift/SwiftUI" — [pub.dev widgets_kit](https://pub.dev/documentation/widgets_kit/0.1.1/); [pub.dev widget_kit_plugin](https://pub.dev/documentation/widget_kit_plugin/latest/)
- **App Intents, Flutter:** Flutter has "no official App Intents integration and no committed plan" (flutter/flutter #170589). SiriKit is being deprecated in favor of App Intents — [VGV WWDC 2026 Flutter lens](https://verygood.ventures/blog/wwdc-2026-through-a-flutter-lens/)

### Inferences
- **[background knowledge, not verified this session]** Tauri 2 has official plugins for notifications (`tauri-plugin-notification`), global shortcuts (`tauri-plugin-global-shortcut`), SQL/SQLite (`tauri-plugin-sql`), and Stronghold/store. Its macOS tray icon supports `set_title`, which shows text next to the icon, enough for an "01:23:45" timer. Electron has `Tray.setTitle`, `globalShortcut`, the `Notification` API, and better-sqlite3. Flutter uses community packages (`tray_manager`, `hotkey_manager`, `flutter_local_notifications`, drift/sqflite/Isar). Compose Desktop uses Java AWT `SystemTray` (weak on macOS) or JNA bridges.
- **[background knowledge, not verified this session]** SwiftUI has `MenuBarExtra` (macOS 13+) for the status item, `UNUserNotificationCenter` for scheduled and actionable notifications, SwiftData/Core Data/GRDB for local DB, and WidgetKit, App Intents, Live Activities/Controls in the same Xcode project and language. Global hotkeys still need Carbon `RegisterEventHotKey` or a package such as KeyboardShortcuts (sindresorhus), so this is not a SwiftUI advantage.
- "Proactive reminders and insights" (scheduled local notifications, Shortcuts automations, Focus filters, Spotlight via App Intents) depend on Apple-only frameworks. The cross-platform stacks reach them only through native bridges.

### Gaps
- Did not verify current versions or macOS 26 behavior of Tauri's notification, global-shortcut, or SQL plugins.
- Did not find react-native-macos or Compose-specific evidence for menu bar timers, widgets, or App Intents.

---

## 4. Mobile companion story (iPhone / Apple Watch / widgets)

### Takeaway
Tauri 2, Flutter, RN, and Compose can each ship an iPhone app from shared code. **None can build a watchOS app or a widget/complication without Swift.** SwiftUI shares models, views, Charts, App Intents, and widgets across macOS, iOS, and watchOS in one project, which covers the user's likely future (iPhone logging, Watch quick-log, widgets).

### Cited Findings
- Widget extensions must be native Swift/SwiftUI for Flutter and Tauri, as shown above — [tauri-plugin-widgets](https://docs.rs/crate/tauri-plugin-widgets/0.3.0/source/README.md); [widget_kit_plugin](https://pub.dev/documentation/widget_kit_plugin/latest/)
- The iOS 27 SDK requires adopting the UIScene lifecycle. Flutter 3.41 made UIScene the default. Xcode 27 is Apple-Silicon-only. Flutter's proposed iOS minimum rises to 15 — [VGV WWDC 2026](https://verygood.ventures/blog/wwdc-2026-through-a-flutter-lens/). Inference: each Apple SDK cycle adds migration work that cross-platform frameworks must absorb before apps can follow.
- Compose Multiplatform 1.11.0 focused on iOS and web improvements (concurrent rendering by default, v2 ComposeUiTest) — [devbytes on CMP 1.11.0](https://devbytes.co.in/news/jetbrains-releases-compose-multiplatform-v1110)

### Inferences
- **[background knowledge, not verified this session]** Tauri 2 mobile (iOS/Android) exists but has a thinner plugin ecosystem than desktop. A web UI on iPhone feels even less native than on Mac. No stack among the five targets watchOS.
- For a single Apple-ecosystem user, SwiftUI's shared-code story is strictly better. The cross-platform mobile story only matters if Android or Windows ever enters the picture.

### Gaps
- Did not verify current Tauri 2 mobile maturity or Expo-for-macOS status in 2026.

---

## 5. Where cross-platform stacks genuinely win, and whether it matters for a Mac-only personal app; footprint and maturity

### Takeaway
The genuine wins are reach across operating systems, the size of the web/JS ecosystem (charts, UI kits), AI assistants' larger web training corpus, and very fast hot reload. For a private, Mac-only app these are weak: cross-OS reach is irrelevant, SwiftUI Previews and Xcode 27 narrow the iteration gap, and AI assistants now write competent SwiftUI. The costs are permanent: imitation UI, bridge code in Swift anyway for widgets and Intents, and larger memory use (Electron especially) for an app meant to run all day in the menu bar.

### Cited Findings
- **Memory/bundle:** with six windows open, Tauri used about 172 MB and Electron about 409 MB. On macOS, Electron's Chromium renderer processes used roughly twice the memory of Tauri's WKWebView processes. Startup difference was negligible. Bundles were about 8.6 MiB (Tauri) vs about 244 MiB (Electron) — [Hopp, "Tauri vs Electron: performance, bundle size, and the real trade-offs" (DEV)](https://dev.to/gethopp/tauri-vs-electron-performance-bundle-size-and-the-real-trade-offs-1el4)
- Flutter desktop memory figures found (about 182 MB idle vs Tauri about 34 MB) come from a source that cites a nonexistent "Flutter 4.0", so they are **unreliable** — [DEV johal.in comparison](https://dev.to/johalputt/comparison-tauri-20-vs-flutter-40-desktop-for-cross-platform-app-performance-5cng). The multi-framework repo has incomplete ("?" / "Benchmark WIP") tables — [Elanis/web-to-desktop-framework-comparison](https://github.com/Elanis/web-to-desktop-framework-comparison)
- **Current versions found:** Electron 40.0.0 (Jan 13, 2026). E41 (Mar '26) and E42 (May '26) are on the schedule, but I did not confirm the latest shipping version in Nov 2026 — [Electron 40 blog](https://www.electronjs.org/blog/electron-40-0). Flutter 3.47.x was current around Oct 2026, with 3.50 planned for Nov 2026 to deprecate legacy Material/Cupertino in core — [issoh.co.jp](https://www.issoh.co.jp/tech/details/16743/). react-native-macos 0.83.0 is "Latest" (synced to RN 0.83.10) — [GitHub release](https://github.com/microsoft/react-native-macos/releases/tag/react-native-macos%400.83.0). Compose Multiplatform 1.11.x (1.11.1 referenced), Kotlin 2.4.10 — [Nucleus wiki](https://github.com/NucleusFramework/compose-macos-26-ui/wiki); [Kotlin blog summary](https://www.plushcap.com/content/jetbrains/blog/jetbrains-compose-multiplatform-1110-is-now-available-the-kotlin-blog-1). Tauri: current 2.x minor not verified this session.
- Electron had macOS 26-specific performance bugs (WindowServer GPU, input CPU) fixed in 40.0 — [Electron 40 blog](https://www.electronjs.org/blog/electron-40-0). For an always-running menu-bar app, this kind of regression directly affects battery use.
- The anecdotal claim that Tauri has "much smaller binaries and faster startup times and less RAM usage" than Electron agrees with the Hopp numbers — [blendit.bsd.cafe](https://blendit.bsd.cafe/comment/1209460)

### Inferences
- **Maturity on macOS (rough ranking for this app):** SwiftUI (first-party, Liquid Glass by default) far ahead; then Electron (most mature desktop runtime, heaviest); then Tauri 2 (light, WKWebView, but macOS polish depends on community plugins); then Flutter (stable desktop, but Apple-look lagging and officially deprioritized); then react-native-macos (Microsoft-maintained fork that trails upstream); then Compose Desktop (JVM; macOS look depends on one community library).
- **AI-assistant ease:** web stacks have the largest training corpus, and hot reload with a browser devtools loop is very fast. But the hard parts of this app (glass, menu bar, notifications, widgets, Intents) live in exactly the native seams where AI assistants make the most mistakes: plugin version mismatches, private-API flags, Swift bridge targets. A single-language SwiftUI project removes those seams. The user's own machine runs Xcode 27.2 and Swift 6.4, the toolchain native development needs. Swift 6 strict concurrency is a known source of AI-generated compile errors **[background knowledge]**.
- **Prior archived Tauri attempt:** consistent with the findings above. Tauri can get close on the window background but not on Apple-grade controls, charts, and system integrations.
- **Where a non-Swift stack could still be the better choice:** if the user wanted Windows/Linux/Android too, wanted a web-dashboard version, or strongly preferred React/TS for highly custom visualizations. None of these appears in the stated requirements.

### Gaps
- No rigorous 2026 memory/startup benchmark comparing SwiftUI, Tauri, Electron, Flutter, RN-macOS, and Compose on macOS 26/27 was found.
- No data on AI coding assistant success rates per framework. The AI-ease points are reasoning, not measurements.
- Tauri's exact current version (2.x minor) and Electron's Nov 2026 latest major were not confirmed.
