using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

/// <summary>
/// Editor tool: <b>Maradel ▸ Gallery</b>. For every Rocketbox <c>*_facial</c> avatar it spins up an
/// isolated capture rig (off-screen camera + 3-point lights on a private layer), frames the FACE and
/// saves <c>AVATAR.png</c> next to the model, then frames the BODY and saves <c>Body.png</c>, then
/// moves to the next model. Transparent background; built-in render pipeline.
///
/// Framing mirrors <see cref="Maradel.Speech.RocketboxAutoRig"/>'s calibrated face/body offsets so the
/// thumbnails match what the app shows. Progress is logged per model (and shown in a progress bar).
/// </summary>
public static class GalleryCapture
{
    const string ModelsRoot = "Assets/App/Content/Models";
    const int Size = 768;                 // square thumbnail resolution
    const int CaptureLayer = 31;          // private layer so the open scene never leaks into the shot

    // Calibrated framing (copied from RocketboxAutoRig defaults).
    static readonly Vector3 FaceEuler = new(0f, 180f, 0f);          // face the avatar at the camera
    static readonly Vector3 FaceOffset = new(0f, 0.076f, -2.22f);   // camera vs head bone — FACE
    const float FaceFov = 16f;
    static readonly Vector3 BodyOffset = new(0f, -0.43f, -2.22f);   // camera vs head bone — BODY
    const float BodyFov = 39f;
    const string AnchorBone = "Bip01 Head";

    [MenuItem("Maradel/Gallery/Capture Avatar + Body Photos (all models)")]
    public static void CaptureAll()
    {
        var paths = AssetDatabase.FindAssets("_facial t:Model", new[] { ModelsRoot })
            .Select(AssetDatabase.GUIDToAssetPath)
            .Where(p => Path.GetFileNameWithoutExtension(p).EndsWith("_facial", System.StringComparison.OrdinalIgnoreCase))
            .Distinct()
            .OrderBy(p => p, System.StringComparer.OrdinalIgnoreCase)
            .ToList();

        if (paths.Count == 0) { Debug.LogError($"[GALLERY] no *_facial models under {ModelsRoot}"); return; }
        Capture(paths);
    }

    [MenuItem("Maradel/Gallery/Capture Selected Model only")]
    public static void CaptureSelected()
    {
        var sel = Selection.activeObject;
        var path = sel != null ? AssetDatabase.GetAssetPath(sel) : null;
        if (string.IsNullOrEmpty(path) || !Path.GetFileNameWithoutExtension(path).EndsWith("_facial", System.StringComparison.OrdinalIgnoreCase))
        {
            Debug.LogError("[GALLERY] select a *_facial avatar model in the Project window first.");
            return;
        }
        Capture(new System.Collections.Generic.List<string> { path });
    }

    static void Capture(System.Collections.Generic.List<string> paths)
    {
        Debug.Log($"[GALLERY] capturing {paths.Count} avatar(s) → AVATAR.png + Body.png (beside each model)…");

        // Save/restore ambient so we don't permanently alter the open scene's lighting.
        var prevAmbMode = RenderSettings.ambientMode;
        var prevAmbLight = RenderSettings.ambientLight;
        RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
        RenderSettings.ambientLight = new Color(0.18f, 0.20f, 0.25f);

        var rig = new Rig();
        int done = 0, fail = 0;
        try
        {
            for (int i = 0; i < paths.Count; i++)
            {
                var path = paths[i];
                var name = Path.GetFileNameWithoutExtension(path);
                var dir = Path.GetDirectoryName(path);
                EditorUtility.DisplayProgressBar("Maradel Gallery", $"[{i + 1}/{paths.Count}] {name}", (i + 1f) / paths.Count);

                var prefab = AssetDatabase.LoadAssetAtPath<GameObject>(path);
                if (prefab == null) { Debug.LogWarning($"[GALLERY] {i + 1}/{paths.Count} '{name}' — could not load model"); fail++; continue; }

                var inst = (GameObject)PrefabUtility.InstantiatePrefab(prefab, rig.Root.transform);
                inst.transform.localPosition = Vector3.zero;
                inst.transform.rotation = Quaternion.Euler(FaceEuler);
                inst.transform.localScale = Vector3.one;
                SetLayerRecursive(inst.transform, CaptureLayer);

                var head = FindDeep(inst.transform, AnchorBone);
                var anchor = head != null ? head.position : inst.transform.position + Vector3.up * 1.55f;
                if (head == null) Debug.LogWarning($"[GALLERY] '{name}' — no '{AnchorBone}' bone, using fallback anchor");
                rig.AimLights(anchor);

                var facePng = Path.Combine(dir, "AVATAR.png");
                var bodyPng = Path.Combine(dir, "Body.png");
                rig.Shoot(anchor + FaceOffset, FaceFov, facePng);
                rig.Shoot(anchor + BodyOffset, BodyFov, bodyPng);

                Object.DestroyImmediate(inst);
                done++;
                Debug.Log($"[GALLERY] {i + 1}/{paths.Count} '{name}' ✓ → {facePng} + {bodyPng}");
            }
        }
        finally
        {
            rig.Dispose();
            RenderSettings.ambientMode = prevAmbMode;
            RenderSettings.ambientLight = prevAmbLight;
            EditorUtility.ClearProgressBar();
            AssetDatabase.Refresh();
        }
        Debug.Log($"[GALLERY] DONE — {done} captured, {fail} failed. PNGs saved beside each model (run again to refresh).");
    }

    static void SetLayerRecursive(Transform t, int layer)
    {
        t.gameObject.layer = layer;
        for (int i = 0; i < t.childCount; i++) SetLayerRecursive(t.GetChild(i), layer);
    }

    static Transform FindDeep(Transform root, string name)
    {
        if (root.name == name) return root;
        for (int i = 0; i < root.childCount; i++)
        {
            var r = FindDeep(root.GetChild(i), name);
            if (r != null) return r;
        }
        return null;
    }

    /// <summary>Isolated, off-screen render rig: a camera + 3-point lights, all confined to a private
    /// layer so nothing in the open scene appears in (or lights) the shot.</summary>
    sealed class Rig
    {
        public readonly GameObject Root;
        readonly Camera _cam;
        readonly Light _key, _fill, _rim;

        public Rig()
        {
            Root = new GameObject("~GalleryRig") { hideFlags = HideFlags.HideAndDontSave };

            var camGo = new GameObject("GalleryCam") { hideFlags = HideFlags.HideAndDontSave };
            camGo.transform.SetParent(Root.transform, false);
            _cam = camGo.AddComponent<Camera>();
            _cam.clearFlags = CameraClearFlags.SolidColor;
            _cam.backgroundColor = new Color(0f, 0f, 0f, 0f); // transparent thumbnail background
            _cam.cullingMask = 1 << CaptureLayer;
            _cam.allowMSAA = true;
            _cam.nearClipPlane = 0.01f;
            _cam.farClipPlane = 50f;
            _cam.enabled = false; // we drive it manually with Render()

            _key = MakeLight("Key", new Color(1.00f, 0.96f, 0.88f), 1.15f);
            _fill = MakeLight("Fill", new Color(0.82f, 0.87f, 1.00f), 0.55f);
            _rim = MakeLight("Rim", new Color(0.90f, 0.95f, 1.00f), 0.95f);
        }

        Light MakeLight(string n, Color c, float intensity)
        {
            var go = new GameObject("Light_" + n) { hideFlags = HideFlags.HideAndDontSave };
            go.transform.SetParent(Root.transform, false);
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional;
            l.color = c;
            l.intensity = intensity;
            l.shadows = LightShadows.None;
            l.cullingMask = 1 << CaptureLayer;
            l.renderMode = LightRenderMode.ForcePixel;
            return l;
        }

        public void AimLights(Vector3 head)
        {
            Aim(_key, head + new Vector3(-0.7f, 0.9f, -1.4f), head);
            Aim(_fill, head + new Vector3(1.1f, 0.25f, -1.1f), head);
            Aim(_rim, head + new Vector3(0.25f, 1.1f, 1.6f), head);
        }

        static void Aim(Light l, Vector3 from, Vector3 target)
        {
            l.transform.position = from;
            l.transform.LookAt(target);
        }

        public void Shoot(Vector3 camPos, float fov, string pngPath)
        {
            _cam.transform.position = camPos;
            _cam.transform.rotation = Quaternion.identity; // avatar faces -Z (rotated 180); cam looks +Z at it
            _cam.fieldOfView = fov;

            var rt = new RenderTexture(Size, Size, 24, RenderTextureFormat.ARGB32) { antiAliasing = 4 };
            var prevActive = RenderTexture.active;
            _cam.targetTexture = rt;
            _cam.Render();

            RenderTexture.active = rt;
            var tex = new Texture2D(Size, Size, TextureFormat.RGBA32, false);
            tex.ReadPixels(new Rect(0, 0, Size, Size), 0, 0);
            tex.Apply();

            _cam.targetTexture = null;
            RenderTexture.active = prevActive;

            File.WriteAllBytes(pngPath, tex.EncodeToPNG());
            Object.DestroyImmediate(tex);
            rt.Release();
            Object.DestroyImmediate(rt);
        }

        public void Dispose() => Object.DestroyImmediate(Root);
    }
}
