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
| `GOOGLE_CLIENT_ID` | Future Google sign-in (private Calendar, Drive backup) |
| `GOOGLE_CALENDAR_API_KEY`, `GOOGLE_CALENDAR_ID` | Today's events from a **public** calendar (full calendar id, not `primary`) |
| `WEATHER_API_BASE_URL`, `WEATHER_LATITUDE`, `WEATHER_LONGITUDE` | Dawn Briefing conditions (Open-Meteo, no key) |
| `CLOUD_AI_PROVIDER` (`anthropic`\|`openai`), `CLOUD_AI_BASE_URL`, `CLOUD_AI_MODEL`, `CLOUD_AI_API_KEY` | Cloud answers in Uplink, enabled in Loadout. Blank model/base URL use the provider default |
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
lib/api        weather, calendar, cloud AI clients
lib/services   notifications, Firebase push, step sensor, home widgets, output sync
lib/screens    the 16 screens
lib/vigil      design system from the handoff
android/       manifest, widget providers and layouts (Kotlin)
```

## Status

Built: all screens and routes, design system, local persistence (SharedPreferences) with day rollover, capture parser, readiness and sleep recommender, rules-based assistant, env-driven weather, calendar and cloud AI calls, local notifications, optional Firebase push, step counter, home-screen widgets.

Not built: Health Connect, usage stats, wake alarm, biometric lock, voice (STT/TTS), Google sign-in and Drive backup, encrypted SQLite, per-app limits. Screens that depend on them show sample data and say so.
