using System;
using System.Collections.Generic;

namespace Maradel.Face
{
    /// <summary>
    /// Oculus-15 viseme set. A VRM model only physically exposes 5 mouth shapes
    /// (aa/ih/ou/ee/oh + sil); the VisemeMap collapses these 15 onto whatever the
    /// model actually has, so the rest of the pipeline never cares which model it is.
    /// </summary>
    public enum Viseme
    {
        Sil, PP, FF, TH, DD, Kk, CH, SS, Nn, RR, Aa, E, Ih, Oh, Ou
    }

    /// <summary>Idle-life expression presets (blink, brows, micro-smile).</summary>
    public enum Expression
    {
        Blink, BrowUp, BrowDown, Smile, Squint
    }

    /// <summary>
    /// One frame of lipsync output. Produced by an <see cref="ILipSyncProvider"/>,
    /// consumed by <see cref="LipSyncController"/>.
    /// </summary>
    public readonly struct VisemeFrame
    {
        /// <summary>Loudest viseme this frame.</summary>
        public readonly Viseme Dominant;
        /// <summary>Overall loudness 0..1 (drives the crude jaw fallback).</summary>
        public readonly float Volume;
        /// <summary>Per-viseme weights this frame (already 0..1, pre-gain).</summary>
        public readonly IReadOnlyList<(Viseme viseme, float weight)> Weights;

        public VisemeFrame(Viseme dominant, float volume,
            IReadOnlyList<(Viseme, float)> weights)
        {
            Dominant = dominant;
            Volume = volume;
            Weights = weights ?? Array.Empty<(Viseme, float)>();
        }
    }
}
