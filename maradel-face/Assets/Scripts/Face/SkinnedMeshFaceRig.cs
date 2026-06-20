using System.Collections.Generic;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Generic <see cref="IFaceRig"/> for any imported model (FBX / VRM / glTF). Drives a
    /// SkinnedMeshRenderer by blendshape *name* (resolved to index once at startup via the
    /// <see cref="VisemeMap"/>), so it works with any rig whose blendshape names you put in
    /// the map. Unity blendshape weights are 0..100; the public API here is 0..1.
    ///
    /// Add this to the GameObject that has the face's SkinnedMeshRenderer (or assign the
    /// renderer explicitly), assign a VisemeMap, and it implements IFaceRig.
    /// </summary>
    [AddComponentMenu("Maradel/Skinned Mesh Face Rig")]
    public sealed class SkinnedMeshFaceRig : MonoBehaviour, IFaceRig
    {
        [Tooltip("Face renderer. If null, the first SkinnedMeshRenderer with blendshapes in " +
                 "children is used.")]
        [SerializeField] SkinnedMeshRenderer faceRenderer;

        [SerializeField] VisemeMap visemeMap;

        [Header("Smoothing")]
        [Tooltip("Higher = snappier mouth, lower = smoother. Per-second lerp speed toward target.")]
        [Range(1f, 40f)][SerializeField] float responsiveness = 18f;

        // blendshape name -> index on the renderer
        readonly Dictionary<string, int> _index = new();
        // index -> current / target weight (0..1)
        readonly Dictionary<int, float> _current = new();
        readonly Dictionary<int, float> _target = new();

        public bool IsReady { get; private set; }

        void Awake()
        {
            if (faceRenderer == null)
                faceRenderer = FindRendererWithBlendShapes();

            if (faceRenderer == null || faceRenderer.sharedMesh == null)
            {
                Debug.LogError($"{nameof(SkinnedMeshFaceRig)}: no SkinnedMeshRenderer with " +
                               "blendshapes found.", this);
                return;
            }
            if (visemeMap == null)
            {
                Debug.LogError($"{nameof(SkinnedMeshFaceRig)}: VisemeMap not assigned.", this);
                return;
            }

            var mesh = faceRenderer.sharedMesh;
            for (int i = 0; i < mesh.blendShapeCount; i++)
                _index[mesh.GetBlendShapeName(i)] = i;

            IsReady = true;
        }

        SkinnedMeshRenderer FindRendererWithBlendShapes()
        {
            foreach (var r in GetComponentsInChildren<SkinnedMeshRenderer>(true))
                if (r.sharedMesh != null && r.sharedMesh.blendShapeCount > 0) return r;
            return null;
        }

        // ── IFaceRig ──

        public void SetViseme(Viseme v, float weight01)
        {
            if (!IsReady) return;
            float w = Mathf.Clamp01(weight01) * visemeMap.Gain(v); // gain cap from the map
            foreach (var name in visemeMap.BlendShapesFor(v))
                SetTargetByName(name, w);
        }

        public void SetMouthOpen(float amount01)
        {
            if (!IsReady) return;
            float w = Mathf.Clamp01(amount01) * visemeMap.MouthOpenMax;
            foreach (var name in visemeMap.MouthOpenBlendShapes)
                SetTargetByName(name, w);
        }

        public void SetExpression(Expression e, float weight01)
        {
            if (!IsReady) return;
            float w = Mathf.Clamp01(weight01) * visemeMap.Gain(e);
            foreach (var name in visemeMap.BlendShapesFor(e))
                SetTargetByName(name, w);
        }

        public void ResetMouth()
        {
            if (!IsReady) return;
            foreach (var v in visemeMap.MappedVisemes())
                foreach (var name in visemeMap.BlendShapesFor(v))
                    SetTargetByName(name, 0f);
            foreach (var name in visemeMap.MouthOpenBlendShapes)
                SetTargetByName(name, 0f);
        }

        void SetTargetByName(string blendShapeName, float weight01)
        {
            if (_index.TryGetValue(blendShapeName, out int idx))
                _target[idx] = weight01;
            // Unmapped name -> silently ignored so a partial map still runs.
        }

        /// <summary>
        /// Right-click the component > "Log Blend Shape Names" to print every blendshape on
        /// the model. Use these exact names to fill the VisemeMap (e.g. for Rocketbox / VRM /
        /// ARKit rigs, whose naming differs).
        /// </summary>
        [ContextMenu("Log Blend Shape Names")]
        void LogBlendShapeNames()
        {
            var r = faceRenderer != null ? faceRenderer : FindRendererWithBlendShapes();
            if (r == null || r.sharedMesh == null) { Debug.LogWarning("No mesh with blendshapes.", this); return; }
            var mesh = r.sharedMesh;
            var sb = new System.Text.StringBuilder($"[{r.name}] {mesh.blendShapeCount} blendshapes:\n");
            for (int i = 0; i < mesh.blendShapeCount; i++)
                sb.AppendLine($"  {i}: {mesh.GetBlendShapeName(i)}");
            Debug.Log(sb.ToString(), this);
        }

        void LateUpdate()
        {
            if (!IsReady || _target.Count == 0) return;

            float k = 1f - Mathf.Exp(-responsiveness * Time.deltaTime); // frame-rate-independent lerp
            // iterate over a snapshot of keys so we can mutate _current
            foreach (var kvp in _target)
            {
                int idx = kvp.Key;
                float cur = _current.TryGetValue(idx, out var c) ? c : 0f;
                float next = Mathf.Lerp(cur, kvp.Value, k);
                _current[idx] = next;
                faceRenderer.SetBlendShapeWeight(idx, next * 100f); // 0..1 -> Unity 0..100
            }
        }
    }
}
