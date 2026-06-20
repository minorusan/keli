# maradel-face — Documentation

This folder holds in-project documentation. Because it lives under `Assets/`, Unity
imports it and generates a `.meta` file, so the docs travel with the project and are
fetchable through Unity (e.g. via the Collab / version-control client).

## Index

- **[UNITY_HANDOFF.md](UNITY_HANDOFF.md)** — integration spec: what's built + the exact events/
  endpoints Maradel must emit. **Share this with the backend owner.**

- [LIPSYNC.md](LIPSYNC.md) — architecture spec for the lipsynced 3D face (UaaL + uLipSync).
- [SETUP.md](SETUP.md) — step-by-step: from zero to a talking head (M0→M3), script reference.
- [GALLERY.md](GALLERY.md) — prefab gallery panel (browse/scale/switch face models).
- [ADDRESSABLES.md](ADDRESSABLES.md) — remote content pipeline (models out of Resources → Addressables,
  per-avatar bundles, download-on-demand, preload screen, build script).
- [LIPSYNC_OPTIONS.md](LIPSYNC_OPTIONS.md) — engine investigation (uLipSync vs OVR vs SALSA) +
  the Rocketbox `SR_01..15 = Oculus visemes` finding + the `RocketboxFaceRig` drop-on-prefab component.
- [SPEECH_HOOK.md](SPEECH_HOOK.md) — Maradel's voice backend (the audio to lipsync): `/voice/stream`,
  `voice:chunk`/`voice:speaking`, `/voice/preview`.
- [SPEECH_SETUP.md](SPEECH_SETUP.md) — Unity-side voice client (`Assets/Scripts/Speech/`): live
  radio, per-chunk WAV path, and the OnGUI tester.

## End goal

**Maradel swaps FACES.** The face models are auditioned through the prefab gallery now
(loaded from `Resources/`), and in the tablet product Maradel selects and loads a face at
runtime — which becomes the lipsynced talking head. Each face carries its own `VisemeMap`
so swapping the avatar is a data change. **Content path: `Resources/` today (to see models)
→ Addressables for the shipping app** (a 5 GB+ asset library can't live in `Resources`).

## Conventions

- One file per feature: `Assets/Docs/<feature-name>.md`.
- Each feature doc records: purpose, key scenes/scripts, how to run/test, open issues.
- Keep this README's **Index** in sync when adding a doc.
- The project-wide overview and step-by-step change log live in the root `CLAUDE.md`.

## Project at a glance

- **Engine:** Unity **2023.2.22f1** (upgraded/reimported from Unity 2020).
- **Scenes:** `Assets/Scenes/Face.unity`, `Assets/Scenes/SampleScene.unity`.
- **Render/UI:** uGUI 2.0.0, Timeline 1.8.6, AI Navigation 2.0.0.
