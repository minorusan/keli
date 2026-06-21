using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Drives FACIAL EXPRESSION on a Rocketbox face from an emotion id, using the ARKit (AK_*)
    /// blendshapes. Runs on the SAME SkinnedMeshRenderer as <see cref="RocketboxFaceRig"/> but on a
    /// DIFFERENT shape set (AK_* vs the AA_VI_* visemes) — so expression and lipsync layer cleanly.
    /// Subscribe its <see cref="SetEmotion"/> to the EmotionSequencer's OnFaceEmotion.
    /// </summary>
    [AddComponentMenu("Maradel/Expression Controller")]
    public sealed class ExpressionController : MonoBehaviour
    {
        // emotion id → set of (ARKit blendshape suffix, weight 0..1). Empty = neutral.
        static readonly Dictionary<string, (string shape, float w)[]> Poses = new()
        {
            { "neutral", System.Array.Empty<(string, float)>() },
            // Conversational "ears" states (driven by voice:attention → setMood): listening = attentive,
            // brows up + a small smile + eyes a touch wide; thinking = pondering, inner brow up + one brow
            // down + mouth pucker + slight squint. These make the VAD/generating signal VISIBLE on the face.
            { "listening",    new[] { ("AK_03_BrowInnerUp",.2f), ("AK_04_BrowOuterUpLeft",.25f), ("AK_05_BrowOuterUpRight",.25f), ("AK_21_EyeWideLeft",.12f), ("AK_22_EyeWideRight",.12f), ("AK_44_MouthSmileLeft",.15f), ("AK_45_MouthSmileRight",.15f) } },
            { "thinking",     new[] { ("AK_03_BrowInnerUp",.3f), ("AK_01_BrowDownLeft",.2f), ("AK_38_MouthPucker",.2f), ("AK_19_EyeSquintLeft",.15f), ("AK_20_EyeSquintRight",.15f) } },
            { "happy",        new[] { ("AK_44_MouthSmileLeft",.6f), ("AK_45_MouthSmileRight",.6f), ("AK_07_CheekSquintLeft",.25f), ("AK_08_CheekSquintRight",.25f) } },
            { "joyful",       new[] { ("AK_44_MouthSmileLeft",.85f), ("AK_45_MouthSmileRight",.85f), ("AK_07_CheekSquintLeft",.4f), ("AK_08_CheekSquintRight",.4f), ("AK_21_EyeWideLeft",.15f), ("AK_22_EyeWideRight",.15f) } },
            { "excited",      new[] { ("AK_44_MouthSmileLeft",.7f), ("AK_45_MouthSmileRight",.7f), ("AK_21_EyeWideLeft",.35f), ("AK_22_EyeWideRight",.35f), ("AK_03_BrowInnerUp",.3f) } },
            { "amused",       new[] { ("AK_44_MouthSmileLeft",.45f), ("AK_45_MouthSmileRight",.6f), ("AK_07_CheekSquintLeft",.3f), ("AK_08_CheekSquintRight",.3f) } },
            { "playful",      new[] { ("AK_44_MouthSmileLeft",.55f), ("AK_45_MouthSmileRight",.5f), ("AK_19_EyeSquintLeft",.25f) } },
            { "affectionate", new[] { ("AK_44_MouthSmileLeft",.45f), ("AK_45_MouthSmileRight",.45f), ("AK_07_CheekSquintLeft",.3f), ("AK_08_CheekSquintRight",.3f), ("AK_03_BrowInnerUp",.15f) } },
            { "proud",        new[] { ("AK_44_MouthSmileLeft",.4f), ("AK_45_MouthSmileRight",.4f), ("AK_04_BrowOuterUpLeft",.2f), ("AK_05_BrowOuterUpRight",.2f) } },
            { "confident",    new[] { ("AK_44_MouthSmileLeft",.3f), ("AK_45_MouthSmileRight",.3f), ("AK_04_BrowOuterUpLeft",.15f), ("AK_05_BrowOuterUpRight",.15f) } },
            { "curious",      new[] { ("AK_03_BrowInnerUp",.4f), ("AK_04_BrowOuterUpLeft",.35f), ("AK_21_EyeWideLeft",.15f), ("AK_22_EyeWideRight",.15f) } },
            { "thoughtful",   new[] { ("AK_03_BrowInnerUp",.25f), ("AK_01_BrowDownLeft",.2f), ("AK_38_MouthPucker",.15f) } },
            { "focused",      new[] { ("AK_01_BrowDownLeft",.25f), ("AK_02_BrowDownRight",.25f), ("AK_19_EyeSquintLeft",.2f), ("AK_20_EyeSquintRight",.2f) } },
            { "surprised",    new[] { ("AK_21_EyeWideLeft",.6f), ("AK_22_EyeWideRight",.6f), ("AK_25_JawOpen",.3f), ("AK_03_BrowInnerUp",.5f), ("AK_04_BrowOuterUpLeft",.4f), ("AK_05_BrowOuterUpRight",.4f) } },
            { "impressed",    new[] { ("AK_21_EyeWideLeft",.35f), ("AK_22_EyeWideRight",.35f), ("AK_44_MouthSmileLeft",.4f), ("AK_45_MouthSmileRight",.4f), ("AK_04_BrowOuterUpLeft",.3f), ("AK_05_BrowOuterUpRight",.3f) } },
            { "concerned",    new[] { ("AK_03_BrowInnerUp",.5f), ("AK_30_MouthFrownLeft",.2f), ("AK_31_MouthFrownRight",.2f) } },
            { "confused",     new[] { ("AK_01_BrowDownLeft",.3f), ("AK_05_BrowOuterUpRight",.35f), ("AK_38_MouthPucker",.2f) } },
            { "skeptical",    new[] { ("AK_05_BrowOuterUpRight",.45f), ("AK_01_BrowDownLeft",.3f), ("AK_38_MouthPucker",.15f) } },
            { "annoyed",      new[] { ("AK_01_BrowDownLeft",.5f), ("AK_02_BrowDownRight",.5f), ("AK_30_MouthFrownLeft",.25f), ("AK_31_MouthFrownRight",.25f), ("AK_50_NoseSneerLeft",.2f), ("AK_51_NoseSneerRight",.2f) } },
            { "disappointed", new[] { ("AK_30_MouthFrownLeft",.4f), ("AK_31_MouthFrownRight",.4f), ("AK_03_BrowInnerUp",.3f) } },
            { "sad",          new[] { ("AK_30_MouthFrownLeft",.5f), ("AK_31_MouthFrownRight",.5f), ("AK_03_BrowInnerUp",.6f) } },
            { "tired",        new[] { ("AK_09_EyeBlinkLeft",.35f), ("AK_10_EyeBlinkRight",.35f), ("AK_03_BrowInnerUp",.2f), ("AK_25_JawOpen",.12f) } },
            { "embarrassed",  new[] { ("AK_44_MouthSmileLeft",.3f), ("AK_45_MouthSmileRight",.3f), ("AK_07_CheekSquintLeft",.4f), ("AK_08_CheekSquintRight",.4f), ("AK_11_EyeLookDownLeft",.25f), ("AK_12_EyeLookDownRight",.25f) } },
        };

        /// <summary>All emotion ids this controller knows a face pose for (for UI / testing).</summary>
        public static readonly string[] EmotionIds = new List<string>(Poses.Keys).ToArray();

        [SerializeField] SkinnedMeshRenderer faceRenderer;
        [Range(1f, 30f)][SerializeField] float responsiveness = 9f;

        readonly Dictionary<string, int> _suffixToIndex = new();
        readonly Dictionary<int, float> _target = new();
        readonly Dictionary<int, float> _current = new();
        bool _ready;

        public void Configure(SkinnedMeshRenderer r) { faceRenderer = r; _ready = false; }

        void EnsureReady()
        {
            if (_ready) return;
            if (faceRenderer == null) return;
            var mesh = faceRenderer.sharedMesh;
            if (mesh == null) return;
            // resolve every suffix used by any pose → blendshape index (tolerate "<mesh>.AK_xx" names)
            var wanted = new HashSet<string>();
            foreach (var p in Poses.Values) foreach (var s in p) wanted.Add(s.shape);
            for (int i = 0; i < mesh.blendShapeCount; i++)
            {
                string name = mesh.GetBlendShapeName(i);
                foreach (var w in wanted)
                    if (name.EndsWith(w, System.StringComparison.OrdinalIgnoreCase) && !_suffixToIndex.ContainsKey(w))
                        _suffixToIndex[w] = i;
            }
            _ready = true;
        }

        /// <summary>Apply an emotion's facial pose (smoothly). Unknown id → neutral.</summary>
        public void SetEmotion(string emotion)
        {
            EnsureReady();
            if (!_ready) { Debug.LogWarning("[EXPR] no face mesh assigned.", this); return; }

            // zero everything we manage, then set the new pose
            foreach (var idx in _suffixToIndex.Values) _target[idx] = 0f;
            if (Poses.TryGetValue((emotion ?? "neutral").ToLowerInvariant(), out var pose))
                foreach (var (shape, w) in pose)
                    if (_suffixToIndex.TryGetValue(shape, out int idx)) _target[idx] = Mathf.Clamp01(w);
            Debug.Log($"[EXPR] face emotion '{emotion}' ({(pose != null ? pose.Length : 0)} shapes)", this);
        }

        void LateUpdate()
        {
            if (!_ready || _target.Count == 0) return;
            float k = 1f - Mathf.Exp(-responsiveness * Time.deltaTime);
            foreach (var kvp in _target)
            {
                float cur = _current.TryGetValue(kvp.Key, out var c) ? c : 0f;
                float next = Mathf.Lerp(cur, kvp.Value, k);
                _current[kvp.Key] = next;
                faceRenderer.SetBlendShapeWeight(kvp.Key, next * 100f);
            }
        }
    }
}
