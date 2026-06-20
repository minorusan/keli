# SPEECH_HOOK.md — hooking into Maradel's voice (the TTS that goes to the speaker)

How to tap the live audio Maradel speaks — the same stream that plays to the speaker. Everything here
is verified against the running backend (`~/maradel/backend`, 2026-06-17).

> Note on "vosk": Maradel's **TTS** is engine-routed — **Kokoro** for English, **Vosk-TTS** (a Russian
> VITS model, `custom-freeman`) for Cyrillic, chosen per-sentence by script (`engine: "auto"`). The
> stream below carries *whichever* engine is speaking; you don't pick one. (Vosk-the-STT is a separate
> thing used for the mic/wake-word, not this.)

---

## TL;DR — the exact URL

```
http://192.168.0.229:9100/voice/stream
```

- An **always-on MP3 "radio"** (`audio/mpeg`). Connect any time; it plays silence between utterances
  and Maradel's voice when she speaks. This is the single best hook for "play it" or "analyze it live".
- On the LAN it's `192.168.0.229:9100`; locally `http://localhost:9100/voice/stream`. The port is the
  Maradel backend (`MARADEL_PORT`, default **9100**) — same port as its Socket.IO.

---

## Format spec (`/voice/stream`)

| Property | Value |
|---|---|
| Method / path | `GET /voice/stream` (trailing slash ok) |
| Body | **endless** `audio/mpeg` (MP3), one continuous HTTP response, never closes |
| Codec | MP3 (`libmp3lame`), **128 kbps** CBR (`MARADEL_VOICE_BITRATE`) |
| Sample rate | **24000 Hz** (source PCM `MARADEL_VOICE_SAMPLE_RATE`), **mono** |
| Headers | `Content-Type: audio/mpeg`, `Cache-Control: no-cache, no-store`, `Connection: keep-alive`, **`Access-Control-Allow-Origin: *`** |
| Auth | none (LAN service) |
| Mid-join | safe — MP3 decoders resync at the next frame header, so joining mid-stream just works |
| Idle behaviour | a 200 ms keepalive tops up **digital silence** so the stream never underruns/stalls (players stay in "playing" state → speech is audible the instant it arrives) |

Internally: one long-lived `ffmpeg` reads `f32le` mono 24 kHz PCM on stdin and emits MP3 on stdout,
fanned out to every connected client. Kokoro/Vosk chunks are piped straight in as they synthesize.
(Source: `backend/src/speech/stream.ts`, route at `backend/src/index.ts` `/voice/stream`.)

**Caveats:** it's a live, gapless, *endless* body — there's no length, no seeking, and it's always
running regardless of listeners. One shared ffmpeg encoder serves everyone. Between utterances you get
silent MP3 frames (not a closed connection).

---

## The other hook: per-sentence WAV + Socket.IO events

If you'd rather react per utterance (knowing exact boundaries, durations, and getting clean finite
files — best for lipsync, captions, or reliable mobile playback), use the event path instead of/along
with the radio. Maradel emits **Socket.IO** events on the same `:9100`:

```
voice:speaking   { sessionId: string, on: boolean }     // utterance start (true) / end (false)
voice:chunk      { sessionId: string, index: number,
                   url: string, durationSec: number }    // one synthesized sentence is ready
```

- `url` is a path like `/voice/file/<sessionId>/<index>.wav` — fetch it at
  `http://192.168.0.229:9100<url>` to get a **finite `audio/wav`** (CORS `*`). Play/analyze it in
  arrival order (`index`). This is the reliable path on mobile (finite WAV vs endless MP3).
- `voice:speaking{on}` brackets every utterance — use it to show a "talking" state / gate analysis.

(Source: `backend/src/speech/index.ts` — emits `voice:speaking` around synthesis and a `voice:chunk`
per sentence; files served by `GET /voice/file/<sid>/<name>.wav`.)

### One-shot sample (handy for testing / lipsync-profile calibration)
```
GET /voice/preview?text=Hello&voice=<id>&speed=<n>   →   audio/wav   (one synthesized clip)
```
e.g. `curl "http://192.168.0.229:9100/voice/preview?text=testing+one+two" -o sample.wav`.

---

## Which hook to use

| You want to… | Use |
|---|---|
| Just **play** Maradel's voice somewhere (another speaker, a browser, a player) | `/voice/stream` (point an `<audio>`/player at it) |
| **Analyze live** for lipsync / VU meter / reactive visuals | `/voice/stream` + Web Audio `AnalyserNode` (or feed PCM to your DSP) |
| Per-utterance handling, captions, exact timing, reliable mobile playback | `voice:chunk` + `voice:file/*.wav` (+ `voice:speaking`) |
| Know *when* she's talking | `voice:speaking` socket event |

---

## Recipes

### Browser / Web Audio (play + live analyze)
```js
const audio = new Audio("http://192.168.0.229:9100/voice/stream");
audio.crossOrigin = "anonymous";          // CORS is * so this is fine
const ctx = new AudioContext();
const src = ctx.createMediaElementSource(audio);
const analyser = ctx.createAnalyser();
src.connect(analyser); analyser.connect(ctx.destination);
await ctx.resume();                        // unlock on a user gesture (kiosk: once at boot)
await audio.play();
// read analyser.getByteFrequencyData(...) / RMS each frame for visemes/VU
```

### ffmpeg / shell (re-encode, pipe, record)
```bash
ffplay -nodisp http://192.168.0.229:9100/voice/stream            # just listen
ffmpeg -i http://192.168.0.229:9100/voice/stream -f s16le -ar 16000 -ac 1 pipe:1   # to raw PCM
```

### Flutter (just_audio)
```dart
final player = AudioPlayer();
await player.setUrl('http://192.168.0.229:9100/voice/stream');   // endless MP3
player.play();
// (per-utterance instead: subscribe to voice:chunk over Socket.IO and play each WAV in order)
```

### Unity (for the 3D face — prefer per-chunk; see LIPSYNC.md)
```csharp
// best for lipsync: Unity owns the audio, analyzed by the same AudioSource it plays
using var req = UnityWebRequestMultimedia.GetAudioClip(
    "http://192.168.0.229:9100/voice/file/<sid>/<index>.wav", AudioType.WAV);
await req.SendWebRequest();
var clip = DownloadHandlerAudioClip.GetContent(req);
audioSource.PlayOneShot(clip);            // uLipSync on the same GameObject analyzes it
// (the endless /voice/stream also works via streamAudio=true, but finite WAVs are more reliable)
```

### Node — listen for events
```js
import { io } from "socket.io-client";
const s = io("http://192.168.0.229:9100", { transports: ["websocket"] });
s.on("voice:speaking", d => console.log("speaking:", d.on));
s.on("voice:chunk", d => console.log("chunk", d.index, d.durationSec, "→",
  "http://192.168.0.229:9100" + d.url));
```

---

## Gotchas
- **No phoneme/viseme timing** is exposed anywhere — for lipsync you derive it from the audio
  (amplitude/FFT) or run your own analyzer (uLipSync etc.). The TTS only gives audio + boundaries.
- The MP3 stream is **24 kHz mono** — fine for voice; resample if your consumer wants 16 kHz/48 kHz.
- It's **unauthenticated and LAN-only**; don't expose `:9100` to the internet.
- Between utterances the radio is **silent frames, not a closed connection** — gate on
  `voice:speaking` if you only care about actual speech.
- One shared ffmpeg encoder fans out to all `/voice/stream` clients; many simultaneous listeners are
  cheap (it's one encode), but the encoder is always running.

---

### Source of truth (verified)
- `backend/src/speech/stream.ts` — the SpeechStream radio (ffmpeg f32le→MP3, fan-out, silence keepalive).
- `backend/src/index.ts` — routes: `/voice/stream`, `/voice/file/<sid>/<name>.wav`, `/voice/preview`.
- `backend/src/speech/index.ts` — emits `voice:speaking` + `voice:chunk` per utterance; writes the WAVs.
- `backend/src/config.ts` — `port` 9100, `speech.sampleRate` 24000, `speech.bitrate` 128k, `speech.engine` (kokoro|vosk|auto).
- `backend/src/protocol/events.ts` — `voice:speaking`, `voice:chunk` payload shapes.
- See also `~/maradel/docs/SPEECH.md` and `LIPSYNC.md` (this share).
