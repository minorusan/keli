using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Standalone wiring for editor testing (Milestones 0–1) with NO Zenject and NO Flutter.
    /// Drop this on a GameObject, assign the rig, the AudioSource, and the VisemeMap, hit Play.
    ///
    /// Amplitude mode: needs an <see cref="AudioTap"/> on the AudioSource GameObject.
    /// uLipSync mode (ULIPSYNC define + a uLipSync component assigned in the inspector):
    ///   real visemes from hecomi/uLipSync.
    ///
    /// For the Maradel-driven build use a Zenject installer instead (FaceInstaller.cs).
    /// </summary>
    [AddComponentMenu("Maradel/Face Driver (Standalone)")]
    public sealed class FaceDriver : MonoBehaviour
    {
        public enum Mode { Amplitude, ULipSync }

        [SerializeField] Mode mode = Mode.Amplitude;

        [Header("References")]
        [Tooltip("Component implementing IFaceRig (e.g. SkinnedMeshFaceRig or RocketboxFaceRig).")]
        [SerializeField] MonoBehaviour faceRigComponent;
        [Tooltip("Optional. Only used in uLipSync mode to override the phoneme→viseme mapping. " +
                 "Leave null to use PhonemeMap defaults (A/I/U/E/O). RocketboxFaceRig needs none.")]
        [SerializeField] VisemeMap visemeMap;

        [Header("Audio (optional — for the Maradel-driven feed)")]
        [SerializeField] UnityWebRequestAudioFeed audioFeed;

        [Header("Amplitude mode")]
        [SerializeField] AudioTap audioTap;
        [SerializeField] float amplitudeGain = 3f;

#if ULIPSYNC
        [Header("uLipSync mode")]
        [SerializeField] uLipSync.uLipSync uLipSyncComponent;
#endif

        LipSyncController _controller;
        ILipSyncProvider _provider;
        AmplitudeLipSyncProvider _amplitude;
        IFaceRig _rig;

        void Start()
        {
            _rig = faceRigComponent as IFaceRig;
            if (_rig == null)
            {
                Debug.LogError($"{nameof(FaceDriver)}: faceRigComponent does not implement IFaceRig.", this);
                enabled = false;
                return;
            }
            _provider = BuildProvider();
            if (_provider == null) { enabled = false; return; }

            // A no-op feed is fine for amplitude tests with a pre-assigned local clip.
            IAudioFeed feed = audioFeed != null ? audioFeed : new NullAudioFeed();

            _controller = new LipSyncController(_rig, _provider, feed);
            _controller.OnReady += () => Debug.Log("[FaceDriver] rig ready");
            _controller.OnSpeakingStarted += () => Debug.Log("[FaceDriver] speaking");
            _controller.OnSpeakingStopped += () => Debug.Log("[FaceDriver] idle");
            _controller.Initialize();
        }

        ILipSyncProvider BuildProvider()
        {
            switch (mode)
            {
                case Mode.Amplitude:
                    _amplitude = new AmplitudeLipSyncProvider(amplitudeGain);
                    if (audioTap == null)
                    {
                        Debug.LogError($"{nameof(FaceDriver)}: Amplitude mode needs an AudioTap " +
                                       "on the AudioSource GameObject.", this);
                        return null;
                    }
                    audioTap.OnAudio += _amplitude.Feed;
                    return _amplitude;

                case Mode.ULipSync:
#if ULIPSYNC
                    if (uLipSyncComponent == null)
                    {
                        Debug.LogError($"{nameof(FaceDriver)}: uLipSync component not assigned.", this);
                        return null;
                    }
                    return new ULipSyncProvider(uLipSyncComponent, visemeMap);
#else
                    Debug.LogError($"{nameof(FaceDriver)}: ULipSync mode requires the ULIPSYNC " +
                                   "scripting define and the uLipSync package.", this);
                    return null;
#endif
                default:
                    return null;
            }
        }

        void Update()
        {
            // Amplitude provider publishes on the main thread from here (audio thread only stashes).
            _amplitude?.Tick();
        }

        // Convenience: call from a UI button / test harness to play a Maradel chunk.
        public void PlayChunk(string url, int index, float durationSec)
            => _controller?.PlayChunk(url, index, durationSec);

        void OnDestroy()
        {
            if (_amplitude != null && audioTap != null) audioTap.OnAudio -= _amplitude.Feed;
            _controller?.Dispose();
        }

        /// <summary>Stand-in feed when you drive audio by hand (local clip) in M0.</summary>
        sealed class NullAudioFeed : IAudioFeed
        {
            public void Enqueue(string url, int index, float durationSec) { }
            public void Stop() { }
            public bool IsPlaying => false;
            public event System.Action OnPlaybackStarted { add { } remove { } }
            public event System.Action OnPlaybackDrained { add { } remove { } }
        }
    }
}
