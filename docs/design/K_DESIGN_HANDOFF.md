
# K — Design handoff
 · 
## Overview
K is a personal-ops Android app for one person: objectives, habits, money and two bikes, run with an on-device assistant also called K. This handoff is the build spec for the Flutter app, and every value in it matches the (https://claude.ai/artifact/N8h1uvw3B73VAdHwaTBeDL) K design canvas: 115 artboards on 17 pages.
Theme: Light is the default. Dark and System sit in Loadout › Appearance › Theme.
Frame: 360 × 800 dp phone (1080 × 2400 px at 3×), Android 10+, gesture or 3-button navigation. Also drawn at 430 × 932 dp, as a tablet column and with text at 200 %.
Assistant: an on-device model (MiniCPM5-1B, Q4_K_M, 688 MB), offline and free. A cloud model is optional and uses the user's own API key.
Data: lives on the phone and backs up to the user's own Google Drive as k-backup.json. The app ships with zero sample data, so every screen has an empty state.
Look: Storm violet. Rounded cards, pill controls and gradient icon tiles; the Thor marks are the K octagon with its bolt, lightning watermarks, storm clouds and arcs around the orb.
On the canvas, every phone artboard has a Theme tweak (Light / Dark) and a Motion tweak (off = Reduce Motion). Screen names below are the canvas artboard names; Command means Command.dc.html.
## Screen inventory
There are 82 phone screens plus 7 surfaces (widgets, splash, notifications, icon); each area's empty, loading, error and permission states are drawn as their own artboards.
Area (canvas page)
Screens
States drawn
Setup (A)
Welcome · Name, clock, currency · Sign in with Google · Restore your data · K's brain download · Microphone · Health Connect (optional) · Voice & sound · Ready
No Wi-Fi · download interrupted · sign-in cancelled or failed · permission denied
Command (B)
Command (evening)
Day one with zero data · first sync with skeletons · offline
K assistant
First run · thread with diff chips · listening · thinking and streaming · speaking (hands-free) · cloud answer
Waking (cold start) · brain asleep · model not installed · mic permission or voice unavailable · fallbacks and system notes
Ops (C)
Objectives by threat · capture sheet · timeline (two calendars) · event detail · deep ops timer
Empty · calendar sync failed
Garage (C+)
Garage (two bikes) · Meteor 350 · Avenger Street 150 · log fill-up · service reminder · add bike
Empty · insurance overdue
Protocols (D)
Protocols · add protocol · water · steps, sleep, weight, heart
Empty · weight needs permission
Vault (E)
Budget and spend · add expense · bills · notes · set budget
Locked · empty · bill overdue
Alerts and briefings (F–G)
Notifications · dawn briefing · night debrief
Empty
Loadout and K brain (H–I)
Loadout (two scrolls) · K brain · speed test and accuracy check
Cloud key error · erase all confirm · model downloading
Google and Drive (J)
Google accounts · Drive backup
Sync conflict · delete backup confirm
Surfaces (W)
Home screen with widgets · widget picker · Garage widget setup · widget library · splash · notification style · app icon
Every widget state, on the widget library board
System sheets (L)
Confirm delete · add bill · date picker · time picker (24 h) · permission rationale
Offline banner · error toast · undo snackbar
Android behaviours and sizes
Pull to refresh · long-press menu · back from background
Battery Saver · permission revoked · 430 × 932 dp · tablet column · text at 200 %
The Dark theme page repeats 16 key screens in dark. The component library (3 boards) and Motion & sound (4 boards) pages are the specs behind them.
## Colour tokens
Every colour is a named token with a light (default) and a dark value; screens never hard-code a colour. In Flutter, build one ThemeExtension<KColors> with a light and a dark instance and pick it from Loadout › Appearance.
Token
Light (default)
Dark
Used for
bg
#F3F4FA
#060716
App background
card
#FFFFFF
#0D1029
Cards, fields, bubbles
raised
#FFFFFF
#141838
Sheets, dialogs, diff chips
raised-2
#ECEEF8
#1B2048
Pressed rows, tracks
line
rgba(52,56,140,.12)
rgba(132,146,255,.13)
Hairlines, card edges
line-2
rgba(52,56,140,.22)
rgba(132,146,255,.26)
Field, chip and pill outlines
signal
#2F5FE0
#4F8BFF
Progress, links, Instant source
signal-2
#2B4FCC
#A3C0FF
Signal-coloured text
violet
#6A3CF0
#9D6BFF
K, focus ring, on-device AI
magenta
#A51DB8
#E25CFF
Orb core, unread dot, live mic
ice
#191B3D
#DCE6FF
Big readouts
text
#14162E
#EEF1FF
Primary text
text-2
#474C6B
#A9B1D6
Secondary text, body copy
text-3
#62678A
#7D86B2
Labels, metadata (lowest tier)
critical
#C21D43
#FF5C72
CRIT threat, overdue, destructive
warning
#9A5700
#FFB547
HIGH threat, system notes, Cloud
success
#05735A
#3BE3B6
Synced, applied, from your data
cal-a
#3B5BDB
#DCE6FF
Google account 1 (Personal)
cal-b
#8B3FD9
#B18CFF
Google account 2 (Work)
Same in both themes
Primary gradient: 135°, #2759F0 0 % → #6D3CF5 60 % → #8A3CF0 100 %. Primary buttons, mic, switches on, active segment. White text on it measures 5.3–5.8 : 1.
Soft gradient: 135° from signal to violet at 14–17 % (light) or 22–24 % (dark). Selected chips, nav pill, hands-free on.
Hot border: a 1 dp gradient edge from signal through violet to magenta, on the one hot card per screen, with a faint bolt watermark in its corner.
Orb plasma: radial #FFFFFF 0 % → #F0ABFC 14 % → #C026D3 32 % → #6D28D9 56 % → #1E1B4B 78 %.
K octagon badge: #1B1658 fill, #9C8CFF edge, white K. It stays dark on light screens.
Snackbar: stays dark in light (#1C1F45, text #F1F2FF at 14.2 : 1).
Icon tiles (40 dp, radius 12; small 32 dp, radius 10; white glyph, always beside a text label):
Tile
Gradient (135°)
Used for
b
#3B82F6 → #2563EB
Ops, calendar
v
#A855F7 → #6D28D9
K, deep ops
c
#22D3EE → #0E7490
Water, protocols
g
#34D399 → #047857
Done, health
o
#FB923C → #C2410C
Spend, bikes
m
#E879F9 → #A21CAF
Briefings, notes
r
#FB7185 → #BE123C
Critical, delete
Contrast (every text tier passes WCAG AA):
Light, on white · bg · raised-2: text 17.7 · 16.2 · 15.3; text-2 8.4 · 7.6 · 7.2; text-3 5.5 · 5.0 · 4.7; signal-2 6.8 · 6.2 · 5.9; violet 6.0 · 5.4 · 5.2; critical 5.9 · 5.4 · 5.1; warning 5.6 · 5.1 · 4.9; success 5.8 · 5.3 · 5.0.
Dark, on bg · card · raised: text 17.8 · 16.6 · 15.3; text-2 9.5 · 8.9 · 8.2; text-3 5.6 · 5.3 · 4.9; critical 6.7 · 6.3; warning 11.4; success 12.2.
## Type, spacing, shape and frame
Three families: Sora for headings and numbers, Inter for UI text, IBM Plex Mono only for timestamps, logs and file names. All sizes are sp; the floors are 13 for body and 10 for labels.
Style
Size / line
Family, weight
Notes
H0
40 / 42
Sora 600
−2 % tracking
H1
26 / 31
Sora 600
−1.5 %; screen greeting, "Evening, {nickname}."
H2
19 / 24
Sora 600
Sheet and dialog titles
H3
15.5 / 20
Sora 600
Card titles
Body
14.5 / 22
Inter 400
Small
13 / 19
Inter 400
Caption
12 / 17
Inter 400
Label
11.5 / 15
Inter 600
Sentence case
Nav
10.5 / 10.5
Inter 500
Hidden above 160 % text; icons keep TalkBack names
Readout
20–34
Sora 600, tabular
−2 %; odometer, km/l, T−00:48:12
Tag
10 / 10
Inter 700, caps, +8 %
Threat and source tags only, always with an icon
Mono
11–13
IBM Plex Mono 500
Log lines, model files (Q4_K_M)
Spacing is a 4-point scale: 4 hairline · 8 chip gaps · 12 card stack · 16 gutter and card padding (12 tight) · 20 button padding · 24 sheet sections · 28 status inset · 40 sheet bottom · 48 touch target.
Shape:
Element
Radius (dp)
Cards
18 (small tiles 16)
Bottom sheets
26, top corners
Dialogs, widgets
22
Text fields, banners, bike stage
14
Icon tiles
12 (small 10)
Buttons, chips, segmented controls, switches, composer
Pill (999)
Checkboxes
7
K mark, nav K, splash
Octagon, 29 % corner cut: the one hard shape
Elevation: light grounds things with soft violet shadows (cards 0 10 26 −18 at 32 % of #281E78; sheets 0 −20 40 −20; dialogs 0 30 60 −24). Dark lights them with glow instead (gradient actions 0 10 28 −10 at 75 % of #6848FF).
Frame and safe areas (360 × 800 dp):
Status bar inset 28 dp, drawn by the system.
Top bar 56 dp; icon buttons 48 × 48 dp.
Content: 16 dp gutters, 632 dp between the bars.
Bottom nav 64 dp plus a 20 dp gesture inset (84 dp); the K octagon is 56 dp and rises 22 dp above the bar. With 3-button navigation the inset is 48 dp and the bar grows; nothing overlaps.
Touch targets are 48 × 48 dp minimum; 32 dp chips get 8 dp of invisible padding.
## Components
Every screen is built from the parts below; specimens are drawn at 1:1 dp on the Component library page (core, K, overlays and feedback).
Component
Spec
States
Primary button
Gradient pill, 48 dp (small 38), Inter 13.5/600 white; one per screen
Pressed (ripple 90 ms), disabled 38 %, with icon
Secondary, ghost, destructive
Outline pill on card colour; ghost = signal-2 text; destructive = #E8364F → #B8236F gradient or critical outline
Same as primary
Filter chip
32 dp pill, Inter 12.5/500
Off; on = soft gradient fill, violet edge
Suggestion chip
44–48 dp, radius 16, violet icon
K first run, 2 × 2 grid
Threat tag
Diamond + CRIT / HIGH / ROUTINE, Inter 10/700 caps
Critical, warning, quiet text colours
Source tag
22 dp pill: Instant · From your data · On-device AI · Cloud
One colour each, always with icon and word
Sync chip
24 dp pill with dot
Synced · syncing (falling bolt) · offline · waiting · failed
Card
Radius 18, 16 dp padding, 1 dp line
Default, raised, flat (dense grids), critical, warning, success
Hot card
Gradient edge + faint bolt watermark bottom right
One per screen; optional breathing glow (5.5 s)
Text field
48 dp, radius 14, label above (Inter 12/600), 16 sp value
Focus: 3 dp violet ring; error: critical ring + hint; large amount field
Switch
50 × 30 dp pill
On = gradient, white knob; off; disabled
Segmented control
Pill track, gradient active segment, 48 dp (52 with bike thumbnails)
2–4 segments
Checkbox
22 dp, radius 7, border by threat
Done = gradient fill + white check, row struck through
Progress
6 dp pill bar (gradient); segmented bar; ring 8–10 dp stroke
Normal, success, warning, critical
List row
≥ 52 dp; settings rows 56 dp with an 18 dp icon on a soft tile
Swipe right = complete, left = delete; long press = menu
Bottom nav
Command · Ops · K · Protocols · Vault; top radius 24
Active = soft pill behind icon + white spark on top every 3.2 s
Top bar
Tab root: K mark + Sora 18/700 title; sub-screen: back + Sora 15/600
Command reads "K · SYSTEMS NOMINAL"
Bottom sheet
Radius 26 top, handle 40 × 4, 16 dp sides, 40 dp bottom
Scrim 36 % light / 72 % dark
Dialog
Radius 22, 24 dp padding, actions right, primary last
Destructive: critical edge, default focus on Cancel
Snackbar
Radius 16, 96 dp above the bottom, stays dark in both themes
Undo for 5 s; error variant
Banner
Radius 14 under the top bar
Offline, Battery Saver, permission revoked (with Fix)
Empty state
Sleeping storm cloud, a spark every 7 s, one line, one action
Every list screen
Skeleton
Radius 10 blocks with a 1.5 s shimmer
First sync
Bike stage
Radius 14 panel, floor glow, cut-out bike photo, glint every 7 s
Range tag, change-photo button; 56 × 36 dp thumbnail
## K, the assistant
K speaks as "I", changes exactly one thing per reply (always with Undo) and tells the user where every answer came from. The orb is decorative and hidden from TalkBack; K's state is announced as text ("K is thinking").
Source tags: every reply carries exactly one, as icon + word + colour.
Tag
What answers
Speed
Instant
Clear commands done by rules, no model ("log 500 ml")
Under 50 ms
From your data
A local query on app data: water, steps, sleep, calendar, spend, overdue
Under 200 ms
On-device AI
MiniCPM5-1B on the phone: open chat, maths, odd phrasing
10–20 s; the first answer after idle can take a minute
Cloud
Optional, off by default; the user's own Gemini, OpenAI or Anthropic key. The tag names the provider
Network
Orb states (240-unit grid; 24 dp in cards, 104 dp in the thread, 200–252 dp in voice mode):
State
Looks like
Timing
Idle
Breathing core, at most one tiny arc
4.2 s loop
Listening
Level bars and arcs grow with mic level
Every frame, no easing
Thinking
Lightning ring, one more charge arc every 2 s (max 8)
Shows within 100 ms of send
Speaking
Three thunder-pulse rings on the voice rhythm
1.8 s loop; stops within one frame of Stop
Loading model
Capacitor ring fills with real progress, then one release flash
Real progress, never faked (cold load 6.8 s)
Success
Bolt strikes in with a 120 ms white flash
280 ms
Failure
Red arc flickers three times and breaks into embers
420 ms, at most 3 Hz
Asleep
Dim core; memory freed after 1, 2 or 5 min (user setting)
Static
Diff chips: the seven actions K can take. Each shows under K's reply the moment it is applied, with Undo; after Undo it dims and offers Redo.
Add objective (title, day, due, threat)
Add calendar event (title, start, end, calendar)
Complete objective (was → now, count today)
Log water (amount, today's total, streak)
Log expense (title, amount, category, budget before → after)
Add note (text, saved to Vault › Notes)
Check off protocol (protocol, today, streak)
System notes (amber) say when K fell back: "K's brain failed. Answered from your data instead.", "K proposed a change that did not match what you said, so it was ignored.", "Voice is unavailable on this device. Typing still works."
Voice mode: a 252 dp orb, "Listening…" or "Speaking…", the transcript or reply card, a gradient waveform and three round controls: hands-free (52 dp), the main 76 dp mic or stop button, and cancel or keyboard. Hands-free listens again after K finishes speaking.
## Motion and haptics
Input is answered on frame 0 and effects only decorate the change: an optimistic update lands in under 100 ms with Undo ready, and no effect delays, blocks or reorders the UI. Everything is procedural (Compose or Flutter canvas and shaders), with no video, Lottie or GIF, and a 4 ms frame budget for effects.
Easings: e-out cubic-bezier(.2, .8, .2, 1) for entries · e-snap (.3, 1.5, .5, 1) for check and toggle · e-strike (.9, 0, .1, 1) for bolts and wipes · linear for spins and progress · sine for breathing loops.
Trigger
Effect
Duration
Easing
Sound
Haptic
Screen visible
Storm-cloud grain drifts 24 px
60 s loop
linear
—
—
Every 20–40 s
Distant flicker in the top sky
400 ms
steps
—
—
Hot card on screen
Card edge breathing (one card per screen)
5.5 s loop
sine
—
—
Active tab
White spark runs 34 px along the tab pill
3.2 s loop
e-out
—
—
Top bar K mark
Bolt crackle, three dips to 55 %
9 s loop
steps
—
—
Any press
Ripple from the touch point
120 ms
e-out
Tick
Light tick
Objective or protocol checked
Lightning line through the row, streak +1
320 ms
e-strike
Clear
Light tick
Water logged
Ring sweeps to the new value
380 ms
e-snap
Water
Light tick
Expense saved
Spark travels into the budget bar
360 ms
e-out
Tick
Light tick
Critical item on screen
Red marker pulse, one arc along the border
1.6 s loop
sine
Critical (alert)
—
Undo
The change's arc runs back; row restores in place
220 ms
e-out
Tick, reversed
Light tick
K change applied
Success strike into the orb
120 + 120 ms
e-strike
Clear
Firm double-tap
K change rejected
Failure fizzle
420 ms
e-out
Deny
Double tick
Navigate between screens
Diagonal lightning wipe; outgoing dims to 45 %
≤ 250 ms
e-strike
—
—
Background sync
Bolt runs down the sync chip, one flash at Synced
900 ms
e-strike
—
—
Dawn briefing opens
Storm clearing, sky lifts 8 %
1.2 s
e-out
Briefing
—
Night debrief opens
Thunder rolling out, screen settles 6 % darker
1.4 s
e-out
Sleep
—
Empty state
Sleeping cloud, one spark, three blinks
7 s loop
steps
—
—
Setup complete
Full-height bolt, "READY" types in behind it
900 ms
e-strike
Boot
Long low buzz
Orb loops are in the K section above. Rules:
All loops pause when the screen is off, the app is backgrounded or the view leaves the screen.
Battery Saver or Reduce Motion: static glow only, no loops or flashes; transitions become 120 ms cross-fades; state stays readable from shape.
Photosensitivity: never more than 3 flashes a second; flash area under 25 % of the screen, except the setup finale, capped at 60 % white.
One signal at a time: ambient effects stay at intensity 1; intensity 3 is only for moments that confirm a change.
Haptics: light tick = 10 ms at low amplitude; firm double-tap = 2 × 20 ms with a 60 ms gap; long low buzz = 400 ms at 30 % amplitude.
## Sound
Seven short in-app cues (Tick, Clear, Engage, Pulse, Deny, Boot, Water) plus five alert sounds, all synthesized at build time, royalty-free and under 2.5 s. Default level is Low, and every sound has a haptic twin.
Sound
Plays on
Character
Length
Haptic
Tick
Taps, presses, undo (reversed)
Tiny static spark
40 ms
Light tick
Clear
Check-off, K success
Clean crack, fast decay
180 ms
Firm tap
Engage
K starts listening, model wake
Rising electric hum into a snap
600 ms
Ramp, then tick
Pulse
K thinking bed, −30 dB under
Soft low thunder pulse
900 ms loop
None
Deny
Denied, failure, invalid input
Short dull fizzle
250 ms
Double tick
Boot
Cold app start only, never on resume
Full clap, rolling tail
about 1.5 s
Long low buzz
Water
Water logged
Plink with faint crackle
220 ms
Light tick
Critical (alert)
Overdue critical objective
Sharp double strike, low boom
1.2 s
Firm double-tap
Ops (alert)
Objective due, event soon
Single crack
300 ms
Firm tap
Sleep (alert)
Wind-down
Distant fading rumble
2 s
Long low buzz
Briefing (alert)
Dawn briefing, night debrief
Rolling thunder, rising chime
2.4 s
Light tick × 2
Soft (alert)
Nudges, streak at risk
Faint static shimmer
600 ms
Light tick
Levels (Loadout › Sounds): Off · Low −30 dBFS peak (default) · Medium −24 · High −18. Levels apply to in-app effects only.
Channels: in-app effects follow media volume; alerts follow the notification channel's volume and respect silent mode and Do Not Disturb.
Never over K's voice: effects duck −12 dB while K speaks, and the thinking bed stops the instant words stream. Idle K is silent.
Voice cues: listen start = Engage clipped to 300 ms; release snap 200 ms when an utterance is captured or a reply ends.
Previews for every effect and alert live in Loadout › Sounds.
## Home-screen widgets
Seven widgets, built with Jetpack Glance through Flutter's home_widget bridge, so they use only gradients, images and text: no blur and no animation. They follow Android's dark or light setting, not the in-app theme.
Widget
Size (cells · dp)
Shows
Actions
States
K · Objectives
4×2 · 328 × 170
Top three open, by threat then due time; done count
Box completes in place; row opens Ops; + captures
Live · stale · all done · empty
K · Readiness
2×2 · 160 × 170
Readiness ring with objectives, protocols and deep ops
Opens Command
Live · late evening (amber) · no data yet
K · Garage
4×2 · 328 × 170; compact 2×2
Bike photo, odometer, tank, km/l, next reminder; dots switch bikes
Fuel button logs a fill-up; tap opens the bike (configurable)
Meteor · Avenger overdue (critical surface) · no bikes · compact
K · Water
2×1 · 160 × 80
Today's ml and bar
+250 logs without opening K
On pace · behind pace · target hit
K · Next op
2×1 · 160 × 80
Next event and its countdown
Opens the event
Next event · nothing next (shows next briefing)
K · Ask
4×1 · 328 × 80
Pill bar with mic
Bar opens chat; mic opens voice mode
Ready · brain asleep (tap wakes)
K · Spend
2×2 · 160 × 170
This month's spend against budget
Unlock in K
Masked (default) · shown
Grid: cell 76 × 80 dp with 8 dp gutters; widgets resize in whole cells, and below 2 rows the list widgets fall back to their 4×1 layout.
Updates: instantly when something changes in K, every 30 minutes through WorkManager, and within a minute of a calendar change. After 2 hours without one, the widget dims and shows "Updated 19:12" with a refresh pill.
Countdown: Next op uses Android's Chronometer, so it ticks without waking K.
Privacy: Spend stays masked until Show amounts is turned on in that widget's setup. Bike photos never leave the phone.
Shape and surface: outer radius follows the launcher (22 dp fallback); the surface stays 95 % opaque so text keeps 4.5 : 1 on any wallpaper.
Text size: at large font sizes the list keeps two rows and truncates titles with an ellipsis; numbers never truncate.
Garage widget setup (configuration screen): bike (Meteor, Avenger or both, overdue first), what to show (mileage, next reminder, odometer, cost per km), what a tap opens (bike page or log fill-up) and surface (Storm 95 %, Glass 80 % or Solid). Change later with touch and hold › Reconfigure.
## Garage
The Garage tab in Ops tracks two bikes with their own photos, fuel log, mileage and service reminders; fuel spend flows into Vault › Transport. The figures below are the design's fixtures, not shipped data.
Royal Enfield Meteor 350
Bajaj Avenger Street 150 (2016, black)
Odometer
9,412 km
18,642 km
Tank
15 L
14 L
Mileage, last 8 full tanks
34.6 km/l average
39.9 km/l average
Running cost
₹3.03 / km
₹2.63 / km
Reminders shown
Chain lube every 500 km (138 km left) · service and oil every 5,000 km or 12 months (588 km) · PUC (13 days) · tyre pressure every 14 days (today) · insurance to 14 Mar 2027
Insurance overdue (linked to an Ops objective) · chain lube (58 km) · service every 5,000 km or 6 months (1,658 km) · battery check (rarely ridden) · PUC (114 days)
Mileage chart: bars for the last 8 full tanks, a dashed average line, the latest bar highlighted; mileage is measured only between full tanks.
Log fill-up sheet: bike switch with thumbnails, odometer, litres, price per litre, total, full-tank switch, then "this tank" against the average. Saving adds the cost to Vault › Transport.
Service reminder sheet: type (service, oil, chain, tyres, insurance, PUC, battery, custom); remind by km, by date or whichever comes first; heads-up at 100, 300 or 500 km. Alerts arrive on the K · Ops channel and land in Ops as a HIGH objective when due.
Add bike sheet: photo first, then make and model, odometer, tank, insurance and PUC dates and a service interval. K then adds chain, tyre and battery reminders, which the user can edit.
Bike photo: the user takes or picks a side-on photo, and the background is removed on the phone by an on-device segmentation model. The cut-out (WebP with alpha) sits on the bike stage. With no bikes, the empty state shows a cruiser outline.
Fuel price is prefilled on the fill-up sheet (₹104.90 / L in the design).
## Accessibility
Every text tier passes WCAG AA in both themes (lowest: 4.7 : 1 in light, 4.9 : 1 in dark), every target is at least 48 dp, and layouts hold at 200 % text.
Text scaling: all type is in sp. At 200 % labels wrap, rows grow and nothing that holds text has a fixed height. Above 160 % the bottom-nav labels hide and the icons keep their TalkBack names.
Never colour alone: threat levels carry CRIT, HIGH or ROUTINE with a diamond; bills carry PAID, UPCOMING or OVERDUE; calendars carry P or W letters; source tags carry an icon and a word; icon tiles always sit beside a label; "Behind pace" is written, not only amber.
Real controls: buttons, links, labelled fields, switches with role switch, segmented controls as radio groups. Icon-only buttons have labels ("Change photo", "Log fill-up").
Motion: Reduce Motion and Battery Saver turn every loop into a static frame; flashes stay under 3 per second.
Decorative layers (orb, grain, arcs, bolt watermarks) are hidden from TalkBack. K's state is announced as text, and voice mode is a polite live region.
TalkBack labels: say what it is, then its state.
Element
Announcement
K tab
"K assistant. Tab, 3 of 5."
Objective checkbox
"Complete objective. Renew two-wheeler insurance. Critical. Overdue by 1 hour 42 minutes."
Readiness card
"Ops readiness, 63 percent. Objectives 5 of 8. Synced 2 minutes ago."
Diff chip
"K logged water, 250 millilitres. Undo, button."
Mic
"Tap to talk to K. Hands-free off."
Garage card
"Royal Enfield Meteor 350, your photo. 9,412 kilometres, average 34.6 kilometres per litre."
## Android behaviour
K is drawn for a 360 × 800 dp phone and adapts by width; every Android interruption has a drawn state.
Case
Behaviour
Large phone, 430 × 932 dp
Same layout, larger hero orb, and a Garage strip with both bike thumbnails on Command
Tablet or foldable
A centred 560 dp column; the bottom nav spans the full width
Text at 200 %
Labels wrap and cards grow (see Accessibility)
Pull to refresh (Ops)
64 dp strip with a charging ring and bolt: "Release to sync", calendars and Drive, last sync time
Long press on an objective
Row lifts; menu: Complete · Edit · Move to tomorrow · Change threat · Start deep ops on this · Delete
Battery Saver
Banner "Battery Saver · effects paused", static effects, sync waits for charging
Offline
Banner "Offline · changes saved on this phone"; sync chips show offline
Permission revoked in Android settings
Banner with Fix, which opens the rationale sheet
Back from background
K finishes the answer silently and stops speaking; on return a note offers Play
Back gesture
Closes the open sheet or dialog first, then goes back
Permissions are asked in context, each after a K rationale sheet ("Before Android asks"): microphone in setup, Health Connect (optional) for steps, sleep, weight and heart rate, notifications, and usage access for screen-time protocols. If one is denied, the feature stays usable another way (typing instead of voice) and setup continues.
Notifications use four channels the user can tune in Android: K · Alerts (high, critical items), K · Ops (default), K · Briefings (default, media style with play and pause) and K · Protocols (low, soft). Alert actions are Complete, Snooze 1 h and Open.
Splash: the K monogram struck by a bolt, with "On-device · private"; Boot plays only on a cold start.
## Data, sync and privacy
There is no server: data lives on the phone, backs up to a hidden app folder in the user's own Google Drive as k-backup.json, and the app ships with zero sample data.
Names are never hard-coded. Setup asks for a nickname and a full name. The nickname is used in greetings and briefings ("Evening, {nickname}."); the full name is used by the Butler persona and in exports. The design shows them as {nickname} and {full name} tokens.
Locale: 24-hour clock by default (12-hour option); currency INR with Indian grouping (₹1,24,500).
Backup contents: objectives, notes, protocols, water, expenses, bills, budget, settings and the K chat log. Not backed up: API keys and Google sign-in tokens, which are re-entered on a new phone.
Auto-sync a few seconds after each change, with a Wi-Fi only option. Status shows on sync chips across the app.
Sync conflict (phone and Drive both changed): Merge, keeping both with the newest edit winning (recommended), Keep this phone, or Use Drive. Nothing is deleted until the user chooses.
Restore: setup finds an existing backup and offers Restore or Start fresh.
Google accounts: up to two (Personal and Work) for backup and calendars. Calendars are read-only, and K never sees the password.
Vault lock: budget, spend, bills and notes stay hidden until unlocked with the phone's fingerprint or PIN; Vault locks again when the user leaves the tab.
Cloud AI: off by default. With the user's own key, the message goes to the chosen provider and the reply is tagged Cloud. The key stays on the phone and never enters the Drive backup.
Erase all: typing ERASE removes everything from the phone, including K's 688 MB brain. The Drive backup is untouched and is deleted separately.
Delete Drive backup: data stays on the phone and auto-sync turns off.
## Assets and files
Everything a developer needs beyond this doc is in K-design-handoff.zip (sent with this doc in chat); the screens themselves are on the (https://claude.ai/artifact/N8h1uvw3B73VAdHwaTBeDL) K design canvas.
File
What it is
k-tokens.json
Every token: light and dark colours, gradients, icon tiles, type, spacing, radii, sizes, motion, sound levels, haptics
k_theme.dart
The same tokens for Flutter 3.27+: KColors (ThemeExtension with light and dark), KGradients, KSpace, KRadius, KSize, KMotion, KType and kTheme(Brightness); read colours with context.k
k-mark.svg, k-mark-256.png
The K mark: bold K, bolt cut through its diagonal, octagon. Top bar, nav K, splash
k-app-icon.svg, k-app-icon-512.png
Adaptive launcher icon on a 108 dp canvas; the octagon stays inside the 66 dp safe circle
meteor-350.webp, avenger-street-150.webp
Bike cut-outs (WebP with alpha) used in the design
cruiser-outline.svg
Outline drawing for the Garage empty state
README.md
What is in the zip and how to register the fonts
Fonts: Sora, Inter and IBM Plex Mono from Google Fonts (SIL Open Font License). Bundle them and register the family names Sora, Inter and IBMPlexMono in pubspec.yaml.
Icons: inline 24 dp stroke icons (1.6 dp stroke). Draw them from the canvas specimens or map to an outline icon set; never emoji.
Google sign-in: use the official Google button asset; the mocks show a neutral "G" placeholder.
## Open items before build
These are decisions or checks the design leaves to the build; none of them changes a screen.
Replace the bike photos: the design uses catalogue-style stand-ins, and the shipped app shows the rider's own photo.
Pick the on-device background-removal model for bike photos and check its size and speed on a 360 × 800 dp, Reno 8 class phone.
Confirm the K model runtime on Android and measure against the design's targets: cold load about 6.8 s, on-device answers in 10–20 s.
Produce the 12 sounds from the Sound table (synthesized, under 2.5 s each) and check levels at Low, Medium and High.
Confirm the four notification channels and their default importance in Android settings.
Decide how Glance widgets pick dark or light (Android setting) and test both on light and dark wallpapers.
Add the official Google sign-in button asset in place of the "G" placeholder.
Confirm "K" as the final app and assistant name ("Jane" is a one-pass swap on the canvas).
