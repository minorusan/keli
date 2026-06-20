#if ADDRESSABLES
using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;
using Debug = UnityEngine.Debug;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// Timestamped build logging + per-step duration/size history (for ETA averages).
    /// History persists to Assets/App/Content/BuildLog.json so ETAs improve over runs.
    /// All lines tagged [BUILD] with HH:mm:ss — grep to measure sizes + time.
    /// </summary>
    public static class BuildLog
    {
        const string TAG = "[BUILD]";

        [Serializable] class Rec { public string step; public double seconds; public long bytes; public string at; }
        [Serializable] class Hist { public List<Rec> records = new(); }

        static Hist _h;
        static string Path => System.IO.Path.Combine(Application.dataPath, "App/Content/BuildLog.json");

        static Hist H
        {
            get
            {
                if (_h == null)
                {
                    try { if (File.Exists(Path)) _h = JsonUtility.FromJson<Hist>(File.ReadAllText(Path)); } catch { }
                    _h ??= new Hist();
                }
                return _h;
            }
        }

        public static void Line(string m) => Debug.Log($"{TAG} {DateTime.Now:HH:mm:ss} {m}");

        public static double AvgSeconds(string step)
        {
            double s = 0; int n = 0;
            foreach (var r in H.records) if (r.step == step) { s += r.seconds; n++; }
            return n > 0 ? s / n : 0;
        }

        public static double AvgBytesPerSec(string step)
        {
            double b = 0, s = 0;
            foreach (var r in H.records) if (r.step == step && r.seconds > 0) { b += r.bytes; s += r.seconds; }
            return s > 0 ? b / s : 0;
        }

        public static void Record(string step, double seconds, long bytes)
        {
            H.records.Add(new Rec { step = step, seconds = seconds, bytes = bytes, at = DateTime.Now.ToString("s") });
            try { File.WriteAllText(Path, JsonUtility.ToJson(_h, true)); }
            catch (Exception e) { Debug.LogWarning($"{TAG} log save failed: {e.Message}"); }
            Line($"✔ {step}: {seconds:0.0}s, {bytes / (1024 * 1024f):0.1} MB  (avg {AvgSeconds(step):0.0}s over {Count(step)} runs)");
        }

        static int Count(string step) { int n = 0; foreach (var r in H.records) if (r.step == step) n++; return n; }
    }
}
#endif
