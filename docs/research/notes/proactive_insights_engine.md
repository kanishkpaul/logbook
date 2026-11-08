# Proactive Insights Engine for a Private Single-User macOS Logbook (research notes, Nov 2026)

Scope note: about 19 searches and fetches. Primary sources: vendor help and blog pages (Exist, MacroFactor, WHOOP, Apple), Apple developer docs, and peer-reviewed sleep papers (via PMC). Where I found no vendor method documentation, I say so. Items marked **[Heuristic]** are design recommendations inferred from the sources, not evidence-backed findings. None of this is medical advice. Medical-caveat points are marked **[Medical caveat]**.

---

## 1. How commercial tracking apps generate insights (Exist, Gyroscope, Bearable, Oura, WHOOP, MacroFactor, Apple Health Trends, Apple Vitals)

### Takeaway
Every vendor uses simple, explainable statistics, and none publishes full formulas. The common building blocks are:
- minimum-sample gates (for example, at least 3 days with and 3 without a factor, or at least 5 "yes" and 5 "no");
- with/without comparisons or correlations, shown with a separate strength and confidence;
- a personal baseline with "typical range vs outlier" bands;
- long-window vs short-window comparisons (Apple compares 90 days against 365 days).

MacroFactor is the most transparent. It runs energy balance on a smoothed weight trend, deliberately damps daily noise, and tolerates missing days up to a stated threshold.

### Cited Findings
**Exist.io**
- Exist describes a correlation as a relationship between two attributes, positive or negative, and stresses that it does not imply cause — [Exist KB: What are correlations?](https://kb.exist.io/article/37-what-are-correlations)
- Each correlation carries two separate indicators. One is strength (weak if values only sometimes move together, very strong if they almost always do). The other is confidence, shown as 0 to 5 stars. A correlation can be very strong but low-confidence when little data backs it, and confidence can rise as data accumulates. Exist publishes no numeric cutoffs, statistical method, or minimum days — [Exist KB](https://kb.exist.io/article/37-what-are-correlations)
- If Exist finds no same-day correlation, it checks for correlations across two consecutive days, which is a one-day lag — [Exist KB: correlations across multiple days](https://kb.exist.io/article/55-will-exist-find-correlations-across-multiple-days) (from the search snippet; the full page was not fetched)

**Bearable**
- Correlations begin to appear after at least 3 days with a factor and at least 3 days without it, plus Mood, Symptom, Sleep, or Energy scores on those days. Bearable "compare[s] your scores for days when the factor occurred vs. the days it didn't." Bearable advises logging at least one outcome score every day — [Bearable: what are factors](https://bearable.app/support/tips/what-are-factors/)
- I found no Bearable documentation of p-values, thresholds, or effect-size cutoffs. Bearable's subreddit includes users questioning how meaningful the correlations are — [r/BearableApp mirror](https://redlib.hbubli.cc/r/BearableApp)

**WHOOP**
- Journal "Impacts" analysis appears only after at least 5 "yes" and 5 "no" responses for a behavior within a 90-day window — [WHOOP: The WHOOP Journal](https://www.whoop.com/thelocker/the-whoop-journal/)
- WHOOP's Monthly Performance Assessment sorts behaviors into impact buckets (significant, standard, or negligible; positive or negative). WHOOP explicitly says other behaviors or conditions could still confound each behavior's estimated impact — [WHOOP: monthly assessment recovery analysis](https://whoop.com/eu/en/thelocker/monthly-performance-assessment-now-features-enhanced-recovery-analysis)
- WHOOP recommends tracking fewer than 10 behaviors to avoid confounding — [WHOOP: insights on which behaviors affect recovery](https://whoop.com/thelocker/a-new-way-to-see-insights-on-which-behaviors-affect-your-recovery) (from the search summary)
- WHOOP community users have complained about accuracy and plausibility of the impacts — [WHOOP community: Issues with insights impacts accuracy](https://community.whoop.com/t/issues-with-insights-impacts-accuracy/929); [Journal Data Makes No Sense](https://www.community.whoop.com/t/journal-data-makes-no-sense/11763)

**Oura**
- Readiness has long-term contributors (Sleep Balance, Activity Balance, HRV Balance). Activity Balance looks at activity over the past 2 weeks. HRV Balance compares recent HRV against a long-term average — [Oura: Readiness score](https://ouraring.com/blog/readiness-score/)
- Body temperature is compared against a personal baseline that Oura calculates "during the first couple of weeks" of wear and adjusts as needed — [Oura support](https://support.ouraring.com/hc/lv/articles/360025587493)
- Oura does not publish the exact baseline or deviation math. I found none.

**MacroFactor (adaptive expenditure)**
- Expenditure is "a deterministic calculation based on calorie intake and change in trend weight," which rearranges energy balance. For example, a logged 1800 kcal/day with 1 lb/week of loss gives an estimate of about 2300 kcal/day — [MacroFactor help: expenditure](https://help.macrofactorapp.com/dashboard/expenditure)
- Trend weight is a moving average that weights recent weigh-ins more heavily and tolerates gaps. MacroFactor recommends weighing daily or at least 3 times a week — [MacroFactor help: weight trend](https://help.macrofactorapp.com/dashboard/weight_trend/); [How often to weigh](https://help.macrofactorapp.com/en/articles/109-how-frequently-do-i-need-to-log-my-weight-for-the-expenditure-algorithm-and-weekly-coaching-updates)
- Under-reporting intake makes the algorithm underestimate expenditure — [MacroFactor help: do I need to log everything](https://help.macrofactorapp.com/en/articles/140-do-i-need-to-log-everything-i-eat-and-drink-to-have-an-accurate-expenditure-and-use-macrofactor-s-coaching-features)
- The estimate starts moving after about a week and converges after roughly 14 to 30 days, depending on logging consistency — [MacroFactor: Algorithms and core philosophy](https://macrofactor.com/macrofactors-algorithms-and-core-philosophy/) (from the search summary)
- V3 details: the trend-weight core is undisclosed ("secret sauce").
  - Philosophy: daily weight and intake are noisy, so single days or weeks shouldn't drive large changes. The algorithm predicts, compares with outcomes, and updates gradually.
  - Missing data: V2 paused updates when a 7-day window had fewer than 6 logged days. V3 pauses only when more than 3 of 7 days are missing.
  - Imputation: V3 imputes intake for unlogged days with about 13% average error (over 90% of errors under 30%), but still advises against partial logging.
  - Robustness: with 50% of nutrition data randomly deleted, V3 stayed close to the full-data result.
  - Stability: day-to-day updates are about 35% smaller than V2.
  - Physiology constants: about 39.5 MJ/kg for fat and 7.6 MJ/kg for lean tissue.
  - Source: [MacroFactor: Expenditure V3](https://macrofactor.com/expenditure-v3/)

**Apple Health Trends**
- Trends compare the last 90 days with the last 365 days. The arrow points up if the 90-day average is above the one-year average and down if below. Trends need 180 days of data to start, and may change when Apple updates how metrics are calculated — [Apple Support: Track your trends](https://apple.co/36ggRsf); [Macworld iOS 13 Activity Trends](https://www.macworld.com/article/233093/ios-13-and-apple-watch-activity-trends-give-you-the-big-picture.html)

**Apple Vitals (watchOS 11 and later)**
- Vitals tracks overnight heart rate, respiratory rate, wrist temperature, blood oxygen, and sleep duration. It needs about a week of sleep data to establish a typical range. Each metric is labeled "Typical" or "Outlier" against the user's own range — [Tom's Guide](https://www.tomsguide.com/wellness/smartwatches/watchos-11-public-beta-i-tried-the-new-apple-watch-vitals-health-app-heres-how-it-works-and-first-impressions); [Wareable](https://www.wareable.com/apple/how-vitals-app-finally-makes-apple-watch-a-wellness-powerhouse)
- Notification rule: a single out-of-range metric triggers no alert. Two or more outliers in the same night trigger one "gentle" notification — [BGR](https://bgr.com/tech/watchos-11-everything-you-need-to-know-about-apples-new-vitals-app/); [iGeeksBlog](https://www.igeeksblog.com/how-to-use-vitals-app-on-apple-watch/)
- Possible causes Apple lists include illness onset, alcohol, stress, and time-zone change. Vitals is not diagnostic — [MacRumors](https://www.macrumors.com/2024/10/07/apple-watch-vitals-detects-illness-before-symptoms); [heise](https://heise.de/-9980130)
- Device support is reported inconsistently (Series 6+ vs Series 8+). The secondary sources conflict.

**Gyroscope**
- I found no documentation of Gyroscope's insight method (see Gaps).

### Inferences
- **[Heuristic]** The field converges on four detector types that suit this logbook directly:
  1. A personal baseline with a typical band, plus outlier flags (Vitals, Oura).
  2. Short-window vs long-window comparison (Apple Trends: 90 vs 365 days; adapt to 7 vs 28 days given 50 to 80 days of data).
  3. With/without factor comparison, gated by minimum counts in both groups (Bearable 3+3, WHOOP 5+5 within 90 days).
  4. A smoothed-trend model that damps daily noise and pauses when coverage is too low (MacroFactor's "pause if more than 3 of 7 days are missing").
- **[Heuristic]** Separate strength from confidence in the UI, as Exist does. A strong-but-low-confidence finding should look visibly tentative.
- **[Heuristic]** Copy Vitals' "require 2 or more concurrent signals before notifying" rule to cut false alarms. A single deviating metric goes on a card, not a push notification.
- **[Heuristic]** MacroFactor's caveat applies directly. This app has logged intake and logged *active* burn but no weight trend, so it cannot estimate true expenditure. "Net calories" is intake minus logged burn, not a true energy balance. Label it that way, and never imply weight-change predictions from it.
- **[Heuristic]** With 50 to 80 days of history, Apple-style 180-day gates are unattainable. Use shorter windows, but show lower confidence, and grow windows automatically as history accumulates.

### Gaps
- Gyroscope: I found no public description of its insight or correlation method.
- Exact statistical tests and thresholds for Exist, Bearable, and WHOOP are undisclosed. Exist's "How long does it take to find correlations?" page was not retrieved.
- Oura's precise baseline window and deviation math are unpublished.
- Apple Health "Highlights" selection rules are not documented in the sources I found. Only Trends' 90/365/180-day rule is.

---

## 2. Statistically sound methods for small personal (n-of-1) datasets

### Takeaway
Self-tracking data are serially autocorrelated. Ordinary tests that assume independent days overstate significance, and observational associations from personal logs are hypotheses, not causal effects. At 50 to 80 days, use robust baselines (median/MAD or EWMA), minimum-count gates in both comparison groups, effect sizes with uncertainty, a small pre-registered set of lagged hypotheses instead of all-pairs mining, and an explicit "suggest a self-experiment" path for causal claims.

### Cited Findings
- N-of-1 data show serial correlation such as first-order autocorrelation, and most studies fail to account for it. Standard t-tests assume independence. Tang and Landes propose single-individual t-tests that handle autocorrelation — [arXiv 1904.01622](https://arxiv.org/abs/1904.01622v2)
- Daza: analyses of single-subject observational data can surface *possible* cause-effect relationships that should then be self-tested in an n-of-1 randomized trial, and a principled method for when an association can be read as causal is still needed — [Daza 2018](https://statsof1.netlify.com/2018_daza_latexversion.pdf)
- Randomizing the "treatment" each period (Model-Twin Randomization) protects causal estimates from confounding. Autocorrelation and carryover can delay an effect from appearing — [arXiv 2208.00739](https://arxiv.org/pdf/2208.00739)
- A simulation study of an mHealth n-of-1 tool says more work is needed on how autocorrelation, seasonality, and trends affect statistical validity and power — [PMC6999905](https://pmc.ncbi.nlm.nih.gov/articles/PMC6999905) (from the search summary)
- Vendor practice for minimum samples: Bearable uses at least 3 factor days and 3 non-factor days ([Bearable](https://bearable.app/support/tips/what-are-factors/)). WHOOP uses at least 5 "yes" and 5 "no" within 90 days ([WHOOP](https://www.whoop.com/thelocker/the-whoop-journal/)). WHOOP recommends fewer than 10 tracked behaviors to limit confounding ([WHOOP](https://whoop.com/thelocker/a-new-way-to-see-insights-on-which-behaviors-affect-your-recovery)).
- Smoothing and missing data in practice: MacroFactor uses a recency-weighted moving average that tolerates gaps ([weight trend](https://help.macrofactorapp.com/dashboard/weight_trend/)), pauses estimates when more than 3 of 7 days are missing, and imputes unlogged days with about 13% average error ([Expenditure V3](https://macrofactor.com/expenditure-v3/)).
- Exist checks same-day correlations first and then one-day lags ([Exist KB](https://kb.exist.io/article/55-will-exist-find-correlations-across-multiple-days)). That is two tests per pair, which multiplies comparisons.

### Inferences
These are statistical-practice recommendations. The sources above establish the problems, and the specific numbers below are design choices to tune.

- **Baselines:**
  - Use an EWMA with a half-life of about 7 to 14 days for "recent". Use a rolling 28-day median with MAD (median absolute deviation) for "typical".
  - The robust z-score is z = (x − median) / (1.4826 × MAD). It resists the outliers that manual logs produce, such as a single 16-hour sleep.
  - Flag only |z| ≥ 2 sustained for at least 2 of the last 3 days, or a single |z| ≥ 3.
  - Require at least 14 valid days in the baseline window before any deviation card appears.
- **Trend detection:**
  - Compare the 7-day mean with the 28-day mean (the Apple Trends pattern, shortened).
  - Optionally use a Mann-Kendall test or Theil-Sen slope over 28 days. Both are robust to outliers and need no normality assumption.
  - Report a direction only when the change exceeds both a practical threshold (for example, sleep ±30 min or work ±45 min) and a noise threshold.
- **Lagged hypotheses (pre-registered, small set):**
  - Late caffeine (any caffeine after 16:00, or after bedtime minus 8 hours) vs the following sleep's duration and onset.
  - Sleep duration on night t vs work minutes on day t+1.
  - Sleep midpoint shift vs work start time.
  - Protein or calories vs next-day work.
  - Use a with/without split (Bearable/WHOOP style) with at least 8 to 10 days in each group, a slightly stricter variant of the 5+5 rule.
  - Report the median difference with a bootstrap 90% interval (block bootstrap with 3 to 7 day blocks respects autocorrelation), or Spearman ρ with an effective sample size adjusted for lag-1 autocorrelation: n_eff ≈ n(1−r₁)/(1+r₁).
- **Multiple comparisons:**
  - With about 10 metrics and 2 lags there are about 90 or more pairs. Expect about 5% false positives at p < .05.
  - Use Benjamini-Hochberg FDR at 10% across all tested pairs each run.
  - Restrict auto-mined pairs to a whitelist of plausible directional pairs.
  - Require that a finding replicates when re-run on the last 28 days alone before promoting it to a card.
- **Missing data:**
  - Treat "~" estimates as valid but down-weighted (for example, weight 0.5) or excluded from significance tests.
  - Never impute for correlation tests. Use pairwise-complete days only.
  - Suppress a metric's insights when coverage in the window is below about 60%. This mirrors MacroFactor's "pause if more than 3 of 7 days are missing."
  - Distinguish "not logged" from "zero", for example no caffeine logged vs zero caffeine. This is the main source of spurious insights in manual logs.
- **Confounding by weekday:** compare like with like (weekday vs weekday), or residualize on a day-of-week mean once there are at least 8 weeks of data.
- **Causal language:** use only "tends to" or "on days when…" wording, never "causes". When a pattern is promising, offer a 2-week self-experiment (for example, alternating caffeine cutoffs) rather than asserting it, following Daza.

### Gaps
- I found no source giving validated minimum sample sizes for personal correlation detection. The 8 to 10 per group above is a heuristic extrapolated from vendor gates of 3+3 and 5+5.
- I found no direct literature on FDR control in consumer self-tracking apps.

---

## 3. Domain-specific heuristics (caffeine, sleep regularity, circadian timing, protein, energy balance, work focus, bathroom)

### Takeaway
Two areas have strong evidence:
- Caffeine taken even 6 hours before bedtime measurably shortens sleep, by more than an hour objectively, without people noticing.
- Sleep *regularity* (SRI) predicts mortality more strongly than sleep duration in a 61,000-person cohort, though causality is unproven.

Everything else should be encoded as user-adjustable heuristics with conservative, non-diagnostic wording. That includes the protein target, energy-balance framing, and bathroom patterns.

### Cited Findings
- **Caffeine timing (Drake et al. 2013, J Clin Sleep Med):**
  - Design: 12 healthy sleepers, 400 mg caffeine given at 0, 3, or 6 hours before habitual bedtime, placebo-controlled.
  - Result: caffeine 6 hours before bed reduced objectively measured total sleep time by more than 1 hour, yet participants' subjective reports suggested they were unaware of the disruption.
  - Authors' conclusion: caffeine 6 hours before bedtime has "important disruptive effects on sleep."
  - Sources: [PMC3805807](https://pmc.ncbi.nlm.nih.gov/articles/PMC3805807/); [AASM press release](https://aasm.org/late-afternoon-and-early-evening-caffeine-can-disrupt-sleep-at-night/)
- **Sleep Regularity Index (Windred et al. 2024, SLEEP):**
  - Design: UK Biobank, 60,977 participants with 1 week of actigraphy.
  - Result: a 1-SD (+10.7) higher SRI predicted a 20.4 ± 2.0% lower hazard of all-cause mortality, and regularity was a stronger predictor than duration.
  - Caveat: the authors say regularity may be causal or may be a marker of poor health.
  - Secondary sources give a wider 20 to 50% range. Prefer the paper's own figures.
  - Sources: [PMC10782489](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC10782489/); [Flinders research page](https://researchnow.flinders.edu.au/en/publications/sleep-regularity-is-a-stronger-predictor-of-mortality-risk-than-s/)
- **Energy balance:** MacroFactor derives expenditure from intake plus *trend weight change*, and says under-logged intake biases expenditure low — [MacroFactor help](https://help.macrofactorapp.com/dashboard/expenditure); [logging FAQ](https://help.macrofactorapp.com/en/articles/140-do-i-need-to-log-everything-i-eat-and-drink-to-have-an-accurate-expenditure-and-use-macrofactor-s-coaching-features)
- **Vitals-style non-diagnostic framing:** Apple's Vitals describes outliers as possibly linked to illness, alcohol, stress, or travel, and is not a diagnostic tool — [MacRumors](https://www.macrumors.com/2024/10/07/apple-watch-vitals-detects-illness-before-symptoms); [heise](https://heise.de/-9980130)

### Inferences
**Caffeine**
- **[Heuristic]** Compute a modeled caffeine-remaining curve, C(t) = Σ dose × 0.5^((t − t_dose)/t½), with a user-adjustable t½ defaulting to 5 hours (see Gaps on sourcing).
- **[Heuristic]** Show "estimated caffeine remaining at your usual bedtime." Set the default cutoff alert at bedtime minus 6 hours, anchored to Drake 2013. Let the user move it to 8 hours.
- **[Heuristic]** Bedtime must be the user's *personal median sleep onset* (for example 03:30), not a clock-time "4 pm" rule. For this user, a cutoff of about 21:30 may be appropriate, while a fixed 4 pm rule would be wrong.

**Sleep regularity and timing**
- **[Heuristic]** Compute SRI from logged sleep blocks: sample 30-minute epochs as asleep (1) or awake (0), and compare each epoch with the same clock time 24 hours later. SRI = 200 × P(same state) − 100, giving a range of −100 to 100. Require at least 5 consecutive valid day-pairs, or show "insufficient data."
- **[Heuristic]** Simpler companions: SD of sleep onset and SD of sleep midpoint over 7 and 28 days. Social-jetlag-style difference between workday and free-day midpoint.
- **[Heuristic]** Do not frame irregular or late sleep (for example 03:30 to 14:15) as "bad." Frame consistency relative to the user's own pattern. **[Medical caveat]** Never cite the mortality finding in-app as a personal risk statement.

**Protein**
- **[Heuristic]** Let the user set the target, as g/day or g/kg if they enter weight. Show a 7-day average vs target, not daily scolding. No default clinical target is sourced here (see Gaps).

**Energy balance**
- **[Heuristic]** Label "net = intake − logged active burn." Add a tooltip: logged burn excludes resting metabolism and is an estimate, and net is not your true energy balance. Never project weight change.

**Work focus**
- **[Heuristic]**
  - Streaks are days at or above a user target, or at or above the personal 28-day median.
  - Use the deep-work block count (blocks of 50 minutes or more) and the start-time distribution: median, and P25/P75 of first block start.
  - "You usually start by X" is based on the 28-day median of first work block start, restricted to the same weekday type.

**Bathroom ("nature's call") blocks**
- **[Heuristic]** Show frequency and duration only as descriptive personal trends, such as "longer than your usual" versus the 28-day median and MAD. Never push-notify on them.
- **[Medical caveat]** Any sustained change shown should carry neutral copy, for example "If something about this concerns you, a clinician is the right person to ask." Never name conditions or suggest causes.

**Timer hygiene**
- **[Heuristic]** If a work, sleep, or bathroom timer exceeds max(P95 of that block type, a hard cap such as 4 hours for work or 30 minutes for bathroom), prompt: "Still running?"

### Gaps
- **Caffeine half-life:** I did not retrieve a primary source in this session for the about-5-hour figure (commonly cited as about 3 to 7 hours with wide inter-individual variation). The writer should cite a pharmacology source or keep it labeled as a default.
- **Protein targets:** I retrieved no evidence-based source. Keep it user-set.
- **Bathroom duration:** I found no source on normal ranges. Intentionally not researched, to avoid medical framing.
- **SRI computation:** I did not fetch the original Phillips et al. 2017 SRI definition. The formula above follows the standard definition (probability of the same sleep/wake state 24 hours apart, scaled to −100 to 100) and should be verified against the original paper.

---

## 4. Proactive UX: when and how to notify, and avoiding notification fatigue

### Takeaway
The evidence for notifications is mixed. Better *timing* models raise receptivity by about 36 to 40% over random timing, and poorly timed prompts risk "intervention fatigue." One stress-app study found frequency did not clearly reduce engagement. Apple's HIG says to match interruption level to real urgency, use Time Sensitive only for events happening now or within an hour, and expect users to switch off apps that over-interrupt.

### Cited Findings
- **ML timing:** in the Ally physical-activity app (83 participants, 3 weeks), ML-timed delivery gave up to 40% higher receptivity than random timing — [Mishra et al., receptivity](https://cs.dartmouth.edu/dfk/research/mishra-receptivity/mishra-receptivity.pdf). A Dartmouth highlight reports "up to 36%" — [highlight](https://cs.dartmouth.edu/dfk/research/mishra-receptivity-highlight/mishra-receptivity-highlight.pdf). The figures differ by source.
- **Receptivity definition:** the person's ability to receive, process, and use support (Künzler et al.) — [Künzler receptivity](https://www.cs.dartmouth.edu/dfk/research/kunzler-receptivity/kunzler-receptivity.pdf)
- **Fatigue risk:** poorly timed interventions can cause intervention fatigue and reduce continued engagement — [Mishra WellComp](https://cs.dartmouth.edu/dfk/research/mishra-wellcomp/mishra-wellcomp.pdf)
- **Counter-evidence:** a stress-management app study found frequent notifications did not appear to deter engagement, and adaptive timing did not always increase use — [PMC5207732](https://pmc.ncbi.nlm.nih.gov/articles/PMC5207732) (from the search summary). I found no study isolating notification fatigue as a measured outcome.
- **Apple HIG on interruption levels:**
  - Use Time Sensitive only when relevant now, or for an event within an hour.
  - Be realistic when assigning interruption levels, because people can turn off all notifications.
  - The system periodically asks users to re-evaluate Time Sensitive notifications.
  - Passive and Active levels do not break through Focus.
  - Source: [Apple HIG: Managing notifications](https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md); [WWDC21 10091](https://developer.apple.com/videos/play/wwdc2021/10091?time=117)
- **Vitals:** no alert for a single outlier, and one gentle notification when 2 or more metrics deviate — [BGR](https://bgr.com/tech/watchos-11-everything-you-need-to-know-about-apples-new-vitals-app/)

### Inferences
**Notification budget**
- **[Heuristic]** At most 2 proactive pushes per day by default, plus user-scheduled reminders. Everything else goes to in-app cards or a menu-bar badge.
- **[Heuristic]** Use the Passive interruption level for summaries and insights, and Active for reminders the user explicitly enabled.
- **[Heuristic]** Use Time Sensitive only for a forgotten running timer (it is happening now) and the caffeine cutoff if the user opts in.

**Notification types for this app**
- **End-of-day close-out:** fire at the user's personal "day end", meaning sleep onset median minus 60 minutes, not midnight. Show a checklist of missing fields.
- **Missed-log nudge:** at most one per day, only when a usual-time anchor has passed by more than P75 + 60 minutes with no entry. Suppress it when the day is marked off or traveling.
- **"You usually start work by X":** informational only, after the start time passes P75 with no work block. Disabled by default.
- **Caffeine cutoff:** fires at cutoff minus 30 minutes, only on days with prior caffeine logged.
- **Bedtime nudge:** relative to the personal median onset, opt-in only.
- **Weekly review:** a Passive notification at a user-chosen time, linking to an in-app review.
- **Forgotten timer:** Time Sensitive, with quick actions "Stop now", "Stop at…", and "Still going".

**Adaptive suppression**
- **[Heuristic]** If a notification type is dismissed without action 3 times in a row, halve its frequency and offer "turn off this type" inline.
- **[Heuristic]** Respect macOS Focus. Add app-level quiet hours, defaulting to sleep-median ± 1 hour. Never send during a running sleep timer.
- **[Heuristic]** Learn receptive times simply: record the hour of each notification the user acted on, and prefer the top-2 hours (a lightweight version of the Mishra ML-timing result).

### Gaps
- I found no peer-reviewed quantification of a "safe" daily notification count. Budget numbers above are heuristic.
- I did not retrieve macOS-specific notification research or the full Apple HIG page (details came from search snippets of the HIG page). Verify against the live HIG.

---

## 5. Using an on-device LLM (Apple Foundation Models, ~3B parameters, 4,096-token context)

### Takeaway
Apple's on-device model has a hard 4,096-token-per-session window. That window includes instructions, prompts, Generable JSON schemas, tool definitions, tool I/O, and responses. Apple reportedly says the model is not designed for world knowledge or advanced reasoning. The safe pattern is: Swift computes every number, the LLM receives a compact, pre-formatted fact sheet and returns a constrained `@Generable` struct that references fact IDs, and code then verifies and renders the numbers.

### Cited Findings
- **Context window:**
  - Apple's on-device model has a context window of 4096 tokens per session. Every interaction consumes it: prompts, instructions, tool definitions and their I/O, generable type schemas, and responses.
  - English text is about 3 to 4 characters per token.
  - `tokenCount(for:)` and `contextSize` APIs exist, and overflow throws `LanguageModelError.contextSizeExceeded`.
  - Source: [Apple: Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md); [TN3193](https://developer.apple.com/tutorials/data/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window.md)
- **Prompts and tools:**
  - Keep prompts to three paragraphs or fewer, and use imperative verbs.
  - Specify length ("In three sentences…"), and use `@Guide(.maximumCount)` on arrays.
  - Avoid `maximumResponseTokens` except to stop verbosity, because it can truncate mid-sentence.
  - Offer no more than 3 to 5 tools per request. Skip tool calling when the model always needs specific information: retrieve it directly and put it in the prompt.
  - Source: [Apple: Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md)
- **Generable types:** each is converted to a JSON schema sent to the model, and `@Guide` descriptions cost tokens. Keep types simple with short, clear property names. `@Guide(.minimum, .maximum)` constrains numeric ranges — [Apple](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md)
- **Large tasks:** split them across fresh sessions (chunk, then summarize, then combine). When a session overflows, re-seed it with the first and last transcript entries — [Apple](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window.md)
- **Model limits:** the model is about 3B parameters. Reporting says Apple explicitly states it is not designed for world knowledge or advanced reasoning — [Washington Times (WWDC25 coverage)](https://twt-assets.washtimes.com/news/2025/jun/9/apple-making-ai-accessible-developers-researchers-cast-doubt-large); [Infinum](https://infinum.com/blog/apple-on-device-ai/). This is a secondary source. I did not retrieve Apple's primary wording.
- **Error cases:** a guardrail-violation error exists for safety-filtered content (third-party guide) — [atelier-socle guide](https://www.atelier-socle.com/en/articles/foundation-models-api-guide)
- **Conflicting reports:** some 2026 blogs describe a newer "AFM 3" generation, including a reported 20B sparse on-device model. They conflict with each other and with WWDC25 reporting, so they are unverified — [dev.to (WWDC26 read)](https://dev.to/owen_fox/apples-third-generation-foundation-models-a-developers-read-on-wwdc-2026-2ej1)

### Inferences
**[Heuristic] Division of labor**
- The insight engine, in deterministic Swift, decides *what* is true and *whether* to show it.
- The LLM only phrases it, and only for summaries such as the weekly review, the end-of-day recap, and "why am I seeing this" elaboration.
- Cards and notifications must work with no LLM (template strings), which is the fallback when the model is unavailable or errors.

**[Heuristic] Prompt payload**
- Use a fact sheet of about 300 to 800 tokens: 5 to 12 facts, each with an id, a pre-formatted value string (for example "6 h 40 m", "−52 min vs your 28-day median"), a direction, and a confidence label.
- Never pass raw logs. The LLM never sees numbers it has to combine.

**[Heuristic] Output schema**

```swift
@Generable struct DailyRecap {
  @Guide(description: "One-sentence headline") var headline: String
  @Guide(.maximumCount(3)) var points: [RecapPoint]
}
@Generable struct RecapPoint {
  var factID: String   // must match a provided id
  var phrasing: String // must not contain digits
}
```

- Swift then interpolates the verified value strings into `phrasing` via a placeholder such as `{value}`.
- Post-validate the output:
  - Reject or regenerate if any `factID` is unknown, if digits appear in free text, or if banned words appear (diagnose, disease, causes, should, risk).
  - On a second failure, fall back to templates.

**[Heuristic] Instructions**
- "Use only the facts provided. Do not compute, estimate or add numbers. Do not give medical advice. Use 'tended to', not 'caused'."

**[Heuristic] Caching**
- Key the cache on a hash of the fact sheet plus the prompt version. Regenerate only when facts change.
- Prewarm the session when the close-out window opens.
- Use one session per summary to avoid context growth.

**[Heuristic] Tool calling**
- Mostly unnecessary per Apple's own advice: if the data is always needed, put it in the prompt.
- Possible exception: a "chat with my log" mode with at most 3 to 5 read-only query tools (for example `getMetricSummary(metric, window)`) that return pre-aggregated strings, each call in a fresh session.

**[Heuristic] Where the LLM hurts**
- Arithmetic, date math, comparing numbers, deciding significance, anything medical, and long histories that won't fit in 4K tokens.
- Treat it as a copywriter, not an analyst.

### Gaps
- I did not retrieve Apple primary documentation quoting the "not designed for world knowledge or advanced reasoning" limitation, or Apple's Foundation Models acceptable-use or safety guidance. I also did not fetch the WWDC25 "Meet the Foundation Models framework" transcript.
- Documented case studies of how Apple's own features (for example notification summaries) avoid hallucinated numbers were not found in this session.
- The 2026 model-generation and context-size changes are unverified. The writer should check current Apple docs. `contextSize` lets code read the limit at runtime instead of hard-coding 4096.

---

## 6. Rule-engine architecture for extensible insight "cards"

### Takeaway
No vendor publishes its engine internals. The patterns observable across vendors combine into a pluggable-detector design with gating, scoring, de-duplication, memory, and explanation:
- minimum-data gates (Bearable, WHOOP);
- strength vs confidence (Exist);
- multi-signal escalation (Vitals);
- update damping and pause-on-missing-data (MacroFactor);
- user re-evaluation of interrupting notifications (Apple HIG).

### Cited Findings
- Strength and confidence are presented separately, with confidence growing with data — [Exist KB](https://kb.exist.io/article/37-what-are-correlations)
- Per-factor minimum gates: 3+3 days ([Bearable](https://bearable.app/support/tips/what-are-factors/)), and 5 yes + 5 no in 90 days ([WHOOP](https://www.whoop.com/thelocker/the-whoop-journal/))
- Impact buckets (significant, standard, negligible × positive, negative) with an explicit confounding caveat — [WHOOP](https://whoop.com/eu/en/thelocker/monthly-performance-assessment-now-features-enhanced-recovery-analysis)
- Escalation only when 2 or more signals co-occur — [BGR on Vitals](https://bgr.com/tech/watchos-11-everything-you-need-to-know-about-apples-new-vitals-app/)
- Pausing estimates under insufficient data, and damping updates (35% smaller daily changes) — [MacroFactor V3](https://macrofactor.com/expenditure-v3/)
- The system periodically lets users re-evaluate interrupting notifications — [Apple HIG](https://developer.apple.com/design/human-interface-guidelines/managing-notifications.md)

### Inferences
**[Heuristic] Detector protocol**

```swift
protocol InsightDetector {
  var id: String { get }                      // "caffeine.lateVsSleep"
  var version: Int { get }
  var requiredMetrics: [MetricID] { get }
  var minValidDays: Int { get }
  func evaluate(_ ctx: AnalysisContext) -> [InsightCandidate]
}
struct InsightCandidate {
  let detectorID: String
  let subjectKey: String                      // de-dupe key, e.g. "sleep.duration.7d"
  let kind: Kind                              // .anomaly .trend .correlation .streak .reminder .dataQuality
  let effectSize: Double                      // standardized
  let confidence: Confidence                  // .low/.medium/.high from n, coverage, CI width
  let actionability: Double                   // 0–1, set per detector
  let facts: [Fact]                           // id + formatted value; feeds UI and LLM
  let explanation: Explanation                // method, window, n, threshold, data excluded
  let medicalSensitivity: Bool                // forces neutral copy, no push
}
```

**[Heuristic] Pipeline**
1. Data-quality pass: coverage per metric, excluding or down-weighting "~" values.
2. Run the detectors.
3. Gate: drop candidates that fail `minValidDays`, coverage, or confidence.
4. FDR correction across correlation candidates.
5. Score.
6. Suppress via memory.
7. Rank and cap: at most 3 cards per day, and at most 1 per subject.
8. Route each card to card, notification, or weekly digest.

**[Heuristic] Scoring**

score = w_e·|effect| + w_c·confidence + w_a·actionability + w_n·novelty − w_f·fatigue(type)

- Novelty decays when the same subjectKey was shown recently.
- Fatigue grows with recent dismissals of that detector.

**[Heuristic] Memory table**

`(detectorID, subjectKey, lastShown, timesShown, timesDismissed, snoozedUntil, userFeedback: helpful|notHelpful|wrong)`

- Dismiss suppresses for 14 days unless the effect grows by at least 50%.
- "Not helpful" twice disables the detector and offers re-enable in settings.
- "Wrong" flags the input data for review (often a logging error).

**[Heuristic] "Why am I seeing this"**
- Render it from `explanation`, not the LLM: "Compared your last 7 days (6 valid, 1 estimated) with your 28-day median. Flagged because it was more than 2 typical deviations below on 2 of 3 days. 3 days without sleep logs were excluded."
- The LLM may only rephrase this text.

**[Heuristic] Versioning**
- Store `detector.version` with each shown insight so threshold changes don't re-fire old insights.
- Make thresholds config-driven (JSON or plist) so they can be tuned without code changes.

**[Heuristic] Initial detector set**
- Data-quality detectors: missing day, forgotten timer, unusual value that might be a typo.
- Sleep: duration anomaly, onset drift, SRI or onset-SD trend.
- Caffeine: remaining at bedtime, late-caffeine vs sleep correlation.
- Work: start-time deviation, total vs baseline, focus streak.
- Protein: 7-day average vs user target.
- Calories: net-calorie 7-day trend, with the caveat label.
- Steps: trend.
- Bathroom: descriptive trend only, medically sensitive, no push.

### Gaps
- I found no public engineering write-ups of Exist, Bearable, WHOOP, or Oura insight-engine architecture, scoring, or dismissal memory. The architecture above is synthesized, not sourced.
- I found no research on optimal cards-per-day caps or snooze durations for personal informatics. These are heuristics to validate with the user's own feedback data.
