import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';
import 'theme.dart';

/// One release's changelog (bundled on-device, newest first). RULE: every build bump adds an entry
/// here in the same change (see ~/maradel/CLAUDE.md #10).
class ChangelogEntry {
  final int build;
  final String version;
  final String date;
  final String title;
  final String body; // markdown
  const ChangelogEntry({
    required this.build,
    required this.version,
    required this.date,
    required this.title,
    required this.body,
  });
}

const List<ChangelogEntry> kChangelog = [
  ChangelogEntry(
    build: 57,
    version: '1.0.57',
    date: '2026-06-21',
    title: 'The tablet follows the active persona — colors + avatar',
    body: '''
- Keli now **dresses for whoever Maradel currently is**. Switch the active persona (in the admin) and
  the tablet **recolors its whole UI** to that persona's palette and **swaps to its avatar** — live, no
  restart. On cold start it loads the active persona's colors + avatar too.
- Picking an avatar with the ◀/▶ buttons or the picker now **sticks it to the current persona**, so it
  comes back the same way next time.
- Under the hood the theme is now a live palette (recolors on the fly) seeded from the usual fel-frost
  look, so personas without a custom scheme look exactly as before.
''',
  ),
  ChangelogEntry(
    build: 56,
    version: '1.0.56',
    date: '2026-06-20',
    title: 'Avatar ◀/▶ that stick + a live Maradel chat view + audio fix',
    body: '''
- **Avatar ◀/▶ right on the face** flip to the next/previous look, show its name + category, and
  **remember your pick** across restarts — no menu needed. The in-Unity dev overlay is hidden by
  default now (Flutter owns avatar switching). Fixed an early-startup bug where the buttons did
  nothing until you opened the picker.
- New **MARADEL chat window**: a read-only, draggable mirror of the live session — your messages,
  Maradel's replies (markdown), and her **tool calls** (status, progress notes, collapsible output).
  Toggled from the chat icon in the top bar (off by default); auto-scrolls. It fills in once the
  backend's live session feed is switched on.
- Fixed spoken replies **cutting out after a sentence or two** — the player could stall after a chunk
  if its finish event got dropped; it now always advances to the next.
''',
  ),
  ChangelogEntry(
    build: 53,
    version: '1.0.53',
    date: '2026-06-20',
    title: 'Maradel sees — live perception panel',
    body: '''
- New **"MARADEL SEES"** floating panel (top-right, draggable). Every ~5 minutes Maradel looks through
  the roomba's **Tapo** and **USB** cameras, describes what she sees on each, notes **whether a person is
  present**, and shows her best guess of **which room the roomba is in**.
- Same perception also drives the voice level (quieter when a person is seen) and shows in maradel-status.
''',
  ),
  ChangelogEntry(
    build: 52,
    version: '1.0.52',
    date: '2026-06-20',
    title: 'Master voice level + ambient loudness',
    body: '''
- The bottom status bar now shows **Maradel's master voice level** here — a speaker icon + percentage,
  so you can see at a glance how loud the tablet will speak right now.
- That level is driven by Maradel's new **ambient-volume brain**: she watches camera presence + the time
  of day and keeps her voice at the lowest of the configured caps — quieter when someone's in the room,
  quieter at night, louder when the place is empty. The tablet follows the room speaker automatically
  (pushed via the `set_volume` command). All the caps live in the Maradel settings dashboard.
''',
  ),
  ChangelogEntry(
    build: 51,
    version: '1.0.51',
    date: '2026-06-20',
    title: 'Emotions actually render on the face',
    body: '''
- The face now **reacts with Maradel's mood**. The whole chain is finally connected: backend
  `voice:emotion` → the app forwards it to the embedded face as `setMood` (the main screen never did
  this — it only happened on the unused preview screen) → Unity's bridge now **handles `setMood`** and
  drives the facial expression. Logged as `→setMood <mood>` / `[EXPR]`.
- Note: spoken (talk-to-robot) replies only carry a mood once the backend emits `voice:emotion` for the
  mic loop; chat replies already do.
''',
  ),
  ChangelogEntry(
    build: 50,
    version: '1.0.50',
    date: '2026-06-20',
    title: 'No more talking over itself',
    body: '''
- The mic now stays muted **until the device actually finishes playing** Maradel's reply (not just when
  the backend stops), plus a short **tail** — so the end of her reply can't leak back into the mic and
  make her answer herself.
- **Safety net:** the mic can never get **stuck silent** — if the "stopped speaking" signal is ever
  lost, it auto-unmutes after a few seconds.
- (Backend) speech-band **de-noising** before the VAD so it detects silence cleanly in a noisy room.
''',
  ),
  ChangelogEntry(
    build: 49,
    version: '1.0.49',
    date: '2026-06-20',
    title: 'set_volume + full-screen flashlight + face stays visible',
    body: '''
- **`set_volume` command** — Maradel can set this device's **master volume**; it applies to the app
  audio and the 3D face (written to the shared config Unity reads).
- **Front flashlight** is now truly **full-screen white** (was a centred card on a dim scrim).
- **The face stays visible during pop-ups** — when a tool opens a window, Maradel's face tucks into the
  **top-right corner** (like the camera window, opposite side) instead of being hidden behind it.
''',
  ),
  ChangelogEntry(
    build: 48,
    version: '1.0.48',
    date: '2026-06-20',
    title: 'Face shows emotion on spoken replies',
    body: '''
The 3D face now reacts with Maradel's **mood**: the app forwards the backend's
`voice:emotion` to Unity as `setMood`, so spoken replies drive facial + body
emotion (Unity's mood layer renders it). Logged as `→setMood <mood>`.
''',
  ),
  ChangelogEntry(
    build: 47,
    version: '1.0.47',
    date: '2026-06-20',
    title: 'The mouth moves — lip-sync on spoken replies',
    body: '''
- **Fixed the frozen mouth.** The 3D face was *ignoring* the live voice chunks (it waited for an
  end-of-reply "plan" that the talk-to-robot loop never sends), so the mouth stayed shut. Now the face
  **lip-syncs from the streaming audio in real time** (analysed silently — you still hear the reply once,
  from the app). Emotion/camera beats still time to the speech.
''',
  ),
  ChangelogEntry(
    build: 46,
    version: '1.0.46',
    date: '2026-06-20',
    title: 'No double voice + Unity logs in the shared log',
    body: '''
- Maradel's reply now plays **once** — the **app** plays it; the **3D face's own voice is muted** so
  you don't hear it twice. The mouth still lip-syncs (the face still analyses the audio, it just
  doesn't output it). Global audio / future sound effects are unaffected.
- The **3D face now forwards its console** to the app log — every Unity message shows as a `[unity]`
  line, so a single shared log captures Flutter + Unity together (for chasing face/lipsync issues).
''',
  ),
  ChangelogEntry(
    build: 45,
    version: '1.0.45',
    date: '2026-06-20',
    title: 'Avatar button + clean black face',
    body: '''
- **Avatar/skin picker** is a visible **face icon in the top bar** → searchable list → tap to swap.
- Removed the **teal-green glow halo** around the 3D face — clean black now.
- (Tooling) build.ps1 now also publishes the auto-update channel (keli/keli.apk + version.json).
''',
  ),
  ChangelogEntry(
    build: 44,
    version: '1.0.44',
    date: '2026-06-20',
    title: 'Unity logs in the shared log',
    body: '''
The bridge now pipes Unity's console into the app log, so a shared log contains
**everything** — Flutter *and* Unity — for debugging the face/lipsync.

- Inbound `log` messages from Unity → `[unity]` lines in the log (clean), plus a
  catch-all so no Unity message is ever dropped.
- (Unity side, for the dev: forward `Application.logMessageReceived` as
  `SendToFlutter.Send(envelope("log", {msg, level}))` — then its console shows up
  in every shared log.)
''',
  ),
  ChangelogEntry(
    build: 42,
    version: '1.0.42',
    date: '2026-06-20',
    title: 'Mic fix — the real one',
    body: '''
The mic recorded but never reached Maradel, and the level meter stayed dead. Root
cause found: each audio frame crashed an internal step (`Int16List.view` on an
odd-offset buffer) **before** it was sent — silently, every frame. So nothing was
transmitted and the VU never moved.

- Copy each frame to a clean, aligned buffer before processing/sending.
- Read levels with offset-safe `ByteData` (no more crash).
- Wrapped the audio handler so any future error is logged instead of silently
  killing the mic.
''',
  ),
  ChangelogEntry(
    build: 40,
    version: '1.0.40',
    date: '2026-06-20',
    title: 'Mic actually transmits',
    body: '''
Fixes the mic streaming nothing to Maradel even though it looked connected.

- **Send a contiguous copy of each audio chunk.** The recorder hands the app
  buffer *views*; sending a view over the WebSocket could transmit **zero
  bytes** — which is exactly what was happening (the app logged "first chunk"
  and showed connected, but the backend received nothing).
- **Disable WebSocket compression** (Dart enables permessage-deflate by default,
  which mis-framed the binary audio against the server).
- **Stall watchdog:** if the recorder goes silent for >4s, capture restarts
  automatically (some devices deliver a chunk then stop).
- Added a 3s health log (chunks captured/sent) for diagnostics.
''',
  ),
  ChangelogEntry(
    build: 39,
    version: '1.0.38',
    date: '2026-06-20',
    title: 'Share logs',
    body: '''
- New **Share logs** button in the logs panel (next to Copy): uploads this session's log to the lab
  share as a file (`keli-log-<time>.log`), so it can be opened on nukshare without pasting into chat.
''',
  ),
  ChangelogEntry(
    build: 38,
    version: '1.0.37',
    date: '2026-06-20',
    title: 'Steadier mic connection',
    body: '''
- Fixed the mic to Maradel **flapping** — it was reconnecting every 1–2 seconds, chopping the audio.
- Now the reconnect **backs off** when a link is short-lived (only resetting after it's been stable ≥8s),
  there's only ever **one** pending reconnect, and drops are **logged with why + how long it lasted** so we
  can chase any remaining cause.
''',
  ),
  ChangelogEntry(
    build: 37,
    version: '1.0.36',
    date: '2026-06-20',
    title: 'Pick the face skin',
    body: '''
- New **Select skin** in the + menu: it asks the 3D face for its available skins and shows a
  **searchable list** (friendly names, with the real name underneath). Pick one and the face puts it
  on. Powered by a new Unity bridge (`get_skins` / `set_skin`).
''',
  ),
  ChangelogEntry(
    build: 36,
    version: '1.0.35',
    date: '2026-06-20',
    title: 'Registration popup fixes',
    body: '''
- The registration popup now **scrolls above the keyboard** (the Register button was getting hidden),
  is **dismissible** (Close button + tap-outside; re-open from the side panel), all fields are
  **single-line**, and on error the **offending field is focused** (and the password cleared) with the
  message clearly shown.
''',
  ),
  ChangelogEntry(
    build: 35,
    version: '1.0.34',
    date: '2026-06-20',
    title: 'Unity bridge + timing logs',
    body: '''
- The 3D face now logs **load and response timings** (`[Time]` — avatar load+wire, and per-reply
  voice request→play) into its session log, and its **Send Logs** now uploads to the same
  `keli/logs/` folder as the app.
- The **Bridge → Unity** message you send now shows up in the **Unity console**, and the face's Dev
  panel has a **→Flutter** box to send a string back to the app's console.
''',
  ),
  ChangelogEntry(
    build: 34,
    version: '1.0.33',
    date: '2026-06-20',
    title: 'Upload logs + Unity bridge (Flutter half)',
    body: '''
- **Upload logs** in the side panel — sends this session's log to the share (`keli/logs/`) as a file
  you can open in the watcher.
- **Bridge → Unity** in the + menu — type a string and send it to the embedded Unity face; messages
  Unity sends back now appear in the bottom console log (tagged `unity`).
''',
  ),
  ChangelogEntry(
    build: 33,
    version: '1.0.32',
    date: '2026-06-20',
    title: 'Mic-test no longer fights the Ears stream',
    body: '''
- The **hold-to-record test** was recording an empty (44-byte) clip whenever **Ears** was on — because
  Android only allows one mic capture at a time, and the live Ears stream already held it. The test now
  **pauses Ears while recording** and resumes after, so it captures real audio. (The live Ears stream
  itself was already working.)
''',
  ),
  ChangelogEntry(
    build: 32,
    version: '1.0.31',
    date: '2026-06-20',
    title: 'Mic capture fix (empty recording)',
    body: '''
- Fixed the mic **capturing nothing** on some devices (a 44-byte / empty recording even with
  permission): the recorder now forces the raw **MIC** audio source instead of the system default,
  which returns silence on certain OEM tablets. Applies to both the live "ears" stream and the
  hold-to-record test.
''',
  ),
  ChangelogEntry(
    build: 31,
    version: '1.0.30',
    date: '2026-06-20',
    title: 'Device registration + settings',
    body: '''
- **First-launch registration**: name this device + set a login & password. Re-using the same login &
  password on another tablet moves this instance to it (device-swap). Re-open it from **Registration**
  in the side panel.
- Keli now syncs a **per-device config** from Maradel every minute (first setting: **master volume**,
  applied to both the app and the 3D face) and ships its **logs** to Maradel in 10-second batches.
''',
  ),
  ChangelogEntry(
    build: 30,
    version: '1.0.29',
    date: '2026-06-19',
    title: 'Talk to the robot — and hear it answer',
    body: '''
- **Maradel now answers out loud on the tablet.** The app plays her spoken reply (every voice chunk
  from :9100) through the device speaker — the missing reply path, so you talk to the roomba and it
  talks back.
- **Mic now uses the proper WebSocket** the backend expects (binary PCM, tagged with this device) —
  the canonical "ears" transport instead of the fallback.
- **Echo guard fixed:** the mic correctly mutes while Maradel is speaking (it was listening on the
  wrong channel before, so it never muted).
''',
  ),
  ChangelogEntry(
    build: 29,
    version: '1.0.28',
    date: '2026-06-19',
    title: 'Smaller + button, bigger face-overlay scale',
    body: '''
- The **+** action button is now **small** (was the oversized large FAB).
- Updated the embedded **3D face**: the UI-scale **[−][+]** on the face overlay are now **large and
  centered** (easy to hit on the tablet).
''',
  ),
  ChangelogEntry(
    build: 28,
    version: '1.0.27',
    date: '2026-06-19',
    title: 'Mic-test Send → file on the share',
    body: '''
- The mic-test **Send** now uploads the clip to the **lab share as a plain .wav file** (open it in the
  watcher) instead of dropping it into Maradel's chat — so Maradel no longer reads it as text or
  responds to it.
''',
  ),
  ChangelogEntry(
    build: 27,
    version: '1.0.26',
    date: '2026-06-19',
    title: 'Mic on older tablets (Android 8)',
    body: '''
- Added **MODIFY_AUDIO_SETTINGS** — some older OEM tablets (HUAWEI MediaPad, Android 8) report
  *"no audio device available"* for recording without it.
- The mic permission is now **requested explicitly** (more reliable prompt on old Android), and the
  log says whether it's granted, denied, or permanently denied (with how to fix it in Settings).
''',
  ),
  ChangelogEntry(
    build: 26,
    version: '1.0.25',
    date: '2026-06-19',
    title: 'Hold-to-record records the full time',
    body: '''
- Fixed the mic-test recording **cutting off after ~2 s**: holding now records for **exactly as long
  as you hold** (it used a tap gesture that could be cancelled mid-hold; now it tracks the raw press).
''',
  ),
  ChangelogEntry(
    build: 25,
    version: '1.0.24',
    date: '2026-06-19',
    title: 'Mic test + console tools',
    body: '''
- The bottom console now has a **Hold to record** button: hold it, speak, release — then **Play** the
  clip back or **Send** it to Maradel. This proves whether the mic captures audio at all (the recorded
  byte size + a warning are logged).
- A **Copy logs** button copies the whole session log to the clipboard.
- Removed the **Tapo map** overlay from the home screen.
''',
  ),
  ChangelogEntry(
    build: 24,
    version: '1.0.23',
    date: '2026-06-19',
    title: 'Mic actually captures',
    body: '''
- Fixed the **mic delivering no audio** even with permission granted: removed the hardware
  echo-cancel/noise-suppress request that fails to initialise on many devices and leaves capture dead.
- The status bar now **tells you if the mic is silent** — it logs the first audio chunk when it starts,
  and warns *"NO audio after 3s"* if nothing comes through (e.g. another app is holding the mic).
''',
  ),
  ChangelogEntry(
    build: 23,
    version: '1.0.22',
    date: '2026-06-19',
    title: 'Ears actually connect',
    body: '''
- Fixed **talk-to-the-robot**: the mic now streams to Maradel over the **HTTP endpoint the backend
  actually exposes** (`POST /keli/audio`) instead of a WebSocket — so it connects instead of looping
  on connection errors. The status bar's dot should go **green** and the chunk counter should climb.
- The reconnect log no longer **spams** one error per retry — it logs once and stays quiet until it
  recovers.
''',
  ),
  ChangelogEntry(
    build: 22,
    version: '1.0.21',
    date: '2026-06-19',
    title: 'Talk to the robot (mic)',
    body: '''
- New **Ears**: the tablet's **microphone** now streams to Maradel so you can **talk to the robot** and
  she hears you. Toggle it from the **mic button** in the top bar or the **side panel** (asks for mic
  permission the first time).
- A new **status bar** at the bottom shows a **live voice meter** (see how loud you are), whether the
  **connection** is up, and how many audio **chunks** have been sent — **tap it to expand** the full log.
- Maradel's voice is muted from the stream **while she's speaking** so the robot doesn't hear itself.
''',
  ),
  ChangelogEntry(
    build: 21,
    version: '1.0.20',
    date: '2026-06-19',
    title: 'Model browser',
    body: '''
- The face overlay is redesigned: **search** for a model, or **Browse** a per-category list with a
  one-tap **copy name** on each. Plus a built-in **log window** at the bottom.
''',
  ),
  ChangelogEntry(
    build: 20,
    version: '1.0.19',
    date: '2026-06-19',
    title: 'Lipsync works on device',
    body: '''
- Fixed the **mouth not moving** on the tablet (the lipsync profile wasn't shipping in the build).
- Fixed the **green tint** over the face — the screen is now clean **black**.
- The face overlay's log button is now **Send Logs** and uploads a timestamped session log.
''',
  ),
  ChangelogEntry(
    build: 19,
    version: '1.0.18',
    date: '2026-06-19',
    title: 'Face looks better + lipsync fix',
    body: '''
- The 3D face now has **proper lighting, surface detail and smooth edges**, sits on a clean **black**
  background, and the **intermittent lipsync** (audio that played "sometimes") is fixed.
''',
  ),
  ChangelogEntry(
    build: 18,
    version: '1.0.17',
    date: '2026-06-18',
    title: 'Face diagnostics',
    body: '''
- The 3D face now writes a **verbose per-session log file** on the device, and the face overlay has a
  **Dump log** button that uploads it for diagnosis (chasing the intermittent lipsync on the tablet).
''',
  ),
  ChangelogEntry(
    build: 17,
    version: '1.0.16',
    date: '2026-06-18',
    title: 'Scrollable side panel',
    body: '''
- The **side panel** (menu drawer) is now **vertically scrollable**, so the **update button** and
  version at the bottom are always reachable on the landscape tablet.
''',
  ),
  ChangelogEntry(
    build: 16,
    version: '1.0.15',
    date: '2026-06-18',
    title: 'Maradel has a face',
    body: '''
- Maradel's **3D talking face** is now **always on, front and centre** on the main screen — a live
  square that lipsyncs to her voice in real time. It speaks on its own (connects straight to Maradel),
  so it just works whenever she talks.
''',
  ),
  ChangelogEntry(
    build: 15,
    version: '1.0.14',
    date: '2026-06-17',
    title: 'Landscape-friendly',
    body: '''
- Fixed landscape layout: the **+** action menu now fits the screen (more columns when wide,
  scrolls if needed) and **popups no longer span the whole width** — they're centered and capped,
  with tall ones scrolling instead of overflowing.
''',
  ),
  ChangelogEntry(
    build: 14,
    version: '1.0.13',
    date: '2026-06-17',
    title: 'Face (preview)',
    body: '''
- Groundwork for Maradel's **3D talking face**: a new **Face** screen (side menu). The link to
  Maradel's voice is live — the sigil pulses when she speaks and counts her sentences — and the
  Unity face will mount here once it's ready.
''',
  ),
  ChangelogEntry(
    build: 13,
    version: '1.0.12',
    date: '2026-06-17',
    title: 'Bigger buttons',
    body: '''
- The **Send to Maradel** actions are now big glowing button cards (3 per row) and the **+** button is
  larger — easy targets for a wall tablet. (Feature request.)
''',
  ),
  ChangelogEntry(
    build: 12,
    version: '1.0.11',
    date: '2026-06-17',
    title: 'Live Tapo cam window',
    body: '''
- Added a floating, **draggable Tapo camera** window (top-left) showing the robot's live view —
  same as the map window: drag it anywhere, collapse it, resets each launch.
''',
  ),
  ChangelogEntry(
    build: 11,
    version: '1.0.10',
    date: '2026-06-17',
    title: 'Installs on older tablets',
    body: '''
- Fixed **"App not installed"** on older Android (e.g. HUAWEI MediaPad, Android 8): the release APK
  now carries a legacy **v1 (JAR) signature** alongside v2/v3, which EMUI requires.
''',
  ),
  ChangelogEntry(
    build: 10,
    version: '1.0.9',
    date: '2026-06-17',
    title: 'Maradel look + live map',
    body: '''
- **Maradel-themed redesign.** Keli now wears Maradel's fel aesthetic, frost-shifted to a cold
  spectral teal/blue — obsidian void, glowing accents, the Maradel sigil on the home screen.
- **Live Tapo map.** A floating, **draggable** minimap of the robot sits top-right every session
  (drag it anywhere; collapse it with the corner button). Position resets each launch.
- New app icon (Maradel's).
''',
  ),
  ChangelogEntry(
    build: 9,
    version: '1.0.8',
    date: '2026-06-17',
    title: 'Landscape + Diary view',
    body: '''
- **Landscape orientation.** Keli now runs horizontally — built for a big wall tablet. Stays level
  whichever way you set it down.
- **Diary on the phone.** Maradel can now push your current diary page to the screen, nicely
  rendered, with a separate **Claude** tab for recent activity (the new `show_diary` capability).
''',
  ),
  ChangelogEntry(
    build: 8,
    version: '1.0.7',
    date: '2026-06-17',
    title: 'Request a feature',
    body: '''
- **Request a feature** in the side panel — send a wish to Maradel (shows up in its Feature Requests).
''',
  ),
  ChangelogEntry(
    build: 7,
    version: '1.0.6',
    date: '2026-06-17',
    title: 'Flashlights',
    body: '''
- **Front light** (full-white screen at max brightness) and **Rear light** (LED torch) from the **+**
  menu — 30 s or tap to turn off.
- Maradel can switch them on too (to light up a photo in the dark before taking it).
''',
  ),
  ChangelogEntry(
    build: 6,
    version: '1.0.5',
    date: '2026-06-17',
    title: 'Report a bug',
    body: '''
- **Report a bug** in the side panel — describe what went wrong; Keli attaches its **session log**
  and sends it to Maradel, which captures the full picture. View it in Maradel's Bug Reports.
- The app now keeps a **verbose session log**.
''',
  ),
  ChangelogEntry(
    build: 5,
    version: '1.0.4',
    date: '2026-06-17',
    title: 'Send to Maradel (the + button)',
    body: '''
- A **+ button** on the main screen opens a grid of things you can launch yourself and send to
  Maradel: a **text** message, a **front** or **rear** **photo**, or a **file**.
- It lands in your current Maradel chat (or starts a new one if the last was >5 min ago), Maradel
  replies, and you get a **push** to pick it up in the Maradel app.
- New **Device name** setting (side panel) — Maradel sees which device a message came from.
''',
  ),
  ChangelogEntry(
    build: 4,
    version: '1.0.3',
    date: '2026-06-17',
    title: 'Changelogs',
    body: '''
- **Changelogs** — this app now shows what changed on each update, and keeps the full history under
  **Changelogs** in the side panel (current build highlighted).
''',
  ),
  ChangelogEntry(
    build: 3,
    version: '1.0.2',
    date: '2026-06-16',
    title: 'Pictures & interactive actions',
    body: '''
- **Show image** — Maradel can push a picture; pinch-zoom inline or tap for full-screen.
- **Interactive requests** — Maradel can ask you for something: a **text input** popup, or a
  **photo** (front/back camera, Take button + countdown). Requests queue one at a time.
''',
  ),
  ChangelogEntry(
    build: 2,
    version: '1.0.1',
    date: '2026-06-16',
    title: 'Reliable delivery',
    body: '''
- Messages are **queued and never lost** — if the phone is offline they wait and arrive on reconnect.
- Open windows are **restored** when the app restarts.
''',
  ),
  ChangelogEntry(
    build: 1,
    version: '1.0.0',
    date: '2026-06-16',
    title: 'First release',
    body: '''
- Connection status + **closable markdown windows** Maradel can show on this phone.
- In-app updates from the side panel.
''',
  ),
];

ChangelogEntry? changelogFor(int build) {
  for (final e in kChangelog) {
    if (e.build == build) return e;
  }
  return null;
}

const _seenKey = 'keli.lastSeenChangelogBuild';

/// On first launch after an update, show the current build's changelog once.
Future<void> showChangelogIfNew(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getInt(_seenKey) ?? 0;
  if (kAppBuild <= seen) return;
  await prefs.setInt(_seenKey, kAppBuild);
  final entry = changelogFor(kAppBuild);
  if (entry == null || !context.mounted) return;
  await showChangelogDialog(context, entry, isNew: true);
}

Future<void> showChangelogDialog(BuildContext context, ChangelogEntry e, {bool isNew = false}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: KeliTheme.surface,
      title: Text(
        isNew ? "What's new · v${e.version}" : '${e.title} · v${e.version}',
        style: TextStyle(color: KeliTheme.accent, fontWeight: FontWeight.w700, fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: MarkdownBody(
          data: '### ${e.title}\n\n${e.body}',
          styleSheet: MarkdownStyleSheet(
            p: TextStyle(color: KeliTheme.text, fontSize: 14, height: 1.5),
            h3: TextStyle(color: KeliTheme.text, fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text('Got it', style: TextStyle(color: KeliTheme.accent)),
        ),
      ],
    ),
  );
}
