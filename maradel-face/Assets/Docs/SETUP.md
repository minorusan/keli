# SETUP.md — Face lipsync, from zero to a talking head

Implements the architecture in [LIPSYNC.md](LIPSYNC.md). Scripts live in
`Assets/Scripts/Face/`. The **core compiles with no external packages**; uLipSync, Zenject,
and Flutter pieces are gated behind scripting-define symbols and stay dark until you opt in.

## Scripts at a glance

| File | Role | Needs |
|------|------|-------|
| `Viseme.cs` | Enums + `VisemeFrame` | — |
| `IFaceRig.cs` / `ILipSyncProvider.cs` / `IAudioFeed.cs` | The 3 abstractions | — |
| `VisemeMap.cs` | **Per-model data** (phoneme→viseme, viseme→blendshape, gains) | — |
| `SkinnedMeshFaceRig.cs` | **MonoBehaviour that drives the model** (IFaceRig) | — |
| `AmplitudeLipSyncProvider.cs` | RMS jaw-flap (M0) | — |
| `AudioTap.cs` | Feeds PCM to the amplitude provider | — |
| `UnityWebRequestAudioFeed.cs` | Downloads + plays Maradel WAV chunks | — |
| `LipSyncController.cs` | Orchestrator (pure C#) | — |
| `FaceDriver.cs` | **Standalone wiring — run it now** | — |
| `ULipSyncProvider.cs` | Real visemes from hecomi/uLipSync | `#if ULIPSYNC` |
| `FlutterFace.cs` / `FlutterFaceBridge.cs` / `FaceInstaller.cs` | UaaL + Zenject (M2+) | `#if ZENJECT` / `#if FLUTTER_EMBED_UNITY` |

## Milestone 0 — jaw flaps in time with a WAV (no packages)

1. Import a model with blendshapes (Rocketbox / VRM / any FBX). Drop it in the scene.
2. On the model's body GameObject (the one with the face `SkinnedMeshRenderer`), add
   **Maradel ▸ Skinned Mesh Face Rig**.
3. **Discover the blendshape names:** right-click the `SkinnedMeshFaceRig` component ▸
   **Log Blend Shape Names**. Copy the mouth-open / vowel names from the Console.
4. Create a map: **Assets ▸ Create ▸ Maradel ▸ Viseme Map**. Fill
   `Mouth Open Blend Shapes` with the model's open-mouth shape(s) (e.g. a viseme/jaw-open
   shape). Assign the map to the rig.
5. Add a child GameObject with an **AudioSource** (assign a test WAV) + **Maradel ▸ Audio Tap**.
6. Add **Maradel ▸ Face Driver (Standalone)**: Mode = *Amplitude*, assign the rig component,
   the VisemeMap, and the Audio Tap. Set the AudioSource to *Play On Awake*.
7. **Play.** Mouth opens/closes with the audio. ✅

## Milestone 1 — real visemes (uLipSync)

1. Package Manager ▸ **+ ▸ Add package from git URL**:
   `https://github.com/hecomi/uLipSync.git#upm`
2. Project Settings ▸ Player ▸ **Scripting Define Symbols** ▸ add `ULIPSYNC`.
3. On the AudioSource GameObject add a **uLipSync** component (assign a Profile — start with
   the bundled 5-vowel/VRM sample profile).
4. In the VisemeMap, fill each vowel binding's `phonemes` with the profile's phoneme labels
   (`A I U E O`) and `blendShapes` with the model's matching mouth shapes.
5. Face Driver: Mode = *ULipSync*, assign the uLipSync component. Play. Real mouth shapes. ✅
6. **Tuning that matters:** calibrate a uLipSync Profile against ~10 s of Maradel's Kokoro
   `af_heart` output for noticeably better sync.

## Milestone 2–3 — Maradel-driven over Flutter (UaaL)

1. Add scripting defines `ZENJECT` (+ install Extenject) and `FLUTTER_EMBED_UNITY`.
2. Add a `SceneContext` + `FaceInstaller`, assign references. Add a GameObject named
   exactly **`FlutterFace`** with `FlutterFaceBridge`.
3. Keli forwards `voice:chunk` → `sendToUnity("FlutterFace","OnMessage", …)`; events mirror
   back. See LIPSYNC.md §6.

## Notes for specific models

- **Microsoft Rocketbox** (verified from the repo, MIT):
  - **FBX + textures**, fully rigged skinned meshes, 115 characters.
  - Facial blendshapes: **15 visemes** + 48 FACS expressions + ARKit-compatible. The 15
    visemes line up with this project's Oculus-15 `Viseme` enum → near 1:1 `VisemeMap`
    (no 5-vowel collapse needed, unlike VRM).
  - **Run/keep `Assets/Editor/FixRocketboxMaxImport.cs`** (ships with the download) — it fixes
    3ds-Max→Unity materials and sets the humanoid rig on import. Without it, materials look wrong.
  - They are **FBX, not prefabs**: the gallery loads FBX roots as GameObjects fine, but make a
    **prefab variant per character** to attach `SkinnedMeshFaceRig` + its `VisemeMap` once.
  - Use *Log Blend Shape Names* to read the exact viseme blendshape names, then fill the map.
- **VRM (VRoid)**: needs UniVRM to import; exposes `aa/ih/ou/ee/oh` mouth presets — the
  5-vowel uLipSync profile maps onto these directly.
