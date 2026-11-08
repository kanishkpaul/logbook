# Build tooling, signing, and developer workflow for a CLI/agent-maintained SwiftUI macOS app (as of Nov 2026)

Local environment verified on 2026-11-08 by running commands on the user's machine (primary evidence, cited as "local check"):
- `xcodebuild -version` → Xcode 27.2, build 27B52
- `swift --version` → Apple Swift 6.4.2 (swiftlang-6.4.2.1.9), target arm64-apple-macosx27.0.0
- `sw_vers` → macOS 27.0.1
- XcodeGen, Tuist, mise: not installed. Homebrew is installed at /opt/homebrew/bin/brew.
- `xcrun --find xcodeproj` → /Applications/Xcode.app/Contents/Developer/usr/bin/xcodeproj (Apple's new project-editing CLI is present)
- `xcrun --find xcprojformatter` → present
- `xcodebuild -help` lists `-convert-project FORMAT`
- `xcrun --find mcpbridge` → present ("STDIO Bridge for Xcode MCP Tools"; has a `run-agent` subcommand)

## 1. Project structure options: SwiftPM-bundled .app vs Xcode project + CLI vs XcodeGen vs Tuist vs buildable folders

### Takeaway
The landscape changed in fall 2026: Xcode 27.2 made a JSON project file (`project.xcproj`) the default and shipped Apple's own `xcrun xcodeproj` CLI for editing projects, explicitly aimed at coding agents. Combined with synchronized ("buildable") folders, this removes most of the reason to adopt XcodeGen or Tuist for a single-developer app. The recommended setup is a native Xcode project in the JSON format, created and edited only through `xcrun xcodeproj`, with app code in synchronized folders and features in local Swift packages. XcodeGen 2.46.0 is a mature fallback that supports synced folders and app extensions. Tuist 4.x is moving fast and only has experimental JSON-format support through its XcodeProj library, so it is more than this project needs.

### Cited Findings
**Apple's JSON project format (Xcode 27.2)**
- Apple: "In Xcode 27.2 and later, the default project configuration file is a smaller, hierarchical, self-describing JSON file with a `.xcproj` extension. Xcode 27 and later supports both file formats." The page also says the format "makes it easier for coding intelligence agents to edit the file for you" and that "merge conflicts are less likely." — [Apple: Updating your Xcode project configuration file format](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)
- The format is open source as `apple/xcode-project-format`, with a Swift package `XcodeProjectFormat` (v0.1.0 on Swift Package Index). — [Apple doc above](https://developer.apple.com/documentation/xcode/updating-your-xcode-project-configuration-file-format)
- Xcode 27.2 release notes, under Project Format: "Xcode now supports a JSON-based project format (`.xcproj`) that's more readable, merge-friendly, and easier for coding agents to edit… Projects using `.xcproj` also open in earlier versions of Xcode 27." The same notes say Xcode 27.2 includes Swift 6.4 and requires macOS Tahoe 26.6 or later. — [Xcode 27.2 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)
- InfoQ (Oct 12, 2026): the JSON schema covers targets, file tree, build configurations, settings and external dependencies. It uses human-readable names and paths instead of opaque IDs, except for targets and products. It also advises checking that fastlane, CocoaPods and Tuist support the format before migrating. — [InfoQ](https://www.infoq.com/news/2026/10/xcode-json-project-format/)
- Daring Fireball linked the JSON format news on 2026-09-22, likely at the beta announcement. InfoQ's article is dated Oct 12, 2026. — [Daring Fireball](https://daringfireball.net/linked/2026/09/22/xcode-json-project-files)
- Secondary sources say the file is effectively JSON5 (trailing commas and comments allowed), so a plain `JSON.parse` may fail on it. — [DEV Community guide](https://dev.to/arshtechpro/goodbye-pbxproj-a-friendly-guide-to-xcode-272s-new-json-project-format-bhh). Not verified against the Apple spec.

**Apple's `xcrun xcodeproj` CLI (Xcode 27.2)**
- Local check: `xcrun xcodeproj --help` reads "Inspect and modify Xcode project files (.xcodeproj) from the command line… does not modify .xcworkspace files, schemes, or the contents of .xcconfig files." Its subcommands are `init`, `setting`, `target`, `group`, `config`, `pkg`. `init` writes "project.xcproj, the JSON project format". `target add --product-type` accepts `application, app-extension, framework, library.dynamic, library.static, bundle, unit-test-bundle, ui-test-bundle, tool, … watch-app, watch-extension…` or any full `com.apple.product-type.*` identifier. `target add` defaults `PRODUCT_NAME=$(TARGET_NAME)` and, for app/framework/bundle/test targets, `GENERATE_INFOPLIST_FILE=YES`. (local check, Xcode 27.2 27B52)
- Artem Novichkov (Oct 15, 2026) describes the following workflow:
  - Commands: `xcrun xcodeproj init App.xcodeproj`; add Sources/Frameworks/Resources phases, then a synchronized group, then settings. Set `SWIFT_VERSION` and the deployment target yourself because `init` doesn't.
  - `xcrun xcodeproj setting set [--config Debug] KEY value --target T`; `xcrun xcodeproj config set` links xcconfig files (keep them outside synced groups).
  - `xcrun xcodeproj pkg add <url> --from <ver> --product <name> --target <T>`; read-only `target info`, `group ls`, `pkg list`.
  - `xcodebuild -convert-project xcproj|pbxproj`.
  - `xcprojformatter --update` canonicalizes the file and silently drops unknown keys, so a formatter diff exposes typos.
  - Gotchas: test targets need manual wiring of `TEST_HOST`, `BUNDLE_LOADER`, a dependency on the app, and `ENABLE_TESTABILITY`. Add build phases before attaching a synced group, or the exclusions written cause link failures.
  - Agent advice: change projects only through `xcrun xcodeproj`, never hand-edit `project.xcproj` or `project.pbxproj`, create files on disk for synced groups instead of adding file references, run a formatter check after every change, and put these rules in AGENTS.md or CLAUDE.md.
  - Xcode's MCP tools "can't add packages, link xcconfig files, or edit build phases"; `xcodeproj` covers those.
  - Tuist and XcodeGen "remain options," but a readable project plus Apple's CLI may be enough. — [Artem Novichkov: Xcode Projects for the Command Line and Coding Agents](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents)

**XcodeGen**
- Latest release is 2.46.0 (16 Jul 2026, per the GitHub releases page; the year is inferred from Swift Package Index building tag 2.46.0 on 19 Jul 2026). It added Swift package traits support, made targets follow source declaration order, and embeds static frameworks by default. — [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases); [Swift Package Index build](https://swiftpackageindex.com/builds/B73AC29F-68F7-4860-BCF3-AC59C471EB92)
- 2.45.0–2.45.4 (Mar–Apr 2026) added the following:
  - `projectFormat`, `explicitFolders`, glob `excludes` and `groupOrdering` for synced folders
  - automatic exclusion of `Info.plist` inside synced folders
  - built-in `.icon` (Icon Composer) folder support (2.45.1)
  - several synced-folder bug fixes — [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases)
- 2.44.0 added "basic support" for Xcode 16 synchronized folders (`type: syncedFolder`, `defaultSourceDirectoryType`). 2.43.0 began copying `.appex` into PlugIns by default, which matters for app extensions. — [XcodeGen releases](https://github.com/yonaskolb/XcodeGen/releases)
- No source found saying XcodeGen can emit the new JSON `.xcproj` format; it presumably still writes `project.pbxproj`. — searched; [Tuist/XcodeGen search results](https://github.com/tuist/XcodeProj/releases/tag/9.17.0) mention only Tuist's library.

**Tuist**
- The CLI is still on major version 4. The releases page on 2026-11-07 shows `4.217.0-canary.49` and `4.216.0-rc.2`, and a 4.201.0 canary added release channels (canary/rc/stable). No Tuist 5 was found. — [tuist/tuist releases](https://github.com/tuist/tuist/releases); [newreleases.io](https://newreleases.io/project/github/tuist/tuist/release/4.201.0-canary.19)
- Tuist's XcodeProj library 9.17.0 lists "[Experimental] support Xcode 27.2's JSON project format (project.xcproj)". — [tuist/XcodeProj 9.17.0](https://github.com/tuist/XcodeProj/releases/tag/9.17.0)
- Tuist's 2026 roadmap focuses on going cross-platform (Gradle cache, Linux CLI, flaky-test detection), i.e. team and CI features. — [Tuist community](https://community.tuist.dev/latest?page=1)

**Xcode 27 general changes relevant to build setup** (third-party summary, Sep 15, 2026, updated Oct 26)
- Xcode 27 (27A266a) shipped Sep 14, 2026 and requires Apple silicon. The ld64 linker was removed.
- macOS 27 deployment-target projects no longer build Universal by default.
- `PreviewProvider` and its modifiers are deprecated in favor of the `#Preview` macro.
- `swift test` gained `--maximum-repetitions` and `--repeat-until`.
- Xcode 27.1 shipped Oct 15, 2026; 27.2 RC (27B48) on Oct 19. — [Blake Crosley: Xcode 27 Is Out](https://blakecrosley.com/blog/xcode-27-release). Secondary source; the local machine runs 27.2 build 27B52.

### Inferences
- **Recommendation:** use a native Xcode 27.2 project in JSON format, created with `xcrun xcodeproj init` and edited only through `xcrun xcodeproj`.
  - Put app sources in synchronized folders so adding a Swift file needs no project edit.
  - Put almost all code in local Swift packages, added with `xcrun xcodeproj pkg add` or as a local package reference.
  - The `.xcodeproj` then holds only targets, signing, entitlements and Info.plist keys, so it rarely changes.
  - Add `xcprojformatter` as a pre-commit or verify step.
  - This avoids a third-party generator dependency and reduces pbxproj churn. It also keeps extensions (WidgetKit = `app-extension`), watch targets and iOS targets first-class, since `target add` accepts those product types.
- **XcodeGen** is the best fallback if `xcrun xcodeproj` proves too low-level, for example when manually wiring test hosts and extension embedding is painful.
  - Its declarative `project.yml` is easy for an agent to edit and regenerate, and it supports synced folders and `.appex` embedding.
  - The cost is a Homebrew dependency and pbxproj output (not JSON).
- **Tuist** is aimed at large teams (caching, dependency graph, server features). Its frequent canary cadence and experimental JSON support make it heavier than this single-user app needs.
- **Plain SwiftPM executable bundled into a .app by a script** works for a toy app but poorly fits the "extensions later" requirement. WidgetKit and App Intents extensions, asset-catalog/app-icon compilation and entitlements are Xcode build-system features. This is background knowledge, not sourced in this session; see Gaps.
- Because `xcodeproj` doesn't edit schemes, rely on Xcode's auto-generated schemes (Artem notes `xcodebuild -scheme <name>` works with auto-generated schemes) or commit a shared scheme once.

### Gaps
- Whether XcodeGen has a roadmap for emitting `.xcproj` (JSON) was not found.
- Whether Tuist CLI 4.21x fully supports `.xcproj` is unknown; only the XcodeProj library's experimental support is documented.
- No primary source was fetched on what `swift build` cannot do for SwiftUI apps (asset catalogs/actool, app icons, extension embedding, Info.plist generation). This is well-known practice, but no 2026 source was retrieved.
- The exact JSON5 vs strict-JSON nature of `.xcproj` comes from a secondary source only.

## 2. Building, running, testing and screenshotting from the CLI

### Takeaway
`xcodebuild` with an explicit `-derivedDataPath` builds and tests deterministically; `open` launches the built `.app`. Xcode 27.2 also ships an Xcode MCP bridge (`xcrun mcpbridge`) that includes a RenderPreview tool for SwiftUI previews, and the third-party XcodeBuildMCP adds build-and-run for macOS. Screenshotting a running macOS app from the CLI relies on `screencapture` rather than any simulator tooling.

### Cited Findings
- `xcodebuild -scheme <name> -destination ... build` builds with an auto-generated scheme; `xcodebuild -showBuildSettings` shows resolved settings. — [Artem Novichkov](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents)
- Local check: `xcrun mcpbridge` exists and its help reads "Without a subcommand, acts as a STDIO bridge between MCP (Model Context Protocol) clients and Xcode's MCP tool service". It also has a `run-agent` subcommand ("Launch a coding agent with Xcode-provided configuration").
- Xcode 27.2 release notes: "The RenderPreview MCP tool now returns the list of available render destinations, and lets the caller specify which destination to use for rendering." This means an agent can render SwiftUI previews to images through Xcode's MCP. — [Xcode 27.2 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)
- Xcode's MCP tools can't add packages, link xcconfigs, or edit build phases. — [Artem Novichkov](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents)
- XcodeBuildMCP (third-party) installs with `claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp` and needs Node.js. It includes `build_run_macos` and `get_mac_app_path`. Its screenshot tooling is simulator-focused, and no macOS-window screenshot tool was confirmed. — [chriscalo dev-skills: xcodebuildmcp setup](https://chriscalo.github.io/dev-skills/skills/apple-dev/xcodebuildmcp-setup); [Blake Crosley: Xcode MCP + Claude Code](https://blakecrosley.com/ja/blog/xcode-mcp-claude-code)
- `swift test` in Swift 6.4 / Xcode 27 gained `--maximum-repetitions` and `--repeat-until` plus a failure summary, which is useful for flaky tests in SPM feature packages. — [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release) (secondary)

### Inferences
Suggested CLI loop, using standard tools (not individually sourced here):
- **Build:** `xcodebuild -project Logbook.xcodeproj -scheme Logbook -configuration Debug -destination 'platform=macOS' -derivedDataPath build/DD build`. Pipe through `xcbeautify` if installed, or use `-quiet`.
- **App path:** `build/DD/Build/Products/Debug/Logbook.app`.
- **Run:** `open -n build/DD/Build/Products/Debug/Logbook.app`, or run the binary in `Contents/MacOS/` directly to see stdout and logs.
- **Quit:** `osascript -e 'quit app "Logbook"'` or `pkill -x Logbook`.
- **Screenshot:** `screencapture -l <windowID> out.png` (a window ID from a small Swift/CGWindowList helper) or `screencapture -x out.png`. Needs Screen Recording permission for the terminal app.
- **Test:** `xcodebuild test -scheme Logbook -destination 'platform=macOS' -resultBundlePath build/Tests.xcresult`. For pure feature packages, `swift test --package-path Packages/LogbookCore` is faster and skips Xcode.
- Keeping most logic in SPM packages means the agent runs `swift build` and `swift test` for most changes and invokes `xcodebuild` only for app or extension integration.
- Prefer committing a small `Makefile` or `scripts/` (build, run, test, screenshot, install) so the agent uses stable commands instead of re-deriving flags.

### Gaps
- No primary source fetched for `xcodebuild` flag reference (Apple's `man xcodebuild` is authoritative; not retrieved).
- No confirmation of which Xcode MCP tools exist beyond RenderPreview, or whether they work without the Xcode GUI running.
- macOS window screenshot from MCP tools: unconfirmed.

## 3. Signing without a paid Apple Developer Program membership

### Takeaway
macOS does not require a provisioning profile to run third-party code. A Mac app that uses no restricted entitlements needs no profile at all. Ad-hoc signing ("Sign to Run Locally", `codesign -s -`) is enough for a private logbook app, and the iOS-style 7-day free-profile expiry does not apply in that case. The limits come with capabilities:
- iCloud/CloudKit and Push are not available to free Personal Teams.
- App Groups are an "unrestricted" entitlement on macOS. But since macOS 15, an ad-hoc signed app touching a group container gets a persistent privacy prompt, and Apple DTS says a profile can't fix that for ad-hoc apps. This matters for future widgets, which share data with the app through an App Group.
- Locally built apps are not quarantined, so Gatekeeper does not interfere.

### Cited Findings
- TN3125: "Unlike Apple's other platforms, macOS doesn't require a provisioning profile to run third-party code." Also: "A Mac app that uses no restricted entitlements doesn't need a provisioning profile." — [TN3125: Inside Code Signing: Provisioning Profiles](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- TN3125: macOS unrestricted entitlements (no profile needed) include `com.apple.security.get-task-allow`, `com.apple.security.application-groups`, App Sandbox entitlements, and Hardened Runtime entitlements. Restricted entitlements such as `keychain-access-groups` "must be authorized by a provisioning profile." — [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- TN3125: profile validity "varies by profile type, but it's typically not more than a year"; Developer ID profiles expire far in the future. On macOS the profile is embedded at `MyApp.app/Contents/embedded.provisionprofile`. — [TN3125](https://developer.apple.com/documentation/technotes/tn3125-inside-code-signing-provisioning-profiles)
- Free Personal Team provisioning profiles expire after about 7 days, versus about a year for paid teams. This is reported in iOS-device contexts. — [Apple Developer Forums 69248](https://developer.apple.com/forums/thread/69248); [Apple Developer Forums 712540](https://developer.apple.com/forums/thread/712540)
- Apple forum answer (DTS): for your own use on your own machine you can "sign to run locally" and make up a bundle identifier. Restricted entitlements require a paid account. Personal Team works for building and running locally on the Mac with any Apple ID. — [Apple Developer Forums 733928](https://developer.apple.com/forums/thread/733928); [Apple Developer Forums 761325](https://developer.apple.com/forums/thread/761325)
- Apple DTS: personal development teams do not support the Push Notifications and iCloud capabilities. — [Apple Developer Forums (search summary, thread 733928 / 749011)](https://developer.apple.com/forums/thread/749011). A secondary guide claims App Groups, Background Modes, HealthKit, HomeKit, Keychain Sharing and Maps work on a free account, but that guide is iOS-focused. — [trianglemesh blog, 2024](https://trianglemesh.github.io/posts/2024/10/27/how-to-use-a-free-apple-developer-account-for-local-testing) (older, unverified for macOS 27)
- macOS 15+ App Groups and ad-hoc signing (Apple Developer Forums thread 767604, Oct–Nov 2024):
  - Ad-hoc signed apps that use an App Group get a "persistent file access prompt" on each launch.
  - The OP's logs showed `Unsatisfied entitlements: com.apple.security.application-groups`.
  - Apple DTS (Quinn) said a provisioning profile cannot authorize App Groups for ad-hoc signed apps, because group container protection exists to stop "random" apps from reading containers. — [Apple Developer Forums 767604](https://developer.apple.com/forums/thread/767604)
- Apple silicon requires all code to be at least ad-hoc signed. Xcode's "Sign to Run Locally" is ad-hoc signing. Quinn recommends `codesign -s - -vvvv --options=runtime` for ad-hoc signing. — [Apple Developer Forums 651730](https://developer.apple.com/forums/thread/651730); [Apple Developer Forums 740680](https://developer.apple.com/forums/thread/740680)
- Gatekeeper typically only checks quarantined apps. Per Quinn, apps you compile yourself don't have the quarantine attribute when run on the same machine. Quarantined ad-hoc builds (e.g. downloaded) are rejected as unnotarized. — [Apple Developer Forums 740680](https://developer.apple.com/forums/thread/740680); [git-nav PR #44](https://github.com/sangonz193/git-nav/pull/44)

### Inferences
- **Signing for this app:** `CODE_SIGN_IDENTITY = "-"` (Sign to Run Locally), `CODE_SIGN_STYLE = Manual` or no team, `DEVELOPMENT_TEAM` empty.
  - The app runs indefinitely, with no 7-day expiry, because no profile is involved.
  - Keep `ENABLE_HARDENED_RUNTIME` optional; it's harmless locally.
  - App Sandbox is optional for a non-distributed app. Keeping it off simplifies file access to the logbook data folder, while keeping it on is the safer default if the data folder lives in the container.
- **7-day question answered for macOS:** the 7-day expiry is a property of free-team provisioning profiles. A macOS app with no restricted entitlements has no profile, so the expiry doesn't apply. If you sign with a Personal Team identity (Apple Development cert) without restricted entitlements, only the certificate's validity matters (TN3125's example cert is valid one year). Signing with a Personal Team cert also gives the app a stable Team ID.
- **Capabilities needing a paid account:** CloudKit/iCloud sync, Push Notifications, and in general any restricted entitlement (keychain access groups/sharing, Associated Domains, etc.). This rules out SwiftData+CloudKit sync to an iOS companion without paying $99/yr. Local SQLite or SwiftData on the Mac works fine.
- **Widgets/App Groups risk:** a WidgetKit extension typically reads data from a shared App Group container. With ad-hoc signing on macOS 15+, expect a privacy prompt on group-container access. A plausible mitigation is signing with a free Personal Team (Apple Development identity) and using a Team-ID-prefixed group (`<TEAMID>.com.example.logbook`). Unverified for Personal Teams on macOS 27; flagged as a gap.
- **iOS/watchOS companion:** possible on a free account, but the device install expires every 7 days and iCloud sync is unavailable. This is a strong argument for buying the paid membership if a companion becomes real.

### Gaps
- No primary 2026 source confirms whether a free Personal Team on macOS can register a Team-ID-prefixed App Group without a prompt, or whether WidgetKit extensions load and show when the host app is ad-hoc signed.
- Apple's "Supported capabilities" table for free vs paid was not fetched. The help.apple.com page is referenced by TN3125 but not retrieved.
- Whether ad-hoc signed apps can use App Intents/Shortcuts reliably is not covered. App Intents uses no restricted entitlement, so it likely works, but this is unverified.

## 4. Swift 6 strict concurrency for SwiftUI app code

### Takeaway
Use Swift 6 language mode with "Approachable Concurrency" and Default Actor Isolation = MainActor for the app target and UI feature modules. Keep `nonisolated` default in pure model/persistence/import packages that must run off the main actor. New Xcode 26+ app projects enable both by default; projects created via `xcrun xcodeproj init` don't seed settings, so set them explicitly.

### Cited Findings
- **Xcode build settings**, in Swift Compiler, Concurrency:
  - "Approachable Concurrency" (Yes/No)
  - "Default Actor Isolation" (nonisolated / MainActor)
  - Strict Concurrency Checking: Complete
  - Separate toggles for "Infer Isolated Conformances" (SE-0470) and "nonisolated(nonsending) By Default" (SE-0461) — [Use Your Loaf, Jul 21, 2025](https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/) (2025 source; still applicable to Swift 6.4 per search results)
- **Package.swift** (tools version ≥ 6.2), per target:
  - `swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault"), .enableUpcomingFeature("InferIsolatedConformances")]`
  - Default isolation is SE-0466. — [Use Your Loaf](https://useyourloaf.com/blog/approachable-concurrency-in-swift-packages/)
- New projects created in Xcode 26 enable MainActor default isolation and approachable concurrency by default; existing projects opt in per target. — [Michael Long, Medium](https://michaellong.medium.com/swift-6-2-approachable-concurrency-default-actor-isolation-4e537ab21233)
- Under approachable concurrency, nonisolated async functions inherit the caller's isolation (SE-0461) instead of hopping to the global executor as in Swift 6.0. Michael Long's July 2025 Substack argues this interacts confusingly with MainActor default isolation. Treat that as an opinion piece; other sources present the settings as complementary. — [Michael Long Substack](https://hmlong.substack.com/p/swift-62-approachable-concurrency)
- Xcode 27 introduced a source break (SE-0508) around computed properties with `init` accessors, and `@State` macro initializer-ordering errors. — [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release) (secondary)

### Inferences
- The raw build-setting keys are commonly `SWIFT_VERSION = 6.0`, `SWIFT_APPROACHABLE_CONCURRENCY = YES`, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, `SWIFT_STRICT_CONCURRENCY = complete`. Verify on this machine with `xcodebuild -showBuildSettings` from a template project before writing them via `xcrun xcodeproj setting set`, since no source here confirmed the exact key names.
- Pattern for a logbook app:
  - UI packages: MainActor default.
  - `LogbookCore` (models, storage): nonisolated default, with `Sendable` value types (structs) and an `actor`, or a `@ModelActor` for SwiftData, for persistence.
  - `ImportCLI`: nonisolated.
  - This keeps heavy parsing off the main actor without sprinkling annotations.
- Put the concurrency rules in CLAUDE.md, e.g. "value types are Sendable; don't add @unchecked Sendable; prefer `@concurrent` for explicitly background functions". This stops agents from silencing errors with `nonisolated(unsafe)`.

### Gaps
- Swift 6.3/6.4-specific concurrency changes (e.g., whether any upcoming features became default in Swift 7 mode, or changes to `@concurrent`) were not researched. No Swift Forums primary source was fetched.
- Exact build setting identifiers are unconfirmed (see Inferences).

## 5. Testing: Swift Testing vs XCTest, snapshot tests, CLI

### Takeaway
Use Swift Testing (`import Testing`, `@Test`, `#expect`) for all new unit and integration tests in SPM packages, run via `swift test` or `xcodebuild test`. Keep XCTest only for UI tests (XCUIAutomation). pointfreeco/swift-snapshot-testing (1.19.x) supports Swift Testing and works for SwiftUI views on macOS via `NSHostingView`. Pin it and record snapshots on one machine, since rendering differs across OS versions.

### Cited Findings
- swift-snapshot-testing latest release is listed as 1.19.2 (2026-03-30), supporting both XCTest and Swift Testing. — [dev.co listing](https://dev.co/testing/open-source/swift-snapshot-testing) (third-party; verify on GitHub)
- Swift Testing support was added in 1.17.0, initially labeled beta. — [Point-Free blog #146](https://pointfree.co/blog/posts/146-swift-testing-support-for-snapshottesting)
- A fork (choule99) has a 2.0.0 requiring Swift tools 6.3 and macOS 13. It is not upstream, so don't confuse it with pointfreeco. — [choule99 fork releases](https://github.com/choule99/swift-snapshot-testing/releases)
- `swift test` in the Swift 6.4 toolchain adds `--maximum-repetitions` / `--repeat-until` and a failure summary. — [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release) (secondary)
- Xcode 27.2 RenderPreview MCP tool can render previews to a chosen destination, an alternative visual check for agents. — [Xcode 27.2 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes)

### Inferences
- **Test pyramid:**
  - many Swift Testing unit tests in `LogbookCore` (parsing, model rules, persistence round-trips with an in-memory store)
  - a modest number of snapshot tests for key views at fixed sizes, light and dark
  - one or two XCUITest smoke tests, if any
- Snapshot tests are brittle across macOS/Xcode upgrades. Set a precision tolerance (`precision: 0.99, perceptualPrecision: 0.98`) and re-record deliberately after OS updates. Even so, they are valuable for an agent, which can't otherwise "see" regressions.
- The markdown importer is ideal for table-driven tests: `@Test(arguments:)` over fixture snippets from the real log.

### Gaps
- No upstream GitHub release page for swift-snapshot-testing was fetched to confirm 1.19.2 or any later release, or macOS 27 rendering issues.
- No source checked on Swift Testing's 2026 feature additions (e.g., exit tests, attachments) in Swift 6.4.

## 6. Modular architecture and conventions that make AI assistants effective

### Takeaway
Use a thin app target plus local Swift packages:
- `LogbookCore`: models, storage, import parsing
- `LogbookUI` or per-feature packages, each with `#Preview`s
- `LogbookWidgets` (later), sharing Core
- an `ImportTool` executable

Document the build/run/test commands and the "never hand-edit project files; use `xcrun xcodeproj`" rule in CLAUDE.md (or AGENTS.md symlinked). Agents work best with small files, stable scripts, and fast `swift test` feedback.

### Cited Findings
- Put project-tool instructions in AGENTS.md or CLAUDE.md because "agents won't discover the tool on their own." Rules: inspect before modifying, create files on disk for synced groups, run the `xcprojformatter` check after every change. — [Artem Novichkov](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents)
- `xcrun xcodeproj pkg` manages Swift package dependencies, including adding and linking products to targets. — [Artem Novichkov](https://artemnovichkov.com/blog/xcode-projects-for-the-command-line-and-coding-agents); local check of `xcodeproj --help`
- `PreviewProvider` is deprecated in Xcode 27; use `#Preview`. — [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release) (secondary)
- Xcode 27's built-in agents use editable Markdown plans and include Gemini as a model option, so Xcode itself now expects agent workflows. — [Blake Crosley](https://blakecrosley.com/blog/xcode-27-release) (secondary)

### Inferences
- Suggested layout:
  ```
  Logbook/
    Logbook.xcodeproj/        (project.xcproj, JSON; edited only via xcrun xcodeproj)
    App/                      (synced folder: LogbookApp.swift, Assets.xcassets, Logbook.entitlements)
    Packages/
      LogbookCore/            (Package.swift; Sources/LogbookCore, Tests/LogbookCoreTests; nonisolated default)
      LogbookFeatures/        (one library product per feature, MainActor default; previews; snapshot tests)
      LogbookImport/          (executable target `logbook-import` depending on LogbookCore)
    scripts/ (build.sh, run.sh, test.sh, install.sh, screenshot.sh) or Makefile
    CLAUDE.md (+ AGENTS.md symlink)
  ```
  A single multi-product local package is simpler than many packages. Split later.
- Later extensions:
  - WidgetKit: `xcrun xcodeproj target add LogbookWidgets --product-type app-extension`, then embed into the app and link LogbookCore.
  - Menu bar: just a `MenuBarExtra` scene in the main app; no extension needed.
  - App Intents: can live in the app target or a package (`AppIntents` in a package is supported in recent Xcodes; verify).
  - iOS companion: another `application` target sharing the packages.
- CLAUDE.md should cover:
  - exact build/test/run commands
  - the module map and dependency direction (Features → Core, never the reverse)
  - the concurrency policy
  - file-size guidance (~200–300 lines)
  - "add a `#Preview` for each new view"
  - "add a test with each bug fix"
  - "never edit project.xcproj by hand; run `xcrun xcprojformatter` check"
  - the signing setup (ad-hoc; don't add iCloud/push entitlements)

### Gaps
- No authoritative source found on Anthropic's or Apple's recommended CLAUDE.md/AGENTS.md conventions for Swift specifically. The recommendations above are practice-based.
- Not verified whether App Intents defined in a Swift package are discovered by the system on macOS 27 when the app is ad-hoc signed.

## 7. Secondary language for the one-time import of a messy markdown log

### Takeaway
Do it in Swift as a small executable target (`logbook-import`) that depends on the same `LogbookCore` model and persistence code the app uses. The import then writes directly into the real store format with the real validation, and can be unit-tested with Swift Testing. Python would only pay off for exploratory regex work on the messy file, and duplicating the model in Python risks drift.

### Cited Findings
- `xcodeproj target add` supports `tool` (command-line) product types, and SPM packages support executable targets, so a CLI sharing model code fits either way. — local check of `xcrun xcodeproj target add --help`
- Apple's `swift-markdown` (cmark-gfm-based) package exists for Swift-native markdown parsing. — no source fetched in this session; see Gaps.

### Inferences
- The import is one-time but likely iterative: parse, inspect failures, adjust, re-run. An `ArgumentParser`-based `logbook-import --dry-run --report issues.json` loop works well for an agent. Swift regex literals and `Regex` builders handle line-oriented log formats well.
- Python is acceptable as a throwaway pre-cleaner (normalize dates, split entries into JSON) if the user already knows it. The final write should still go through Swift/Core to avoid two schemas. Writing an intermediate JSON from Python and importing it via a Swift `Codable` path is a reasonable hybrid.
- Keep the original markdown file untouched and checked in, or backed up. Make the importer idempotent (stable IDs from date plus content hash) so re-runs don't duplicate entries.

### Gaps
- swift-markdown's current version and maintenance status were not checked.
- No benchmark or source comparing Swift vs Python ergonomics for this task; the recommendation is judgment.

## 8. Distribution to self: install to /Applications, launch at login

### Takeaway
Build Release, copy the `.app` into `/Applications` (`ditto` or `cp -R`), and launch from there. Locally built apps aren't quarantined, so Gatekeeper doesn't block them. For auto-launch, use `SMAppService.mainApp.register()` (macOS 13+) from a settings toggle. Ad-hoc re-signing on every rebuild can confuse Background Task Management, so always install to one fixed location. Sparkle is unnecessary.

### Cited Findings
- `SMAppService` (macOS 13+) registers login items, launch agents and daemons. `mainApp` is "An app service object that corresponds to the main application as a login item". `register()` "Registers the service so it can begin launching subject to user approval". `openSystemSettingsLoginItems()` opens the Login Items panel, and `status` reports registration and authorization state. — [Apple: SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- `SMAppService.mainApp` can only register from a `.app` bundle. — [rightkit-tauri-shell login_item.rs](https://docs.rs/crate/rightkit-tauri-shell/0.4.0/source/src/login_item.rs)
- Developers report login items showing "registered" but never launching (launchd status 78). Fixes involved:
  - removing stale copies from other builds
  - inspecting `sfltool dumpbtm`
  - Quinn's advice to test with a single copy of the app in /Applications
  - A disabled-by-user item reports `.notFound` rather than `.notRegistered`. — [Apple Developer Forums 726826](https://developer.apple.com/forums/thread/726826); [Apple Developer Forums 727785](https://developer.apple.com/forums/thread/727785); [Apple Developer Forums 730551](https://developer.apple.com/forums/thread/730551); [Apple Developer Forums 777520](https://developer.apple.com/forums/thread/777520)
- Self-compiled apps lack the quarantine attribute, so Gatekeeper typically doesn't assess them. — [Apple Developer Forums 740680](https://developer.apple.com/forums/thread/740680)

### Inferences
- `scripts/install.sh` should do the following:
  - run `xcodebuild -configuration Release … -derivedDataPath build/DD build`
  - quit the running app with `osascript -e 'quit app "Logbook"'`
  - run `ditto build/DD/Build/Products/Release/Logbook.app /Applications/Logbook.app`
  - run `open /Applications/Logbook.app`
  - Always installing to the same path keeps a single BTM record.
- Ad-hoc signatures have no stable Team ID, and the designated requirement is the cdhash, which changes every build. Background Task Management may treat each rebuild as a new app; the login-item toggle may need re-approval or show duplicates. Signing with a free Personal Team identity gives a stable identity and may reduce this. This is unverified (see Gaps) and also bears on TCC permission prompts (e.g., Files & Folders access) re-appearing after each rebuild.
- A menu-bar presence is a `MenuBarExtra` scene in the main app, not a separate helper. Combined with `SMAppService.mainApp`, this gives "always available" without a helper login item.
- Data should live in `~/Library/Application Support/<bundle id>/`, or in a user-chosen folder in iCloud Drive via a plain file path. A plain file path is not CloudKit, so it needs no entitlement when unsandboxed. The data store then survives app reinstalls.

### Gaps
- No primary source confirms how `SMAppService.mainApp` and TCC behave across rebuilds of an ad-hoc signed app (cdhash changes). This is worth a quick empirical test on the user's machine.
- Not checked whether iCloud Drive file-path storage (non-CloudKit) behaves well for SQLite/SwiftData stores. SQLite on synced folders is commonly discouraged; this is an adjacent researcher's topic.
