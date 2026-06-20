# LIPSYNC_OPTIONS.md — engine investigation + the drop-on-prefab component

Investigation of lipsync engines for the Rocketbox talking head, with the decisive finding
about Rocketbox's own blendshapes and a concrete component to drop on a `*_facial` prefab.

## TL;DR

- **Rocketbox `*_facial` meshes carry `SR_01..SR_42` + `AK_01..AK_52` blendshapes. `SR_01..SR_15`
  ARE the 15 Oculus-Lipsync visemes, in Oculus order — identical on all 117 avatars.** (Verified
  by reading the FBX channels directly + the HeadBox docs.)
- **Recommendation: uLipSync** (MIT, maintained, no native plugin, ARM64-clean) — consistent
  with [LIPSYNC.md](LIPSYNC.md). Drop **`RocketboxFaceRig`** on the prefab; it bakes the
  `Viseme → SR_01..SR_15` mapping so there is **zero per-model setup**.
- The one trade-off: uLipSync is MFCC/vowel-based, so it actively drives ~5–6 of the 15 visemes
  (the vowels + silence). That's enough for a convincing talking head. If you ever want crisp
  consonant visemes on all 15, OVRLipSync maps 1:1 — but it's deprecated (see below).

## The decisive finding (ground truth from the model)

Reading `Female_Adult_01_facial.fbx` directly:

- 175 `BlendShapeChannel`s named `SR_01..SR_42` (SRanipal/VIVE set) and `AK_01..AK_52` (ARKit set).
- HeadBox README: *"the first 15 blendshapes are the visemes compatible with Oculus Lipsync."*

Oculus viseme order → Rocketbox shape:

| # | Oculus viseme | Rocketbox | our `Viseme` |
|---|---|---|---|
| 1 | sil | `SR_01` | `Sil` |
| 2 | PP | `SR_02` | `PP` |
| 3 | FF | `SR_03` | `FF` |
| 4 | TH | `SR_04` | `TH` |
| 5 | DD | `SR_05` | `DD` |
| 6 | kk | `SR_06` | `Kk` |
| 7 | CH | `SR_07` | `CH` |
| 8 | SS | `SR_08` | `SS` |
| 9 | nn | `SR_09` | `Nn` |
| 10 | RR | `SR_10` | `RR` |
| 11 | aa | `SR_11` | `Aa` |
| 12 | E | `SR_12` | `E` |
| 13 | ih | `SR_13` | `Ih` |
| 14 | oh | `SR_14` | `Oh` |
| 15 | ou | `SR_15` | `Ou` |

This is why `RocketboxFaceRig` needs no `VisemeMap` asset — the mapping is constant.

## Engine options compared

| Engine | License / status | Output | Rocketbox fit | Mobile (ARM64) | Verdict |
|---|---|---|---|---|---|
| **uLipSync** (hecomi) | **MIT, maintained** | MFCC → phoneme ratios (you define phonemes in a Profile; default ≈ A/I/U/E/O) | Maps vowels → SR_11/13/15/12/14 (+ sil). ~5–6 of 15 visemes driven. | ✅ Burst/Jobs, no native plugin | ✅ **Recommended** |
| **OVRLipSync** (Meta) | Proprietary, **EOL/deprecated** | 15 Oculus visemes directly | **1:1 with SR_01..SR_15** (Rocketbox was built for it) | ⚠️ native plugin, ARM64/licensing risk | Best fidelity, worst longevity. Fallback only. |
| **SALSA LipSync** | Paid (Asset Store) | Amplitude/volume-based shapes | Works, but volume-driven (no real phonemes); needs its own mapping | ✅ works iOS/Android | Skip — paid + no phonemes. |
| **Azure / TTS visemes** | Service | Viseme stream alongside TTS | Would be 1:1 with SR_01..15 | n/a | **N/A** — Maradel's Kokoro TTS emits no viseme timing (LIPSYNC.md §8), so audio-derived is mandatory. |
| **Amplitude (ours)** | — | RMS loudness only | Drives SR_11 (jaw) | ✅ | M0 PoC only. |

### Why uLipSync over the "perfect" OVR match

Rocketbox's visemes were literally designed for Oculus Lipsync, so OVRLipSync is the 1:1
partner. But OVRLipSync is end-of-life, ships a native plugin, and carries Meta licensing +
ARM64 packaging risk for an embedded Flutter/UaaL build. uLipSync is MIT, pure-managed +
Burst, actively maintained, and already the spec's choice. The cost — driving fewer of the 15
visemes — is minor because vowels dominate visible mouth motion. (You can later author a
richer uLipSync Profile with consonant phonemes to light up more of SR_02..SR_10, but it's
not needed for a believable head.)

## The component we drop on the prefab

**`Assets/Scripts/Face/RocketboxFaceRig.cs`** — implements `IFaceRig`, bakes the
`Viseme → SR_01..SR_15` map, auto-finds the facial SkinnedMeshRenderer (the one with `SR_01`),
tolerates `<mesh>.SR_01` style names, and smooths weights frame-rate-independently. No external
package required to compile.

How a Rocketbox prefab becomes a talking head:

1. Open a Rocketbox **`*_facial`** model (e.g. `Female_Adult_01_facial`), make a prefab.
2. Add **`Maradel ▸ Rocketbox Face Rig`**. (Auto-finds the mesh; nothing else to map.)
3. Add an `AudioSource`. Install uLipSync (`#define ULIPSYNC`), add a `uLipSync` component on
   the AudioSource, and a `FaceDriver` (Mode = ULipSync) — or bind via Zenject (`FaceInstaller`).
4. The provider's phoneme→viseme step maps uLipSync's vowels (`A/I/U/E/O`) → `Aa/Ih/Ou/E/Oh`
   (+ silence → `Sil`); `RocketboxFaceRig` turns those into `SR_*` blendshape weights.
5. Calibrate a uLipSync Profile on Maradel's Kokoro `af_heart` output for best sync.

### Resolved
- **uLipSync phoneme labels** = `A I U E O N -` (sample profiles, confirmed). `PhonemeMap`
  already maps these → `Aa/Ih/Ou/E/Oh/Nn/Sil`, so the provider needs **no VisemeMap asset**.
- **SR_01..15 ordering verified** on Adults, Professions, and Children `_facial` FBX (42 SR
  shapes each, identical order). The baked map in `RocketboxFaceRig` is safe across the library.

### Still open
- **Expressions (blink/brows)** map to `AK_*` / `SR_16+`; not wired yet (no-op in the rig).
  Wire specific `AK_` indices later if idle-life is wanted.
- Unity-side only: install uLipSync + `ULIPSYNC` define, then verify weights move on Play.
