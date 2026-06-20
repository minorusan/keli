using System;
using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// The single piece of per-model data. Each binding ties one <see cref="Viseme"/> to:
    ///   - the uLipSync phoneme label(s) that map onto it (e.g. "A" -> Aa),
    ///   - the blendshape name(s) on the model's SkinnedMeshRenderer to drive,
    ///   - a max weight (gain cap) so a model that over-opens can be tamed.
    /// Swap the avatar => author a new VisemeMap asset. No code changes.
    ///
    /// Create via: Assets > Create > Maradel > Viseme Map.
    /// </summary>
    [CreateAssetMenu(menuName = "Maradel/Viseme Map", fileName = "VisemeMap")]
    public sealed class VisemeMap : ScriptableObject
    {
        [Serializable]
        public sealed class Binding
        {
            public Viseme viseme;

            [Tooltip("uLipSync phoneme labels that resolve to this viseme (case-insensitive). " +
                     "E.g. a 5-vowel VRM profile uses A, I, U, E, O.")]
            public string[] phonemes = Array.Empty<string>();

            [Tooltip("Blendshape names on the target SkinnedMeshRenderer to drive for this viseme. " +
                     "VRM 0.x examples: Fcl_MTH_A, Fcl_MTH_I, Fcl_MTH_U, Fcl_MTH_E, Fcl_MTH_O.")]
            public string[] blendShapes = Array.Empty<string>();

            [Range(0f, 1f)]
            [Tooltip("Gain cap. Final weight = providerWeight * maxWeight.")]
            public float maxWeight = 1f;
        }

        [Header("Mouth visemes")]
        [SerializeField] List<Binding> bindings = new();

        [Header("Jaw fallback (Milestone 0 / amplitude mode)")]
        [Tooltip("Blendshape(s) used by SetMouthOpen when there are no real visemes yet.")]
        [SerializeField] string[] mouthOpenBlendShapes = { "Fcl_MTH_A" };
        [Range(0f, 1f)][SerializeField] float mouthOpenMax = 1f;

        [Header("Expressions (idle life)")]
        [SerializeField] List<ExpressionBinding> expressions = new();

        [Serializable]
        public sealed class ExpressionBinding
        {
            public Expression expression;
            public string[] blendShapes = Array.Empty<string>();
            [Range(0f, 1f)] public float maxWeight = 1f;
        }

        // ── lookups, built lazily ──
        Dictionary<string, Viseme> _phonemeToViseme;
        Dictionary<Viseme, Binding> _visemeToBinding;
        Dictionary<Expression, ExpressionBinding> _expressionToBinding;

        void EnsureMaps()
        {
            if (_phonemeToViseme != null) return;

            _phonemeToViseme = new Dictionary<string, Viseme>(StringComparer.OrdinalIgnoreCase);
            _visemeToBinding = new Dictionary<Viseme, Binding>();
            foreach (var b in bindings)
            {
                _visemeToBinding[b.viseme] = b;
                if (b.phonemes == null) continue;
                foreach (var p in b.phonemes)
                    if (!string.IsNullOrEmpty(p)) _phonemeToViseme[p] = b.viseme;
            }

            _expressionToBinding = new Dictionary<Expression, ExpressionBinding>();
            foreach (var e in expressions) _expressionToBinding[e.expression] = e;
        }

        /// <summary>Resolve a uLipSync phoneme label to a viseme. Unknown / silence -> Sil.</summary>
        public Viseme FromPhoneme(string phoneme)
        {
            EnsureMaps();
            if (!string.IsNullOrEmpty(phoneme) &&
                _phonemeToViseme.TryGetValue(phoneme, out var v)) return v;
            return Viseme.Sil;
        }

        /// <summary>Blendshape names driven by this viseme (empty if unmapped).</summary>
        public IReadOnlyList<string> BlendShapesFor(Viseme v)
        {
            EnsureMaps();
            return _visemeToBinding.TryGetValue(v, out var b) && b.blendShapes != null
                ? b.blendShapes
                : Array.Empty<string>();
        }

        /// <summary>Gain cap for a viseme (1 if unmapped).</summary>
        public float Gain(Viseme v)
        {
            EnsureMaps();
            return _visemeToBinding.TryGetValue(v, out var b) ? b.maxWeight : 1f;
        }

        public IReadOnlyList<string> MouthOpenBlendShapes => mouthOpenBlendShapes;
        public float MouthOpenMax => mouthOpenMax;

        public IReadOnlyList<string> BlendShapesFor(Expression e)
        {
            EnsureMaps();
            return _expressionToBinding.TryGetValue(e, out var b) && b.blendShapes != null
                ? b.blendShapes
                : Array.Empty<string>();
        }

        public float Gain(Expression e)
        {
            EnsureMaps();
            return _expressionToBinding.TryGetValue(e, out var b) ? b.maxWeight : 1f;
        }

        /// <summary>All visemes that have at least one blendshape — used to zero the mouth.</summary>
        public IEnumerable<Viseme> MappedVisemes()
        {
            EnsureMaps();
            return _visemeToBinding.Keys;
        }

#if UNITY_EDITOR
        void OnValidate() => _phonemeToViseme = null; // rebuild after inspector edits
#endif
    }
}
