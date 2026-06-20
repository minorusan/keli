# LIPSYNC.md — Maradel's 3D talking face (Unity-in-Flutter)

Spec for wiring a **lipsynced 3D face** into Maradel via **Unity-as-a-Library embedded in the Keli
Flutter app**. Written against the project layout the user will hand over (Zenject + a face prefab),
so the integration is *drop-in*: bind one controller, add one static bridge utility, expose events
the same way `flutter_unity_widget` does.

> **Decision (from research):** Unity-in-Flutter via **`flutter_embed_unity`** (the maintained UaaL
> rewrite), avatar = **VRM** (Ready Player Me shut down Jan 31 2026 — use VRoid Studio), lipsync =
> **uLipSync** (hecomi, MIT — real-time MFCC→viseme from raw audio, no pre-baked phonemes, no native
> plugin, ARM64-clean). Audio is driven by Maradel's existing per-sentence WAV chunks; **no backend
> change is required.**

---

## 0. What you (the user) provide

A Unity project, ready to open, containing:

- Scene **`Simulation`** — a square stage with the avatar centered, a camera framed on the face.
- A **face prefab** with:
  - a **`MonoBehaviour` that drives the SkinnedMeshRenderer** (blendshapes/visemes) — exposes a
    *basic API* (§2.1),
  - a **Zenject-injected service controller** already on the prefab/context.
- A Zenject **`SceneContext` + installer** I can extend.

## 0.1 What I (this spec) add — and it's genuinely this small

1. One generic layer of interfaces + a default impl (§2).
2. One **Zenject controller** `LipSyncController` bound in the installer (§3, §4).
3. One **static `.cs` utility** `FlutterFace` — the UaaL message codec + the inbound entry point (§5).
4. The **Flutter side** in Keli: forward `voice:chunk` → Unity, mirror events back (§6).

That's the whole integration. Everything below is the contract for those four pieces.

---

## 1. Architecture (one diagram)

```
Maradel backend (:9100)                 Keli Flutter app                  Unity (embedded, Zenject)
─────────────────────                   ─────────────────                 ─────────────────────────
voice:chunk {url,index,            ──►  UnityFaceBridge (Dart)       ──►   FlutterFace (static .cs)
            durationSec}  (socket)        sendToUnity("FlutterFace",         OnMessage(json)
voice:speaking {on}                        "OnMessage", json)                   │ resolves →
GET /voice/file/..wav  ◄───────────────────────────────────────────────  LipSyncController (Zenject)
                                                                               ├─ IAudioFeed  → AudioSource
SendToFlutter.Send(json) ◄── events ◄──  UnityFaceBridge (onMessage)         ├─ ILipSyncProvider (uLipSync)
                                                                               └─ IFaceRig (the prefab MB)
```

- **Flutter never decodes audio.** It only forwards *which WAV to play* (a URL) and a few control
  messages. Unity fetches + plays + analyzes the audio itself → **lipsync is perfectly in sync by
  construction** (the bytes uLipSync analyzes are the exact bytes the AudioSource emits; zero
  cross-process drift). This is the decisive reason to let Unity own audio.

---

## 2. The generic layer (Unity, C#)

Three small interfaces decouple *the model*, *the lipsync engine*, and *the audio source* so any of
the three can be swapped without touching the others. All live in `Assets/Scripts/Face/`.

### 2.1 `IFaceRig` — abstraction over the provided face MonoBehaviour

The prefab's skinned-mesh MonoBehaviour implements this (or a 20-line adapter wraps it). This is the
"basic API" the model is assumed to offer:

```csharp
public enum Viseme { Sil, PP, FF, TH, DD, Kk, CH, SS, Nn, RR, Aa, E, Ih, Oh, Ou } // Oculus 15
public enum Expression { Blink, BrowUp, BrowDown, Smile, Squint }

public interface IFaceRig {
    bool IsReady { get; }
    /// Set one viseme's weight (0..1). Caller may set several per frame; rig blends them.
    void SetViseme(Viseme v, float weight01);
    /// Crude jaw-open for the amplitude-only PoC (Milestone 0). 0 = closed, 1 = wide.
    void SetMouthOpen(float amount01);
    /// Idle life: blink, brows, micro-smile.
    void SetExpression(Expression e, float weight01);
    /// Zero all mouth visemes (call on speaking stop).
    void ResetMouth();
}
```

- **Viseme → blendshape mapping is data, not code:** a `VisemeMap` `ScriptableObject` maps each
  `Viseme` to the model's blendshape name(s) + a max-weight. Different model → new asset, no code.
  (VRM models expose only 5 mouth presets `aa/ih/ou/ee/oh` + sil; the map collapses the 15-viseme
  output onto those. RPM/ARKit models get a richer map. Same `IFaceRig`.)

### 2.2 `ILipSyncProvider` — abstraction over the lipsync engine

```csharp
public readonly struct VisemeFrame {
    public readonly Viseme Dominant;
    public readonly float Volume;                       // 0..1 overall loudness (for jaw fallback)
    public readonly IReadOnlyList<(Viseme v, float w)> Weights; // per-viseme this frame
}

public interface ILipSyncProvider {
    event Action<VisemeFrame> OnFrame;                  // raised on the audio/Update thread, ~per audio block
    /// Feed raw mono PCM (-1..1). Used only by the external-PCM feed; the AudioSource feed taps internally.
    void Feed(float[] pcm, int channels, int sampleRate);
    void Reset();
}
```

Concrete impls (pick at install time):

| Impl | Engine | Use |
|---|---|---|
| `AmplitudeLipSyncProvider` | RMS of the buffer → `Volume`, `Dominant = Aa` | **Milestone 0** — proves end-to-end with one blendshape, no profile needed |
| `ULipSyncProvider` | **hecomi/uLipSync** — `uLipSync.OnDataReceived(float[],ch)` → MFCC → profile classify → viseme weights | **Production**. No pre-baked phonemes; runs on Burst/Job System, no native plugin. |
| `OvrLipSyncProvider` *(optional)* | legacy Meta OVRLipSync (15 visemes) | only if you already have it; OVRLipSync is EOL |

> uLipSync exposes a public `OnDataReceived(float[] input, int channels)`. The `ULipSyncProvider`
> subscribes to the `uLipSync` component's callback and republishes as `VisemeFrame`. If you ever push
> PCM from Flutter (§7), call `OnDataReceived` directly — the uLipSyncWebGL fork proves the
> AudioSource-less path works.

### 2.3 `IAudioFeed` — where the audio comes from

```csharp
public interface IAudioFeed {
    /// Queue a finite clip (a Maradel WAV chunk) for playback in arrival order.
    void Enqueue(string url, int index, float durationSec);
    void Stop();
    bool IsPlaying { get; }
    event Action OnPlaybackStarted;   // first chunk began
    event Action OnPlaybackDrained;   // queue emptied
}
```

- Default impl **`UnityWebRequestAudioFeed`**: `UnityWebRequestMultimedia.GetAudioClip(url, WAV)` →
  `DownloadHandlerAudioClip` → enqueue → `AudioSource.PlayOneShot` in `index` order. The
  `uLipSync` component sits **on the same GameObject** as the `AudioSource`, so it analyzes via
  `OnAudioFilterRead` automatically — no manual `Feed`.
- WAV (not the endless MP3 `/voice/stream`) because finite clips decode trivially and reliably on
  Android (same reason the Flutter app prefers them).

---

## 3. `LipSyncController` — the Zenject service (the heart)

```csharp
public sealed class LipSyncController : IInitializable, IDisposable {
    [Inject] readonly IFaceRig _rig;
    [Inject] readonly ILipSyncProvider _provider;
    [Inject] readonly IAudioFeed _audio;
    [Inject] readonly VisemeMap _map;

    public event Action OnReady;
    public event Action OnSpeakingStarted;
    public event Action OnSpeakingStopped;
    public event Action<VisemeFrame> OnVisemeFrame;     // optional, for debug/telemetry to Flutter

    public void Initialize() {
        _provider.OnFrame += ApplyFrame;
        _audio.OnPlaybackStarted += () => OnSpeakingStarted?.Invoke();
        _audio.OnPlaybackDrained += () => { _rig.ResetMouth(); OnSpeakingStopped?.Invoke(); };
        if (_rig.IsReady) OnReady?.Invoke();
    }

    // ── inbound commands (called by the Flutter bridge, §5) ──
    public void PlayChunk(string url, int index, float dur) => _audio.Enqueue(url, index, dur);
    public void Stop()       { _audio.Stop(); _rig.ResetMouth(); }
    public void SetMood(string mood) { /* drive idle Expression presets */ }

    void ApplyFrame(VisemeFrame f) {
        foreach (var (v, w) in f.Weights) _rig.SetViseme(v, w * _map.Gain(v));
        OnVisemeFrame?.Invoke(f);
    }
    public void Dispose() => _provider.OnFrame -= ApplyFrame;
}
```

- It owns **nothing Unity-specific in its logic** — pure orchestration over the three interfaces.
  Testable headless.
- **Idle life** (blink/breath when not speaking) is a tiny `ITickable` that nudges `IFaceRig`
  `Expression`s; bind it alongside. Keeps the face alive between utterances.

---

## 4. Zenject wiring (the installer)

Extend the scene's existing installer (or add `FaceInstaller : MonoInstaller` to the `SceneContext`):

```csharp
public sealed class FaceInstaller : MonoInstaller {
    [SerializeField] MonoBehaviour faceRigComponent; // the prefab MB implementing IFaceRig (or its adapter)
    [SerializeField] uLipSync.uLipSync uLipSyncComponent;
    [SerializeField] AudioSource audioSource;        // same GO as uLipSyncComponent
    [SerializeField] VisemeMap visemeMap;            // ScriptableObject

    public override void InstallBindings() {
        Container.Bind<IFaceRig>().FromInstance((IFaceRig)faceRigComponent).AsSingle();
        Container.Bind<VisemeMap>().FromInstance(visemeMap).AsSingle();
        Container.Bind<ILipSyncProvider>().To<ULipSyncProvider>()
                 .AsSingle().WithArguments(uLipSyncComponent);     // swap To<AmplitudeLipSyncProvider> for M0
        Container.Bind<IAudioFeed>().To<UnityWebRequestAudioFeed>()
                 .AsSingle().WithArguments(audioSource);
        Container.BindInterfacesAndSelfTo<LipSyncController>().AsSingle().NonLazy();

        // the inbound bridge MonoBehaviour (named GameObject "FlutterFace" in the scene)
        Container.Bind<FlutterFaceBridge>().FromComponentInHierarchy().AsSingle().NonLazy();
    }
}
```

`NonLazy` on `LipSyncController` + the bridge means they exist the moment the scene loads — so Unity
emits `ready` to Flutter as soon as injection completes. **This is exactly the "bind a controller on
the installer and use it" flow** — no plumbing beyond these bindings.

---

## 5. The static utility + the UaaL bridge (`FlutterFace.cs`)

`flutter_embed_unity` delivers a Flutter→Unity call as `sendToUnity(gameObjectName, methodName,
message)` → it invokes `methodName(string)` on the component on `gameObjectName`. Unity→Flutter is
`SendToFlutter.Send(string)`. We keep a **static codec** + a tiny **injected MonoBehaviour** that owns
the GameObject those calls target.

```csharp
// ── static utility: message names + JSON helpers + outbound send ──
public static class FlutterFace {
    // inbound (Flutter → Unity)
    public const string PlayChunk = "playChunk";   // {url, index, durationSec}
    public const string Stop      = "stop";
    public const string SetMood   = "setMood";     // {mood}
    public const string PushPcm   = "pushPcm";     // {b64, sampleRate, channels}  (optional, §7)
    // outbound (Unity → Flutter)
    public const string Ready            = "ready";
    public const string SpeakingStarted  = "speakingStarted";
    public const string SpeakingStopped  = "speakingStopped";
    public const string VisemeFrame       = "visemeFrame";  // {dominant, volume}
    public const string Error             = "error";        // {message}

    public static void Emit(string type, object payload = null) =>
        SendToFlutter.Send(JsonUtility.ToJson(new Envelope { type = type, json = JsonUtility.ToJson(payload ?? new {}) }));

    [Serializable] public struct Envelope { public string type; public string json; }
}

// ── the GameObject "FlutterFace" carries this; it is Zenject-injected with the controller ──
public sealed class FlutterFaceBridge : MonoBehaviour {
    [Inject] LipSyncController _ctl;

    void Start() {                       // forward controller events out to Flutter
        _ctl.OnReady           += () => FlutterFace.Emit(FlutterFace.Ready);
        _ctl.OnSpeakingStarted += () => FlutterFace.Emit(FlutterFace.SpeakingStarted);
        _ctl.OnSpeakingStopped += () => FlutterFace.Emit(FlutterFace.SpeakingStopped);
    }

    // THE inbound entry point flutter_embed_unity calls: sendToUnity("FlutterFace","OnMessage", json)
    public void OnMessage(string raw) {
        var env = JsonUtility.FromJson<FlutterFace.Envelope>(raw);
        switch (env.type) {
            case FlutterFace.PlayChunk: { var p = JsonUtility.FromJson<PlayChunkMsg>(env.json);
                                          _ctl.PlayChunk(p.url, p.index, p.durationSec); break; }
            case FlutterFace.Stop:      _ctl.Stop(); break;
            case FlutterFace.SetMood:   _ctl.SetMood(JsonUtility.FromJson<MoodMsg>(env.json).mood); break;
        }
    }
    [Serializable] struct PlayChunkMsg { public string url; public int index; public float durationSec; }
    [Serializable] struct MoodMsg      { public string mood; }
}
```

> **Static can't `[Inject]`.** So the static `FlutterFace` is pure codec/transport; the *injected*
> `FlutterFaceBridge` MonoBehaviour holds the `LipSyncController` and is what the named GameObject
> exposes. This is the same shape `flutter_unity_widget` uses (a `UnityMessageManager`-style
> GameObject method in, `SendToFlutter`/`UnityMessageManager.Instance.SendMessageToFlutter` out).

---

## 6. The Flutter side (Keli)

A thin `UnityFaceBridge` next to the existing `voice` handling. (Mirror of the Unity protocol — keep
the message-name constants identical.)

```dart
// on each Maradel voice chunk, tell Unity which WAV to play
socket.on('voice:chunk', (d) => sendToUnity('FlutterFace', 'OnMessage', jsonEncode({
  'type': 'playChunk',
  'json': jsonEncode({'url': '$kBackendUrl${d['url']}', 'index': d['index'], 'durationSec': d['durationSec']}),
})));
socket.on('voice:speaking', (d) { if (d['on'] != true) sendToUnity('FlutterFace','OnMessage',
  jsonEncode({'type':'stop','json':'{}'})); });

// inbound from Unity (flutter_embed_unity onMessage): show/hide the face, drive UI
onUnityMessage((raw) {
  final env = jsonDecode(raw);
  switch (env['type']) {
    case 'ready':            /* face screen ready */ break;
    case 'speakingStarted':  /* e.g. raise the face */ break;
    case 'speakingStopped':  /* idle */ break;
    case 'error':            /* log/bug-report */ break;
  }
});
```

- The `EmbedUnity` widget lives on a **persistent screen** in Keli (Unity stays resident — it inits
  once, ~multi-second cold start, then warm). Build size +40–80 MB — fine; the tablet runs only Keli.
- `kBackendUrl` = `http://192.168.0.229:9100` (Maradel). The WAV chunk URLs are relative paths from
  `voice:chunk` — prefix them.

---

## 7. Optional: audio in Flutter instead of Unity (only if speaker routing forces it)

If Maradel's voice must play through Flutter (e.g. routed to the HOCO BT speaker via the existing
`just_audio` path), switch the feed: Flutter decodes/plays the WAV and **pushes PCM** to Unity via
`FlutterFace.PushPcm` (base64 float32, non-interleaved, −1..1); the bridge calls
`uLipSync.OnDataReceived(pcm, channels)` directly (no AudioSource). Costs you manual buffering and
some sync risk — **prefer §3 (Unity owns audio)** unless you must. Don't send a lossy amplitude
envelope; send PCM so uLipSync still does real visemes.

---

## 8. Maradel audio facts (verified, for reference)

- `voice:chunk {sessionId, index, url, durationSec}` socket event per synthesized sentence.
- `GET /voice/file/<sessionId>/<name>.wav` — finite WAV chunk (the reliable mobile path).
- `GET /voice/stream` — endless `audio/mpeg` radio (don't use for lipsync; streaming-MP3 is finicky).
- `voice:speaking {on:bool}` — talk/idle transitions.
- All voice endpoints send `Access-Control-Allow-Origin: *`.
- **No phoneme/viseme timing exists** in the speech layer — lipsync MUST be derived from audio. That
  is exactly uLipSync's job; nothing to add backend-side.
- TTS = **Kokoro**, default voice `af_heart`, 24 kHz mono.

---

## 9. Milestones

| # | Goal | Provider | Rig API | Bridge |
|---|------|----------|---------|--------|
| **M0** | Mouth flaps in time with a test WAV | `AmplitudeLipSyncProvider` | `SetMouthOpen` | hard-coded local clip |
| **M1** | Real visemes, in editor | `ULipSyncProvider` + **profile calibrated on Kokoro `af_heart`** | `SetViseme` + `VisemeMap` | — |
| **M2** | Driven by Maradel over UaaL | same | same | `playChunk` from Keli's `voice:chunk` |
| **M3** | Alive: blink/idle + talk transitions + `setMood` | + idle `ITickable` | `SetExpression` | `speaking*` events |

**The one tuning step that matters:** record ~10 s of Maradel's `af_heart` output (`GET
/voice/preview?...`) and calibrate a uLipSync **Profile** against it. The default profile is tuned for
a human mic; Maradel's Kokoro timbre lipsyncs *noticeably* better with its own profile. (Add a second
profile for Russian/Ukrainian output and swap at runtime if needed.)

---

## 10. Risks / notes

- **APK +40–80 MB**, Unity cold-start multi-second → keep the face screen persistent so Unity inits
  once and stays warm. Single Unity instance only (can't reclaim its RAM) — fine for an appliance.
- **Build alignment:** Unity **6000.3.0f1+** (16 KB page-size, required by Play since Nov 2025) +
  `flutter_embed_unity` 2.0.0; Java 17 + Gradle 8.x must match Keli's Android config (the #1 build
  break). uLipSync needs **Burst AOT for Android ARM64** enabled in Player settings.
- **Keli already ships v1+v2 signing** via `tool/sign-keli-apk.sh` (EMUI fix) — the Unity-bearing APK
  must keep going through that re-sign.
- Keep `VisemeMap` per-model so swapping the avatar is a data change, not a code change.

---

### TL;DR for the user
Hand over the project. I bind `LipSyncController` + the three interface impls in your installer, drop
in `FlutterFace.cs` + the `FlutterFaceBridge` MonoBehaviour on a "FlutterFace" GameObject, point the
`VisemeMap` at your model's blendshapes, and wire Keli to forward `voice:chunk`. uLipSync + a
Kokoro-calibrated profile does the rest. Events flow exactly like `flutter_unity_widget`. **You find
the face (VRM); I'll make it talk.**
