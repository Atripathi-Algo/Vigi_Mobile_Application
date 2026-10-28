# K redesign: decisions and build plan

Source of truth: the Claude Design canvas (70 screens). Its visible text is saved in `docs/design/K_DESIGN_TEXT.md`.
The app is renamed **K** in the UI only: package id `com.algoanalytics.vigil`, repo name and stored data do not change.

## Decisions (from the owner)

| Topic | Decision |
|---|---|
| Firebase push | Dropped. Reminders use local scheduled notifications. The Loadout row is removed |
| Bank SMS parser | Kept in Loadout > Links, restyled |
| Accent swatches | Removed. Thor is the only theme |
| K actions | 9 actions: the existing 7 plus `log_fill_up` and `move_event`. Still one change per reply, always undoable |
| Cloud AI | Open chat only. Commands and the user's own data never leave the phone |
| Drive backup | Includes Garage data (bikes, fill-ups, reminders) |
| Calendar picker | Needs a read-only calendar-list scope (one-time re-consent) |
| Usage access | Not decided. Default: keep the row, build the bridge in the last phase |

## Phases

1. **Foundation**: rename in the UI, Thor-only theme and tokens (`k.css` values), fonts, splash, icon, notification channels, widget titles, nickname and full name.
2. **Setup guide**: 7 steps plus 4 error screens, restore-from-Drive, re-open from Loadout.
3. **K screen**: source tags, streaming, loading, asleep, warm dot, fallback notes, composer states, 9 actions, Cloud limited to open chat, 50-prompt accuracy check.
4. **Drive**: auto-sync, Wi-Fi only, conflict dialog, status chip, delete backup.
5. **Ops**: Timeline (hour grid, account filter, event detail, read-only Google events), Garage (bikes, fill-ups, mileage, reminders), swipe complete and delete, Deep Ops sessions.
6. **Protocols and Vault**: per-protocol reminders and days, body screen, budget alert and roll-over, bills actions, notes, biometric or PIN unlock.
7. **Loadout, notifications, briefings**: settings parity, notification inbox, dawn and night screens, widgets, sounds and haptics, thunder effects.
8. **Usage access bridge** (if kept), real-phone checks, release.

## Status

- Phase 1 (theme, name, K mark) and Phase 2 (setup guide): done and pushed (efd673e).
- Phase 3 (K screen): done. Source tags with timing, streaming with Cancel, waking and asleep states, first-run block, microphone card, Cloud for open chat only (no app data sent), `move_event` (rules and agent; not offered to the model). `log_fill_up` waits for the Garage (Phase 5). The 50-prompt accuracy check is still the 24-prompt one.

- Phase 4 (Drive): done in code and unit tests (fake Drive, two phones, conflicts, merge, Wi-Fi only, lapsed approval). Auto-sync a few seconds after a change (at most once a minute, only when something really changed), checks Drive when the app opens or resumes, takes newer data from another phone when this phone has no changes, and asks (Merge / Keep this phone / Use Drive) when both changed. The chat log is now saved and part of the backup. **Not verified against a real Google account**: sign-in, Drive consent and the real Drive API need a phone and your account. Sync runs only while the app is open; changes made while it is closed are sent the next time it opens.

- Phase 5 (Ops): the **Garage** is done: up to two bikes, fill-ups (counted in Vault > Transport, with Undo), mileage between full tanks, cost per km, range left, reminders by km, date or both (insurance and PUC by "valid till" date) that become Ops objectives when due, and K: `log_fill_up` by rule ("filled 10 litres in the Meteor for 1050 at 9412") and bike questions answered from the Garage. Swipe left on an objective now deletes with Undo (as in the design); Reschedule moved into the objective's detail sheet. **Not done yet**: the Timeline's account filter, event detail with "Remind me 30 min before", and Deep Ops session history.

Each phase ends with `flutter analyze`, `flutter test`, an emulator check and a commit. Pushes are asked for each time.
