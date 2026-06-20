using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Maradel.Content
{
    /// <summary>
    /// Cache/bundle event log. Writes timestamped lines to BOTH the Console ([CACHE]) and a file in
    /// the app dir (<persistentDataPath>/Logs/maradel-cache.log), and keeps a recent-lines ring buffer
    /// the in-Unity cache overlay renders. This is the audit trail for Addressables caching /
    /// auto-update so we can see exactly what was downloaded, cached, and re-fetched.
    /// </summary>
    public static class CacheLog
    {
        public const int MaxRecent = 60;
        static readonly List<string> _recent = new();
        public static IReadOnlyList<string> Recent => _recent;

        public static string FilePath => Path.Combine(Application.persistentDataPath, "Logs", "maradel-cache.log");

        public static void Log(string msg)
        {
            string line = $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {msg}";
            _recent.Add(line);
            if (_recent.Count > MaxRecent) _recent.RemoveAt(0);
            Debug.Log($"[CACHE] {msg}");
            try
            {
                string dir = Path.GetDirectoryName(FilePath);
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                File.AppendAllText(FilePath, line + "\n");
            }
            catch (Exception e) { Debug.LogWarning($"[CACHE] file write failed: {e.Message}"); }
        }

        /// <summary>Current Unity AssetBundle cache usage (bytes). Works without Addressables.</summary>
        public static long CacheUsedBytes => Caching.defaultCache.valid ? Caching.defaultCache.spaceOccupied : 0;
        public static long CacheFreeBytes => Caching.defaultCache.valid ? Caching.defaultCache.spaceFree : 0;

        public static void LogCacheState(string note)
            => Log($"{note} — cache used {CacheUsedBytes / (1024 * 1024f):0.1} MB, free {CacheFreeBytes / (1024 * 1024f):0.0} MB");
    }
}
