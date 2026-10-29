# K revamp plan (audit + design handoff)

Sources (saved in `docs/design/`): `K_AUDIT.txt` (the usability audit, 28 Oct 2026) and `K_DESIGN_HANDOFF.md` (the build spec for the design canvas: Storm violet, 115 artboards). Standing rules: free services only, real data only, ask before each push, no secrets or APKs in git.

## Decisions (29 Oct 2026)

| Question | Decision |
|---|---|
| Look | **Storm violet, Light default**, Dark and System in Settings. Replaces the earlier "Thor navy, dark only" rule. Fonts: Sora (headings, numbers), Inter (UI), IBM Plex Mono (logs only). |
| Navigation | **5 tabs, plain names**: Today (was Command), Plan (Ops), K (raised octagon), Habits (Protocols), Money (Vault); Settings (was Loadout). Every handoff screen maps 1:1. |
| Extras | All four chosen: bike photos with on-device cut-out; all 7 home-screen widgets; quick-add + search + weekly review; keep Screen time and Bank SMS (the audit wanted them cut). |
| Trust fixes first | Yes: done as phase R0, pushed separately. |

Assumptions to confirm as we go:
- Setup: the audit wants 4 steps, the handoff draws 9 screens. Plan: 4 core steps (name, modules, one guided command, done), with the handoff's microphone, Health, brain and voice screens shown as in-context rationale sheets the first time they are needed.
- Bank SMS parser stays, off by default, and is labelled as sideload-only; Play Store builds would have to drop it.
- Release signing: the audit says builds use the debug key. A new keystore would stop updates installing over the current app, so it is **not** changed until you decide (it needs an uninstall once, which clears local data unless Drive backup is on).
- `.env` is still bundled. For any APK shared with others, build with `.env.example` copied to `.env` so no keys ship.

## Phases

| Phase | What | Gate |
|---|---|---|
| R0 | Trust fixes (below) | tests pass, emulator check |
| R1 | Design system: `KColors` light/dark, gradients, shapes, bundled fonts, Appearance setting, rebuilt components (pill buttons, cards, chips, tags, sheets, snackbar, banners, skeletons, empty states) | components board matches the canvas; contrast checks |
| R2 | Shell: 5 plain-named tabs, raised K octagon, route transitions (fade-through, shared axis), top bar | every route reachable; reduced-motion respected |
| R3 | Setup (4 steps + rationale sheets), splash | first run on a clean emulator |
| R4 | Today and K: hero card, quick-add bar, suggestion chips, Confirm/Cancel buttons, plain source tags (Instant, From your data, On-device AI, Cloud), orb states, diff chips with Redo | K flow on emulator |
| R5 | Plan (tasks + timeline merged, due-time markers), Habits and Health, Money, Garage (two bikes, photos, cut-out), Notifications, briefings, Settings regrouped in 5 sections | each screen vs canvas |
| R6 | Motion and sound: spark burst, lightning v2, glass layers, rolling numbers, Effects Full / Subtle / Off, paired haptics; 7 widgets; weekly review, search | profiling on the Oppo Reno 8 in release mode |
| R7 | Real-phone verification (speed, sounds, fingerprint, widgets, Google/Drive) | your sign-off |

## R0: trust fixes (audit "blockers")

| Audit item | Fix |
|---|---|
| Android auto-backup copies all app data to Google | `android:allowBackup="false"` |
| Speech goes to the network recogniser | `onDevice: true` by default, no fallback; a clear message when the offline pack is missing |
| Notes screen said "ENCRYPTED" | Label now "STORED ON THIS PHONE" (real encryption is a later step) |
| Cloud "test connection" sent the full sitrep | Sends nothing but the test question |
| Cloud chat history included on-device replies | Only earlier cloud answers are sent |
| Settings copy said it sends the sitrep | Copy now says it sends only the question |
| Mic copy promised on-device speech | Copy updated to match (offline pack needed) |

Not done in R0 (needs your call or a later phase): release keystore, real encryption of notes and money, weather default city, `.env` bundling.

## Status

- **R0** done and pushed (b6a1933).
- **R1** done (design system): Storm violet tokens for Light (default) and Dark (`VigilColors.light/dark`, gradients, icon tiles), Sora / Inter / IBM Plex Mono bundled in `assets/fonts` (OFL, no network fetch), rounded shapes (cards 18, sheets 26, dialogs 22, fields 14, pills), restyled button, icon button, K octagon, card, hot-card edge (the old corner brackets), section label, progress bar, checkbox, switch, segmented control, filter chip, threat tag, nav bar (pill indicator, rounded top), snackbar always dark. Settings has Appearance: Light / Dark / System. Checked on the emulator in both themes; 285 tests pass. **Left for the next phases**: nav labels are still the old names (R2); screens still write many labels in capitals and several draw more than one hot card (R4/R5); screens that draw their own boxes keep their old look until rebuilt; the grid background is gone from every screen; the splash, launcher icon and widgets are still the old navy (R3, R6).
- **R2** done (shell): 5 plain-named tabs (Today, Plan, K, Habits, Money), Settings instead of Loadout, sub-tabs Tasks / Timeline / Garage, Habits / Health / Screen time, Budget / Journal, priority Urgent / High / Normal, K badge in tab top bars, fade-through between sub-tabs and a short slide-and-fade between tabs (both off with reduce-motion), K's chat names updated. Checked on the emulator (dark theme); 285 tests pass. **Left**: many row sub-labels are still in capitals (filter chips, due lines, subtitles); route paths and internal ids keep the old names on purpose; Garage stays under Plan until the Track restructure is decided.
