using UnityEngine;

namespace Maradel.UI
{
    /// <summary>
    /// Helpers for IMGUI overlays anchored to the **square viewport**. The Maradel face renders
    /// on a square stage, so the screen's usable area is the largest centred square — not the full
    /// (possibly letterboxed/widescreen) window. These map "design units" (0..<see cref="ReferenceSize"/>
    /// across the square edge) to screen pixels, so an overlay sits in the same place and keeps the
    /// same proportions regardless of the actual window aspect. Transparency is a 0..1 alpha.
    /// </summary>
    public static class GuiOverlay
    {
        /// <summary>Design-unit span across one edge of the square viewport.</summary>
        public const float ReferenceSize = 1000f;

        /// <summary>Largest centred square that fits the current screen.</summary>
        public static Rect SquareViewport()
        {
            float side = Mathf.Min(Screen.width, Screen.height);
            return new Rect((Screen.width - side) * 0.5f, (Screen.height - side) * 0.5f, side, side);
        }

        /// <summary>
        /// Begin an overlay. After this, lay out in design units (0..ReferenceSize across the
        /// square). <paramref name="scale"/> zooms the overlay; <paramref name="alpha"/> fades it.
        /// Returns the previous GUI matrix+color to restore with <see cref="End"/>.
        /// </summary>
        public static (Matrix4x4 matrix, Color color) Begin(float scale, float alpha)
        {
            var prev = (GUI.matrix, GUI.color);
            Rect sq = SquareViewport();
            float unit = sq.width / ReferenceSize * Mathf.Max(0.01f, scale);

            Color c = GUI.color;
            GUI.color = new Color(c.r, c.g, c.b, Mathf.Clamp01(alpha));
            GUI.matrix = Matrix4x4.TRS(new Vector3(sq.x, sq.y, 0f), Quaternion.identity,
                new Vector3(unit, unit, 1f));
            return prev;
        }

        public static void End((Matrix4x4 matrix, Color color) prev)
        {
            GUI.matrix = prev.matrix;
            GUI.color = prev.color;
        }

        // ── shared, persistent overlay scale (one value for every OnGUI overlay) ──
        const string ScaleKey = "maradel.guiScale";
        static float _scale = -1f;

        /// <summary>Common GUI scale, persisted in PlayerPrefs and shared by all overlays.</summary>
        public static float Scale
        {
            get { if (_scale < 0f) _scale = PlayerPrefs.GetFloat(ScaleKey, 1.34f); return _scale; }
            set { _scale = Mathf.Clamp(value, 0.3f, 3f); PlayerPrefs.SetFloat(ScaleKey, _scale); PlayerPrefs.Save(); }
        }

        /// <summary>Begin using the shared persistent <see cref="Scale"/>.</summary>
        public static (Matrix4x4 matrix, Color color) Begin(float alpha) => Begin(Scale, alpha);

        static GUIStyle _scaleBtnStyle;

        /// <summary>Draw the common "GUI x1.34 [−][+]" UI-scale control that adjusts the shared
        /// persistent scale. Buttons are large/tappable (for the wall tablet); pass
        /// <paramref name="centered"/> to center the whole control horizontally in its row.</summary>
        public static void ScaleControls(GUIStyle labelStyle = null, bool centered = false)
        {
            _scaleBtnStyle ??= new GUIStyle(GUI.skin.button) { fontSize = 26, fontStyle = FontStyle.Bold };
            var label = labelStyle ?? GUI.skin.label;

            if (centered) { GUILayout.BeginHorizontal(); GUILayout.FlexibleSpace(); }
            GUILayout.Label($"GUI x{Scale:0.00}", label, GUILayout.Width(96), GUILayout.Height(52));
            if (GUILayout.Button("−", _scaleBtnStyle, GUILayout.Width(96), GUILayout.Height(52))) Scale -= 0.1f;
            GUILayout.Space(8);
            if (GUILayout.Button("+", _scaleBtnStyle, GUILayout.Width(96), GUILayout.Height(52))) Scale += 0.1f;
            if (centered) { GUILayout.FlexibleSpace(); GUILayout.EndHorizontal(); }
        }

        // ── common IMGUI progress bar (e.g. Addressables loading) ──
        static Texture2D _bg, _fill;
        static Texture2D Solid(Color c)
        {
            var t = new Texture2D(1, 1) { hideFlags = HideFlags.HideAndDontSave };
            t.SetPixel(0, 0, c); t.Apply();
            return t;
        }

        /// <summary>A labelled filled progress bar laid out in the current GUILayout flow (0..1).</summary>
        public static void ProgressBar(string label, float value01, float height = 26f)
        {
            value01 = Mathf.Clamp01(value01);
            if (_bg == null) _bg = Solid(new Color(0f, 0f, 0f, 0.45f));
            if (_fill == null) _fill = Solid(new Color(0f, 0.78f, 1f, 0.9f)); // cyan

            Rect r = GUILayoutUtility.GetRect(60f, height, GUILayout.ExpandWidth(true));
            Color prev = GUI.color;
            GUI.color = Color.white;
            GUI.DrawTexture(r, _bg, ScaleMode.StretchToFill);
            GUI.DrawTexture(new Rect(r.x, r.y, r.width * value01, r.height), _fill, ScaleMode.StretchToFill);
            GUI.color = prev;

            var s = new GUIStyle(GUI.skin.label) { alignment = TextAnchor.MiddleCenter, richText = true };
            GUI.Label(r, $"{label}  {value01 * 100f:0}%", s);
        }
    }
}
