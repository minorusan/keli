using System;

namespace Maradel.Face
{
    /// <summary>
    /// The heart: pure orchestration over the three interfaces. No Unity types in its logic,
    /// so it is testable headless and reusable. Construct it with the three impls + a map,
    /// call <see cref="Initialize"/>, and forward inbound commands (PlayChunk / Stop / SetMood).
    ///
    /// Wiring is done either by <see cref="FaceDriver"/> (standalone, no DI) or by a Zenject
    /// installer (see FaceInstaller.cs, behind the ZENJECT define).
    /// </summary>
    public sealed class LipSyncController : IDisposable
    {
        readonly IFaceRig _rig;
        readonly ILipSyncProvider _provider;
        readonly IAudioFeed _audio;

        public event Action OnReady;
        public event Action OnSpeakingStarted;
        public event Action OnSpeakingStopped;
        public event Action<VisemeFrame> OnVisemeFrame; // debug / telemetry

        public LipSyncController(IFaceRig rig, ILipSyncProvider provider, IAudioFeed audio)
        {
            _rig = rig ?? throw new ArgumentNullException(nameof(rig));
            _provider = provider ?? throw new ArgumentNullException(nameof(provider));
            _audio = audio ?? throw new ArgumentNullException(nameof(audio));
        }

        public void Initialize()
        {
            _provider.OnFrame += ApplyFrame;
            _audio.OnPlaybackStarted += HandleStarted;
            _audio.OnPlaybackDrained += HandleDrained;
            if (_rig.IsReady) OnReady?.Invoke();
        }

        // ── inbound commands ──
        public void PlayChunk(string url, int index, float dur) => _audio.Enqueue(url, index, dur);

        public void Stop()
        {
            _audio.Stop();
            _provider.Reset();
            _rig.ResetMouth();
        }

        public void SetMood(string mood)
        {
            // Hook for idle Expression presets; left to IdleLife / app logic.
        }

        void HandleStarted() => OnSpeakingStarted?.Invoke();

        void HandleDrained()
        {
            _provider.Reset();
            _rig.ResetMouth();
            OnSpeakingStopped?.Invoke();
        }

        void ApplyFrame(VisemeFrame f)
        {
            if (f.Weights != null)
                foreach (var (v, w) in f.Weights)
                    _rig.SetViseme(v, w); // gain is applied inside the rig via the VisemeMap
            OnVisemeFrame?.Invoke(f);
        }

        public void Dispose()
        {
            _provider.OnFrame -= ApplyFrame;
            _audio.OnPlaybackStarted -= HandleStarted;
            _audio.OnPlaybackDrained -= HandleDrained;
        }
    }
}
