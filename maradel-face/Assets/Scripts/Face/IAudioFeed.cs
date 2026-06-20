using System;

namespace Maradel.Face
{
    /// <summary>
    /// Source of audio for the face. Unity owns playback so the bytes uLipSync analyzes are
    /// exactly the bytes the AudioSource emits — lipsync is in sync by construction.
    /// </summary>
    public interface IAudioFeed
    {
        /// <summary>Queue a finite clip (a Maradel WAV chunk) for playback in arrival order.</summary>
        void Enqueue(string url, int index, float durationSec);

        void Stop();
        bool IsPlaying { get; }

        /// <summary>First chunk of an utterance began.</summary>
        event Action OnPlaybackStarted;
        /// <summary>Queue emptied (utterance finished).</summary>
        event Action OnPlaybackDrained;
    }
}
