# ADDRESSABLES.md — remote content pipeline

Models moved **out of `Resources/`** to `Assets/App/Content/Models/`. Avatars now load via
**Addressables** — one bundle per avatar, downloaded on demand (or preloaded if "essential").

## Scripts (`Assets/Scripts/Content/`)

| File | Role | Guard |
|---|---|---|
| `BuildConfig.cs` | ScriptableObject: remote load/build paths, version, labels | always compiles |
| `DownloadProgress.cs` | global progress bus | always |
| `DownloadProgressView.cs` | drives an `Image.fillAmount` from the bus | always (uGUI) |
| `RemoteAvatars.cs` | helpers + **AssetBundle error coaching** (CRC/catalog/404/network/src-mismatch) | `#if ADDRESSABLES` |
| `MaradelPreloader.cs` | boot screen: downloads `essential` label w/ progress | `#if ADDRESSABLES` |
| `Editor/AddressableModelSetup.cs` | mark models addressable (groups=dirs, pack-separately, labels) | `#if ADDRESSABLES` |
| `Editor/AddressableBuilder.cs` | set remote paths from BuildConfig, build content | `#if ADDRESSABLES` |
| `RocketboxAutoRig` (Speech) | now loads avatars remotely; ◀/▶ download-on-demand + progress | `#if ADDRESSABLES` |

## Activation sequence (do in order)

1. **Let Unity reimport** — the model move + the Addressables package both trigger work. Wait for it.
2. Once the package resolves: **Project Settings ▸ Player ▸ Scripting Define Symbols** → add
   **`ADDRESSABLES`** (Standalone + Android). (Until then, addressable code is compiled out and the
   rig logs "models moved to Addressables".)
3. **Create a BuildConfig**: Assets ▸ Create ▸ Maradel ▸ Build Config. Set `remoteLoadPath` to your
   server (default `http://192.168.0.229:9100/addressables/[BuildTarget]`).
4. **Maradel ▸ Addressables ▸ 1. Mark Models Addressable** — groups per category (Adults/Children/
   Professions), pack-separately, label `avatar` on all + `essential` on the first N.
5. **Maradel ▸ Addressables ▸ 2. Build Remote (from BuildConfig)** — writes bundles to
   `remoteBuildPath` (e.g. `ServerData/StandaloneWindows64`). **Upload that folder** to the server at
   `remoteLoadPath`.

### Test in-editor WITHOUT a server
Window ▸ Asset Management ▸ Addressables ▸ Groups ▸ **Play Mode Script = "Use Asset Database (fastest)"**.
Avatars then load straight from the project (no build/upload). `GetDownloadSizeAsync` returns 0, so
the ◀/▶ load instantly. Switch to **"Use Existing Build"** to exercise real bundles/downloads.

## How it runs

- `RocketboxAutoRig` enumerates avatars via `Addressables.LoadResourceLocationsAsync(avatarLabel)`,
  then `InstantiateAsync(key)`. ◀/▶ → `GetDownloadSizeAsync` → if >0, `DownloadDependenciesAsync`
  with progress pushed to `DownloadProgress` (the `DownloadProgressView` sets `image.fillAmount`).
- `MaradelPreloader` (drop on a boot Canvas, assign BuildConfig) downloads the `essential` label up
  front with the same progress bar, then raises `OnReady`.
- Switching releases the old instance via `Addressables.ReleaseInstance`.

## Logging
All content logs are tagged **`[CONTENT]`**: sizes (MB), version, cache usage, download progress,
and decoded failures (hash/CRC mismatch, catalog mismatch, 404, network, build/src mismatch).

## One-button build pipeline — `Maradel ▸ Build`

`Assets/Scripts/Content/Editor/MaradelBuildPipeline.cs` runs the whole chain (must NOT be in Play):

1. **Build Addressables** — `CleanPlayerContent` + `BuildContent` (remote, pack-separately, remote
   catalog on, version stamped) → `ServerData/`.
2. **Wipe remote** — `DELETE /api/file?path=/mnt/cache/addressables` then `mkdir` (clears old bundles).
3. **Upload** — `PUT /api/shared/addressables/<rel>` per file (lands on the HDD via the symlink),
   cancelable progress bar with MB done + **ETA**.
4. **Verify** — `GET /api/fs` recursive count of remote files vs local; aborts on mismatch.
5. **Export Android client** — `exportAsGoogleAndroidProject` + `BuildPipeline.BuildPlayer` (EXPORT
   PROJECT) → `Build/Android`.

Every step is **timestamped `[BUILD] HH:mm:ss`**, sized (MB), and timed; durations persist to
`Assets/App/Content/BuildLog.json` and feed **ETA averages** shown in the progress bars.
The standalone `tool/upload-addressables.ps1` does just the upload if you want it outside the pipeline.

## Auto-update + cache (why catalog matters)
`MaradelPreloader` calls `Addressables.CheckForCatalogUpdates` → `UpdateCatalogs` on boot, so a
rebuilt+re-uploaded content set is picked up **without an app rebuild** — changed bundles re-download
on next access. Cache state (version, load path, MB cached) is logged `[CONTENT]`/`CACHE:` before and
after updates. The build's `BuildRemoteCatalog = true` + bumped `contentVersion` are what make this work.

## Notes / TODO
- **Server:** anything that serves the `ServerData` folder over HTTP works (even the Maradel box).
- **Android:** cleartext HTTP must be allowed for a plain-`http` remote path (manifest
  `usesCleartextTraffic`), same as the voice WAVs.
- **Content updates:** `BuildRemoteCatalog` is on; bump `BuildConfig.contentVersion` and rebuild to
  ship new/changed avatars without a new app build.
