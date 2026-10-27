# VIGIL

Personal daily-ops companion for Abhishek ("Batman"). Flutter (Android first), dark only, on-device first.
Design source: `docs/HANDOFF.md`. Architecture: `docs/VIGIL-Architecture-Spec.md` and the interactive diagram `docs/architecture.html`.

## Run

```bash
flutter pub get
cp .env.example .env      # then fill in the keys you need
flutter run
```

`.env` is a bundled asset, so the build fails without the file. Copying the example is enough; every key is optional.

## Build the APK

```bash
flutter build apk --release --split-per-abi
# build/app/outputs/flutter-apk/app-arm64-v8a-release.apk   <- phones (Oppo Reno 8 5G)
# build/app/outputs/flutter-apk/app-x86_64-release.apk      <- emulator
```

Needs Flutter 3.27+, JDK 17 and the Android SDK (platform 36, build-tools 36). The release build is signed with the debug key; create a keystore before any Play Store upload. Code shrinking is off because R8 breaks `shared_preferences_android`.

Install on a phone with USB debugging: `adb install -r app-arm64-v8a-release.apk`, or copy the file to the phone and open it.

## Configuration (`.env`)

All keys are optional. A blank value switches that feature off and the app stays fully on-device.

| Key | Used for |
|-----|----------|
| `VIGIL_API_BASE_URL`, `VIGIL_API_KEY` | Optional backend (reserved, not called yet) |
| `GOOGLE_CALENDAR_API_KEY`, `GOOGLE_CALENDAR_ID` | Today's events from a **public** calendar (full calendar id, not `primary`). For private calendars link Google accounts instead (below) |
| `WEATHER_API_BASE_URL`, `WEATHER_LATITUDE`, `WEATHER_LONGITUDE` | Dawn Briefing conditions (Open-Meteo, no key) |
| `CLOUD_AI_PROVIDER` (`gemini` free tier \| `openai` for Groq/OpenRouter/Ollama \| `anthropic` paid), `CLOUD_AI_BASE_URL`, `CLOUD_AI_MODEL`, `CLOUD_AI_API_KEY` | Cloud answers in Uplink, enabled in Loadout. Default provider is Gemini (model `gemini-flash-latest`). The Gemini free tier lets Google use what you send to improve its products |
| `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_STORAGE_BUCKET` | Firebase Cloud Messaging push. No `google-services.json` needed |

`.env` is bundled into the APK, so anyone with the APK can read it. Do not put production secrets in it. Rebuild after editing.

### Firebase push

1. Firebase console, create a project, add an Android app with package `com.algoanalytics.vigil`.
2. Copy the API key, App ID, Sender ID and Project ID from Project settings into `.env`.
3. Rebuild, open Loadout, and tap **Firebase push** to copy the device token.
4. Cloud Messaging in the console, send a test message to that token.

Local notifications work without any of this.

## Notifications, widgets, steps

- **Notifications:** seven channels from the handoff. Reminders (due in 30 min, next op in 15 min, streak at risk, wind-down, dawn briefing, night debrief) are re-armed after every change, capped at six proactive nudges a day. Grant the permission in Boot or Loadout.
- **Home widgets:** long-press the home screen, Widgets, VIGIL. *Objectives* (4×2) shows the next op, three objectives, steps and water; tap an objective to check it off or **+250 ML** to log water without opening the app. *Readiness* (2×2) shows the score and a water button.
- **Steps:** read from the phone's built-in step counter after the Physical activity permission.

### Oppo / ColorOS

ColorOS stops background apps aggressively. For reliable reminders and widget updates: Settings, Apps, VIGIL, Battery, allow background activity and auto-start (Loadout has a shortcut to the app's settings), and allow Alarms & reminders for exact times.

## Layout

```
lib/app        env, formatting, providers, router, shell
lib/data       store, models, capture parser, assistant
lib/api        weather, calendar, cloud AI clients, model catalog
lib/services   notifications, Firebase push, step sensor, home widgets, output sync, Google accounts, calendar sync
lib/screens    the 16 screens
lib/vigil      design system from the handoff
android/       manifest, widget providers and layouts, Google sign-in bridge (Kotlin)
```

## Status

Built: all screens and routes, design system, local persistence (SharedPreferences) with day rollover, capture parser, readiness and sleep recommender, rules-based assistant, env-driven weather, calendar and cloud AI calls, local notifications, optional Firebase push, step counter, home-screen widgets, API keys screen, **model picker with cost badges, two linked Google accounts (calendar read and add)**, **Health Connect sleep, weight and resting heart rate (read-only) with manual logging as a fallback**.

Not built: usage stats (so the Screen tab says "No data"), wake alarm, biometric lock, voice (STT/TTS), encrypted SQLite, per-app limits.

### Choosing a model (Loadout, API keys & services, Cloud AI)

The arrow on the Model field opens a list with a cost badge on every model: **green** FREE (a free tier, rate limited) or CHEAP (paid, up to $1.50 per 1M output tokens), **amber** PAID (up to $10), **red** PREMIUM (above $10), grey UNRATED (price not known). Picking anything that is not free asks you to confirm first. The list is curated, with prices as published around October 2026; they change, so check the provider. **Load live list** asks the service which models your key can use (OpenRouter's list includes real prices, so those are rated exactly). Each service keeps its own key, so switching service never sends one company's key to another.

### Google accounts (Loadout, Google accounts)

Link up to two accounts (PERSONAL and WORK). Their calendars merge into the Timeline with a tag on each event, a meeting that is in both shows once, and an overlap between the two is flagged as a conflict naming both. Tap an event you made in VIGIL to add it to either calendar. VIGIL asks Google only for calendar events.

It uses Google's own Android authorization, so **no secret or redirect is stored in the app**: the phone keeps the approval and VIGIL asks for a short-lived token each time. Google only lets an app do this once its owner registers it (free, about five minutes):

1. [console.cloud.google.com](https://console.cloud.google.com): create a project.
2. APIs & Services, Library: enable **Google Calendar API**.
3. OAuth consent screen: user type External, add both Gmail addresses as **Test users**.
4. Credentials, Create credentials, OAuth client ID, type **Android**. The package name (`com.algoanalytics.vigil`) and this build's SHA-1 are on the Google accounts screen, with copy buttons. A build signed with a different key has a different SHA-1: add it to the same client.
5. Open Loadout, Google accounts, Link account.

While the consent screen is in Testing, Google asks you to approve again every 7 days (the screen then shows APPROVE AGAIN). Set the publishing status to **In production** to stop that; Google shows an "unverified app" screen once, which is fine for your own use (limit 100 users). Needs Google Play services on the phone. Not verified against a live Google account yet.

### K's on-device brain (Loadout, K brain)

K runs MiniCPM5-1B on the phone (llama.cpp, CPU, no key, no network, no cost). Download the model once from the K brain screen (Q4_K_M 688 MB, or Q8_0 1.15 GB for more accuracy); K then answers in plain language, can add and log things, and falls back to the keyword router if the model is missing or fails. The model is loaded only when asked and released after a short idle time, so it costs nothing in the background. Cloud AI is optional and only used if you switch it on. The research, quantization options, accuracy and battery design, and what is still unverified are in [docs/LOCAL_AI_PLAN.md](docs/LOCAL_AI_PLAN.md). Builds now target arm64 and x86_64 only (`--target-platform android-arm64,android-x64`).

Signal themes include **Thor** (storm navy, lightning blue, lightning on the orb). The assistant is named **K**.

### Assistant and voice (Uplink)

With Cloud AI on (Loadout) and a key set, a language model handles requests in plain language, remembers the last 10 messages, and can add objectives and events, log water and spend, add notes, clear an objective or check a protocol. Every change shows a diff card with Undo, and the model has no way to delete or send anything. If the chosen Gemini model is refused (402, 404, 429, 503) the app retries on free Gemini models only and says which answered. Without a key, or if the call fails, the on-device router answers.

Tap the orb or the mic to speak; replies are read aloud (always for spoken requests, and for typed ones when Spoken replies is on). Hands-free listens again after each spoken reply. Speech uses the phone's own recogniser (free; it may use the network unless an offline language pack is installed) and the phone's text-to-speech voice. There is no always-on "Hey Vigil" wake word. Voice is not yet verified with a real microphone.

### Real data only

The app starts empty and shows only what you log, what your calendars return, or what a sensor reports. Add protocols (+ on Protocols), bills (+ in the Ledger) and a monthly budget (Ledger, Set budget); log spend and objectives with Capture. Long-press a protocol or bill to delete it. Sample data from builds up to v1.3 is removed once on first launch of a newer build; your own entries stay.

### Google Drive backup (Loadout, Google Drive backup)

Needs a linked Google account (above) and the **Google Drive API** enabled in the same Cloud project. Back up and restore use a private app folder on that account's Drive: one file, invisible in your Drive and to other apps (scope `drive.appdata`). It holds objectives, protocols, ledger, notes, sleep and settings, never API keys or linked accounts. Restore asks first, checks the file before erasing anything, and is also on the first-run screen. Google asks you to approve Drive once. Not verified against a live Google account yet.

### Sleep and body data

- **Health Connect** is free and on-device. It only holds what other apps write, so you need a watch, band or sleep app that writes to it. On Android 13 and older, install the Health Connect app from the Play Store first (Android 14+ has it built in).
- **No watch?** Use **Log night** on the Sleep tracker and **Log weight** on Vitals. Manual entries win over Health Connect for the same night.
- Averages and debt appear after 3 nights, as in the handoff.
