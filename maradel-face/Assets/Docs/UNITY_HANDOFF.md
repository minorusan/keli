# UNITY_HANDOFF.md — the 3D lipsynced face, and what Maradel must emit

This is the integration spec for the Unity talking-head. **Audience:** (1) the Maradel backend
owner — to confirm the events/endpoints below exist on the right channel; (2) the Unity
integrator — to wire the scene. Verified against this project on 2026-06-17.

> **Headline for the backend owner:** the Unity face needs **no new backend work** *if* Maradel
> already emits `voice:speaking` + `voice:chunk` over Socket.IO on `:9100` and serves the chunk
> WAVs. This doc states the exact channel, event names, and payload shapes so you can confirm.
> The 3 things to verify are in [§7 Open questions](#7-open-questions-for-the-maradel-side).

---

## 1. Goal

Maradel speaks → a 3D face (Microsoft Rocketbox avatar) lipsyncs **in real time**, and Maradel
can **swap faces** at runtime. Lipsync is derived from the audio (no phoneme timing needed from
the backend). Sync is realtime — **do not delay the speaker**.

## 2. End-to-end data flow

```
Maradel backend (:9100)                     Unity (this project)
─────────────────────                       ─────────────────────────────────────────
TTS (Kokoro / Vosk)
   │  per sentence
   ├─ emit  voice:speaking {on:true} ──────► MaradelVoiceSocketClient  (Socket.IO, WebSocket)
   ├─ emit  voice:chunk {url,index,dur} ───► → UnityWebRequestAudioFeed.Enqueue(fileUrl,...)
   │                                              │ downloads GET /voice/file/..wav
   │                                              ▼
   │                                          AudioSource.Play()  ──►  uLipSync (same GameObject)
   │                                              │                       │ MFCC → phonemes
   └─ emit  voice:speaking {on:false} ─────►  feed.Stop()                 ▼
GET /voice/file/<sid>/<i>.wav  ◄── fetched ──                        ULipSyncProvider
GET /voice/preview?text=..     (testing)                                 ▼
GET /voice/stream  (live MP3, alt path)                             LipSyncController
                                                                         ▼
                                                                    RocketboxFaceRig → SR_01..15
                                                                         (the face talks)
```

## 3. THE CONTRACT — what Maradel must provide

### 3.1 Socket.IO channel
| Item | Value the Unity client uses |
|---|---|
| URL | `http://<host>:9100` (default host `192.168.0.229`; `localhost` if co-located) |
| Transport | **WebSocket** (client forces it) |
| Engine.IO | **EIO v4** (modern socket.io v3/v4). If backend is socket.io **v2**, tell us → set `EIO=V3`. |
| Namespace | default **`/`** |
| Auth | none (LAN) |
| Delivery | Unity assumes events are **broadcast to every connected socket** (no room/session join). |

### 3.2 Events the Unity client subscribes to
**Names and payload keys are matched exactly and case-sensitively** (deserialized by
System.Text.Json). Keys must be **camelCase** as below.

```jsonc
// event: "voice:speaking"   — brackets each utterance
{ "sessionId": "string", "on": true }      // on:true at start, on:false at end

// event: "voice:chunk"      — one synthesized sentence is ready to play
{ "sessionId": "string",
  "index": 0,                 // playback order (int)
  "url": "/voice/file/<sid>/<index>.wav",   // path or absolute URL
  "durationSec": 1.23 }       // float
```

- On `voice:chunk` → Unity fetches the WAV and plays it in `index` order.
- On `voice:speaking {on:false}` → Unity stops/drains and resets the mouth.

### 3.3 HTTP endpoints used
| Endpoint | Used for | Must return |
|---|---|---|
| `GET /voice/file/<sid>/<name>.wav` | per-chunk playback (the lipsync path) | finite `audio/wav`, CORS `*` |
| `GET /voice/preview?text=...` | **testing** (speak without the full pipeline) | one-shot `audio/wav` |
| `GET /voice/stream` | optional live MP3 radio (alt path) | endless `audio/mpeg`, 24 kHz mono, CORS `*` |

All of the above are documented as already existing in `SPEECH_HOOK.md`.

## 4. What's built on the Unity side (done)

| Area | Scripts (`Assets/Scripts/…`) | Status |
|---|---|---|
| Lipsync core | `Face/IFaceRig`, `ILipSyncProvider`, `IAudioFeed`, `Viseme`, `PhonemeMap`, `LipSyncController` | ✅ compiles, no deps |
| Face rig (Rocketbox) | `Face/RocketboxFaceRig` — bakes `Viseme→SR_01..15`, **zero per-model setup** | ✅ |
| Generic face rig | `Face/SkinnedMeshFaceRig` + `VisemeMap` (for non-Rocketbox models) | ✅ |
| Lipsync providers | `Face/AmplitudeLipSyncProvider` (PoC) · `Face/ULipSyncProvider` (`#if ULIPSYNC`) | ✅ / gated |
| Audio in | `Face/UnityWebRequestAudioFeed`, `Face/AudioTap` | ✅ |
| Standalone wiring | `Face/FaceDriver` (Amplitude or ULipSync) | ✅ |
| DI wiring (optional) | `Face/FaceInstaller` + `FlutterFaceBridge` (`#if ZENJECT`) | gated |
| Voice client | `Speech/MaradelVoiceConfig`, `MaradelStreamPlayer`, `MaradelVoiceSocketClient`, `MaradelVoiceTester` | ✅ (`MARADEL_SOCKETIO` define on) |
| Model gallery | `Gallery/RocketboxGalleryGUI` (OnGUI, folder dropdown, scale) | ✅ |
| Overlay UI | `Common/GuiOverlay` (square-viewport, transparency) | ✅ |

**Verified facts:** Rocketbox `*_facial` meshes carry `SR_01..SR_42`+`AK_01..AK_52`; `SR_01..SR_15`
= the 15 Oculus visemes in order, identical across Adults/Children/Professions (117 avatars).
uLipSync sample profiles use phonemes `A I U E O N -`. See `LIPSYNC_OPTIONS.md`.

## 5. Packages / defines

| Need | How | For |
|---|---|---|
| **SocketIOUnity** | UPM git: `https://github.com/itisnajim/SocketIOUnity.git` | per-chunk voice path |
| define **`MARADEL_SOCKETIO`** | Player ▸ Scripting Define Symbols (Standalone+Android) — **set** | enables `MaradelVoiceSocketClient` |
| **uLipSync** | UPM git: `https://github.com/hecomi/uLipSync.git#upm` + import Samples | real visemes |
| define **`ULIPSYNC`** | Player ▸ Scripting Define Symbols | enables `ULipSyncProvider` |

## 6. Scene setup (per-chunk talking head)

```
AudioGO   : AudioSource + uLipSync (assign a Profile) + UnityWebRequestAudioFeed
AvatarGO  : a *_facial Rocketbox model  + RocketboxFaceRig
DriverGO  : FaceDriver (Mode=ULipSync; faceRig=RocketboxFaceRig; uLipSync=AudioGO's uLipSync)
VoiceGO   : MaradelVoiceSocketClient (audioFeed=AudioGO's feed; host=192.168.0.229)
(optional): MaradelVoiceTester (Speak preview), RocketboxGalleryGUI (browse faces)
```
For a no-backend smoke test: `MaradelVoiceTester` → type text → **Speak** hits `/voice/preview`.

## 7. Open questions for the Maradel side

Please confirm these three — each is a 1-line change on our side if the answer differs:

1. **Channel scope:** are `voice:speaking` / `voice:chunk` **broadcast to all connected sockets**,
   or scoped to a room/session the client must `join`? (Unity currently assumes broadcast.)
2. **Socket.IO version:** v3/v4 (EIO4)? If v2, we set `EIO=V3`.
3. **`voice:chunk.url`:** confirmed a path like `/voice/file/<sid>/<index>.wav` (we prefix the
   base URL) — or already absolute?

Also confirm: backend reachable at `192.168.0.229:9100` from the Unity device, WebSocket allowed,
CORS `*` on the voice endpoints (all per `SPEECH_HOOK.md`).

## 7b. DELIVERY — embedding Unity into the Flutter (Keli) app

Voice/lipsync already works over the broadcast socket; the Flutter↔Unity bridge is only for
**control** (embed, show/hide, face-swap). Minimum path to a talking square: install the embed
package → export → send `unityLibrary`.

- **Unity side — there is NO Unity Package Manager / Asset Store entry.** Download the `.unitypackage`
  from the plugin's GitHub **Releases** (`https://github.com/learntoflutter/flutter_embed_unity/releases`)
  and import via **Assets ▸ Import Package ▸ Custom Package**. We are **Unity 6.5 → use
  `flutter_embed_unity_6000_0.unitypackage`** (NOT `flutter_embed_unity_2022_3.unitypackage`). This adds a
  `FlutterEmbed` folder with the export menu **`Flutter Embed ▸ Export project to Flutter app`** and the
  bridge classes (`SendToFlutter`, etc.). Then add scripting define **`FLUTTER_EMBED_UNITY`**.
  *(Alt: Package Manager ▸ + ▸ git URL for the Unity-6 repo, or copy the example's `FlutterEmbed` folder.)*
- **Flutter side — `pubspec.yaml` (the app dev, NOT Unity):** add `flutter_embed_unity` **plus the Unity 6
  Android impl `flutter_embed_unity_6_android`**. Do **NOT** add `flutter_embed_unity_2022_3_android` (that's
  the 2022.3 impl / the opt-OUT of Unity 6). **iOS** needs no extra dependency.
- **Bridge (already in this project):** `Assets/Scripts/Bridge/FlutterControlBridge.cs` — a
  non-Zenject component on a GameObject named **`FlutterFace`** (auto-created on Play) with
  **`OnMessage(string)`**. Inbound control JSON `{type,value,index}`:
  `next | prev | load | scale | show | hide` → drives `RocketboxAutoRig`. Outbound via
  `SendToFlutter.Send` (wrapped by `Face/FlutterFace.cs`, gated `#if FLUTTER_EMBED_UNITY`).
- **Build settings (the exporter's pre-check enforces all of these or it aborts):** platform **Android** ·
  **IL2CPP** · **Export Project** ticked · target architectures **ARMv7 + ARM64 (BOTH required by the
  plugin)** · **Application Entry Point = Activity** (Player Settings ▸ Other Settings — Unity-6 setting).
  ✅ **Unity version:** project is now **6000.5** (> 6000.3.0f1), so the 16 KB-page-size Play requirement
  is satisfied — no version blocker for sideload OR Play.
- **Flutter app manifest (the ONE Flutter-side requirement):** the embedded Unity runs inside the Flutter
  app's Android process, so the **Flutter app's** `AndroidManifest.xml` must allow cleartext
  (`android:usesCleartextTraffic="true"`) for the plain-http voice WAVs (`:9100`) and addressables
  (`:7777`), and the tablet must be able to reach both hosts on the LAN.
- **Export:** menu **`Flutter Embed ▸ Export project to flutter app (Android)`**. It makes you pick a folder
  named **`unityLibrary` inside an `android` folder** (validated — no real Flutter project needed; a stand-in
  `…/android/unityLibrary` works). → **zip `unityLibrary`** (the Gradle module) → upload to **nukshare
  `http://192.168.0.229:9090`** → report Unity version, inbound GameObject+method (`FlutterFace.OnMessage`),
  and the event names emitted back. The integrator drops `unityLibrary` into `<flutter app>/android/`.
- **Addressables + Android:** the remote `remoteLoadPath` must be reachable from the tablet, and
  plain-`http` needs cleartext enabled in the Android manifest (same as the voice WAVs).

## 7c. Emotion sequence — `voice:plan` (expected data structure)

Per reply, the backend sends ONE `voice:plan` (before/with the voice). Its `beats` play **in order**;
each beat is **face** (talk + lipsync + face emotion, camera centred on the face, audio plays here) or
**body** (full-body gesture for the emotion, camera centred on the body, silent). Any order/length.

```jsonc
// event: "voice:plan"   (camelCase keys)
{
  "sessionId": "abc",
  "beats": [
    { "kind": "body", "emotion": "excited", "durationSec": 2.5 },          // gesture, camera→body, silent
    { "kind": "face", "emotion": "happy",                                  // talk, camera→face, audio here
      "chunks": [ { "index": 0, "url": "/voice/file/<sid>/0.wav", "durationSec": 1.2 } ] }
  ]
}
```
- `emotion` is one of the 22 `AVATAR_EMOTIONS` (backend `speech/emotion.ts`).
- Face-beat `chunks` carry the WAVs to speak during that beat (the existing per-sentence WAVs, as an
  array). `url` may be a path (Unity prefixes the base) or absolute.
- Examples: `[face]` = just talk; `[body,face]` = gesture then talk; `[face,body]` = talk then gesture.
- Unity side: `VoicePlan`/`VoiceBeat`/`VoiceChunkRef` (`Speech/VoicePlan.cs`) + `EmotionSequencer`
  drive camera perspective (calibrated face/body framings), audio on face beats, and raise
  `OnFaceEmotion`/`OnBodyEmotion` for the expression/gesture controllers.
- Back-compat: the old single `voice:emotion` + streamed `voice:chunk` still work; `voice:plan` is the
  richer superset for sequenced face/body beats.

## 8. Pending (Unity side, not blocking the backend)

- Install uLipSync + `ULIPSYNC` define; calibrate a uLipSync **Profile** on Kokoro `af_heart`.
- Make prefab variants of chosen avatars carrying `RocketboxFaceRig`.
- (Later) Expressions/blink via `AK_*` blendshapes; **Resources → Addressables** for shipping.

## 9. Verification checklist

- [ ] Backend emits `voice:speaking` and `voice:chunk` on `:9100` (Socket.IO, broadcast).
- [ ] `voice:chunk` payload uses keys `sessionId,index,url,durationSec` (camelCase).
- [ ] `GET /voice/file/...wav` returns a finite WAV with CORS `*`.
- [ ] Unity device can reach `192.168.0.229:9100` over WebSocket.
- [ ] On Play, `MaradelVoiceSocketClient` status shows **Connected**; speaking a line moves the mouth.

---
*Companion docs in this folder:* `SPEECH_HOOK.md` (backend voice API, source-of-truth),
`SPEECH_SETUP.md` (Unity client), `LIPSYNC.md` / `LIPSYNC_OPTIONS.md` (engine + Rocketbox visemes),
`GALLERY.md` (model browser), `SETUP.md` (milestones).
