# Product & UX Patterns for a Premium Personal Logbook (macOS), as of Nov 2026

Scope note: Research covered Apple Health/Watch Sleep, Apple HIG (Charting data), Oura (Oct 2024 / Oct 2025 redesigns), Whoop, Gyroscope, Exist.io, Bearable vs Daylio, MacroFactor (timeline logger, FLSI speed study, AI Describe), Timing, Rize, Structured, Streaks, Things 3 Quick Entry, Fantastical, and a set of iOS caffeine half-life trackers. Many sources are vendor-authored (changelogs, blogs, App Store listings) and flagged as such. Toggl Track, Session/Flow, Day One, Cronometer/Lose It/MyFitnessPal UI specifics were not researched in depth (see Gaps).

User context for the reader: one user, macOS, logs work blocks, foods (kcal/protein/caffeine), calories burnt/steps/net, bathroom blocks, sleep blocks; currently uses shorthand in Apple Notes like `0945 - 1045 [1h] > study` and `pulao 250g - 408 / 8 / 0`.

---

## 1. Which metrics/KPIs do best-in-class apps surface daily / weekly / monthly, and which are useful vs vanity?

### Takeaway
The leading apps converge on a three-layer cadence: (a) a few daily "headline" scores or totals at the top, (b) a "vitals vs personal baseline" layer, and (c) slow-moving long-term trends plus periodic (weekly/quarterly/yearly) reports. The useful metrics are those compared against the user's own baseline or target (deltas, ranges, adherence); raw counts with no reference point and streak-maximising mechanics carry the most vanity risk.

### Cited Findings
- Oura's redesign collapsed five tabs (Home, Readiness, Sleep, Activity, Resilience) into three: **Today** (daily companion), **Vitals** (snapshot), **My Health** (long-term) — [Oura blog, Oct 3 2024](https://ouraring.com/blog/new-oura-app-experience/)
- Oura Today: Sleep/Readiness/Activity scores as shortcuts at the top, a time-of-day-dependent "daily highlight" insight, a **Timeline** of the day where you add tags/activities, and **Discoveries** showing how tagged habits correlate with health changes — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- Oura Vitals shows each metric with **the user's personal baseline range** "so you can see when values shift"; down-arrow reveals top contributors, side-arrow opens full detail, swipe moves between metrics — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- Oura My Health holds slow-moving metrics (Cardiovascular Age, Stress Resilience), long-term trend graphs, and **weekly, quarterly and yearly reports** — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- A further Oura redesign (Oct 2025) focused Today on "One Big Thing," overhauled Vitals with colour-coded sections anchored in personalised baselines, and changed the overview window from 1 month to **12 months** — [9to5Google, Oct 2025](https://9to5google.com/2025/10/20/oura-app-redesign/); [Droid Life, Nov 2025](https://www.droid-life.com/2025/11/13/oura-ring-app-gets-big-facelift-ai-gets-more-access-to-your-metrics/)
- Whoop: three dials (Sleep, Recovery, Strain) at the top of Home, each with a deep-dive page; reordered to match how people use the app across a day; morning recommendation based on Recovery and later-day sleep recommendation based on accrued strain (2023-era redesign) — [Whoop, "The all new Whoop home screen"](https://www.whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/); [the5krunner review, Mar 2023](https://the5krunner.com/2023/03/28/new-whoop-home-screen-looks-pretty-but-is-it-as-intuitive/) (reviewer questioned whether it is as intuitive as it looks)
- Whoop lets users **hide** Sleep and Recovery metrics from Home temporarily — [Whoop What's New](https://ww2.whoop.com/thelocker/nouvel-ecran-daccueil-whoop/)
- Apple Health Summary = **Pinned** (daily progress in user-chosen categories, editable via "Edit"), then **Trends** (whether a metric is moving over several weeks, with optional notifications), then **Highlights** (broader view over time, e.g. average steps) — [Apple Support](https://support.apple.com/en-ie/HT203037); [iMore](https://www.imore.com/health-ios); [MacRumors guide](https://macrumors.com/guide/health)
- Apple Activity Trends (introduced iOS 13) compare recent performance against a longer baseline with up/down arrows per metric (older-version pattern; details not re-verified for iOS 26) — [Macworld](https://www.macworld.com/article/233093/ios-13-and-apple-watch-activity-trends-give-you-the-big-picture.html)
- Apple Sleep Score (watchOS 26 / iOS 26, Sept 2025): 0–100 each morning; tapping "i" breaks it into components such as **duration, bedtime (consistency) and interruptions**; watchOS 26.2 relabelled the top band from "Excellent" to "Very High" — [AppleInsider](https://appleinsider.com/articles/25/09/12/how-sleep-score-works-on-apple-watch-with-watchos-26); [iPhoneSoft, Nov 2025](https://iphonesoft.fr/2025/11/05/apple-jour-plages-scores-sommeil-ios-watchos-26-2)
- Rize's **Focus Quality Score** is built from context switching, focus-session length and daily focus time (draws on 20+ attributes); reviewers describe it as 0–100 under Productivity > Trends; there is a weekly productivity assessment — [Rize blog](https://rize.io/blog/releasing-the-new-weekly-productivity-assessment); [Dhruvir Zala review 2026](https://dhruvirzala.com/rize-review/)
- MacroFactor's week banner shows intake vs calorie target per day, and target circles **never turn orange or red** ("adherence-neutral" design) — [MacroFactor timeline logger](https://macrofactor.com/timeline-based-food-logger/)
- Exist.io: 2019 user survey found mood tracking and custom tags each rated most useful (76%); correlations were divisive — 41% rated 4–5, 41% rated 3/5, with complaints of "obvious correlations" — [Exist blog / survey coverage](https://exist.io/blog/post/use-cases/) (older data, 2019–2020)
- Streaks deliberately limited users to six goals originally (now twelve) to keep habit tracking uncluttered — [MacStories Streaks 3 review](https://www.macstories.net/?p=49979); [App Store](https://apps.apple.com/us/app/streaks/id963034692)

### Inferences
- For this user, high-value KPIs map cleanly onto the "baseline" pattern: total work hours vs 7-day/28-day average; net calories vs target; protein vs target (adherence %); caffeine total and "caffeine at bedtime"; sleep duration + **sleep midpoint/bedtime consistency** (Apple's Sleep Score explicitly rewards bedtime consistency); bathroom count/total minutes vs personal baseline (anomaly detection is the useful signal, not the raw number).
- Rolling averages (7d/28d) and "vs your baseline range" bands are more decision-useful than single-day scores; composite scores (Readiness-style) only make sense if components are transparent (Apple and Oura both expose component breakdowns).
- Vanity risk: unbounded streak counters, badges, and red/green moral colouring of food intake (MacroFactor's explicit counter-pattern). Personal records are useful for work (longest deep-work block, most focused week) but less so for food.
- Cadence model to borrow: Today (live), Week (adherence + averages), Month/Year (trend lines, heatmaps, reports).

### Gaps
- Could not verify current (2026) Apple Health Trends algorithm windows (e.g. 90-day vs 365-day comparison) — older Macworld source only.
- No independent evidence quantifying which KPIs drive retention; usefulness judgments are inferred from design choices and the Exist survey.
- Whoop's 2025–2026 Home changes not found; only 2023-era material.

---

## 2. Fast-entry patterns (shorthand parsing, recents/favourites, templates, command palette, menu bar, keyboard-first, timers vs retroactive)

### Takeaway
Speed comes from (1) a global, always-available capture surface (Things Quick Entry style), (2) a forgiving natural-language/shorthand parser with live visual feedback (Fantastical style), (3) reuse of last-used quantities/servings and copy/paste of whole days (MacroFactor), and (4) "quick add" of raw numbers when no food item is warranted. Measured speed differences between nutrition apps are large (MacroFactor 24 actions vs 30–35 for the next-best across four standard tasks).

### Cited Findings
- **Things 3 Quick Entry**: system-wide shortcut Ctrl+Space; "Quick Entry with Autofill" (Ctrl+Opt+Space) captures the link to the current website/email/file into the new to-do; shortcuts configurable in Settings; Autofill needs a helper app because of macOS sandboxing; system-wide quick entry dates to Things 1.2 (2009) — [Cultured Code support](https://culturedcode.com/things/support/articles/2249437/); [Things Helper](https://culturedcode.com/things/help/things-sandboxing-helper-things3); [Cultured Code blog 2009](https://culturedcode.com/things/blog/2009/08/things-1-2-fasten-your-keyboards/)
- **Fantastical** natural-language input: a near-sentence ("meet X at location between 2 and 3 tomorrow") is parsed into title, date, location, start/end; parsed tokens animate into their corresponding fields **as you type**; `/calendarname` selects a calendar — [MacStories preview](https://www.macstories.net/news/preview-fantastical-upcoming-calendar-app-for-mac/); [Macworld Fantastical 2 review](https://www.macworld.com/article/225186/review-fantastical-2-ups-the-ante-for-events-in-os-x.html). Reviewers found the vocabulary large but brittle (e.g. "every night at 8 pm" worked, "nightly forever" failed) — same sources (older versions; current parser not documented).
- **MacroFactor Food Logging Speed Index (FLSI), Oct 2025**: counts discrete actions for four tasks (search-log 2 foods with non-default serving; multi-add 2 foods; barcode scan; quick-add calories). Totals: MacroFactor speed mode 24 (search 10 / multi-add 6 / scan 5 / quick-add 3); MyNetDiary 30; Lose It 32; Fitatu 35; Nutracheck 35. MyFitnessPal: search 15, scan 7, quick-add 5, multi-add "weak". Cronometer: scan 7, quick-add 7, search/multi-add "weak" — [MacroFactor FLSI 2025](https://macrofactor.com/fastest-food-logger-2025/) (vendor-run benchmark)
- FLSI speed drivers: reusing a food's **last-logged serving and quantity**; quick-add of calories was the fastest method overall; "speed mode" returns to logging after each food vs "context mode" which shows the whole meal plate first (28 actions) — [MacroFactor FLSI 2025](https://macrofactor.com/fastest-food-logger-2025/)
- MacroFactor Quick Add: enter energy, protein, fat, carbs, alcohol, optional name — for foods not eaten often — [MacroFactor help](https://help.macrofactorapp.com/en/articles/215-how-to-log-food-in-macrofactor)
- MacroFactor AI Describe/photo: AI searches its database and **populates a Plate** that the user edits before committing — [MacroFactor 5.0.0 release notes](https://macrofactor.com/version-5-0-0/); [MacroFactor AI food logging](https://macrofactor.com/ai-food-logging/)
- MacroFactor timeline logger: auto-timestamps to the minute and places food in the current hour; "Add" next to any hour logs ahead; Tap-to-Select across days; Copy/Move/Remove; in Copy mode every hour's Add becomes Paste; Multi-Paste to several days; "To Today"/"To Tomorrow"; batch-edit timestamps; custom numeric keyboard with serving quantity preselected; calendar shortcuts to today / yesterday / 7 days ago; create a recipe directly from selected timeline foods — [MacroFactor timeline logger](https://macrofactor.com/timeline-based-food-logger/) (Timeline 2.0; article updated Sept 2024)
- Exist: 69% of custom-tag users add tags **once at end of day** (retroactive batch entry dominates) — [Exist use-cases post](https://exist.io/blog/post/use-cases/) (2020)
- Whoop Journal is reachable from a morning prompt, a Home card, or a global (+) action; 300+ loggable behaviours — [Whoop Journal](https://www.whoop.com/au/it/thelocker/the-whoop-journal/)
- Rize focus sessions default to 45 min, extendable/endable from the timer; breaks can **auto-start on idle detection**; after a session you rate it and see context switches/interrupting apps — [Rize changelog](https://rize.io/changelog/the-rize-session-timer); [Rize docs](https://docs.rize.io/sessions/overview)
- Timing (Mac) records app/website/document usage automatically so manual start/stop isn't needed; vendor lists AI summaries, idle tracking, Screen Time import — [Timing blog (vendor)](https://timingapp.com/blog/mac-time-tracking-apps/)

### Inferences
- The user's existing Notes shorthand is effectively a DSL and should be the **primary input grammar**: a single global-hotkey field (Things-style) that accepts `0945-1045 study`, `pulao 250g`, `poop 1210 8m`, `sleep 0500-1300`, with Fantastical-style live token highlighting/preview of parsed fields before commit, and a Plate-style confirm step (MacroFactor) only when ambiguous.
- Food shorthand `pulao 250g - 408 / 8 / 0` maps to MacroFactor's two paths: when macros are typed explicitly, treat as Quick Add and offer "save as food"; when only name+grams, look up the library and scale by grams (remembering last quantity).
- Support both live timers (start/stop for work and bathroom) and retroactive ranges; evidence (Exist 69%) suggests end-of-day batch entry is common, so a fast "review the day" bulk-edit surface matters as much as live capture.
- Command palette (⌘K) + menu-bar extra with a running timer would combine Things' global capture and Rize/Timing session UX on macOS.
- Copy-yesterday / multi-paste is high leverage for repetitive meals and routine work blocks.

### Gaps
- Toggl Track's timer/tag/"continue previous entry" patterns and Session/Flow pomodoro menu-bar UX were not researched (tool budget).
- No current documentation of Fantastical's parser (rule vs ML) or of MacroFactor's recent/favourites list behaviour (FLSI explicitly excluded recents/favourites/copy-meal/AI describe from scoring).

---

## 3. Visualising time blocks across a day and across weeks

### Takeaway
Two dominant day patterns: a vertical **hour-by-hour timeline** (Structured, MacroFactor's food timeline, Oura Today timeline, Gyroscope Places timeline) and **staged horizontal bands** (Apple sleep-stages chart). Multi-day views rely on stacked bars, consistency of start/end windows, and long-range (12-month) trends. Timelines break down when many short blocks crowd a column — density controls are essential.

### Cited Findings
- Structured is a time-blocking planner presenting "a clean visual timeline of your entire day" on Mac/iOS/iPad/Watch; 2026 Apple Design Awards finalist (Inclusivity) — [Makerstack review 2026](https://makerstack.co/reviews/structured-review/); [Structured](https://structured.app)
- Critique: on busy days "stacking a dozen fifteen-minute tasks" compresses the column into "an unreadable ribbon of colour"; no monthly view — [Makerstack review 2026](https://makerstack.co/reviews/structured-review/); [coolcuration review, Aug 2026](https://coolcuration.com/structured-app-review-uk)
- MacroFactor timeline density controls: spacious vs dense view, **Hide Empty Hours**, collapse each hour's items into an icon row, toggle per-hour macro summaries, left/right alignment, show/hide minute timestamps — [MacroFactor timeline logger](https://macrofactor.com/timeline-based-food-logger/)
- MacroFactor shows **per-hour macro summaries above each hour** (aggregation embedded in timeline) — same source
- Oura Today includes a Timeline showing how the day progressed with user-added tags/activities — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- Gyroscope Daily Report: day overview, Places timeline, fullscreen map, food photos, daily goals, with day-to-day navigation at top and larger buttons to flip days — [Gyroscope v3.36 changelog](https://about.gyrosco.pe/changelog/v3-series/v336-update); [Gyroscope Daily Report guide](https://about.gyrosco.pe/guides/daily-report)
- Apple Sleep: a sleep-stages chart appears on waking; full analysis on scroll; Sleep Score credits bedtime consistency — [AppleInsider](https://appleinsider.com/articles/25/09/12/how-sleep-score-works-on-apple-watch-with-watchos-26)
- Oura moved its overview window from 1 month to 12 months (Oct 2025) — [9to5Google](https://9to5google.com/2025/10/20/oura-app-redesign/)
- Apple HIG: when several charts show the same dataset, keep the same chart type, colours, annotations and layout (e.g. Health Trends small charts expand into same-style full charts) — [Apple HIG, Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)

### Inferences
- Day view: a single 24-hour vertical (or horizontal) track with lanes per category (sleep, work, bathroom, meals as point markers) avoids Structured's ribbon problem; sleep spanning midnight (0500–1300 or 2300–0700) needs a configurable day boundary (e.g. day starts at 04:00).
- Week/month: Apple-sleep-style **range bars** (start→end per day) for sleep and work make consistency visible; stacked daily bars for work hours by category; a GitHub-style calendar heatmap for work hours or adherence is a good year view (not sourced here—see Gaps).
- A 24h radial clock is novel; per HIG, novel charts need onboarding (Activity rings animate each ring at first pairing) — use sparingly.

### Gaps
- Did not retrieve a primary description of Apple Health's sleep range chart (week view with bedtime/wake bars) or Timing's Mac timeline view; Toggl's calendar view and Daylio's "Year in Pixels" were not verified from primary sources (only an AI-generated audit mentioned Year in Pixels).
- No sourced evidence on heatmap effectiveness for personal logs.

---

## 4. Nutrition logging UX (food library, servings/multipliers, caffeine half-life, protein targets)

### Takeaway
Best-in-class nutrition logging is timeline-based rather than meal-bucket-based, remembers servings, supports raw-number quick add, and stays adherence-neutral. Caffeine is best modelled as a decaying concentration curve with a user-adjustable half-life and a "level at bedtime" projection — a pattern now common in dedicated iOS caffeine apps.

### Cited Findings
- MacroFactor places foods on a time-of-day timeline **instead of Breakfast/Lunch/Dinner buckets** — [MacroFactor timeline logger](https://macrofactor.com/timeline-based-food-logger/)
- Five logging methods in MacroFactor: AI Describe, barcode/label scan, search, Quick Add, custom foods/recipes — [MacroFactor help collection](https://help.macrofactorapp.com/en/collections/3-food-logging)
- MacroFactor's AI "does not rely on LLMs to generate all food entries"; it maps to its curated database — [MacroFactor vs Cal AI, 2026](https://macrofactor.com/macrofactor-vs-cal-ai/) (vendor)
- Recipe "Explode" action splits a recipe into its components on the log; recipes can be created from selected logged foods — [MacroFactor timeline logger](https://macrofactor.com/timeline-based-food-logger/)
- Adherence-neutral: target circles never go orange/red — same source
- **Caffeine Clock**: models absorption plus half-life; set target bedtime to see whether projected level will still be high; warns "often before you even add a drink"; estimates based on published half-life ranges — [App Store](https://apps.apple.com/us/app/caffeine-clock/id6504160396)
- **Unbuzz**: default 5 h half-life, adjustable in 0.1 h steps; questionnaire to calibrate (smoking, hormonal factors) — [App Store](https://apps.apple.com/app/id6757951639)
- **HalfCup**: half-life adjustable 2–10 h; 30-minute absorption window — [App Store](https://apps.apple.com/app/id6756392479)
- **CaffeineTrack**: ~5.7 h half-life, on-device data — [App Store](https://apps.apple.com/us/app/id6759205408)
- **CoffeeLog**: "in your system right now" curve + last-cup-before-bed time, Apple Health sync — [App Store](https://apps.apple.com/app/id6774424227); **Caffeine Flow**: 24-hour concentration curve + widgets — [App Store](https://apps.apple.com/app/id6759970536)

### Inferences
- For this user: compute caffeine-in-system with first-order decay (default ~5 h half-life, user-adjustable, optional ~30 min absorption ramp); show a curve over today's timeline with a horizontal "sleep threshold" line and the planned sleep start marker; nudge "last caffeine cutoff" time. These are estimates and should be labelled as such (as the App Store apps do).
- Food library: each food stores per-100g (or per-serving) kcal/protein/caffeine; entering grams scales automatically; remember last quantity per food; "explode/save as recipe" for composite dishes like pulao.
- Protein: show as progress toward a daily target with remaining grams, and per-meal distribution on the timeline (hour summaries), without red/green judgment colours.
- Net calories = intake − burnt (BMR/active estimate or manual); show with confidence caveat since burn estimates are noisy.

### Gaps
- Cronometer, Lose It and MyFitnessPal library/serving UIs (multipliers, favourites, meal templates) not researched in detail beyond FLSI action counts.
- Caffeine pharmacokinetic parameters (half-life ranges) come from App Store marketing, not primary medical sources; no peer-reviewed source fetched.

---

## 5. Dashboard layouts that feel Apple-like vs anti-patterns

### Takeaway
"Premium/Apple" dashboards are sparse and hierarchical: few user-pinned items, plain-language summary headlines above charts, common chart types, consistent visual language between small and expanded charts, and progressive disclosure. Anti-patterns are dense card grids, many equal-weight tiles, novel charts without onboarding, and judgmental colour.

### Cited Findings
- Apple HIG: "Keep a chart simple, letting people choose when they want additional details"; reveal detail gradually — [Apple HIG, Charting data](https://developer.apple.com/design/human-interface-guidelines/charting-data)
- HIG: prefer common chart types (bar, line); add descriptive headline/summary text (e.g. Weather's "Chance of light rain in the next hour" above the chart); match chart size to functionality (small glanceable vs large interactive); consistency across charts; continuity between small Trends charts and their expanded views — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/charting-data)
- HIG: if you only need to provide data, not insight, use a list/table people can scroll, search and sort — same source
- HIG: make every chart accessible (accessibility labels; Swift Charts supports audio graphs) — same source; [WWDC22 "Design an effective chart"](https://developer.apple.com/videos/play/wwdc2022-110342)
- WWDC22: interactive charts (Stocks, Health) are typically full view width but not full height; an effective chart focuses on a few key pieces of information — [WWDC22 110342](https://developer.apple.com/videos/play/wwdc2022-110342)
- Apple Health Summary: Pinned → Trends → Highlights ordering; highlights tappable for detail with "Show All Highlights" — [Apple Support](https://support.apple.com/en-ie/HT203037)
- Oura's move from 5 tabs to 3 and to "One Big Thing" on Today shows consolidation toward a single focal insight — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/); [9to5Google](https://9to5google.com/2025/10/20/oura-app-redesign/)
- Whoop: three hero dials, each a door to a deep-dive page; reviewer questioned intuitiveness despite visual appeal — [Whoop](https://www.whoop.com/us/en/thelocker/the-all-new-whoop-home-screen/); [the5krunner](https://the5krunner.com/2023/03/28/new-whoop-home-screen-looks-pretty-but-is-it-as-intuitive/)
- Streaks constrained the number of goals and moved overflow to "the back of the card" to stay uncluttered — [MacStories](https://www.macstories.net/?p=49979)
- Structured's timeline praised as clean but degrades with density — [Makerstack](https://makerstack.co/reviews/structured-review/)

### Inferences
- Recommended macOS IA: sidebar (Today / Timeline / Food / Sleep / Work / Trends / Library / Settings) + Today canvas with 3–5 pinned "hero" metrics (work hours, net kcal, protein, caffeine now, last sleep), each with a one-line headline and sparkline, then the day timeline, then auto-generated highlights.
- Every chart gets a sentence headline ("Worked 6h 10m, 40m above your 4-week average").
- Use semantic system colours per category consistently across every chart (HIG continuity), SF Pro/SF Mono for numbers, tabular figures for timers.
- Anti-patterns to avoid: 12+ equal-weight cards, gauges for everything, red/green moralising of food, gamified badges.

### Gaps
- No design-teardown article (e.g. 925studios Whoop breakdown) was fetched; Mobbin-style references not consulted.
- macOS-specific dashboard exemplars (beyond HIG "no additional considerations") not sourced.

---

## 6. Personalisation patterns (custom metrics, pinned widgets, goals, themes)

### Takeaway
Personalisation in leading apps is mostly: choose what's pinned, define custom tags/fields that feed correlation engines, set targets, and hide metrics you don't want to see. Free-form custom tracking (Exist tags, Whoop's 300+ behaviours, Bearable factors) is the extensibility mechanism.

### Cited Findings
- Apple Health: user edits the Pinned list; some items are app-suggested — [Apple Support](https://support.apple.com/en-ie/HT203037); [AppleInsider](https://forums.appleinsider.com/discussion/240443)
- Exist custom tracking (2017) lets users tag events, habits, medications, feelings; Exist finds correlations including on days a tag is **not** used — [Exist custom tags](https://exist.io/about/custom-tags/); [Exist blog 2017](https://exist.io/blog/custom-tracking/)
- Whoop Journal: 300+ behaviours feeding "Behavior Insights"/Impacts on Recovery, reachable from the Recovery dial — [Whoop insights](https://www.whoop.com/ca/en/thelocker/a-new-way-to-see-insights-on-which-behaviors-affect-your-recovery/)
- Oura: Today insights reorder through the day based on the user's goals and metrics; opt-in modules (Cycle Insights) — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- Bearable tracks mood plus symptoms and arbitrary factors, positioned as deeper correlation than Daylio; Daylio is faster/simpler (vendor and roundup sources, low reliability) — [Bearable vs Daylio (vendor)](https://bearable.app/?p=3082); [ChoosingTherapy Bearable review](https://www.choosingtherapy.com/bearable-app-review/)
- MacroFactor offers per-user display density/alignment options on its timeline — [MacroFactor](https://macrofactor.com/timeline-based-food-logger/)
- Whoop allows hiding metrics from Home — [Whoop What's New](https://ww2.whoop.com/thelocker/nouvel-ecran-daccueil-whoop/)

### Inferences
- Design a generic "tracker" schema (name, unit, type: duration-block / point-event / quantity / boolean / rating, aggregation: sum/avg/count, target, colour, icon, shorthand keyword) so new metrics (e.g. water, meds, mood) are user-added without code — this matches the Exist/Bearable extensibility model.
- Pinned Today metrics, per-tracker targets, and shorthand aliases are the three highest-value personalisation levers for this user; theme/accent colour is secondary.

### Gaps
- Theming patterns (custom icons/accent colours in Streaks, Day One journals) not researched.

---

## 7. Retention / proactivity UX (daily review, weekly report, close-out, reminders)

### Takeaway
Proactivity in leading apps is time-of-day aware: morning summary/recommendation, contextual mid-day insights, evening wind-down nudge, and periodic (weekly/quarterly/yearly) reports. End-of-day batch review is a real usage pattern and deserves a dedicated "close out the day" flow.

### Cited Findings
- Whoop: morning Recovery-based recommendation; later-day sleep recommendation from accrued strain; morning Journal prompt after sleep processes — [Whoop What's New](https://ww2.whoop.com/thelocker/nouvel-ecran-daccueil-whoop/); [Whoop Journal](https://www.whoop.com/au/it/thelocker/the-whoop-journal/)
- Oura: daily highlight changes by time of day; weekly/quarterly/yearly reports, shareable — [Oura blog](https://ouraring.com/blog/new-oura-app-experience/)
- Apple Health Trends can notify the user when a trend changes — [iMore](https://www.imore.com/health-ios)
- Exist: daily and weekly insights (correlations, trends, anomalies); 69% of tag users log once at end of day — [Exist use-cases](https://exist.io/blog/post/use-cases/); [Composio Exist listing](https://composio.dev/toolkits/exist/framework/claude-code.md)
- Rize: weekly productivity assessment; post-session rating; AI break suggestions to prevent burnout — [Rize blog](https://rize.io/blog/releasing-the-new-weekly-productivity-assessment); [Rize docs](https://docs.rize.io/sessions/overview)
- Caffeine Clock warns before a drink pushes bedtime level too high (predictive nudge) — [App Store](https://apps.apple.com/us/app/caffeine-clock/id6504160396)
- Gyroscope made the Reports tab the app's start screen; Daily Report called "the core of the Gyroscope experience" — [Gyroscope v3.50](https://about.gyrosco.pe/changelog/v3-series/v350-update); [Gyroscope v4.14](https://about.gyrosco.pe/changelog/v414-update)

### Inferences
- Nudge set for this user: "caffeine cutoff" (projected level at planned bedtime), "protein remaining" in evening, "no work block logged since 11:00" gap detection, "timer still running" (forgotten stop), bedtime-window reminder derived from average sleep start, and an evening "Close the day" sheet listing unlogged gaps in the 24h track.
- Weekly report (Sunday) with averages vs prior week and 4-week baseline, best day, longest work block, sleep consistency.
- Keep nudges local (UserNotifications) and quiet by default; allow per-nudge toggles.

### Gaps
- Daylio/Day One reminder and "On This Day" patterns not researched; no data on optimal nudge frequency or notification fatigue.
