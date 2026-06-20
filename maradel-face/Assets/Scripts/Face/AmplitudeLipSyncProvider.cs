using System;
using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Milestone-0 provider: no profile, no package. Computes RMS loudness of each fed PCM
    /// block and reports it as a single "Aa" viseme + Volume, so the jaw flaps in time with
    /// the audio. Proves the whole end-to-end path with one blendshape. Feed it from an
    /// <see cref="AudioTap"/> sitting on the AudioSource.
    ///
    /// Thread-safety: <see cref="Feed"/> is called on the audio thread, so it only stores a
    /// volatile float. <see cref="OnFrame"/> is raised from <see cref="Tick"/> (call it on the
    /// main thread each frame — FaceDriver does), so the rig is never touched off-thread.
    /// </summary>
    public sealed class AmplitudeLipSyncProvider : ILipSyncProvider
    {
        public event Action<VisemeFrame> OnFrame;

        readonly float _gain;
        readonly float _noiseFloor;
        readonly (Viseme, float)[] _scratch = new (Viseme, float)[1];

        volatile float _latestVolume; // written on audio thread, read on main thread (atomic)

        public AmplitudeLipSyncProvider(float gain = 3f, float noiseFloor = 0.01f)
        {
            _gain = gain;
            _noiseFloor = noiseFloor;
        }

        /// <summary>Audio thread: just measure and stash. No Unity calls, no events.</summary>
        public void Feed(float[] pcm, int channels, int sampleRate)
        {
            if (pcm == null || pcm.Length == 0) { _latestVolume = 0f; return; }

            double sumSq = 0;
            for (int i = 0; i < pcm.Length; i++) sumSq += pcm[i] * (double)pcm[i];
            float rms = Mathf.Sqrt((float)(sumSq / pcm.Length));

            _latestVolume = Mathf.Clamp01((rms - _noiseFloor) * _gain);
        }

        /// <summary>Main thread: publish the latest measured loudness as a frame.</summary>
        public void Tick()
        {
            float v = _latestVolume;
            _scratch[0] = (Viseme.Aa, v);
            OnFrame?.Invoke(new VisemeFrame(v > 0f ? Viseme.Aa : Viseme.Sil, v,
                (IReadOnlyList<(Viseme, float)>)_scratch));
        }

        public void Reset()
        {
            _latestVolume = 0f;
            _scratch[0] = (Viseme.Aa, 0f);
            OnFrame?.Invoke(new VisemeFrame(Viseme.Sil, 0f,
                (IReadOnlyList<(Viseme, float)>)_scratch));
        }
    }
}
