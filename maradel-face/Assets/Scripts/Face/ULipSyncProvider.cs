// Real-viseme provider backed by hecomi/uLipSync.
// Guarded so the project compiles before the package is installed.
// Enable: Project Settings > Player > Scripting Define Symbols  ->  add  ULIPSYNC
#if ULIPSYNC
using System;
using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Subscribes to the uLipSync component's <c>onLipSyncUpdate</c> UnityEvent and
    /// republishes each <c>LipSyncInfo</c> as a <see cref="VisemeFrame"/>. uLipSync analyzes
    /// the AudioSource it sits on via OnAudioFilterRead, so no PCM is fed here.
    ///
    /// LipSyncInfo fields (uLipSync v3): string phoneme; float volume; float rawVolume;
    /// Dictionary&lt;string,float&gt; phonemeRatios.
    /// </summary>
    public sealed class ULipSyncProvider : ILipSyncProvider
    {
        public event Action<VisemeFrame> OnFrame;

        readonly uLipSync.uLipSync _uLipSync;
        readonly VisemeMap _map;
        readonly List<(Viseme, float)> _weights = new();

        public ULipSyncProvider(uLipSync.uLipSync uLipSyncComponent, VisemeMap map = null)
        {
            _uLipSync = uLipSyncComponent ?? throw new ArgumentNullException(nameof(uLipSyncComponent));
            _map = map; // null => use the built-in PhonemeMap defaults (zero-config Rocketbox path)
            _uLipSync.onLipSyncUpdate.AddListener(HandleUpdate);
        }

        Viseme Resolve(string phoneme) =>
            _map != null ? _map.FromPhoneme(phoneme) : PhonemeMap.FromPhoneme(phoneme);

        void HandleUpdate(uLipSync.LipSyncInfo info)
        {
            _weights.Clear();

            float top = 0f;
            Viseme dominant = Viseme.Sil;

            if (info.phonemeRatios != null)
            {
                foreach (var kvp in info.phonemeRatios)
                {
                    Viseme v = Resolve(kvp.Key);
                    float w = kvp.Value * info.volume; // scale phoneme ratio by loudness
                    _weights.Add((v, w));
                    if (w > top) { top = w; dominant = v; }
                }
            }
            else
            {
                dominant = Resolve(info.phoneme);
                _weights.Add((dominant, info.volume));
            }

            OnFrame?.Invoke(new VisemeFrame(dominant, info.volume,
                (IReadOnlyList<(Viseme, float)>)_weights));
        }

        public void Feed(float[] pcm, int channels, int sampleRate)
        {
            // uLipSync taps the AudioSource itself. For the optional Flutter-PCM path,
            // call _uLipSync.OnDataReceived(pcm, channels) here if your uLipSync build
            // exposes it.
        }

        public void Reset()
        {
            _weights.Clear();
            OnFrame?.Invoke(new VisemeFrame(Viseme.Sil, 0f,
                (IReadOnlyList<(Viseme, float)>)_weights));
        }
    }
}
#endif
