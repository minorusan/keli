using System;
using System.Collections.Generic;
using Maradel.UI;
using UnityEngine;
#if UNITY_EDITOR
using System.IO;
using UnityEditor;
#endif

namespace Maradel.Gallery
{
    /// <summary>
    /// Legacy IMGUI model browser (no Canvas). Drag onto ONE empty GameObject. Pick a folder from
    /// an OnGUI dropdown, step models with ◀/▶, scale the GUI (<see cref="_scale"/>) and the model.
    /// Loads ONE model at a time via <see cref="Resources.Load"/> by path — never LoadAll.
    ///
    /// Editor ▸ right-click ▸ <b>Scan Resources</b> groups every model under <see cref="_rootFolder"/>
    /// by its immediate subfolder (e.g. Adults / Children / Professions).
    /// </summary>
    [AddComponentMenu("Maradel/Rocketbox Gallery (OnGUI)")]
    public sealed class RocketboxGalleryGUI : MonoBehaviour
    {
        [Serializable]
        public sealed class FolderEntry
        {
            public string name;
            public List<string> paths = new(); // Resources-relative, no extension
        }

        [Tooltip("Root to browse, RELATIVE TO A Resources/ folder. Its immediate subfolders become " +
                 "the dropdown entries. e.g. Microsoft-Rocketbox-master/Assets/Avatars")]
        [SerializeField] string _rootFolder = "Microsoft-Rocketbox-master/Assets/Avatars";

        [Tooltip("Only include *_facial FBX (the ones with viseme blendshapes).")]
        [SerializeField] bool _onlyFacial = true;

        [Tooltip("Folders + their model paths (filled by 'Scan Resources').")]
        [SerializeField] List<FolderEntry> _folders = new();

        [Header("Overlay (square-viewport anchored)")]
        [Tooltip("Zooms the OnGUI overlay.")]
        [Range(0.2f, 3f)][SerializeField] float _scale = 1f;
        [Tooltip("Overlay transparency: 0 = invisible, 1 = opaque.")]
        [Range(0f, 1f)][SerializeField] float _overlayAlpha = 0.85f;
        [SerializeField] bool _verbose = false;

        [Header("Model")]
        [Tooltip("Uniform scale applied to the spawned model.")]
        [SerializeField] float _modelScale = 1f;
        [Tooltip("Optional parent for the spawned model. Defaults to this transform.")]
        [SerializeField] Transform _mount;

        int _folderIndex;
        int _itemIndex;
        GameObject _instance;
        string _lastError;

        // GUI state
        bool _folderListOpen;
        Vector2 _folderScroll;
        GUIStyle _rich;

        int TotalCount() { int n = 0; foreach (var f in _folders) n += f.paths.Count; return n; }

        FolderEntry Folder => _folderIndex >= 0 && _folderIndex < _folders.Count ? _folders[_folderIndex] : null;
        List<string> Paths => Folder != null ? Folder.paths : null;
        public string Current => Paths != null && _itemIndex >= 0 && _itemIndex < Paths.Count ? Paths[_itemIndex] : "";

        void Start()
        {
            if (_folders.Count == 0)
                Debug.LogWarning($"{nameof(RocketboxGalleryGUI)}: no folders. Right-click the component " +
                                 "▸ Scan Resources (Editor), then Play.", this);
            else
                SelectFolder(0);
        }

        // ── folder selection ──

        public void SelectFolder(int index)
        {
            if (_folders.Count == 0) return;
            _folderIndex = Wrap(index, _folders.Count);
            _itemIndex = 0;
            _folderListOpen = false;
            Show(0);
        }

        public void NextFolder() => SelectFolder(_folderIndex + 1);
        public void PrevFolder() => SelectFolder(_folderIndex - 1);

        // ── item navigation ──

        public void Next() => Show(_itemIndex + 1);
        public void Prev() => Show(_itemIndex - 1);

        void Show(int index)
        {
            if (_instance != null) Destroy(_instance);
            _lastError = null;

            var paths = Paths;
            if (paths == null || paths.Count == 0) return;

            _itemIndex = Wrap(index, paths.Count);
            var prefab = Resources.Load<GameObject>(paths[_itemIndex]);
            if (prefab == null)
            {
                _lastError = $"Resources.Load null for '{paths[_itemIndex]}'";
                Debug.LogError($"{nameof(RocketboxGalleryGUI)}: {_lastError}", this);
                return;
            }

            var parent = _mount != null ? _mount : transform;
            _instance = Instantiate(prefab, parent);
            _instance.transform.localPosition = Vector3.zero;
            _instance.transform.localRotation = Quaternion.identity;
            _instance.transform.localScale = Vector3.one * _modelScale;

            if (_verbose) Debug.Log($"[Gallery] show [{_itemIndex + 1}/{paths.Count}] {paths[_itemIndex]}", this);
        }

        // ── legacy IMGUI ──

        void OnGUI()
        {
            _rich ??= new GUIStyle(GUI.skin.label) { richText = true };
            var prev = GuiOverlay.Begin(_scale, _overlayAlpha);
            Rect sq = GuiOverlay.SquareViewport();

            // Lay out in design units (0..1000 across the square edge).
            GUILayout.BeginArea(new Rect(20, 20, 620, _folderListOpen ? 540 : 300), GUI.skin.box);

            GUILayout.Label($"<b>Rocketbox Gallery</b>   <color=#7CFC00>▶ RUNNING</color>   square {sq.width:0}px", _rich);
            GUILayout.Label($"folders: {_folders.Count}   models: {TotalCount()}", _rich);

            if (_folders.Count == 0)
            {
                GUILayout.Label("No models. Editor: right-click this component ▸ Scan Resources.");
            }
            else
            {
                // folder "dropdown"
                GUILayout.BeginHorizontal();
                if (GUILayout.Button("◀", GUILayout.Width(34), GUILayout.Height(28))) PrevFolder();
                string folderName = Folder != null ? Folder.name : "—";
                if (GUILayout.Button($"Folder: {folderName} ({_folderIndex + 1}/{_folders.Count}) {(_folderListOpen ? "▲" : "▼")}",
                        GUILayout.Height(28)))
                    _folderListOpen = !_folderListOpen;
                if (GUILayout.Button("▶", GUILayout.Width(34), GUILayout.Height(28))) NextFolder();
                GUILayout.EndHorizontal();

                if (_folderListOpen)
                {
                    _folderScroll = GUILayout.BeginScrollView(_folderScroll, GUILayout.Height(170));
                    for (int i = 0; i < _folders.Count; i++)
                    {
                        string mark = i == _folderIndex ? "• " : "   ";
                        if (GUILayout.Button($"{mark}{_folders[i].name}  ({_folders[i].paths.Count})"))
                            SelectFolder(i);
                    }
                    GUILayout.EndScrollView();
                }

                // item path
                int count = Paths != null ? Paths.Count : 0;
                GUILayout.Label(count == 0 ? "(folder empty)" : $"[{_itemIndex + 1}/{count}]  {Current}");
                if (!string.IsNullOrEmpty(_lastError))
                    GUILayout.Label($"<color=red>{_lastError}</color>");

                // item nav
                GUILayout.BeginHorizontal();
                if (GUILayout.Button("◀  Prev", GUILayout.Height(40))) Prev();
                if (GUILayout.Button("Next  ▶", GUILayout.Height(40))) Next();
                GUILayout.EndHorizontal();

                // model scale
                GUILayout.BeginHorizontal();
                GUILayout.Label($"model x{_modelScale:0.00}", GUILayout.Width(110));
                if (GUILayout.Button("–", GUILayout.Width(40), GUILayout.Height(26))) SetModelScale(_modelScale * 0.8f);
                if (GUILayout.Button("+", GUILayout.Width(40), GUILayout.Height(26))) SetModelScale(_modelScale * 1.25f);
                GUILayout.EndHorizontal();
            }

            GUILayout.EndArea();
            GuiOverlay.End(prev);
        }

        void SetModelScale(float s)
        {
            _modelScale = Mathf.Max(0.001f, s);
            if (_instance != null) _instance.transform.localScale = Vector3.one * _modelScale;
        }

        static int Wrap(int i, int n) => n <= 0 ? 0 : ((i % n) + n) % n;

#if UNITY_EDITOR
        [ContextMenu("Scan Resources")]
        void ScanResources()
        {
            var result = new List<FolderEntry>();
            string anchorRoot = null;

            foreach (var resDir in Directory.GetDirectories(Application.dataPath, "Resources",
                         SearchOption.AllDirectories))
            {
                string rootOnDisk = string.IsNullOrEmpty(_rootFolder)
                    ? resDir
                    : Path.Combine(resDir, _rootFolder.Replace('/', Path.DirectorySeparatorChar));
                if (!Directory.Exists(rootOnDisk)) continue;
                anchorRoot = resDir;

                foreach (var sub in Directory.GetDirectories(rootOnDisk))
                {
                    var entry = new FolderEntry { name = Path.GetFileName(sub) };
                    foreach (var fbx in Directory.GetFiles(sub, "*.fbx", SearchOption.AllDirectories))
                    {
                        string nameNoExt = Path.GetFileNameWithoutExtension(fbx);
                        bool isFacial = nameNoExt.EndsWith("_facial", StringComparison.OrdinalIgnoreCase);
                        if (_onlyFacial != isFacial) continue;

                        string rel = fbx.Substring(resDir.Length + 1);
                        rel = rel.Substring(0, rel.Length - ".fbx".Length).Replace('\\', '/');
                        entry.paths.Add(rel);
                    }
                    entry.paths.Sort(StringComparer.OrdinalIgnoreCase);
                    if (entry.paths.Count > 0) result.Add(entry);
                }
                break;
            }

            if (anchorRoot == null)
            {
                Debug.LogWarning($"{nameof(RocketboxGalleryGUI)}: '{_rootFolder}' not found under any " +
                                 "Resources/ folder.", this);
                return;
            }

            result.Sort((a, b) => string.Compare(a.name, b.name, StringComparison.OrdinalIgnoreCase));
            _folders = result;
            EditorUtility.SetDirty(this);
            int total = 0; foreach (var f in result) total += f.paths.Count;
            Debug.Log($"{nameof(RocketboxGalleryGUI)}: {result.Count} folders, {total} models " +
                      $"({(_onlyFacial ? "_facial only" : "non-facial")}).", this);
        }
#endif
    }
}
