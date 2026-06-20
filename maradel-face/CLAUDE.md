# CLAUDE.md — maradel-face

Guidance and living documentation for this Unity project. Keep this file current:
**document every feature and every change step here as work progresses.**

## Project overview

- **Engine:** Unity **2023.2.22f1**.
  Upgraded and reimported from Unity **2020** → **2023** (in progress / completed during this session).
- **Project root:** `maradel-face/` (the Unity project lives one level down, in `maradel-face/maradel-face/`).
- **Version control:** Unity Collab (`.collabignore` present).

### Layout

| Path | Purpose |
|------|---------|
| `Assets/Scenes/` | Scenes: `Face.unity`, `SampleScene.unity` |
| `Assets/Scripts/Face/` | Lipsync face system (interfaces, rig, providers, controller, driver) |
| `Assets/Docs/` | In-project documentation (Unity-imported, one file per feature) |
| `Packages/manifest.json` | Package dependencies |
| `ProjectSettings/ProjectVersion.txt` | Pins Unity editor version |

### Key packages

- uGUI `2.0.0`, Timeline `1.8.6`, AI Navigation `2.0.0`, Test Framework `1.3.9`.

## Product direction

- **End goal: Maradel swaps FACES at runtime** — the selected face becomes the lipsynced
  talking head (ties into `Assets/Scripts/Face/`; each face ships a `VisemeMap`).
- **Content pipeline:** a 5 GB+ prefab import lands in `Resources/` *now* so models can be
  seen/picked in-editor via the prefab gallery. **Migrate to Addressables** for the shipped
  tablet app — `Resources/` cannot hold a 5 GB+ library in a real build. Gallery source
  loading is isolated to ease that swap.

## Speech / audio source

Maradel's voice backend (`Docs/SPEECH_HOOK.md`): `http://192.168.0.229:9100`. Two hooks —
endless `/voice/stream` MP3 (live, 24 kHz mono, CORS `*`) and per-sentence Socket.IO
`voice:chunk`/`voice:speaking` + finite WAVs at `/voice/file/...` (reliable mobile path), plus
`/voice/preview?text=` one-shot WAV for testing. **No phoneme timing exposed → lipsync derived
from audio.** Unity client in `Assets/Scripts/Speech/`. Sync is realtime (no speaker delay).

## Documentation rules

- **`Assets/Docs/`** = feature docs that ship with the project (fetchable via Unity).
  One Markdown file per feature; update `Assets/Docs/README.md` index when adding one.
- **This file (`CLAUDE.md`)** = project overview + chronological change log (below).
- Document each step *as it happens*, not after.

## ✅ MILESTONE — lipsync WORKING (2026-06-17)

Full chain confirmed in-editor: Maradel TTS → Socket.IO (broadcast) `voice:chunk` → `UnityWebRequestAudioFeed`
(HttpClient download + `WavAudio` decode) → AudioSource → uLipSync (`uLipSync-Profile-Sample`) →
`ULipSyncProvider` → `LipSyncController` → `RocketboxFaceRig` driving `AA_VI_00..14` blendshapes → **mouth
synced to speech, audible in Unity**. Zero manual setup: press Play, `RocketboxAutoRig` auto-bootstraps,
auto-loads a `_facial` avatar, frames it, auto-finds mesh + profile, wires audio+socket+lipsync. Overlay
shows status + scale controls. THIS IS THE KNOWN-GOOD STATE.

## Change log

- **Mute Maradel's voice in Unity (avoid double audio).** `RocketboxAutoRig` now sets the uLipSync
  component's `outputSoundGain = 0` (gated by a serialized `muteUnityVoice`, default true). uLipSync
  analyzes the signal BEFORE that output gain, so the mouth still lip-syncs while Unity emits no sound —
  the Flutter `voice_player` is the single audible owner of the reply. Only this voice AudioSource is
  silenced; `AudioListener` / future sound effects are unaffected.

- **Per-Keli config volume (`Common/KeliConfigVolume.cs`).** Reads `keli_config.json` from
  `Application.persistentDataPath` and applies `volume` to `AudioListener.volume`, re-reading on the
  file's write-time change. The Flutter app writes that file to the app's **external files dir**, which
  on Android is the **same** path as Unity's `persistentDataPath`
  (`/storage/emulated/0/Android/data/com.example.keli_client/files/keli_config.json`) — that's the one
  coordination point between the two halves (see `configs_handoff.md`). Auto-bootstraps on play
  (`RuntimeInitializeOnLoadMethod`, `FindFirstObjectByType`), no scene setup.

- **UI-scale buttons enlarged + centered.** The shared GUI-scale control (`GuiOverlay.ScaleControls`)
  `[−][+]` were tiny (32×24) and tucked in the panel's top-right. Now **96×52 with a bold 26px glyph**
  and a `centered` option (FlexibleSpace both sides). In `RocketboxAutoRig` OnGUI they moved out of the
  header onto their **own centered row** under the title/✕ — big, easy targets on the wall tablet that
  size the whole overlay. (Other callers — `RocketboxGalleryGUI`, `MaradelVoiceTester` — get the larger
  buttons inline automatically.) Panel base height bumped 360→426 for the extra row. Needs a Unity
  re-export + APK rebuild to reach the device.

- **Overlay redesign — friendly model browser + log window.** OnGUI rebuilt around the model browser:
  ◀ current ▶, a **search field** (live filter / autosuggest by filename) and **Browse ▼** that opens a
  vertically scrollable **per-category** list; **every row has a ⧉ copy-name-to-clipboard** button
  (`CopyName` → `GUIUtility.systemCopyBuffer`). Compact status line (mesh/profile/socket/viz). **Send Logs**
  + **Log ▼** open a **bottom live log window** (`SessionLog.Tail()` ring buffer, newest first). All the
  dev tools (emotion testers, body/idle tuning, camera calib, cache) moved behind a **Dev ▼** toggle so the
  main panel stays clean. Persistent GUI scale kept. `SessionLog` gained a 200-line `Tail()` buffer.

- **Fix: green tint over the embedded Unity view → opaque black.** On the Android Unity-as-a-library
  surface, an un-cleared / alpha<1 framebuffer shows green (uninitialised GPU memory / driver default).
  The camera clear was only set in `AutoFrameHead` (runs after an avatar with a head bone loads, and
  early-returns if no anchor) → green for the first seconds. Added `SetupCameraOpaqueBlack()` in `Build()`
  — sets `Camera.main` to SolidColor **opaque** black (alpha 1) from frame 0. Verified no green is drawn by
  our own UI (DownloadProgressView auto-hides; no green literals).

- **Fix: lipsync dead on device (null profile in build) — the REAL cause.** Mouth didn't move on the
  tablet though audio+animation worked. `AutoFindProfile` finds the uLipSync Profile via `AssetDatabase`
  (`#if UNITY_EDITOR`) in-editor, but the build path is `Resources.LoadAll<Profile>("")` — and there was
  **no `Resources/` folder**, so `_ulip.profile` was null on device → uLipSync analyzed but recognised
  nothing. Fix: copied `uLipSync-Profile-Sample.asset` (phonemes A/I/U/E/O/…) into **`Assets/Resources/`**
  so it ships. Diagnostic confirms: 0 viseme frames during speech ⇒ null profile. Overlay log button
  renamed **Send Logs**; uploads a uniquely **timestamped** file (`<session>__<device>__<ts>.log`) to
  nukshare `keli/unity/logs/`.

- **Fix: intermittent lipsync/audio ("plays from time to time") — the post-Play() race.** `UnityWebRequest
  AudioFeed.Pump` did `audioSource.Play(); while(audioSource.isPlaying) yield;` — but on device `isPlaying`
  is FALSE for the first DSP buffer(s) after Play(), so the loop exited on frame 1, cutting the clip and
  firing `OnPlaybackDrained` instantly → sequencer moved on, uLipSync got no sustained audio. Now waits the
  clip's **full duration** (tolerating engine start latency), only bailing early if it genuinely stops, and
  logs a warning if a clip **never** reports isPlaying (→ audio-focus loss, not the race). NB: the clip
  needs no pre-processing — `WavAudio` makes a `stream:false` PCM clip that's Loaded instantly.

- **Visual quality pass (Tier 0/1/2, Built-in RP, no pipeline change):**
  - **Normals/materials:** `Content/Editor/RocketboxTextureSetup.cs` — AssetPostprocessor marks
    `*_normal*.tga` as **NormalMap** on import (they shipped as plain colour → flat face), + menu
    **Maradel ▸ Visuals ▸ Fix Avatar Normal Maps** to reimport existing ones. `RocketboxAutoRig.
    ImproveSkinMaterials()` (in WireFaceRig) enables `_NORMALMAP`/`_SPECGLOSSMAP`, kills metallic, sets
    skin smoothness (~0.28) on head/body materials — wiring the supplied normal+specular maps that the
    auto-FBX materials ignored.
  - **Lighting (hardened against "weird light"):** `EnsureLights()` builds a **3-point rig** (warm key +
    dim cool fill + moderate cool rim), disables the scene's default directional, and forces deterministic
    ambient/reflections (Flat ambient + `reflectionIntensity 0.35` so the skybox doesn't show in glossy
    eyes). **Only the key casts shadows** (no multi-light shadow conflicts), lights are explicit
    **Realtime + ForcePixel**, key shadow bias/normalBias tuned against acne on the skinned mesh.
    `AimLights(head)` re-aims via LookAt each avatar switch.
  - **AA/sampling/shadows (it's ONE model — spend the budget):** `ApplyRenderQuality()` — MSAA 4x +
    forced anisotropic, **4 per-pixel lights**, **full-res textures** (`globalTextureMipmapLimit 0`),
    **VeryHigh StableFit** shadows over a **6 m** distance (no shimmer during camera lerps/gestures),
    0 cascades. Camera `allowMSAA=true`. No HDRP / no heavy post (sane for the old tablet).
  - Needs: run **Fix Avatar Normal Maps** → rebuild Addressables (bundles carry the corrected textures) →
    re-export Unity → rebuild APK. (Tier 3 post-processing/URP deferred.)

- **File-based session logging + Dump button (diagnose tablet lipsync):** `Common/SessionLog.cs` —
  `[RuntimeInitializeOnLoadMethod]` opens a NEW `persistentDataPath/Logs/session-<ts>.log` per run and
  mirrors EVERY Unity log (`Application.logMessageReceivedThreaded`, all threads) into it with
  `AutoFlush` (survives a kill); errors include stack traces. Overlay gains a **📤 Dump log** button →
  `RocketboxAutoRig.DumpLog()` PUTs the file to nukshare `http://192.168.0.229:7777/api/shared/keli/unity/
  logs/<file>` via HttpClient (bypasses Unity's http policy; works on the tablet). Shows file name + line
  count + upload status. Captures the existing `[AudioFeed]`/`[MaradelVoice]`/`[EMOTE]` etc. for the
  intermittent-lipsync investigation. (Requires a Unity re-export + APK rebuild to reach the device.)

- **`Maradel/Build` review + bundles-only mode.** Added **`Maradel ▸ Build Bundles (no client)`** —
  runs build Addressables → wipe remote → upload → verify and **STOPS** (skips the Android export) for
  testing remote loading. `Build()`/`BuildBundles()` share `RunPipeline(includeClient)`; step labels +
  ETA history adapt (1/4..4/4 vs 1/5..5/5). Dialog/log now show the **active build target** (bundles are
  built for whatever platform the editor is on). Fixed `AddressableBuilder` to **not** force PackSeparately
  on every group — each group keeps its own packing (models PackSeparately, `Anim_Gestures` PackTogether),
  so the ~70 small clips stay one bundle. Verified: HTTP downloads allowed (`insecureHttpOption: 2`), so
  remote http loading isn't blocked.

- **Fix: male/idle gestures failed to load (`Unrecognized bundle error`).** Root cause: `Anim_Gestures`
  only had the 17 original `f_` entries — the `m_` + idle clips added with the gender/idle work were never
  marked addressable (so a male avatar's `m_*` clips threw `InvalidKeyException`). `AddressableAnimSetup`
  now **auto-marks on editor load/recompile** (`[InitializeOnLoadMethod]`) whenever the group has fewer
  entries than `AnimationDirector.AllClipAddresses()` expects — self-healing when the clip list grows.
  (In-editor testing still needs Addressables Play Mode = **Use Asset Database**.)

- **Gender-aware clips + capped body + random idles:** (1) `AnimationDirector` now stores clip **stems**
  (no `f_`/`m_`) and prepends the avatar's gender prefix at play time. Gender is detected from the avatar
  name (`RocketboxAutoRig.IsMaleAvatar` — tests `"female"` before `"male"`); `Configure(Animator, male)`.
  Verified all gesture+idle stems have both `f_`/`m_` variants except `self-assured` (female-only →
  `MaleStemOverride`). `AllClipAddresses()` enumerates both genders for `AddressableAnimSetup` (now marks
  ~70 clips). (2) Body gesture is **capped at speech length × (1 + `BodyOverhangPct`)** (default +25%,
  configurable) then drops to idle — `SpeechLengthOf` sums the plan's chunk durations; 0 ⇒ uncapped.
  (3) When **not busy** (not talking, no gesture), the body track plays **gender-appropriate idle clips**
  (`f_/m_idle_*`, 18 curated standing motions) at random intervals (`IdleGapMin/Max`); `IdleRandom` toggles
  random-pick vs first-only; `IdleEnabled` on/off. Idles cut short on a new message or when talking starts.
  `PlayClip(address)` plays an explicit clip; `PlayAndHold(emotion, maxSeconds, cancelled)` caps gestures.
  All tunable live in the OnGUI overlay (overhang %, idle on/off, random/only, gap min/max).

- **Queue speech, interrupt body (per-channel policy):** `EmotionSequencer` now runs three persistent
  tracks instead of a per-plan coroutine. **SPEECH** = FIFO `_speechQueue`, NEVER interrupted — a new
  message waits its turn and every utterance plays in full. **BODY** = latest-wins + INTERRUPTIBLE via a
  `_bodyGen` generation token: a new message bumps the gen, which cuts the running gesture short and plays
  the **last** message's gesture; stale gestures are dropped. `IGesturePlayer.PlayAndHold(emotion, Func<bool>
  cancelled)` / `AnimationDirector` poll the cancel token each frame and bail mid-hold. **CAMERA** director
  frames FACE while talking, BODY otherwise (interruptible `RocketboxAutoRig.StepCameraToward`, with
  `bodyReturnDelay` hold so phrase gaps don't flicker). Net: new message never cuts off speech, always takes
  over the body. All `[EMOTE]`/`[speech]`/`[body]`/`[camera]`/`[ANIM]` logged.
- **(prior) Body + face play TOGETHER (concurrent), camera follows talking** — superseded by the
  per-channel queue/interrupt model above; `StepCameraToward` (interruptible exponential smoothing) retained.

- **Manual emotion tester in overlay (no backend needed):** TWO separate pickers in the OnGUI overlay —
  a **FACE** row (cycles `ExpressionController.EmotionIds`, fires expression + talk) and a **BODY** row
  (cycles `AnimationDirector.EmotionIds`, shows `emotion → clip`, fires the gesture). Clarifies that face vs
  body is the beat **channel**, not a different emotion name. `RocketboxAutoRig.TestSingleEmotion(emotion,
  body)` builds a one-beat `VoicePlan` and runs it through the **same sequencer path** (camera lerp +
  expression/gesture/talk). `ExpressionController.EmotionIds` / `AnimationDirector.EmotionIds` + `ClipFor`
  expose the lists.
- **Sequencer timing reworked (per user spec):** each beat = LERP camera to perspective
  (`RocketboxAutoRig.LerpFrame`, SmoothStep pos/rot/fov, configurable `cameraLerpTime`) → wait
  `preActionDelay` → action → wait `postActionDelay` → next. BODY action = gesture **held for the
  clip's own length** (`AnimationDirector.PlayAndHold` reads `clip.length`, sequencer waits via
  `IGesturePlayer`/`SetGesturePlayer`). FACE action = expression + `voiceDelay` (camera↔voice gap) +
  talk (audio+lipsync, wait drained). All delays configurable on EmotionSequencer; fully `[EMOTE]`/
  `[ANIM]` logged. Camera now lerps (not snaps) between beats.
- **Expression + gesture controllers (emotion → visible motion):** `Face/ExpressionController.cs` —
  emotion id → ARKit `AK_*` blendshape pose (22 emotions mapped), smoothed, on the facial mesh,
  layered over the `AA_VI_*` visemes (disjoint shapes). `Speech/AnimationDirector.cs` (`#if ADDRESSABLES`)
  — emotion id → Rocketbox gesture clip (`ClipByEmotion` map to `f_gestic_*`/`cheer`/`shrug`/etc),
  loaded via Addressables, played via Playables (`AnimationPlayableUtilities.PlayClip`) on the avatar's
  Generic Animator. `Editor/AddressableAnimSetup.cs` → menu **Mark Animations** (group Anim_Gestures,
  label anim+essential, pack-together, remote). Auto-rig creates both once, subscribes to the sequencer's
  `OnFaceEmotion`/`OnBodyEmotion`, and re-binds them to each avatar's mesh/animator in WireFaceRig.
  Expressions work immediately (no setup); gestures need: run **Mark Animations** + Addressables Play
  Mode "Use Asset Database" (in-editor) or a Maradel ▸ Build (remote). Risk: AnimationClip-from-FBX
  addressable load may need a sub-object key tweak; Generic Animator must exist on the avatar.
- **Backend now emits `voice:plan` live** (confirmed in log) with the beat array
  (`[body:excited 1.5s, face:joyful + chunk]`). Sequence runs correctly: camera BODY(fov39)→hold→
  FACE(fov16)→talk+lipsync. **Double-audio bug fixed:** backend sends BOTH `voice:chunk` AND
  `voice:plan` (same chunk) → it was enqueued twice. Added `planDrivesAudio` (default true) so the
  `voice:chunk` handler no longer enqueues; the sequencer (voice:plan) owns audio → plays once on the
  face beat. (Body gesture + face expression still stubs = logged, not rendered.)
- **Emotion sequence (`voice:plan`):** confirmed backend emits emotions (`speech/emotion.ts`, 22
  `AVATAR_EMOTIONS`; current single `voice:emotion`). Designed the richer **`voice:plan`** — an ordered
  array of **beats**, each `face` (talk+lipsync+expression, camera FACE-centred, audio chunks here) or
  `body` (full-body gesture, camera BODY-centred, silent). `Speech/VoicePlan.cs` (VoicePlan/VoiceBeat/
  VoiceChunkRef, System.Text.Json properties) + `Speech/EmotionSequencer.cs` play beats in order
  (camera via `RocketboxAutoRig.SetPerspective`, audio gated to face beats, `OnFaceEmotion`/`OnBodyEmotion`
  events for the future ExpressionController/AnimationDirector). `MaradelVoiceSocketClient` parses
  `voice:plan` (prefixes chunk urls) → `OnPlan`; auto-rig wires `OnPlan → EmotionSequencer.PlayPlan`.
  Documented in `Docs/UNITY_HANDOFF §7c`. Face/body framings = the two calibration DBs.

- **Autozoom (`AutoFrameHead`):** from calibration, camera = `Bip01 Head` worldPos + offset (default
  `(0, 0.076, -2.22)`), identity rotation, fov 16; avatar oriented to face the camera (`avatarFaceEuler`
  default 0,180,0). Runs every avatar load (moves the CAMERA, not the avatar → no drift). Replaced the
  old `FrameToCamera`. All tunable in the inspector.
- **Cache logging + overlay (`Content/CacheLog.cs`):** timestamped lines to Console `[CACHE]` AND a file
  `<persistentDataPath>/Logs/maradel-cache.log`, plus a recent-lines ring buffer. Routed: content/version
  state, catalog check/update (auto-update), per-avatar download (not-cached / cached / failed / already-
  cached), and Unity AssetBundle cache used/free (`Caching.defaultCache`). New **Cache ▼ toggle** in the
  rig overlay shows version, used/free MB, the log path, and the recent `[CACHE]` lines (scroll). Ready
  to observe real-bundle behavior when Play Mode = "Use Existing Build".
- **Project upgraded to Unity 6 (6000.5), Addressables 2.9.1.** Pipeline code targets the 2.x API.
- **`Maradel ▸ Build` one-button pipeline** (`Content/Editor/MaradelBuildPipeline.cs`): (1) build
  Addressables (clean+build, remote, pack-separately) → ServerData; (2) wipe `/mnt/cache/addressables`
  via API; (3) upload each bundle `PUT /api/shared/addressables/<rel>` with cancelable progress + ETA;
  (4) verify remote file count vs local via `/api/fs`; (5) export Android client (exportAsGoogleAndroidProject).
  Timestamped `[BUILD]` logs, per-step size+time → `BuildLog.json` for ETA averages. Helpers:
  `MaradelApi` (egregor-share client via HttpClient), `BuildLog`, `AddressableBuilder.BuildContent`.
  egregor-share API on pi: symlink `shared/addressables → /mnt/cache/addressables` (HDD, 662 GB free;
  root only 11 GB). `tool/upload-addressables.ps1` = standalone uploader.
- **Auto-update + cache:** `MaradelPreloader` checks `CheckForCatalogUpdates`/`UpdateCatalogs` on boot
  (rebuilt content auto-pulls, no app rebuild); cache/version logged `CACHE:`/`[CONTENT]`. Build sets
  `BuildRemoteCatalog=true` + stamps `contentVersion`.
- **Delivery/embedding prep (per UNITY_HANDOFF §11):** Flutter embeds Unity via `flutter_embed_unity`
  2.0.0 (Unity-side package = export pipeline + bridge). Added `Assets/Scripts/Bridge/FlutterControlBridge.cs`
  — non-Zenject component on an auto-created GameObject named **`FlutterFace`** with `OnMessage(string)`;
  control JSON `{type,value,index}` (next/prev/load/scale/show/hide) → drives `RocketboxAutoRig` (added
  `SetVisible`). Outbound via `Face/FlutterFace.Emit` (`#if FLUTTER_EMBED_UNITY`). Voice/lipsync is
  independent (broadcast socket) — bridge is control-only. **Export:** install package + `FLUTTER_EMBED_UNITY`
  define → Flutter Embed Unity ▸ Export Android → zip `unityLibrary` → nukshare `:9090`. Build = Android/
  IL2CPP/ARM64/Burst-AOT. ⚠️ **Unity version gap:** project is 2023.2.22f1 but Play needs 6000.3.0f1+ (16 KB
  pages) — upgrade required for a Play build (fine for HOME sideload).
- **Addressables migration (2026-06-17):** moved all models OUT of `Resources/` →
  `Assets/App/Content/Models/` (filesystem move, GUIDs preserved). Added `com.unity.addressables`
  1.22.3. New `Assets/Scripts/Content/`: `BuildConfig` (SO: remote paths/version/labels),
  `DownloadProgress` + `DownloadProgressView` (Image.fillAmount), `RemoteAvatars` (helpers + bundle-
  error coaching), `MaradelPreloader` (downloads `essential` label w/ progress), `Editor/
  AddressableModelSetup` (mark addressable, groups=category dirs, **pack-separately**, labels
  avatar/essential), `Editor/AddressableBuilder` (set remote paths from BuildConfig → BuildPlayerContent,
  remote catalog). `RocketboxAutoRig` now loads avatars **remotely** (LoadResourceLocations by label →
  InstantiateAsync; ◀/▶ does GetDownloadSize → DownloadDependencies w/ progress → instantiate; releases
  via ReleaseInstance). All gated `#if ADDRESSABLES`. **Activation:** reimport → add `ADDRESSABLES`
  define → create BuildConfig → run menu 1 (mark) + 2 (build) → upload ServerData. In-editor test:
  Addressables Play Mode = "Use Asset Database". See `Docs/ADDRESSABLES.md`. Logs tagged `[CONTENT]`.
- Added live **avatar switching** to `RocketboxAutoRig`: overlay ◀/▶ buttons cycle all discovered
  `_facial` avatars (`AutoFindAllAvatarPaths`), `LoadAvatarAt(i)` destroys+loads+reframes+re-wires the
  rig/controller (provider/audio/socket persist). Plus model scale –/+/reset. = Maradel face-swap, live.

### 2026-06-17
- Confirmed this is a Unity project; verified upgrade to **2023.2.22f1** (from Unity 2020)
  via `ProjectSettings/ProjectVersion.txt`.
- Created `Assets/Docs/` folder with `README.md` index for Unity-imported documentation.
- Created this `CLAUDE.md` as the project overview and step-by-step change log.
- Researched uLipSync v3 runtime API. **Correction to LIPSYNC.md:** uLipSync emits results
  via the `onLipSyncUpdate` UnityEvent carrying `LipSyncInfo { string phoneme; float volume;
  float rawVolume; Dictionary<string,float> phonemeRatios }` — NOT a PCM `OnDataReceived`
  output. `ULipSyncProvider` subscribes to that event.
- Implemented the full Face system in `Assets/Scripts/Face/` per LIPSYNC.md:
  - Core (no deps): `Viseme`, `IFaceRig`, `ILipSyncProvider`, `IAudioFeed`, `VisemeMap` (SO),
    `SkinnedMeshFaceRig` (model-control MonoBehaviour, name→index blendshapes, smoothing,
    "Log Blend Shape Names" context menu), `AmplitudeLipSyncProvider`, `AudioTap`,
    `UnityWebRequestAudioFeed`, `LipSyncController` (pure C#), `FaceDriver` (standalone wiring).
  - Gated: `ULipSyncProvider` (`#if ULIPSYNC`), `FlutterFace`/`FlutterFaceBridge`/`FaceInstaller`
    (`#if ZENJECT` / `#if FLUTTER_EMBED_UNITY`) so the project compiles before packages exist.
- Added `Assets/Docs/SETUP.md` (M0→M3 checklist + script reference). User is downloading the
  Microsoft Rocketbox avatar set (MIT) for testing.
- Built `Assets/Scripts/Gallery/PrefabGallery.cs` — prefab gallery panel (decisions confirmed
  with user): **instantiate** prefabs from `Resources/<root>/<folder>`, Left/Right cycle items,
  Folder Prev/Next cycle folders, Slider 0–100 scales the live instance, **TMP** labels for
  scale/item/folder, and an Editor **"Scan Resources Folders"** context menu (Resources can't
  enumerate subfolders at runtime, so the folder list is serialized + scanned from disk).
- A 5 GB+ prefab import is incoming to `Resources/` (`Assets/App/Content` staging folders exist
  but are empty; no git repo, so no diff). Documented Resources→Addressables plan + the
  Maradel face-swap end goal in `Docs/README.md`, `Docs/GALLERY.md`, and above.
- Verified the **Microsoft Rocketbox** repo (MIT): FBX + textures, fully rigged, 115 chars,
  **15 visemes** + 48 FACS + ARKit blendshapes → near 1:1 with our Oculus-15 `Viseme` enum.
  Ships `Assets/Editor/FixRocketboxMaxImport.cs` (materials/humanoid fix — must keep). Models
  are **FBX not prefabs** → plan: a prefab variant per character carrying `SkinnedMeshFaceRig`
  + `VisemeMap`. Confirms the lipsync + face-swap goal is achievable. Recorded in `Docs/SETUP.md`.
- Rocketbox import finished: ~23 GB at `Assets/App/Content/Resources/Microsoft-Rocketbox-master/`,
  728 FBX. Categories: Animals, Animations, Avatars (Adults 40 / Children 4 / Professions 73 =
  117 humans), Editor. **Each avatar has two FBX: `Name.fbx` + `Name_facial.fbx`** — the
  `_facial` one has the viseme blendshapes (use it for lipsync). `FixRocketboxMaxImport.cs` is
  stuck inside Resources/.../Assets/Editor — should be moved to `Assets/Editor/`.
- Added `Assets/Scripts/Gallery/RocketboxGalleryGUI.cs` — legacy **OnGUI** model browser (no
  Canvas) per user request: drag on one GameObject, ◀/▶ buttons, path label, `Resources.Load`
  by path (one at a time, no LoadAll), `_scale` float scales the GUI, `–/+` scale the model,
  Editor "Scan Resources" context menu fills the path list (filters `_facial`).
- Lipsync engine investigation (`Docs/LIPSYNC_OPTIONS.md`): read the FBX channels directly +
  HeadBox docs → **Rocketbox `_facial` meshes have `SR_01..SR_42` + `AK_01..AK_52`; `SR_01..SR_15`
  are the 15 Oculus visemes in Oculus order, identical on all 117 avatars.** Compared uLipSync
  (MIT, recommended) vs OVRLipSync (1:1 but EOL/native) vs SALSA (paid, volume-only) vs TTS
  visemes (N/A — Kokoro emits no timing). Built **`Assets/Scripts/Face/RocketboxFaceRig.cs`** —
  drop-on-`_facial`-prefab `IFaceRig` with the baked `Viseme→SR_01..15` map (no VisemeMap asset
  needed), auto-finds the facial mesh, tolerates `<mesh>.SR_01` names. Caveat: uLipSync is
  vowel/MFCC-based so it drives ~5–6 of the 15 visemes (enough for a believable head).
- Verified SR_01..15 order holds on Adults/Professions/Children `_facial` FBX. uLipSync sample
  profile phonemes confirmed = `A I U E O N -`. Read `FixRocketboxMaxImport.cs`: it's an
  AssetPostprocessor (fixes materials, sets Generic rig); compiles fine; will throw harmless NREs
  importing non-biped FBX (animals/animations).
- Decoupled the pipeline so the **Rocketbox path is zero-config**: `LipSyncController` no longer
  takes a `VisemeMap` (it never used it); `ULipSyncProvider` takes an *optional* map and falls
  back to new `PhonemeMap` defaults (`A/I/U/E/O/N/-` → visemes); `FaceDriver` no longer requires a
  VisemeMap; `FaceInstaller` only binds one if assigned. Net: drop `RocketboxFaceRig` + uLipSync +
  `FaceDriver` (ULipSync mode) and it works with no authored asset.
- Upgraded `RocketboxGalleryGUI`: OnGUI **folder dropdown** (scrollable list) + folder ◀/▶ + item
  ◀/▶; editor scan now groups facial FBX by subfolder (Adults/Children/Professions).
- Built the Maradel voice client (`Assets/Scripts/Speech/`, see `Docs/SPEECH_SETUP.md`):
  `MaradelVoiceConfig` (URL builders), `MaradelStreamPlayer` (endless `/voice/stream` MP3 →
  AudioSource, zero-dep, desktop-reliable), `MaradelVoiceSocketClient` (`#if MARADEL_SOCKETIO`:
  per-chunk `voice:chunk`→`UnityWebRequestAudioFeed`, the shipped mobile path),
  `MaradelVoiceTester` (OnGUI `/voice/preview` speak + radio toggle, for HOME testing/calibration).
  Confirmed sync is realtime — no speaker delay needed.
- Installed **SocketIOUnity** (`com.itisnajim.socketiounity`, UPM git) — auto-referenced,
  `SocketIOClient` namespace. Added `MARADEL_SOCKETIO` define (Standalone + Android in
  `ProjectSettings.asset`). Rewrote `MaradelVoiceSocketClient` to `SocketIOUnity` + `OnUnityThread`
  (main-thread handlers, no manual queue). DTOs are auto-properties (System.Text.Json binds
  properties, case-sensitive — match Maradel's JSON keys). **No Maradel backend change needed.**
- Overlay polish: added `Assets/Scripts/Common/GuiOverlay.cs` — IMGUI helper anchored to the
  **square viewport** (face renders on a square stage; overlay maps "design units" 0..1000 across
  the square edge, aspect-independent) with a **transparency** alpha. `RocketboxGalleryGUI` and
  `MaradelVoiceTester` now use it (fields `_scale`/`guiScale` + `_overlayAlpha`/`overlayAlpha`).
  Both show a **status line** (▶ running, model/folder counts, audio playing). `MaradelVoiceSocketClient`
  exposes `State` (Disconnected/Connecting/Connected/Error) + `IsSpeaking` + `LastError`, shown
  colour-coded in the tester. **Verbose logging** toggles added (socket client on by default; GUIs opt-in).
- Wrote `Assets/Docs/UNITY_HANDOFF.md` — integration spec for the backend owner: data flow, the
  Socket.IO contract (URL/transport/EIO/namespace), exact event names + camelCase payload shapes
  (`voice:speaking`, `voice:chunk`), HTTP endpoints, scene setup, packages/defines, and **3 open
  questions** to confirm with Maradel (channel scope broadcast vs room, socket.io version, url path).
- Backend owner answered (handoff §10): events now **broadcast** (`io.emit`, was room-scoped — that's
  why Unity heard nothing), socket.io **v4/EIO4**, `voice:chunk.url` is a **path**. No Unity contract
  change needed. Host = `192.168.0.229:9100` (Maradel device).
- Added `Speech/MaradelVoiceProbe.cs` — one drop-in diagnostic: self-creates an audible **2D**
  AudioSource (spatialBlend=0 — the #1 reason Unity was silent) + feed, connects to the socket,
  plays chunks, and draws a status HUD (SOCKET state, chunks received, AUDIO playing/volume/mute,
  AudioListener present) + a local **Beep** to isolate audio-output from network.
- **First live test (Face scene):** socket connected, `voice:speaking`/`voice:chunk` received
  (broadcast confirmed working), enqueue+download started — but download threw
  `InvalidOperationException: Insecure connection not allowed`. Root cause: Unity's
  `insecureHttpOption` (Player ▸ Allow downloads over HTTP) defaults to 0/blocked, and Maradel is
  plain `http://`. **Fixed: set `insecureHttpOption: 2` (Always allowed) in `ProjectSettings.asset`.**
  Pipeline otherwise fully healthy. TODO for Android build: enable cleartext HTTP in the manifest.
- The editor `insecureHttpOption` change wouldn't take (running editor ignored the file edit; UI
  toggle also flaky for the user), AND a download exception left `UnityWebRequestAudioFeed._pumping`
  stuck true so later chunks silently never played. **Rewrote the feed to download via
  `System.Net.Http.HttpClient`** (not subject to Unity's insecure-HTTP policy → plain http:// works
  with no editor toggle), decode WAV via new `Face/WavAudio.cs` (PCM 8/16/24/32 + float32), wrap the
  pump in try/finally (never gets stuck), save each WAV to `<persistentDataPath>/MaradelVoice`, and
  log every step. HOCO speaker is server-side (always worked, independent of Unity).
- **Real silence cause found:** `voice:speaking{on:false}` fires when Maradel *finishes synthesizing*,
  but Unity lags (just started downloading the chunk) — and our handler called `feed.Stop()` on
  on:false, which `StopAllCoroutines()` aborted the in-flight download before it played. **Removed
  the Stop() on speaking:false** in both `MaradelVoiceProbe` and `MaradelVoiceSocketClient`; the feed
  now drains its queue and resets on its own. (Future: flush queue on a NEW utterance / explicit barge-in.)
- **uLipSync installed + `ULIPSYNC` define added** (verified runtime API: `uLipSync.uLipSync.onLipSyncUpdate`,
  `LipSyncInfo{phoneme,volume,phonemeRatios}`). First live Maradel audio **heard in Unity** ✅.
- **Inspected `_facial` hierarchy across Adults/Children/Professions + male/female:** identical shape —
  exactly ONE SkinnedMeshRenderer named `<id>_hipoly` (f001/m002/f014…), skeleton root `Bip01`, one
  `blendShape1` node with `SR_*`+`AK_*`. No LOD meshes in `_facial`. So finding by `SR_01` blendshape
  is fully avatar-agnostic; no LOD ambiguity.
- Built **`Speech/RocketboxAutoRig.cs`** — drop on a `_facial` avatar root, auto-wires the whole talking
  head on Awake (find facial mesh → AudioSource 2D → feed → uLipSync+Profile → RocketboxFaceRig →
  ULipSyncProvider+LipSyncController → MaradelVoiceSocketClient). Logs every step + a full hierarchy
  inventory with the **`[SYNC_BEH]`** tag (grep the Console to verify). Added `MaradelVoiceSocketClient.Configure()`
  for runtime wiring; `RocketboxFaceRig` now prefers the active mesh and logs its viseme resolution `[SYNC_BEH]`.
- Audio path fully verified in editor via the probe (download/decode/play, 1.05s & 6.70s clips, 24kHz mono).
- **Made the uLipSync Profile auto-found** (user wanted zero manual assignment): `RocketboxAutoRig`
  scans `AssetDatabase.FindAssets("t:Profile")` (editor) — the package ships profiles under
  `Packages/com.hecomi.ulipsync/Assets/Profiles/` (e.g. `uLipSync-Profile-Sample`, phonemes A/I/U/E/O),
  so it works without importing Samples; picks most-trained, prefers "Sample". Build fallback:
  `Resources.LoadAll<uLipSync.Profile>`. Now mesh AND profile auto-assign — nothing to wire by hand.
- **Zero-setup bootstrap:** `RocketboxAutoRig` now (a) auto-loads + instantiates a `_facial` avatar from
  Resources if its GameObject has none; (b) frames it to Camera.main; (c) a `[RuntimeInitializeOnLoadMethod]`
  creates a RocketboxAutoRig on Play if none exists in the scene. Press Play in the Face scene — avatar
  loads, wires, lipsyncs, connects to Maradel, nothing placed/dragged/assigned. All steps `[SYNC_BEH]`.
- **CORRECTION — real viseme names:** the runtime hierarchy dump revealed Unity blendshape names are
  `blendShape1.AA_VI_00_Sil .. AA_VI_14_U` (Oculus-15 visemes), NOT `SR_01..15` (those are the
  SRanipal eye/jaw/mouth tracking shapes). Rewrote `RocketboxFaceRig.ShapeByViseme` to `AA_VI_00..14`
  and switched detection to the `AA_VI_` marker (in both RocketboxFaceRig + RocketboxAutoRig).
  Full shape list: AA_VI_00..14 (visemes), AK_01..52 (ARKit), AU_* (FACS), HB_* , SR_01..42 (SRanipal).
- **Fixed `MissingComponentException`:** `GetComponent ?? AddComponent` hits Unity's fake-null `??`
  pitfall → AudioSource never created → Build threw mid-setup (which also suppressed the OnGUI overlay).
  Replaced all with a null-safe `Ensure<T>()` (uses Unity's overloaded `==`). Also added a resilient
  Build (missing mesh no longer aborts audio/socket) + an OnGUI status overlay on RocketboxAutoRig.
