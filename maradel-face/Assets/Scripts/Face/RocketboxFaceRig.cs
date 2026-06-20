using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Drop-on-prefab <see cref="IFaceRig"/> specialised for **Microsoft Rocketbox** avatars.
    ///
    /// Every Rocketbox *_facial mesh exposes blendshapes <c>SR_01..SR_42</c>, and per the HeadBox
    /// toolkit the **first 15 (SR_01..SR_15) are the Oculus-Lipsync visemes, in Oculus order** —
    /// identical across all 117 avatars. So this component bakes that mapping in: drop it on any
    /// Rocketbox <c>*_facial</c> prefab and it Just Works — no VisemeMap asset, no per-model setup.
    ///
    /// Pairs with <see cref="ULipSyncProvider"/> + <see cref="LipSyncController"/> exactly like
    /// <see cref="SkinnedMeshFaceRig"/> (it implements the same interface).
    /// </summary>
    [AddComponentMenu("Maradel/Rocketbox Face Rig")]
    public sealed class RocketboxFaceRig : MonoBehaviour, IFaceRig
    {
        // Oculus-15 viseme -> Rocketbox blendshape suffix. Verified from the actual mesh: the
        // visemes are named "AA_VI_NN_<label>" (with a "blendShape1." prefix in Unity), NOT SR_*.
        static readonly Dictionary<Viseme, string> ShapeByViseme = new()
        {
            { Viseme.Sil, "AA_VI_00_Sil" },
            { Viseme.PP,  "AA_VI_01_PP" },
            { Viseme.FF,  "AA_VI_02_FF" },
            { Viseme.TH,  "AA_VI_03_TH" },
            { Viseme.DD,  "AA_VI_04_DD" },
            { Viseme.Kk,  "AA_VI_05_KK" },
            { Viseme.CH,  "AA_VI_06_CH" },
            { Viseme.SS,  "AA_VI_07_SS" },
            { Viseme.Nn,  "AA_VI_08_nn" },
            { Viseme.RR,  "AA_VI_09_RR" },
            { Viseme.Aa,  "AA_VI_10_aa" },
            { Viseme.E,   "AA_VI_11_E" },
            { Viseme.Ih,  "AA_VI_12_I" },
            { Viseme.Oh,  "AA_VI_13_O" },
            { Viseme.Ou,  "AA_VI_14_U" },
        };

        const string VisemeMarker = "AA_VI_"; // any viseme blendshape contains this

        [Tooltip("Facial SkinnedMeshRenderer. If null, the first child renderer that has the " +
                 "SR_01 blendshape is used.")]
        [SerializeField] SkinnedMeshRenderer faceRenderer;

        [Range(1f, 40f)]
        [Tooltip("Higher = snappier mouth. Frame-rate-independent lerp speed.")]
        [SerializeField] float responsiveness = 18f;

        [Tooltip("Per-viseme weight cap (0..1). SR shapes can over-open; 0.9 is usually safer.")]
        [Range(0f, 1f)][SerializeField] float maxWeight = 1f;

        readonly Dictionary<Viseme, int> _visemeIndex = new();
        readonly Dictionary<int, float> _current = new();
        readonly Dictionary<int, float> _target = new();

        public bool IsReady { get; private set; }

        void Awake()
        {
            if (faceRenderer == null) faceRenderer = FindFacialRenderer();
            if (faceRenderer == null || faceRenderer.sharedMesh == null)
            {
                Debug.LogError($"{nameof(RocketboxFaceRig)}: no Rocketbox facial mesh (AA_VI_*) found. " +
                               "Use the *_facial FBX, not the plain body FBX.", this);
                return;
            }

            var mesh = faceRenderer.sharedMesh;
            var nameToIndex = new Dictionary<string, int>(mesh.blendShapeCount);
            for (int i = 0; i < mesh.blendShapeCount; i++)
                nameToIndex[mesh.GetBlendShapeName(i)] = i;

            // Rocketbox prefixes the shape name with the mesh name, e.g. "Head.SR_01" — match by suffix.
            foreach (var kvp in ShapeByViseme)
                if (TryResolve(nameToIndex, kvp.Value, out int idx))
                    _visemeIndex[kvp.Key] = idx;

            IsReady = _visemeIndex.Count > 0;
            if (!IsReady)
                Debug.LogError($"{nameof(RocketboxFaceRig)}: found a skinned mesh but no AA_VI_* viseme " +
                               "blendshapes — is this really a Rocketbox _facial mesh?", this);
            else
                Debug.Log($"[SYNC_BEH] RocketboxFaceRig resolved {_visemeIndex.Count}/15 visemes on " +
                          $"'{faceRenderer.name}' (mesh '{mesh.name}')", this);
        }

        static bool TryResolve(Dictionary<string, int> names, string shape, out int index)
        {
            if (names.TryGetValue(shape, out index)) return true;
            foreach (var kvp in names) // tolerate "<mesh>.SR_01" style names
                if (kvp.Key.EndsWith(shape, System.StringComparison.OrdinalIgnoreCase))
                { index = kvp.Value; return true; }
            index = -1;
            return false;
        }

        SkinnedMeshRenderer FindFacialRenderer()
        {
            SkinnedMeshRenderer fallback = null;
            foreach (var r in GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                var m = r.sharedMesh;
                if (m == null) continue;
                bool hasViseme = false;
                for (int i = 0; i < m.blendShapeCount; i++)
                    if (m.GetBlendShapeName(i).IndexOf(VisemeMarker, System.StringComparison.OrdinalIgnoreCase) >= 0)
                    { hasViseme = true; break; }
                if (!hasViseme) continue;
                if (r.gameObject.activeInHierarchy && r.enabled) return r; // prefer the visible mesh
                if (fallback == null) fallback = r;
            }
            return fallback;
        }

        // ── IFaceRig ──

        public void SetViseme(Viseme v, float weight01)
        {
            if (!IsReady) return;
            if (_visemeIndex.TryGetValue(v, out int idx))
                _target[idx] = Mathf.Clamp01(weight01) * maxWeight;
        }

        public void SetMouthOpen(float amount01)
        {
            // Jaw fallback (Milestone 0): drive the open-vowel "aa" viseme.
            SetViseme(Viseme.Aa, amount01);
        }

        public void SetExpression(Expression e, float weight01)
        {
            // FACS/ARKit expression mapping (blink, brows...) lives in the AK_/SR_16+ range and
            // isn't needed for lipsync. Left as a no-op; wire specific AK_ indices later if wanted.
        }

        public void ResetMouth()
        {
            if (!IsReady) return;
            foreach (var idx in _visemeIndex.Values) _target[idx] = 0f;
        }

        void LateUpdate()
        {
            if (!IsReady || _target.Count == 0) return;

            float k = 1f - Mathf.Exp(-responsiveness * Time.deltaTime);
            foreach (var kvp in _target)
            {
                int idx = kvp.Key;
                float cur = _current.TryGetValue(idx, out var c) ? c : 0f;
                float next = Mathf.Lerp(cur, kvp.Value, k);
                _current[idx] = next;
                faceRenderer.SetBlendShapeWeight(idx, next * 100f);
            }
        }

        [ContextMenu("Log Blend Shape Names")]
        void LogBlendShapeNames()
        {
            var r = faceRenderer != null ? faceRenderer : FindFacialRenderer();
            if (r == null || r.sharedMesh == null) { Debug.LogWarning("No facial mesh found.", this); return; }
            var mesh = r.sharedMesh;
            var sb = new System.Text.StringBuilder($"[{r.name}] {mesh.blendShapeCount} blendshapes:\n");
            for (int i = 0; i < mesh.blendShapeCount; i++)
                sb.AppendLine($"  {i}: {mesh.GetBlendShapeName(i)}");
            Debug.Log(sb.ToString(), this);
        }
    }
}
