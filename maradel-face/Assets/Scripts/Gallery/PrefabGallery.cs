using System.Collections.Generic;
using TMPro;
using UnityEngine;
using UnityEngine.UI;
#if UNITY_EDITOR
using System.IO;
using UnityEditor;
#endif

namespace Maradel.Gallery
{
    /// <summary>
    /// Browses prefabs stored under a <c>Resources/</c> folder and shows them on a stage.
    ///
    /// Layout it expects (all references wired in the Inspector):
    ///   - a <b>stage mount</b> Transform where the current prefab is instantiated,
    ///   - an optional <b>panel</b> MeshRenderer backdrop,
    ///   - a <b>scale Slider</b> (0..100) + a TMP label,
    ///   - <b>Left/Right</b> buttons to cycle items within the current folder,
    ///   - <b>Folder Prev/Next</b> buttons + a TMP folder label.
    ///
    /// Resources can't enumerate subfolders at runtime, so the folder list is serialized.
    /// Right-click the component ▸ <b>Scan Resources Folders</b> (Editor) to fill it from disk
    /// once the import lands.
    /// </summary>
    [AddComponentMenu("Maradel/Prefab Gallery")]
    public sealed class PrefabGallery : MonoBehaviour
    {
        [Header("Resources source")]
        [Tooltip("Path under a Resources/ folder, e.g. \"Gallery\". Subfolders below are the " +
                 "navigable folders. Leave empty to use the Resources root directly.")]
        [SerializeField] string resourcesRoot = "Gallery";

        [Tooltip("Subfolder names under resourcesRoot. Use 'Scan Resources Folders' to fill.")]
        [SerializeField] List<string> folders = new();

        [Header("Display")]
        [Tooltip("Parent transform for the instantiated prefab. Defaults to this transform.")]
        [SerializeField] Transform stageMount;
        [Tooltip("Optional backdrop panel (the 'panel with MeshRenderer').")]
        [SerializeField] MeshRenderer panelRenderer;
        [SerializeField] bool resetTransformOnShow = true;

        [Header("Scale (slider 0..100)")]
        [SerializeField] Slider scaleSlider;
        [SerializeField] TMP_Text scaleLabel;
        [Tooltip("Slider 0 maps to this world scale.")]
        [SerializeField] float minScale = 0.1f;
        [Tooltip("Slider 100 maps to this world scale.")]
        [SerializeField] float maxScale = 2f;
        [Range(0f, 100f)][SerializeField] float defaultScale = 50f;

        [Header("Item navigation")]
        [SerializeField] Button leftButton;
        [SerializeField] Button rightButton;
        [SerializeField] TMP_Text itemLabel;

        [Header("Folder navigation")]
        [SerializeField] Button folderPrevButton;
        [SerializeField] Button folderNextButton;
        [SerializeField] TMP_Text folderLabel;

        // runtime
        GameObject[] _items = System.Array.Empty<GameObject>();
        int _folderIndex;
        int _itemIndex;
        GameObject _instance;

        public string CurrentFolder => InRange(_folderIndex, folders.Count) ? folders[_folderIndex] : string.Empty;
        public GameObject CurrentInstance => _instance;

        void OnEnable()
        {
            if (leftButton) leftButton.onClick.AddListener(Previous);
            if (rightButton) rightButton.onClick.AddListener(Next);
            if (folderPrevButton) folderPrevButton.onClick.AddListener(PreviousFolder);
            if (folderNextButton) folderNextButton.onClick.AddListener(NextFolder);
            if (scaleSlider) scaleSlider.onValueChanged.AddListener(OnScaleChanged);
        }

        void OnDisable()
        {
            if (leftButton) leftButton.onClick.RemoveListener(Previous);
            if (rightButton) rightButton.onClick.RemoveListener(Next);
            if (folderPrevButton) folderPrevButton.onClick.RemoveListener(PreviousFolder);
            if (folderNextButton) folderNextButton.onClick.RemoveListener(NextFolder);
            if (scaleSlider) scaleSlider.onValueChanged.RemoveListener(OnScaleChanged);
        }

        void Start()
        {
            if (scaleSlider)
            {
                scaleSlider.minValue = 0f;
                scaleSlider.maxValue = 100f;
                scaleSlider.value = defaultScale;
            }
            LoadFolder(0);
        }

        // ── folder navigation ──

        public void NextFolder() => LoadFolder(_folderIndex + 1);
        public void PreviousFolder() => LoadFolder(_folderIndex - 1);

        public void LoadFolder(int index)
        {
            if (folders.Count == 0)
            {
                Debug.LogWarning($"{nameof(PrefabGallery)}: no folders configured. Run " +
                                 "'Scan Resources Folders' or add folder names.", this);
                _items = System.Array.Empty<GameObject>();
                UpdateFolderLabel();
                ShowItem(0);
                return;
            }

            _folderIndex = Wrap(index, folders.Count);
            string path = string.IsNullOrEmpty(resourcesRoot)
                ? folders[_folderIndex]
                : $"{resourcesRoot}/{folders[_folderIndex]}";

            _items = Resources.LoadAll<GameObject>(path) ?? System.Array.Empty<GameObject>();
            if (_items.Length == 0)
                Debug.LogWarning($"{nameof(PrefabGallery)}: no prefabs found at Resources/{path}.", this);

            UpdateFolderLabel();
            _itemIndex = 0;
            ShowItem(0);
        }

        // ── item navigation ──

        public void Next() => ShowItem(_itemIndex + 1);
        public void Previous() => ShowItem(_itemIndex - 1);

        void ShowItem(int index)
        {
            if (_instance != null) Destroy(_instance);

            if (_items.Length == 0)
            {
                UpdateItemLabel();
                return;
            }

            _itemIndex = Wrap(index, _items.Length);
            var parent = stageMount != null ? stageMount : transform;
            _instance = Instantiate(_items[_itemIndex], parent);

            if (resetTransformOnShow)
            {
                _instance.transform.localPosition = Vector3.zero;
                _instance.transform.localRotation = Quaternion.identity;
            }

            ApplyScale();
            UpdateItemLabel();
        }

        // ── scale ──

        void OnScaleChanged(float _) => ApplyScale();

        /// <summary>Map slider 0..100 to minScale..maxScale and apply to the current instance.</summary>
        public void ApplyScale()
        {
            float sliderValue = scaleSlider != null ? scaleSlider.value : defaultScale;
            float t = Mathf.Clamp01(sliderValue / 100f);
            float s = Mathf.Lerp(minScale, maxScale, t);

            if (_instance != null)
                _instance.transform.localScale = Vector3.one * s;

            if (scaleLabel != null)
                scaleLabel.text = Mathf.RoundToInt(sliderValue).ToString();
        }

        // ── labels ──

        void UpdateFolderLabel()
        {
            if (folderLabel == null) return;
            folderLabel.text = folders.Count == 0
                ? (string.IsNullOrEmpty(resourcesRoot) ? "<root>" : resourcesRoot)
                : $"{CurrentFolder}  ({_folderIndex + 1}/{folders.Count})";
        }

        void UpdateItemLabel()
        {
            if (itemLabel == null) return;
            itemLabel.text = _items.Length == 0
                ? "—"
                : $"{_items[_itemIndex].name}  ({_itemIndex + 1}/{_items.Length})";
        }

        static int Wrap(int i, int n) => n <= 0 ? 0 : ((i % n) + n) % n;
        static bool InRange(int i, int n) => i >= 0 && i < n;

#if UNITY_EDITOR
        /// <summary>
        /// Editor helper: scans the on-disk Resources/&lt;resourcesRoot&gt; folder and fills the
        /// <see cref="folders"/> list with its immediate subfolders. Right-click the component.
        /// </summary>
        [ContextMenu("Scan Resources Folders")]
        void ScanResourcesFolders()
        {
            string dataPath = Application.dataPath; // .../Assets
            string[] resourceDirs = Directory.GetDirectories(dataPath, "Resources", SearchOption.AllDirectories);

            var found = new List<string>();
            string matchedRoot = null;

            foreach (var resDir in resourceDirs)
            {
                string candidate = string.IsNullOrEmpty(resourcesRoot)
                    ? resDir
                    : Path.Combine(resDir, resourcesRoot.Replace('/', Path.DirectorySeparatorChar));

                if (!Directory.Exists(candidate)) continue;

                matchedRoot = candidate;
                foreach (var sub in Directory.GetDirectories(candidate))
                    found.Add(Path.GetFileName(sub));
                break; // first matching Resources root wins
            }

            if (matchedRoot == null)
            {
                Debug.LogWarning($"{nameof(PrefabGallery)}: no 'Resources/{resourcesRoot}' folder " +
                                 "found under Assets yet. Import the prefabs first, then re-scan.", this);
                return;
            }

            if (found.Count == 0)
                Debug.Log($"{nameof(PrefabGallery)}: '{matchedRoot}' has no subfolders — prefabs " +
                          "may sit directly in the root. Leaving the folder list empty loads the root.", this);

            found.Sort(System.StringComparer.OrdinalIgnoreCase);
            folders = found;
            EditorUtility.SetDirty(this);
            Debug.Log($"{nameof(PrefabGallery)}: scanned '{matchedRoot}', found {found.Count} folder(s).", this);
        }
#endif
    }
}
