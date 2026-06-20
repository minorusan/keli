using System;

namespace Maradel.Face
{
    /// <summary>
    /// Abstraction over the lipsync engine. Concrete impls:
    ///   AmplitudeLipSyncProvider — RMS only (Milestone 0, no profile, no package).
    ///   ULipSyncProvider         — hecomi/uLipSync (production, real visemes).
    /// </summary>
    public interface ILipSyncProvider
    {
        /// <summary>Raised ~per audio block (audio or main thread, depending on impl).</summary>
        event Action<VisemeFrame> OnFrame;

        /// <summary>
        /// Feed raw mono PCM (-1..1). Used by the amplitude impl (tapped off the AudioSource)
        /// and the optional external-PCM path. The uLipSync impl taps audio internally and
        /// ignores this.
        /// </summary>
        void Feed(float[] pcm, int channels, int sampleRate);

        /// <summary>Clear internal state (call on stop).</summary>
        void Reset();
    }
}
