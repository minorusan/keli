# Keli — build the APK on Windows (with the embedded Unity face)

This is the **Keli Flutter app**, already wired to embed Maradel's 3D Unity face
(`flutter_embed_unity`). Everything on the Flutter/Gradle side is done and verified. The **only**
reason this must build on Windows is that Unity's IL2CPP native compile (`libil2cpp.so`) needs
Unity's toolchain, and your export ships the **Windows** build backend (`bee_backend/win-x64`). The
NUC (Linux) can't run it — that's the whole reason for this handoff.

---

## What's in this zip

The complete Keli Flutter client (`client/`), with the Unity embed already wired:
- `pubspec.yaml` → `flutter_embed_unity: ^2.0.0` added; version bumped to **1.0.15+16**.
- `android/settings.gradle.kts` → `include(":unityLibrary")`.
- `android/build.gradle.kts` → `flatDir` repo on `unityLibrary/libs`.
- `android/app/build.gradle.kts` → `implementation(project(":unityLibrary"))`, `ndkVersion "27.2.12479018"`, `minSdk 26`.
- `android/gradle.properties` → `unityStreamingAssets=.bin, .hash, .json, .xml`.
- `lib/screens/home_screen.dart` → the Unity face is the **always-on, centered SQUARE** on the main page (`_FaceStage`).
- `lib/changelog.dart` + `lib/config.dart` → build 16 entry ("Maradel has a face").
- `tool/sign-keli-apk.sh` → the v1+v2 re-sign for the MediaPad (EMUI). Run under Git Bash / WSL.

**NOT included** (you add / it regenerates):
- `android/unityLibrary/` ← **YOU DROP THIS IN** (see below). It was excluded on purpose.
- `build/`, `.dart_tool/`, `android/local.properties` (machine-specific, regenerated).

---

## ⬇️ The one thing that "arrives" separately: `unityLibrary`

Put your exported Unity Android library here:

```
client/android/unityLibrary/      <-- the exported Gradle module goes here
```

Use the `unityLibrary` folder from **your `Build.zip`** (the flutter_embed_unity "Export Android" you
already made), OR re-export fresh from the `maradel-face` Unity project. It must contain
`unityLibrary/build.gradle`, `src/`, `libs/`, `shared/`, etc. On Windows its bundled `il2cpp.exe` +
`bee_backend/win-x64` are the right binaries, so the native compile works.

> Do NOT reuse any `unityLibrary` that's been touched on the NUC — its `gradle.properties`/runtimeconfig
> were edited to Linux paths for a build experiment. Use a clean Windows export.

---

## Prerequisites on the Windows box

- **Unity 6000.5.0f1** with **Android Build Support + IL2CPP + Android SDK/NDK** modules (you have this — it's where you exported).
- **Flutter** (3.41+ stable) on PATH.
- **JDK 17** (Android Studio's bundled JDK is fine).
- **Android SDK** with **NDK 27.2.12479018**, **build-tools 36.0.0**, **platform 36**. Unity's bundled
  Android SDK/NDK satisfies the NDK; otherwise install via Android Studio SDK Manager.

---

## Build steps

```bat
:: 1. unzip, then:
cd client

:: 2. drop your exported unityLibrary into  client\android\unityLibrary\   (see above)

:: 3. (first time) point Flutter at the project + fetch deps
flutter pub get

:: 4. build the release APK  (this is where il2cpp compiles libil2cpp.so — several minutes)
flutter build apk --release
```

Output: `client\build\app\outputs\flutter-apk\app-release.apk`.

### Re-sign for the MediaPad (EMUI / Android 8) — required
The tablet rejects v2-only signatures ("App not installed"). Re-sign with a v1+v2 signature
(`apksigner --min-sdk-version 21`). Run under **Git Bash** or **WSL**:

```bash
tool/sign-keli-apk.sh
```
(Read the script — it points at the built `app-release.apk` and the debug keystore.)

---

## Config / envs (optional)

Defaults already target the NUC on the LAN — a plain `flutter build apk --release` is correct. To
override, add `--dart-define`s:

| define | default | what |
|---|---|---|
| `KELI_URL` | `http://192.168.0.229:9120` | Keli backend (Socket.IO + REST) |
| `MARADEL_URL` | `http://192.168.0.229:9100` | Maradel backend (the Unity face also talks here) |
| `ROBOT_MAP_URL` | `http://192.168.0.229:9113` | roomba map minimap |
| `ROBOT_CAM_URL` | `http://192.168.0.229:9110` | roomba cam frame |

The **Unity face needs no config** — inside Unity, `MaradelVoiceSocketClient` connects to Maradel
`:9100` itself and fetches the voice WAVs over HTTP, so it talks + lipsyncs on its own once embedded.

---

## Gotchas

- If your fresh export logs a different `unityStreamingAssets` value, update it in
  `android/gradle.properties` to match (Unity prints it in the export log).
- Gradle may warn that plugins want a higher NDK (28.x). It's a non-fatal warning; the build proceeds.
  Keep `ndkVersion "27.2.12479018"` (Unity's) unless you hit an actual NDK-not-found error.
- Single Unity instance only — the face is mounted once on the main screen (persistent). Don't add a
  second `EmbedUnity` elsewhere.
- After installing on the tablet: the square should show the face; have Maradel speak (voice button in
  the Maradel app) and it should lipsync.

— packaged from the NUC on 2026-06-18 (Keli 1.0.15+16).
