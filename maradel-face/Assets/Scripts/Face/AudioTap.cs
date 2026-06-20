using System;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Sits on the AudioSource GameObject and forwards the post-mix PCM buffer to listeners
    /// via <see cref="OnAudio"/>. Used to drive <see cref="AmplitudeLipSyncProvider"/> in
    /// Milestone 0 (uLipSync taps audio itself, so this is not needed once on uLipSync).
    ///
    /// Note: OnAudioFilterRead runs on the audio thread — listeners must be thread-safe and
    /// must not touch Unity objects. AmplitudeLipSyncProvider only stashes a volatile float
    /// here and emits its frame later from Tick() on the main thread, so the rig is never
    /// driven off-thread.
    /// </summary>
    [RequireComponent(typeof(AudioSource))]
    [AddComponentMenu("Maradel/Audio Tap")]
    public sealed class AudioTap : MonoBehaviour
    {
        /// <summary>(pcm, channels, sampleRate). Raised on the audio thread.</summary>
        public event Action<float[], int, int> OnAudio;

        int _sampleRate;

        void Awake() => _sampleRate = AudioSettings.outputSampleRate;

        void OnAudioFilterRead(float[] data, int channels)
        {
            var handler = OnAudio;
            if (handler == null) return;

            // Downmix to mono so providers get a single channel.
            if (channels <= 1)
            {
                handler(data, 1, _sampleRate);
                return;
            }

            int frames = data.Length / channels;
            var mono = new float[frames];
            for (int f = 0; f < frames; f++)
            {
                float sum = 0f;
                int b = f * channels;
                for (int c = 0; c < channels; c++) sum += data[b + c];
                mono[f] = sum / channels;
            }
            handler(mono, 1, _sampleRate);
        }
    }
}
