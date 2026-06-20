# SPEECH_SETUP.md — Unity-side voice client (the audio we lipsync)

Implements the hooks in [SPEECH_HOOK.md](SPEECH_HOOK.md). Scripts in `Assets/Scripts/Speech/`.
**Key rule:** whatever plays the audio must be the **same AudioSource** that `uLipSync`
(or `AudioTap`) analyzes — that's what makes lipsync sync-by-construction (realtime, no delay).

## Components

| Script | Path | Needs |
|---|---|---|
| `MaradelVoiceConfig` | host/port + URL builders (`StreamUrl`, `FileUrl`, `PreviewUrl`) | — |
| `MaradelStreamPlayer` | streams endless `/voice/stream` MP3 → AudioSource (zero-dep, **live**) | — |
| `MaradelVoiceTester` | OnGUI: type text → `/voice/preview` WAV → play; toggle the radio | — |
| `MaradelVoiceSocketClient` | per-chunk: `voice:chunk`/`voice:speaking` → `UnityWebRequestAudioFeed` | Socket.IO lib + `MARADEL_SOCKETIO` define |

## Two ways to feed audio (pick per goal)

### A) Live radio — fastest, no dependencies
`/voice/stream` is an always-on MP3. `MaradelStreamPlayer` pipes it into the AudioSource;
uLipSync on the same GameObject lipsyncs whatever Maradel says.
- Add to the AudioSource GameObject: `AudioSource` + `uLipSync` + `MaradelStreamPlayer`.
- Set the host, `Connect()` (or Play On Start). Done.
- ⚠️ Endless-MP3 streaming is solid on desktop, **finicky on Android** — use (B) for the tablet.

### B) Per-chunk WAV — reliable, the shipped path
Maradel emits `voice:chunk {url,index,durationSec}` per sentence + `voice:speaking{on}`.
`MaradelVoiceSocketClient` fetches each finite WAV and enqueues it into
`UnityWebRequestAudioFeed` (which plays them in order on the lipsync AudioSource).
- Install **SocketIOUnity** (UPM git URL): `https://github.com/itisnajim/SocketIOUnity.git`
  (wraps socket.io-client-csharp; namespace `SocketIOClient`; auto-referenced).
- Add scripting define `MARADEL_SOCKETIO` (set for Standalone + Android).
- Handlers use `socket.OnUnityThread(...)` → run on the main thread (no marshalling).
- DTOs are deserialized by System.Text.Json → properties, case-sensitive (match JSON keys).
- On the AudioSource GameObject: `AudioSource` + `uLipSync` + `UnityWebRequestAudioFeed`.
- On any GameObject: `MaradelVoiceSocketClient`, assign the feed + host. It auto-connects.

### Testing without the backend talking (HOME)
`MaradelVoiceTester` (OnGUI): assign a `UnityWebRequestAudioFeed`, type a sentence, hit
**Speak** → it pulls `/voice/preview?text=...` as a WAV and plays it through the lipsync chain.
Also the best way to grab ~10 s of Kokoro `af_heart` audio to **calibrate a uLipSync Profile**.

## Full talking-head scene (per-chunk path)

```
AudioGO:   AudioSource + uLipSync (Profile) + UnityWebRequestAudioFeed
AvatarGO:  Female_Adult_01_facial  + RocketboxFaceRig
DriverGO:  FaceDriver (Mode=ULipSync; rig=RocketboxFaceRig, uLipSync=AudioGO's uLipSync)
VoiceGO:   MaradelVoiceSocketClient (feed=AudioGO's UnityWebRequestAudioFeed, host=...)
```
Maradel speaks → chunk WAVs stream into the AudioSource → uLipSync → `RocketboxFaceRig` drives
`SR_01..15` → the face talks, in sync.

## Overlay (status + transparency)
`MaradelVoiceTester` and `RocketboxGalleryGUI` draw via `GuiOverlay` (`Assets/Scripts/Common/`),
anchored to the **square viewport** (the face stage is square) so they sit consistently on any
window aspect. `overlayAlpha` / `_overlayAlpha` (0..1) controls transparency; `guiScale` / `_scale`
zooms. The tester's status panel shows ▶ running, audio playing, and the **WebSocket state**
(Connecting / Connected / Error, colour-coded) from `MaradelVoiceSocketClient` (`State`,
`IsSpeaking`, `LastError`). Toggle `verboseLogging` for per-event Console logs.

## Sync note
Realtime. uLipSync analyzes the same buffer it plays; mouth trails ~30–50 ms (within human
tolerance). **Do not delay the speaker.** Anticipatory sync would need pre-baking (offline
clips only), not applicable to live TTS.
