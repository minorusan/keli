using System;
using System.Collections.Generic;
using System.IO;
using UnityEngine;

namespace Maradel.Content
{
    /// <summary>
    /// One hand-framed camera snapshot for an avatar — the raw geometry we'll later fit into an
    /// autozoom formula (frame the head bone at screen-centre at a consistent apparent size).
    /// </summary>
    [Serializable]
    public class CameraSnapshot
    {
        public string avatar;          // e.g. Female_Adult_01_facial
        public string kind;            // "face" (head close-up) or "body" (full-body framing)
        public float modelScale;       // RocketboxAutoRig.modelScale at capture
        public float characterHeight;  // world AABB height of the facial mesh (the "size" metric)
        public float headHeightAboveFloor; // LONG leg: head bone Y − avatar base Y (head-to-floor)
        public float fov;              // camera vertical FOV
        public float camDistance;      // SHORT leg / hypotenuse-ish: |camera − headBone|
        public Vector3 headWorldPos;   // Bip01 Head world position
        public Vector3 camPos;         // camera world position
        public Vector3 camEuler;       // camera world rotation (euler)
        public Vector2 headViewport;   // head bone in viewport coords (0.5,0.5 = dead centre)
    }

    /// <summary>Persisted list of <see cref="CameraSnapshot"/>. JSON on disk; editable + inspectable.</summary>
    [Serializable]
    public class CameraCalibration
    {
        public List<CameraSnapshot> snapshots = new();

        public static string FilePath()
        {
#if UNITY_EDITOR
            return Path.Combine(Application.dataPath, "App/Content/CameraCalibration.json");
#else
            return Path.Combine(Application.persistentDataPath, "CameraCalibration.json");
#endif
        }

        public static CameraCalibration Load()
        {
            string p = FilePath();
            if (File.Exists(p))
            {
                try
                {
                    var c = JsonUtility.FromJson<CameraCalibration>(File.ReadAllText(p));
                    if (c != null) return c;
                }
                catch (Exception e) { Debug.LogWarning($"[CALIB] load failed: {e.Message}"); }
            }
            return new CameraCalibration();
        }

        public void Save()
        {
            string p = FilePath();
            try
            {
                File.WriteAllText(p, JsonUtility.ToJson(this, true));
#if UNITY_EDITOR
                UnityEditor.AssetDatabase.Refresh();
#endif
                Debug.Log($"[CALIB] saved {snapshots.Count} snapshot(s) → {p}");
            }
            catch (Exception e) { Debug.LogError($"[CALIB] save failed: {e.Message}"); }
        }
    }
}
