# VIGIL — Architecture Spec v2 (on-device first)

Companion to the **VIGIL — Daily Ops Companion** design canvas.
Version 2.0 · 22 Oct 2026 · Flutter (Android first, iOS second)

> **What changed from v1:** there is **no custom backend**. Everything runs inside the app: the database, engines, alerts, the sleep recommender, digital wellbeing, briefings and the assistant. Only three things leave the phone: **Google APIs** (sign-in, Calendar, a Drive backup), an optional **weather** fetch, and an optional **cloud AI** call for hard assistant requests. All three are called straight from the app, with no server of yours in between.

---

## 0. TL;DR

- **One process, one database.** An encrypted SQLite database (drift + SQLCipher) is the only source of truth.
- **Deterministic engines in Dart:** scores, alert rules, the sleep recommender, screen-time analysis, capture parsing and budget pace. The AI phrases results. **It never computes numbers.**
- **The assistant runs on the device.** The default is a small local model; an optional cloud model can be switched on in Loadout. Tool calls run as Dart functions with undo.
- **Google is the only cloud dependency.** Sign-in, Calendar read/write (incremental sync from the phone), and a nightly encrypted backup to Drive's hidden app folder.
- **Background work follows the platform rules:** WorkManager and exact alarms on Android. Pre-scheduled notifications and BGTasks on iOS.

---

## 1. Principles

| # | Principle | In practice |
|---|-----------|-------------|
| P1 | On-device by default | No VIGIL server. Every screen works in flight mode except Calendar sync, backup and cloud AI. |
| P2 | Deterministic numbers | Totals, streaks, scores, sleep debt and screen time come from SQL or Dart. |
| P3 | Reversible AI | Each assistant write is logged with an inverse payload. Undo works for 24 h. |
| P4 | Confirm before consequences | Moving meetings with attendees, marking money paid and deletes all need a tap. |
| P5 | Quiet by default | Daily alert budget, quiet hours, Stand Down and Night Shield. |
| P6 | Nothing leaves without asking | Cloud AI is off by default. Backups are encrypted before upload. No analytics by default. |
| P7 | Battery is a feature | Background work is batched. The target is under 3 % of battery a day. |

---

## 2. Architecture

```mermaid
flowchart TB
  subgraph App["VIGIL · Flutter app"]
    UI[Screens · Widgets · Notifications]
    DOM[Domain services<br/>objectives · timeline · protocols · vitals · ledger · log]
    ENG[Engines (pure Dart)<br/>scores · rules · sleep recommender ·<br/>screen analyzer · capture parser · briefing composer]
    AI[Assistant runtime<br/>router · tool executor · response contract]
    LLM[(On-device model)]
    DB[(SQLite + SQLCipher · drift)]
    BG[Background<br/>WorkManager · exact alarms · BGTasks]
    UI <--> DOM <--> DB
    ENG <--> DB
    AI --> DOM
    AI <--> LLM
    BG --> ENG
  end

  subgraph Bridges["Platform bridges (Kotlin / Swift)"]
    HC[Health Connect · HealthKit]
    US[UsageStatsManager · Screen Time API]
    NL[Notification listener]
    SH[Shield: accessibility / ManagedSettings]
    VOX[STT · TTS]
    AL[AlarmManager · UNNotifications]
  end

  App <--> Bridges
  App -- OAuth --> GSI[Google Sign-In]
  App -- syncToken --> GCAL[Google Calendar API]
  App -- encrypted snapshot --> GDRV[Google Drive appDataFolder]
  App -. optional .-> WX[Open-Meteo weather]
  App -. optional, opt-in .-> CLOUD[Cloud LLM API]
```

### What runs where

| Feature | On device | Leaves the phone |
|---------|-----------|------------------|
| Objectives, timeline, protocols, ledger, field log, journal | ✅ all | — |
| Calendar events | Mirror + conflict detection | Google Calendar API (read/write) |
| Scores, readiness, mission score | ✅ | — |
| Proactive alerts and Intel cards | ✅ rules engine + local notifications | — |
| Quick capture parsing | ✅ rules + local model | — |
| Assistant chat | ✅ local model + tools | Cloud LLM only if **Cloud AI** is on |
| Dawn briefing / night debrief | ✅ composed locally, read out with on-device TTS | Weather (optional) |
| Sleep tracker + recommender | ✅ | — |
| Digital wellbeing + Night Shield | ✅ | — |
| Health data | ✅ Health Connect / HealthKit | — |
| Bank SMS → Ledger (Android, sideloaded build) | ✅ | — |
| Backup / restore | Encrypted before upload | Google Drive (hidden app folder) |

---

## 3. Stack

| Layer | Choice | Notes |
|-------|--------|-------|
| State / routing | `flutter_riverpod`, `go_router` | Riverpod streams wrap drift's reactive queries |
| Database | `drift` + `sqlcipher_flutter_libs` | Typed SQL, migrations, encryption at rest |
| Secrets | `flutter_secure_storage` | DB key, backup key, optional cloud API key |
| Background | `workmanager` (Android periodic, minimum 15 min), iOS `BGTaskScheduler` through the same plugin | Batch jobs: sync, rules, aggregation |
| Alarms | `android_alarm_manager_plus` / `alarm` package (AlarmManager.setAlarmClock) | Wake alarm and wind-down. Needs the exact-alarm permission. |
| Notifications | `flutter_local_notifications` | Channels in section 11 |
| Health | `health` | Health Connect (Android), HealthKit (iOS) |
| Screen time | Platform channel to `UsageStatsManager` (or community packages such as `usage_stats` / `app_usage`) | Android. iOS: section 9.4. |
| Google | `google_sign_in` + `googleapis` (calendar/v3, drive/v3) + `extension_google_sign_in_as_googleapis_auth` | No server, no client secret in the app |
| On-device AI | `flutter_gemma` (MediaPipe LLM inference, Gemma-class models), **or** Gemini Nano through ML Kit's Prompt API on supported Android phones (thin Kotlin channel) | Section 7.2 |
| Voice | `speech_to_text` (en-IN), `flutter_tts`, `record`, `just_audio` | All on-device |
| Widgets | `home_widget` | Reads a cached SITREP JSON |
| Auth (local) | `local_auth` | Vault and app unlock |
| UI | `google_fonts` (bundle the font files for offline use), `flutter_svg` | See the design handoff |

---

## 4. Data model (SQLite via drift)

**Conventions:**
- `id TEXT` (UUIDv7)
- `created_at` / `updated_at INTEGER` (epoch ms, UTC). The user's IANA time zone lives in settings.
- `deleted_at` for soft deletes
- `rev INTEGER`, used when merging a restored backup
- `origin`: one of `manual | capture | assistant | calendar | health | sms | usage`
- Money is always `amount_minor INTEGER` (paise) plus `currency TEXT`

| Table | Key columns |
|-------|-------------|
| `objectives` | title, notes, threat (crit/high/routine), status (open/done/dropped), due_at, estimate_min, tags JSON, rrule, parent_id, linked_txn_id, completed_at, carry_count |
| `blocks` | kind (event/focus/personal/task), title, starts_at, ends_at, objective_id, gcal_event_id, gcal_etag, attendees_count |
| `gcal_state` | calendar_id, sync_token, last_synced_at |
| `protocols` / `protocol_logs` | name, rrule, target, unit, window / local_date, value, done |
| `vitals_daily` | local_date, water_ml, steps, resting_hr, weight_g, workout_min |
| **`sleep_schedule`** | weekday (0=Mon…6=Sun = *the night starting that day*), bed_min (minutes after 00:00 on that day; ≥ 1440 means after midnight), wake_min (next day), enabled |
| **`sleep_sessions`** | night_of DATE, start_at, end_at, source (health/phone/manual), latency_min, awakenings, quality 0–1 |
| **`sleep_settings`** | need_min (default 435), latency_buffer_min (15), wind_down_min (30), ramp_min (10), auto_adjust_first_op BOOL, max_shift_min (20) |
| `ledger_txns` / `budgets` / `bills` | amount_minor, category, merchant, occurred_at, raw_hash UNIQUE / month, limit_minor / next_due |
| `notes` / `journal_entries` | kind, title, body, transcript, tags, pinned, embedding BLOB (optional) / local_date, mood 0–4, body |
| `focus_sessions` | objective_id, planned_sec, actual_sec, outcome, shields JSON, blocked_attempts |
| **`screen_daily`** | local_date, screen_ms, unlocks, notifications, first_pickup_at, last_use_at, after_lights_out_ms |
| **`screen_hourly`** | local_date, hour 0–23, screen_ms |
| **`app_usage_daily`** | local_date, package, category, foreground_ms, launches, notifications |
| **`app_category_map`** | package, category (social/video/messaging/work/browser/games/other), user_override BOOL |
| **`shield_rules`** | kind (night/deep_ops/limit), categories JSON, packages JSON, start_min, end_min, daily_limit_ms, action (block/grayscale/nudge) |
| `assistant_messages` / `assistant_actions` | thread, role, content JSON / tool, args, result, inverse, status, undone_at |
| `alerts` | rule, priority, fired_at, acted, dedupe_key UNIQUE |
| `settings` | callsign, tz, persona, verbosity, targets JSON, modules JSON, alert_budget, cloud_ai_enabled |

---

## 5. Engines (pure Dart, unit-tested)

All engines are **pure functions over a snapshot**: `Engine.run(Sitrep s) → Result`. No I/O. That makes them trivial to test and lets the same code run in the UI isolate, in a WorkManager isolate, and in evals.

| Engine | Input | Output | Runs |
|--------|-------|--------|------|
| `ScoreEngine` | today's objectives, protocols, focus, vitals | readiness (live), mission score (end of day) | on write, plus every 15 min |
| `RulesEngine` | SITREP | alerts `{rule, priority, dedupe_key, facts}` | every 15 min, plus on relevant writes |
| `SleepRecommender` | schedule, sessions (14 nights), tomorrow's first op, screen data | tonight's plan + weekly insights (section 8) | 20:00 daily, plus after a schedule edit |
| `ScreenAnalyzer` | usage events | daily/hourly aggregates, category totals, limit breaches, after-lights-out minutes | hourly, plus on app open |
| `CaptureParser` | text + now + tz | structured draft with confidence | on input (< 50 ms) |
| `BriefingComposer` | SITREP for the day | briefing JSON + script text | wake − 20 min |
| `DebriefComposer` | the day's data | score breakdown, carry-over, tomorrow's first objective | stand-down − 60 min |

---

## 6. SITREP: the shared snapshot

One JSON object, built by SQL in under 10 ms and cached for 60 s. It feeds the engines, the assistant, the home-screen widgets (`home_widget` reads the cached copy) and the briefing.

```json
{
  "now": "2026-10-22T18:42:00+05:30", "tz": "Asia/Kolkata", "callsign": "Chandan",
  "objectives": {"open": [{"id": "o1", "t": "Submit client deck v2", "threat": "crit", "due": "20:00", "sub": "3/5"}], "cleared_today": 3},
  "timeline_next": [{"id": "b6", "t": "Intern review sync", "start": "19:00", "end": "19:45", "attendees": 3}],
  "conflicts": [{"a": "b6", "b": "b7", "overlap_min": 15}],
  "protocols": {"done": 4, "total": 6, "at_risk": [{"name": "Workout 30 min", "missed_days": 2}]},
  "vitals": {"water_ml": 1200, "water_target": 3000, "steps": 6420},
  "sleep": {"last": {"bed": "23:48", "wake": "07:00", "asleep_min": 432}, "debt_7n_min": 123,
            "tonight": {"plan_bed": "23:00", "rec_bed": "22:40", "wake": "06:30", "wind_down": "22:10"}},
  "screen": {"today_ms": 11520000, "line_ms": 12600000, "unlocks": 64, "after_lights_out_min": 38,
             "over_limit": [{"cat": "social", "over_min": 13}]},
  "focus": {"today_min": 130, "target_min": 240},
  "ledger": {"spent_pct": 62, "pace_pct": 71, "over_pace": [{"cat": "food", "pct": 18}]},
  "prefs": {"persona": "tactical", "verbosity": "terse", "cloud_ai": false}
}
```

---

## 7. The assistant, on the device

### 7.1 Flow

```
voice ─► speech_to_text (en-IN, on device) ─► text
text ─► Router (rules + keyword classifier) ─► intent + 3–5 candidate tools
     ─► Model (local, or cloud if enabled AND intent is "hard")
        prompt = persona + rules + tool schemas (subset) + SITREP (≤ 800 tokens)
     ─► JSON tool call ─► schema validation ─► Dart tool executor (writes + inverse)
     ─► tool results ─► Model phrases reply in the response contract
     ─► number-grounding check ─► UI cards + flutter_tts speaks `speech`
```

### 7.2 Model options

| Option | Where | Strengths | Limits |
|--------|-------|-----------|--------|
| **Gemini Nano via ML Kit Prompt API** | Android system service on supported phones | No model download; managed and updated by the OS | Supported devices only. Check availability at runtime. Needs a Kotlin platform channel. |
| **Gemma-class model via `flutter_gemma`** (MediaPipe LLM inference) | Bundled or downloaded into app storage | Works on any modern phone, Android and iOS, fully offline | Download from about 0.5 GB up to a few GB; RAM and heat on long prompts. Download once over Wi-Fi and verify its SHA-256. |
| **Cloud LLM (opt-in)** | Direct HTTPS from the app with *your own* API key from secure storage | Best planning and multi-step quality | Needs a network. Data leaves the phone, so replies that used it carry a visible `CLOUD` tag. |

**Recommendation:** use the best local runtime the phone supports (Nano first, otherwise Gemma). Route only the "hard" intents (plan my day, weekly report, multi-step edits) to the cloud, and only when you've switched Cloud AI on.

### 7.3 Making a small model reliable

- **Shrink the job.** The router picks the intent and passes only 3–5 tool schemas, never all 18.
- **Constrain the output.** Ask for a single JSON object, validate it against the schema, and retry once with the validation error. Then fall back to the deterministic parser plus a clarifying question.
- **Let code do the hard parts.** Dates, times, amounts and durations are parsed by `CaptureParser`, never by the model.
- **Use templates for routine replies.** Confirmations like "Logged. Hydration 1.7 of 3.0 L." come from templates. The model only writes the replies that templates can't cover.
- **Grounding check.** Every number in a reply must exist in the SITREP or a tool result. Otherwise the app falls back to the template reply.

### 7.4 Tools (Dart functions; each write returns `{diff, inverse}`)

`objectives.create/update/complete/drop/carry_over` · `timeline.find_free_slots/block_focus/move_event*/resolve_conflict` · `protocols.log` · `vitals.log_water/log_workout/query` · `sleep.tonight/set_schedule/apply_insight` · `screen.query/arm_shield/set_limit` · `ledger.log_txn/query/mark_bill_paid*` · `notes.create/search` · `focus.start` · `reminders.set` (`*` = needs a confirm card)

### 7.5 Response contract

`{speech, text, cards[], actions[], follow_ups[], source: "local"|"cloud"}`. Card types: `diff`, `bar_chart`, `objective_list`, `confirm`, `alert`, `note_ref`, `sleep_plan`, `screen_summary`.

---

## 8. Sleep tracker and recommender

### 8.1 Data

- **Schedule:** one row per night in `sleep_schedule`. *Night of Monday* = bed on Monday evening, wake on Tuesday morning. Edited in **13b Sleep · Weekly Schedule**.
- **Sessions, in priority order:**
  1. Health Connect / HealthKit sleep sessions from any wearable or sleep app that writes them.
  2. **Phone-inferred:** the longest screen-off span overlapping the planned window, bounded by the last screen-off before it and the first unlock after it (from `UsageStatsManager` screen and keyguard events). Saved with `source = phone` and lower confidence.
  3. Manual edit from the Sleep screen.
- **Supporting signals:** screen use after the planned bedtime (from the screen analyzer), workout end times, and caffeine logs if you track them as a protocol.

### 8.2 Tonight's recommendation (deterministic)

```
plan      = sleep_schedule[tonight]
first_op  = earliest timed block tomorrow (calendar or focus)
wake      = plan.wake
if auto_adjust and first_op − prep_buffer(90) < wake:   wake = first_op − prep_buffer   # only ever earlier
debt      = max(0, Σ_{last 7 nights} (need − asleep))                                  # minutes
extra     = clamp(round_to_5(debt / 6), 0, max_shift(20))
bed       = wake − (need + latency_buffer) − extra
bed       = clamp(bed, plan.bed − 45, plan.bed + 30)                                   # no big jumps
wind_down = bed − wind_down_min(30)
```

Worked example from the canvas: need 7h15, buffer 15, debt 123 min → extra 20. Wake 06:30, so bed = 06:30 − 7h30 − 20 = **22:40**, and wind-down = **22:10**.

**ARM** schedules:
1. the wind-down notification, which mutes non-critical channels and arms Night Shield
2. the lights-out nudge
3. the wake alarm, with a gentle 10-minute ramp

### 8.3 Weekly insights (one per day surfaces on Command; all appear on the Sleep screen)

| Insight | Trigger | Suggested action |
|---------|---------|------------------|
| Weekend drift (social jet lag) | \|weekend midpoint − weekday midpoint\| > 60 min | Pull FRI/SAT halfway toward weekdays, rounded to 15 min (**APPLY** patches the schedule) |
| Inconsistent bedtime | Bedtime standard deviation over 14 nights > 45 min | Anchor the wake time and wind-down |
| Phone after lights-out | ≥ 20 min of screen use after the planned bed, on 3 or more of the last 7 nights | Arm Night Shield at wind-down |
| Late workouts | Workout ends < 2 h before bed and latency > 30 min, on 3 or more occasions | Move workouts before 20:00 |
| Chronic short sleep | Debt > 3 h | Raise the sleep need, or move first ops later |

Each insight needs a minimum sample size and carries a confidence score. Below the threshold it isn't shown.

### 8.4 Alarms

- **Android:** `AlarmManager.setAlarmClock`, which is exempt from Doze and shows the alarm icon in the status bar. On Android 14+, the exact-alarm permission isn't granted by default for new installs, so ask for it in Boot. A sideloaded alarm-style build can declare `USE_EXACT_ALARM`.
- **iOS:** AlarmKit on iOS 26+. Older versions fall back to a time-sensitive local notification with sound.

---

## 9. Digital wellbeing (Screen) and shields

### 9.1 Android data (all on the device)

| Signal | Source | Permission |
|--------|--------|------------|
| Screen time | `UsageStatsManager.queryEvents`: `SCREEN_INTERACTIVE` / `SCREEN_NON_INTERACTIVE` (API 28+) | **Usage access** (`PACKAGE_USAGE_STATS`; the user grants it in Settings, so Boot deep-links there) |
| Per-app foreground time and launches | `ACTIVITY_RESUMED` / `ACTIVITY_PAUSED` events | Usage access |
| Unlocks / pickups | `KEYGUARD_HIDDEN` events (API 28+) | Usage access |
| Notifications per app | `NotificationListenerService`, which stores **only the package and timestamp, never content** | Notification access |
| Categories | `ApplicationInfo.category`, plus your overrides in `app_category_map` | — |

The system keeps raw usage events only for a limited window, so the **ScreenAnalyzer runs hourly** (WorkManager) and on app open. It writes `screen_hourly`, `screen_daily` and `app_usage_daily`. The 7-day averages, limit breaches and *after-lights-out minutes* (screen-on time between the planned bed and the start of sleep) all come from those tables.

### 9.2 Night Shield and Deep Ops blocking

Android has no public API that lets one app block another, so for a personal build:

1. **An AccessibilityService** detects the foreground app and shows a full-screen VIGIL shield ("Deep Ops in progress · 18:24 left · OPEN ANYWAY"). This is the most reliable option. Google Play restricts AccessibilityService use, but a sideloaded build is fine.
2. **Overlay fallback:** poll the foreground app through usage events and draw a `SYSTEM_ALERT_WINDOW` overlay. It works but lags.
3. **Do Not Disturb:** `NotificationManager.setInterruptionFilter`, which needs notification-policy access.
4. **Grayscale (optional, power users):** a third-party app can't switch on grayscale by itself. On your own phone you can grant `WRITE_SECURE_SETTINGS` once over adb, and VIGIL can then toggle the system grayscale filter during Night Shield.

Blocked attempts are counted in `focus_sessions.blocked_attempts` and shown in the night debrief.

### 9.3 Limits

Category limits (for example social 45 m, video 45 m) live in `shield_rules`. At 80 % VIGIL sends a nudge; at 100 % it shields with a one-time **+10 MIN** override. The override is logged.

### 9.4 iOS

Apple's Screen Time API (FamilyControls with individual authorization, DeviceActivity and ManagedSettings) can **shield apps and categories** and fire threshold events. Detailed usage numbers are rendered inside a **DeviceActivityReport extension** and can't be freely read back into the app. On iOS, the Screen tab therefore embeds the report extension, and Night Shield uses ManagedSettings. Cross-feature signals such as phone-after-lights-out are coarser there. This needs the Family Controls entitlement from Apple.

---

## 10. Google, directly from the app

| Service | Scope (narrowest that works) | Use |
|---------|------------------------------|-----|
| Sign-in | `openid email profile` | Identity for Google APIs only. VIGIL has no account system of its own. |
| Calendar | `calendar.events` | Read events, write focus blocks. VIGIL blocks are tagged with `extendedProperties.private.vigil=1` and a fixed `colorId`. (A separate "VIGIL Ops" calendar would need the broader `calendar` scope.) |
| Drive | `drive.appdata` | Nightly backup into the hidden app folder. VIGIL can't see your other Drive files. |

**Calendar sync** (no push channels, since those need a server):
- on app open, every 30 min via WorkManager, and right after a VIGIL write
- incremental `syncToken`; a `410 Gone` triggers a full resync
- conflicts are detected locally

**Backup:**
- At 03:00 (only while charging and on Wi-Fi), VIGIL snapshots the SQLite file, encrypts it with AES-256-GCM using a key derived from your **backup passphrase** (Argon2id), and uploads it as `vigil-YYYYMMDD.vgb`.
- It keeps the last 7 snapshots. Restore lives in Boot ("Restore from Drive").

**OAuth project:** a personal Google Cloud project in *Testing* mode with yourself as the test user is fine. Plan for an occasional re-consent prompt, since Google limits token lifetime for unverified apps in testing.

---

## 11. Background work and notifications

| Job | Android | iOS |
|-----|---------|-----|
| `ops-tick`: rules, readiness, widget cache | WorkManager periodic, 15 min | BGAppRefresh (opportunistic) + on app open |
| `screen-aggregate` | WorkManager hourly | DeviceActivity threshold events |
| `calendar-sync` | WorkManager 30 min, network-constrained | BGAppRefresh + on open |
| `briefing-compose` | One-off work at wake − 20 min, plus an exact alarm at wake to post it | Composed on the first open after wake; notification pre-scheduled |
| `debrief-compose` | One-off at stand-down − 60 min | Pre-scheduled notification; composed on open |
| `backup` | Daily at 03:00, charging + unmetered | BGProcessingTask, charging |

**Timed, user-visible events** (next-op reminders, deadlines, wind-down, wake) are scheduled ahead as exact notifications (`zonedSchedule`, exact while idle). Reschedule on every relevant write. iOS caps pending local notifications at 64, so schedule only the next 24 h.

**Android channels:** `critical` (high importance), `ops`, `protocols`, `sleep`, `screen`, `ledger`, `briefings` (low importance, with a media action).

**Rules engine (all on the device):**

| Rule | Fires when | Priority |
|------|-----------|----------|
| `next_op` | An event starts in 15 min | routine |
| `deadline_t60` | A crit objective is due in ≤ 60 min, open, with no Deep Ops session running | **critical** |
| `hydration_pace` | Water is ≥ 500 ml behind the linear target, between wake+2h and bed−2h | routine |
| `conflict` | Blocks overlap in the next 24 h | high |
| `streak_risk` | A protocol was missed ≥ 2 days, or today's window closes within 2 h | high |
| `bill_due` | A bill is due today or tomorrow and unpaid | high |
| `budget_pace` | A category's spent % exceeds month pace % by 15 points or more (checked at 20:00) | routine |
| `wind_down` | 30 min before tonight's recommended bed | routine (`sleep` channel) |
| `screen_limit` | A category reaches 80 % (nudge) or 100 % (shield) of its line | routine |
| `phone_after_lights_out` | Screen on for 10 min or more after the planned bed | routine (once a night) |
| `focus_end` | A Deep Ops session ends or a break is due | routine |

**Alert budget:**
- At most `settings.alert_budget` proactive nudges a day (default 6). `next_op`, `focus_end` and critical alerts don't count.
- At least 45 min between nudges.
- Quiet hours run from bed to wake, and only critical alerts break through.
- During Deep Ops, only critical alerts and starred contacts get through.
- Every alert has a dedupe key of rule + entity + local date.
- If a rule is dismissed 3 times in a row, its frequency halves, and the night debrief says so.
- The model only phrases `facts`. An offline template is always available.

---

## 12. Security and privacy

- The SQLCipher key is generated on first launch and stored in Keystore/Keychain. The Vault (Ledger + Field Log) is gated by `local_auth`.
- **No analytics by default.** Crash reporting is opt-in.
- Cloud AI is off by default. When it's on, only the SITREP and the current request are sent, never the journal. Replies that used it are tagged.
- Backups are encrypted before upload, and the passphrase never leaves the phone.
- **Export** (JSON + CSV zip, through the share sheet) and **Erase all** (wipes the DB, keys and the Drive app folder) both live in Loadout.

---

## 13. Scores (unchanged from v1)

`score = round(35·O + 25·P + 20·F + 20·V)`, with threat weights crit 3 · high 2 · routine 1. Readiness uses the same components divided by the expected progress at the current time. One Dart module, shared by the Command ring, the widgets and the debrief.

---

## 14. Performance and battery targets

| Metric | Target |
|--------|--------|
| Cold start → Command rendered | < 1.5 s |
| Local query / write → UI | < 16 ms |
| Capture parse | < 50 ms |
| Local model, first token (prompt ≤ 1k tokens, recent mid/high-end phone) | < 1.5 s |
| Screen aggregation job | < 2 s |
| Background battery cost | < 3 % / day |
| Model memory while loaded | < 1.5 GB; unload after 60 s idle |

---

## 15. Testing and quality loop

- **Engines:** pure Dart unit tests with fixture SITREPs (scores, rules, sleep recommender, screen analyzer, capture parser), including time-zone and DST edge cases and nights that cross midnight.
- **Assistant golden set:** 150 or more utterances (English, Hinglish, relative dates, amounts, multi-intent, ambiguous, consequential). They run in `integration_test` on an emulator with the same local model, and against the cloud model when it's enabled.
  - Gates: tool accuracy ≥ 95 % local for routed intents, date resolution ≥ 99 %, zero ungrounded numbers.
- **On-device review:** an "Assistant log" in Loadout lists undone, failed and repaired turns, so you can export them and add them to the golden set.

---

## 16. Build roadmap

| Phase | Scope | Done when |
|-------|-------|-----------|
| **0 · Core** | All screens on drift/SQLCipher, engines, local notifications, capture rules parser, Deep Ops timer | Usable daily, fully offline |
| **1 · Bridges** | Health Connect, usage access + notification listener, ScreenAnalyzer, sleep sessions + recommender, alarms | Sleep and Screen screens show real data |
| **2 · Google** | Sign-in, Calendar sync + focus blocks, Drive backup/restore | A round trip to Calendar; restore onto a second phone |
| **3 · Assistant** | Router, local model, tools + undo, response contract, optional cloud | Golden set gates pass |
| **4 · Shields + polish** | Night Shield / Deep Ops blocking, limits, home widgets, iOS port | Two weeks of daily use without a manual fix |

---

## 17. Open decisions

1. **Local model:** Gemini Nano (if your phone supports it) or a downloaded Gemma-class model.
2. **Distribution:** sideload (SMS ledger, accessibility shield and exact alarms all available) or Play Store (manual ledger, overlay-only shield).
3. **iOS:** whether it's in scope for v1. The Screen Time limits in 9.4 apply.
4. **Backup passphrase UX:** separate from the device unlock (recommended) or derived from it.

---

## Appendix — packages

`flutter_riverpod`, `go_router`, `drift`, `sqlcipher_flutter_libs`, `flutter_secure_storage`, `local_auth`, `workmanager`, `android_alarm_manager_plus` / `alarm`, `flutter_local_notifications`, `health`, `home_widget`, `google_sign_in`, `googleapis`, `extension_google_sign_in_as_googleapis_auth`, `flutter_gemma`, `speech_to_text`, `flutter_tts`, `record`, `just_audio`, `google_fonts`, `flutter_svg`, `intl`, `cryptography` (AES-GCM, Argon2id). Platform channels (Kotlin) cover UsageStatsManager, NotificationListenerService, the AccessibilityService shield and the ML Kit Prompt API.