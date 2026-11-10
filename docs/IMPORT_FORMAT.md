# Import format

The importer reads your Apple Notes shorthand from a plain-text or Markdown file, one line at a time. Anything it can't read becomes a warning in the preview; nothing is silently dropped or "fixed".

```bash
swift run --package-path Packages/LogbookImport logbook-import preview path/to/log.md
swift run --package-path Packages/LogbookImport logbook-import apply   path/to/log.md
swift run --package-path Packages/LogbookImport logbook-import undo    <batch-id>
swift run --package-path Packages/LogbookImport logbook-import batches
```

Options: `--year 2026` (year for headers without one; default: this year), `--tz Asia/Kolkata` (zone the times were written in; default: this Mac's), `--db path/to/logbook.sqlite` (default: the live database). Keep real log files out of the repo (`/data/` is git-ignored).

## Synthetic example

```text
## Sat 10 Oct 2026

0100 - 0330 [2h 30m] > study + exam
0945 - 1045 [1h] > writing
$ 3h 30m

pulao 250g - 408 / 8 / 0
coffee - ~40 / 1 / 110
Chicken roll
$ 448 / 9 / 110

burn - 373 / 11,773 steps
$ 75 / 9 / 110

sleep -> 0045 - 0930 [8h 45m]
nc -> 1550 - 1708 [1h 18m] [13m / 17m / 48m]
```

## Line types

Leading list markers (`- `, `* `, `• `) and heading marks (`#`) are stripped first. Separators may be `-`, `–` or `—`; `->` and `:` work after a keyword.

| Line | Pattern | Stored as |
|---|---|---|
| **Day header** | a line that is only a date: `2026-10-10`, `10 Oct`, `Fri 10 Oct 2026`, `10th October 2026`, `Oct 10, 2026`, `10/10/2026`, `10.10.26` (day first) | starts a new day; every following line belongs to it |
| **Work** | `HHMM - HHMM [dur] > label` (the `[dur]`, `>` and label are optional) | `time_block` kind `work` |
| **Sleep** | `sleep -> HHMM - HHMM [dur]` | `time_block` kind `sleep` |
| **Nature's call** | `nc -> HHMM - HHMM [dur] [parts…]` | `time_block` kind `nature_call`; only the total is stored |
| **Burn** | `burn - 373` or `burn - 373 / 11,773 steps` or `burn 373 11773` | metric samples `active_kcal` (and `steps`) |
| **Steps** | `steps 11773` or `11,773 steps` | metric sample `steps` |
| **Food with values** | `name [qty] - kcal / protein / caffeine / nicotine` (see *Values* below) | `food_log_entry` with those values snapshotted |
| **Food without values** | any other line, e.g. `Chicken roll`, `50rs puchka` | `food_log_entry` flagged *needs values*, or filled from the library (as an estimate) if the name matches a food |
| **Total** | `$ 6h 30m` or `$ 1,616 / 102 / 220` | **not stored**; checked against what the app computes, mismatches become warnings |
| **Ignored** | blank lines, ```` ``` ```` fences, `\|` table rows, `---`, headings that aren't dates | — |

Times are `HHMM`, `HMM` or `H:MM` (24-hour); `2400` means midnight at the end of the day.

## Values

After the last ` - ` on a food line (or after `$`):

- **Untagged numbers are positional:** kcal / protein / caffeine / nicotine. `408 / 8 / 0` means what it always did; a 4th number is nicotine (mg).
- **Tagged numbers go where the tag says**, anywhere in the list: `60c` carbs, `12f` fat, `8p` protein, `110caf` caffeine, `2nic` nicotine. Example: `dal 200g - 180 / 9 / 0 / 0 / 25c / 4f`, or just `zyn - 6nic`.
- Unit suffixes `kcal`, `cal`, `g`, `gm`, `mg` count as untagged. Separators: `/`, `,` or spaces. `1,616` is one number.
- A `~` anywhere marks the values as an estimate.
- Fields the line doesn't give are filled from the dictionary entry (scaled), so macros are counted even when you only type `kcal / protein / caffeine`.

## Quick Entry extras (in the app, not in imported files)

| Type | Does |
|---|---|
| `start study` · `start sleep` · `start nc` | starts a timer (`start` alone = work) |
| `stop` · `stop sleep` | stops a timer |
| `copy yesterday` | logs yesterday's food again at the same times, same values |
| `meal breakfast = coffee + 2 eggs + toast 2 slices` | saves a meal (every item must be in the dictionary); redefining replaces it |
| `breakfast` · `breakfast x2` | logs every item of the meal |
| `2 eggs` · `egg x2` | counts; `eggs` and `egg` match the same dictionary entry |
| `t draft outline ~45m !! fri #writing` | a task: `~` estimate, `!`/`!!` priority, a day or date = due, `@day` = scheduled, `@someday`, `#list` |
| `t standup every weekday` · `t gym every mon,wed,fri` · `t water plants after 3 days` | repeating tasks (the next one appears when you complete it) |
| `weight 71.2` · `mood: 4` · `water 500` | one of your own metrics (define it first under Library › Metrics) |
| `plan 1400-1600 deep work` · `plan tomorrow gym 1800-1900` · `plan sleep 0100-0900` | a planned block (kinds: work, sleep, nc, break, gym; sleep after midnight means the coming night) |

Typing a food with values and a count (`egg x2 - 140 / 12 / 0`) stores **one** egg (70 kcal) in the dictionary.

## Rules

- **Day boundary:** calendar day (decision #1).
- **Work and nature's call** start on the header's date; if the end time is earlier than the start, the end is the next day.
- **Sleep** is the sleep that *ended* on the header's date: `sleep -> 2330 - 0700` under 10 Oct means 9 Oct 23:30 → 10 Oct 07:00. It counts toward the day you woke up.
- **Food time** isn't in the notes, so food is stored at 12:00 on the header's date; `13:30 pulao …` (with a colon) sets the time.
- **Estimates:** a `~` before the name or the numbers sets `is_estimate`.
- **Quantities:** a trailing `250g`, `50 ml`, `2 tsp`, `x2` on the name is stored as quantity + unit; the name without it is used for library matching.
- **Dictionary (food library):** each new food name with typed values (not estimates) becomes a dictionary entry, with the logged quantity as its serving. Later lines with the same name (or an alias) and no values are filled from it, scaled by quantity when the units match, or by `x2`. Nicotine products (`cigarette`, `pouch`…) are dictionary entries too.
- **`[dur]` brackets** are checked against the times; a mismatch is a warning. Extra brackets (nature's-call parts) are kept only in `raw_text`.
- **Year:** a header without a year uses the previous header's year (rolling over from Dec to Jan), else `--year`.

## Safety

- Every row keeps its original line in `raw_text` and the batch id in `import_batch_id`.
- One `apply` is one transaction. `undo <batch-id>` removes every row from that batch (and the library foods it created) and leaves the change log.
- Row ids are derived from the date and line text, so re-running the same file skips what's already there. A work/sleep/NC block with the same kind and times as an existing non-imported block is skipped as a likely duplicate.
