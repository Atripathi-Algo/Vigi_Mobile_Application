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

Each phase ends with `flutter analyze`, `flutter test`, an emulator check and a commit. Pushes are asked for each time.
