# FLUTTER_INTEGRATION.md — embedding the Maradel talking head

Self-contained guide for the **Flutter developer/agent**. The Unity side is done and exported; this is
everything the Flutter app needs. Plugin: **`flutter_embed_unity`** (learntoflutter). Unity: **6000.5**.

---

## 0. The artifact

- **`unityLibrary`** (Unity's Android Gradle module) is published on **nuk**:
  `http://192.168.0.229:7777/api/shared/Build.zip`  (112 MB; `/home/erkamen-nuk/shared/Build.zip`).
- Unzip and place it at **`<flutter app>/android/unityLibrary`**.
- It was exported via *Flutter Embed ▸ Export project to flutter app (Android)* (Unity 6, IL2CPP, ARMv7+ARM64,
  Export Project, Application Entry Point = Activity).

The avatars, animations and voice are **NOT** in the zip — they stream at runtime from the LAN (see §5).

## 1. pubspec.yaml

```yaml
dependencies:
  flutter_embed_unity: ^<latest>
  flutter_embed_unity_6_android: ^<latest>   # Unity 6 Android impl — we are on 6.5
  # do NOT add flutter_embed_unity_2022_3_android (that's the 2022.3 / opt-out path)
  # iOS needs no extra dependency
```

## 2. Android setup

- **minSdk 23+** (required for Unity 6000).
- Add the Unity module to `android/settings.gradle` (`include ':unityLibrary'`) per the plugin README, and
  the dependency in the app module (the plugin docs show the exact gradle snippet).
- **Cleartext HTTP** — the head loads voice WAVs and asset bundles over plain `http`. In
  `android/app/src/main/AndroidManifest.xml` `<application …>`:
  ```xml
  android:usesCleartextTraffic="true"
  ```
- **configChanges** on the embedding Activity (prevents Unity being destroyed on rotation/resize):
  `orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode`

## 3. Embed the view

```dart
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

EmbedUnity(
  onMessageFromUnity: (String message) => _onUnityEvent(message),
)
```
That's the whole talking head — once embedded it connects to the backend itself and starts lip-syncing.
No per-frame calls needed.

## 4. Messaging contract

### 4a. Flutter → Unity (control)  —  optional
`flutter_embed_unity` routes by GameObject name + method (reflection). Target is **`FlutterFace`** /
method **`OnMessage`**, payload is a **JSON string**:

```dart
import 'dart:convert';
import 'package:flutter_embed_unity/flutter_embed_unity.dart';

void control(String type, {double value = 0, int index = 0}) =>
  sendToUnity("FlutterFace", "OnMessage", jsonEncode({"type": type, "value": value, "index": index}));
```

| `type`  | fields    | effect                                   |
|---------|-----------|------------------------------------------|
| `next`  | —         | next avatar                              |
| `prev`  | —         | previous avatar                          |
| `load`  | `index`   | load avatar at index                     |
| `scale` | `value`   | set model scale (e.g. 1.0)               |
| `show`  | —         | show the avatar                          |
| `hide`  | —         | hide the avatar                          |

Examples: `control("next")`, `control("load", index: 3)`, `control("scale", value: 1.2)`.
You don't need any of this for a basic talking head — it just connects and talks.

### 4b. Unity → Flutter (status)
Unity sends a JSON envelope string to `onMessageFromUnity`: `{"type": "...", "json": "<payload json>"}`.

```dart
void _onUnityEvent(String raw) {
  final env = jsonDecode(raw);
  switch (env["type"]) {
    case "ready":            break; // a face is loaded & rigged
    case "speakingStarted":  break; // backend voice started
    case "speakingStopped":  break; // backend voice ended
    case "error":            break; // env["json"] = {"message": "..."}
  }
}
```
Currently emitted: **`ready`**, **`speakingStarted`**, **`speakingStopped`** (`error` reserved). More
(e.g. `visemeFrame`, `faceChanged`) can be added Unity-side on request.

## 5. Network (LAN) — required for content + voice

The tablet must reach two hosts (both plain http, hence cleartext above):

| Host | Purpose |
|---|---|
| `192.168.0.229:9100` | Maradel voice backend — Socket.IO (voice plan/chunks) + WAV files |
| `192.168.0.11:7777`  | Addressables server (avatars + animation bundles) on the pi HDD |

Unity connects to these on its own; the Flutter app does nothing here beyond being on the same LAN with
cleartext enabled. (Hosts are baked into the Unity build's `MaradelVoiceConfig` / `BuildConfig`.)

## 6. Verify

1. App launches → Unity view shows an avatar within a few seconds (`ready` arrives).
2. Trigger a reply on the backend → avatar lip-syncs + gestures; `speakingStarted`/`Stopped` fire.
3. `control("next")` swaps the avatar.
If the avatar never appears: check LAN reach to `:7777` and cleartext. If it appears but never talks: check
`:9100` reach. (Unity logs `[MaradelVoice]`, `[CACHE]`, `[EMOTE]` to logcat.)

---
*Unity-side companion:* `UNITY_HANDOFF.md` (full contract + export steps), `EGREGOR_SHARE_API.md` (the
`:7777` API). Bridge source: `Assets/Scripts/Bridge/FlutterControlBridge.cs` (`FlutterFace.OnMessage`) +
`Assets/Scripts/Face/FlutterFace.cs` (outbound `SendToFlutter.Send`).
