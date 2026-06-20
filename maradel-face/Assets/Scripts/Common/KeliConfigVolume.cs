using System;
using System.IO;
using UnityEngine;

namespace Maradel
{
    /// <summary>
    /// Applies the per-Keli master <c>volume</c> to the embedded face's audio. The Flutter app polls
    /// Maradel's per-Keli config every 60 s and caches it to <c>keli_config.json</c> in the app's
    /// external files dir — which on Android is the SAME directory as Unity's
    /// <see cref="Application.persistentDataPath"/> (both = /storage/emulated/0/Android/data/&lt;pkg&gt;/files).
    /// So we read that file and set <see cref="AudioListener.volume"/>, re-reading whenever its write
    /// time changes. Auto-created on play (no scene setup), matching the project's bootstrap style.
    /// (See configs_handoff.md.)
    /// </summary>
    public sealed class KeliConfigVolume : MonoBehaviour
    {
        const string FileName = "keli_config.json";
        const float CheckEvery = 2f;

        string _path;
        float _next;
        DateTime _lastWrite = DateTime.MinValue;

        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Bootstrap()
        {
            if (FindFirstObjectByType<KeliConfigVolume>() != null) return;
            var go = new GameObject("KeliConfigVolume");
            DontDestroyOnLoad(go);
            go.AddComponent<KeliConfigVolume>();
        }

        void Start()
        {
            _path = Path.Combine(Application.persistentDataPath, FileName);
            Debug.Log($"[KeliConfig] watching {_path}");
            Apply(force: true);
        }

        void Update()
        {
            if (Time.unscaledTime < _next) return;
            _next = Time.unscaledTime + CheckEvery;
            Apply(force: false);
        }

        void Apply(bool force)
        {
            try
            {
                if (!File.Exists(_path)) return;
                var w = File.GetLastWriteTimeUtc(_path);
                if (!force && w == _lastWrite) return;
                _lastWrite = w;

                var cfg = JsonUtility.FromJson<Cfg>(File.ReadAllText(_path));
                if (cfg != null && cfg.volume >= 0f)
                {
                    AudioListener.volume = Mathf.Clamp01(cfg.volume);
                    Debug.Log($"[KeliConfig] volume -> {AudioListener.volume:0.00}");
                }
            }
            catch (Exception e)
            {
                Debug.LogWarning($"[KeliConfig] read failed: {e.Message}");
            }
        }

        [Serializable]
        private class Cfg
        {
            public float volume = -1f; // -1 = key absent → leave volume unchanged
        }
    }
}
