/// Keli backend URL (Socket.IO + REST). Override at build/run time with:
///   flutter run --dart-define=KELI_URL=http://192.168.0.229:9120
/// Default targets the NUC on the LAN (the phone is on the home network).
const String kKeliUrl = String.fromEnvironment(
  'KELI_URL',
  defaultValue: 'http://192.168.0.229:9120',
);

/// The roomba-rnd map/pose API (`api.mjs`, :9113) — source of the live Tapo minimap shown
/// in Keli's floating map window. Override with --dart-define=ROBOT_MAP_URL=...
const String kRobotMapUrl = String.fromEnvironment(
  'ROBOT_MAP_URL',
  defaultValue: 'http://192.168.0.229:9113',
);

/// The roomba-rnd direct-control server (`server.mjs`, :9110) — serves the live Tapo camera
/// frame at `/cam.jpg`, shown in Keli's floating cam window. Override with --dart-define=ROBOT_CAM_URL=...
const String kRobotCamUrl = String.fromEnvironment(
  'ROBOT_CAM_URL',
  defaultValue: 'http://192.168.0.229:9110',
);

/// The Maradel backend (:9100) — source of the voice stream that drives the 3D lipsync face.
/// Keli's normal traffic is to the Keli backend (:9120); the face bridge opens a second, voice-only
/// socket here for `voice:chunk` / `voice:speaking`, and Unity fetches the WAV chunks from here.
/// Override with --dart-define=MARADEL_URL=...  See docs (LIPSYNC.md).
const String kMaradelUrl = String.fromEnvironment(
  'MARADEL_URL',
  defaultValue: 'http://192.168.0.229:9100',
);

/// The Maradel mic ingest endpoint — the tablet streams continuous s16le / 16 kHz / mono PCM as
/// **binary WebSocket messages** here (the transport the backend documents as "what the Keli app
/// uses"; `vadwatch/keliMic.ts` → `handleKeliAudioWs`). The backend pipes the bytes into a FIFO that
/// the existing ffmpeg/VAD loop reads. A `?deviceId=<id>` is appended at connect time. The robot's "ears".
/// Override with --dart-define=MARADEL_AUDIO_WS=ws://host:9100/keli/audio.
const String kMaradelAudioWsUrl = String.fromEnvironment(
  'MARADEL_AUDIO_WS',
  defaultValue: 'ws://192.168.0.229:9100/keli/audio',
);

/// The lab file share (egregor-share) — the **Send** button on the mic-test clip PUTs the recording
/// here as a plain file you can open in the watcher (NOT into Maradel's chat). `PUT <base>/<name>`.
/// Override with --dart-define=SHARE_BASE_URL=http://host:7777/api/shared.
const String kShareBaseUrl = String.fromEnvironment(
  'SHARE_BASE_URL',
  defaultValue: 'http://192.168.0.229:7777/api/shared',
);

/// This build's identity. MUST be bumped in lockstep with `pubspec.yaml`'s
/// `version: x.y.z+BUILD` before each release build — the backend reads the
/// pubspec build number from `/version.json`, and the installed app compares it
/// against [kAppBuild] to offer an update.
const String kAppVersion = '1.0.48';
const int kAppBuild = 48;
