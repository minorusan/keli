#if ADDRESSABLES
using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// One-button full pipeline — <b>Maradel ▸ Build</b>:
    ///   1. Build Addressables content (clean + build, remote, pack-separately).
    ///   2. Wipe old bundles on the pi HDD (/mnt/cache/addressables).
    ///   3. Upload new bundles via the API (progress + ETA + sizes).
    ///   4. Verify remote file count vs local.
    ///   5. Export the Android client (EXPORT PROJECT = Google Android Project).
    /// Every step is timestamped ([BUILD] HH:mm:ss), sized, and timed; durations feed ETA averages
    /// (BuildLog.json). API-verified. Progress bars with ETA where applicable.
    /// </summary>
    public static class MaradelBuildPipeline
    {
        const string RemotePrefix = "addressables";          // /api/shared/addressables (symlink → HDD)
        const string RemoteAbsRoot = "/mnt/cache/addressables"; // physical dir on the pi HDD
        const string UploadStep = "3 Upload";

        static long _stepBytes;

        [MenuItem("Maradel/Build")]
        public static void Build() => RunPipeline(includeClient: true);

        /// <summary>Build Addressables → wipe → upload → verify, and STOP (no Android client export).
        /// Use this to push bundles to the server and test remote loading before exporting the client.</summary>
        [MenuItem("Maradel/Build Bundles (no client)")]
        public static void BuildBundles() => RunPipeline(includeClient: false);

        static void RunPipeline(bool includeClient)
        {
            if (EditorApplication.isPlayingOrWillChangePlaymode)
            { Debug.LogError("[BUILD] exit Play mode before building."); return; }

            var cfg = FindBuildConfig();
            if (cfg == null) { Debug.LogError("[BUILD] no BuildConfig asset (Assets ▸ Create ▸ Maradel ▸ Build Config)."); return; }

            int n = includeClient ? 5 : 4;
            string plan = $"  1 build Addressables\n  2 wipe {RemoteAbsRoot}\n  3 upload\n  4 verify"
                        + (includeClient ? "\n  5 export Android client" : "  ← STOP (no client)");
            if (!EditorUtility.DisplayDialog("Maradel Build",
                $"{(includeClient ? "Full pipeline" : "Bundles only")}:\n{plan}\n\nActive platform: {EditorUserBuildSettings.activeBuildTarget}\n{cfg.Summary}\n\nProceed?",
                "Build", "Cancel")) return;

            var total = Stopwatch.StartNew();
            BuildLog.Line($"════ MARADEL BUILD START ({(includeClient ? "full" : "bundles-only")}, target {EditorUserBuildSettings.activeBuildTarget}) ════  {cfg.Summary}");
            bool ok = true;
            try
            {
                ok = ok && RunStep($"1/{n} Addressables", 0.00f, () => StepBuildAddressables(cfg));
                ok = ok && RunStep($"2/{n} Wipe remote",  0.20f, StepWipeRemote);
                ok = ok && RunStep(UploadStep,             0.30f, StepUpload);
                ok = ok && RunStep($"4/{n} Verify",        0.70f, StepVerify);
                if (includeClient)
                    ok = ok && RunStep("5/5 Android export", 0.80f, () => StepBuildAndroid(cfg));
            }
            finally { EditorUtility.ClearProgressBar(); }

            total.Stop();
            BuildLog.Line($"════ MARADEL BUILD {(ok ? "DONE" : "ABORTED")} in {total.Elapsed.TotalSeconds:0.0}s ════");
            EditorUtility.DisplayDialog("Maradel Build",
                $"{(ok ? "✓ Success" : "✗ Aborted (see Console)")}" +
                $"{(ok && !includeClient ? "\nBundles uploaded — set Play Mode to 'Use Existing Build' to test remote." : "")}" +
                $"\nTotal {total.Elapsed.TotalSeconds:0.0}s", "OK");
        }

        static bool RunStep(string name, float baseProgress, Func<bool> body)
        {
            double eta = BuildLog.AvgSeconds(name);
            EditorUtility.DisplayProgressBar("Maradel Build", $"{name}   (~{eta:0}s from history)", baseProgress);
            BuildLog.Line($"▶ {name}  (eta ~{eta:0}s)");
            _stepBytes = 0;
            var sw = Stopwatch.StartNew();
            bool ok;
            try { ok = body(); }
            catch (Exception e) { Debug.LogError($"[BUILD] {name} EXCEPTION: {e}"); ok = false; }
            sw.Stop();
            if (!ok) { Debug.LogError($"[BUILD] {name} FAILED after {sw.Elapsed.TotalSeconds:0.0}s — aborting pipeline."); return false; }
            BuildLog.Record(name, sw.Elapsed.TotalSeconds, _stepBytes);
            return true;
        }

        // 1 ──────────────────────────────────────────────────────────────
        static bool StepBuildAddressables(BuildConfig cfg)
        {
            var result = AddressableBuilder.BuildContent(cfg);
            if (result == null || !string.IsNullOrEmpty(result.Error))
            { Debug.LogError($"[BUILD] addressables: {result?.Error ?? "no settings"}"); return false; }
            _stepBytes = DirSize(ServerData());
            BuildLog.Line($"addressables → {_stepBytes / (1024 * 1024f):0.1} MB at ServerData/");
            return true;
        }

        // 2 ──────────────────────────────────────────────────────────────
        static bool StepWipeRemote()
        {
            BuildLog.Line($"deleting {RemoteAbsRoot} (old bundles) …");
            MaradelApi.DeleteAbs(RemoteAbsRoot, out int del);   // ok if absent
            bool md = MaradelApi.Mkdir(RemoteAbsRoot);
            BuildLog.Line($"wiped: delete http={del}, mkdir={md}  (cache: clients re-download changed bundles)");
            return md || del == 200;
        }

        // 3 ──────────────────────────────────────────────────────────────
        static bool StepUpload()
        {
            string src = ServerData();
            if (!Directory.Exists(src)) { Debug.LogError("[BUILD] no ServerData/ to upload."); return false; }

            var files = Directory.GetFiles(src, "*", SearchOption.AllDirectories);
            long totalBytes = files.Sum(f => new FileInfo(f).Length);
            double rate = BuildLog.AvgBytesPerSec(UploadStep);
            if (rate <= 0) rate = 6 * 1024 * 1024; // 6 MB/s first-run guess for ETA
            BuildLog.Line($"uploading {files.Length} files, {totalBytes / (1024 * 1024f):0.1} MB → {RemoteAbsRoot}");

            long sent = 0; int ok = 0, fail = 0;
            var sw = Stopwatch.StartNew();
            for (int i = 0; i < files.Length; i++)
            {
                string rel = (RemotePrefix + "/" + files[i].Substring(src.Length).TrimStart('\\', '/')).Replace('\\', '/');
                byte[] bytes = File.ReadAllBytes(files[i]);
                bool put = MaradelApi.PutShared(rel, bytes, out int code);
                sent += bytes.Length;
                if (put) ok++; else { fail++; BuildLog.Line($"  ✗ {rel} http={code}"); }

                double remain = (totalBytes - sent) / Math.Max(1, rate);
                if (EditorUtility.DisplayCancelableProgressBar("Maradel Build — Upload",
                        $"{i + 1}/{files.Length}   {sent / (1024 * 1024f):0.1}/{totalBytes / (1024 * 1024f):0.1} MB   ETA {remain:0}s",
                        0.30f + 0.40f * ((i + 1f) / files.Length)))
                { Debug.LogWarning("[BUILD] upload cancelled."); return false; }
            }
            sw.Stop();
            _stepBytes = totalBytes;
            double mbps = totalBytes / (1024 * 1024f) / Math.Max(0.1, sw.Elapsed.TotalSeconds);
            BuildLog.Line($"uploaded {ok}/{files.Length} ({totalBytes / (1024 * 1024f):0.1} MB) in {sw.Elapsed.TotalSeconds:0.0}s = {mbps:0.1} MB/s; {fail} failed");
            return fail == 0;
        }

        // 4 ──────────────────────────────────────────────────────────────
        static bool StepVerify()
        {
            int local = Directory.GetFiles(ServerData(), "*", SearchOption.AllDirectories).Length;
            int remote = MaradelApi.CountFilesRecursive(RemoteAbsRoot, out long remoteBytes);
            BuildLog.Line($"verify: local={local} files, remote={remote} files ({remoteBytes / (1024 * 1024f):0.1} MB on HDD)");
            if (remote < local) { Debug.LogError($"[BUILD] VERIFY MISMATCH: remote {remote} < local {local} — upload incomplete."); return false; }
            BuildLog.Line("verify OK ✓ (remote has all files)");
            return true;
        }

        // 5 ──────────────────────────────────────────────────────────────
        static bool StepBuildAndroid(BuildConfig cfg)
        {
            EditorUserBuildSettings.exportAsGoogleAndroidProject = true; // "Export Project" tick
            var scenes = EditorBuildSettings.scenes.Where(s => s.enabled).Select(s => s.path).ToArray();
            if (scenes.Length == 0) { Debug.LogError("[BUILD] no enabled scenes in Build Settings."); return false; }

            string outDir = Path.Combine(ProjectRoot(), "Build", "Android");
            Directory.CreateDirectory(outDir);

            var opts = new BuildPlayerOptions
            {
                scenes = scenes,
                locationPathName = outDir,
                target = BuildTarget.Android,
                targetGroup = BuildTargetGroup.Android,
                options = BuildOptions.AcceptExternalModificationsToPlayer, // export Gradle project
            };

            BuildLog.Line($"exporting Android project (EXPORT PROJECT) → {outDir} …");
            var report = BuildPipeline.BuildPlayer(opts);
            _stepBytes = (long)report.summary.totalSize;
            BuildLog.Line($"android: {report.summary.result}, {report.summary.totalSize / (1024 * 1024f):0.1} MB, " +
                          $"{report.summary.totalTime.TotalSeconds:0.0}s → {outDir}");
            return report.summary.result == BuildResult.Succeeded;
        }

        // helpers ─────────────────────────────────────────────────────────
        static string ProjectRoot() => Directory.GetParent(Application.dataPath).FullName;
        static string ServerData() => Path.Combine(ProjectRoot(), "ServerData");

        static long DirSize(string dir)
        {
            if (!Directory.Exists(dir)) return 0;
            long s = 0;
            foreach (var f in Directory.GetFiles(dir, "*", SearchOption.AllDirectories)) s += new FileInfo(f).Length;
            return s;
        }

        static BuildConfig FindBuildConfig()
        {
            var guid = AssetDatabase.FindAssets("t:BuildConfig").FirstOrDefault();
            return guid == null ? null : AssetDatabase.LoadAssetAtPath<BuildConfig>(AssetDatabase.GUIDToAssetPath(guid));
        }
    }
}
#endif
