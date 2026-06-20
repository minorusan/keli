#if ADDRESSABLES
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEditor.AddressableAssets;
using UnityEditor.AddressableAssets.Settings;
using UnityEditor.AddressableAssets.Settings.GroupSchemas;
using UnityEngine;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// Marks every Rocketbox *_facial model under Content/Models as an Addressable:
    ///   - one GROUP per category directory (Adults / Children / Professions …),
    ///   - each group set to PACK SEPARATELY (one bundle per avatar → per-avatar on-demand download),
    ///   - address = the file name (e.g. "Female_Adult_01_facial"),
    ///   - label "avatar" on all; label "essential" on the first N (BuildConfig.essentialCount),
    ///   - group build/load paths pointed at the REMOTE profile vars.
    /// Menu: Maradel ▸ Addressables ▸ 1. Mark Models Addressable.
    /// </summary>
    public static class AddressableModelSetup
    {
        const string ModelsRoot = "Assets/App/Content/Models";

        /// <summary>Auto-create the addressable groups once after the package + define are in place,
        /// so you don't have to click the menu. Re-runs only until our groups exist.</summary>
        [InitializeOnLoadMethod]
        static void AutoSetupOnce()
        {
            EditorApplication.delayCall += () =>
            {
                var settings = AddressableAssetSettingsDefaultObject.Settings;
                bool haveOurGroups = settings != null &&
                                     settings.groups.Exists(g => g != null && g.Name.StartsWith("Models_"));
                if (haveOurGroups) return;
                if (AssetDatabase.FindAssets("_facial t:Model", new[] { ModelsRoot }).Length == 0) return;

                Debug.Log("[CONTENT] auto-running 'Mark Models Addressable' (first-time setup)…");
                MarkModels();
            };
        }

        [MenuItem("Maradel/Addressables/1. Mark Models Addressable")]
        public static void MarkModels()
        {
            var settings = AddressableAssetSettingsDefaultObject.GetSettings(true);
            if (settings == null) { Debug.LogError("[CONTENT] could not get/create AddressableAssetSettings."); return; }

            var cfg = FindBuildConfig();
            string avatarLabel = cfg ? cfg.avatarLabel : "avatar";
            string essentialLabel = cfg ? cfg.essentialLabel : "essential";
            int essentialCount = cfg ? cfg.essentialCount : 1;

            settings.AddLabel(avatarLabel);
            settings.AddLabel(essentialLabel);

            var guids = AssetDatabase.FindAssets("_facial t:Model", new[] { ModelsRoot });
            // deterministic order for stable "essential" selection
            var paths = guids.Select(AssetDatabase.GUIDToAssetPath)
                             .Where(p => Path.GetFileNameWithoutExtension(p).EndsWith("_facial", System.StringComparison.OrdinalIgnoreCase))
                             .OrderBy(p => p, System.StringComparer.OrdinalIgnoreCase)
                             .ToList();

            if (paths.Count == 0) { Debug.LogError($"[CONTENT] no *_facial models under {ModelsRoot}."); return; }

            int marked = 0, essentials = 0;
            foreach (var path in paths)
            {
                string groupName = CategoryOf(path);                 // "Adults" / "Children" / "Professions"
                var group = GetOrCreateRemoteGroup(settings, groupName);

                string guid = AssetDatabase.AssetPathToGUID(path);
                var entry = settings.CreateOrMoveEntry(guid, group, readOnly: false, postEvent: false);
                entry.address = Path.GetFileNameWithoutExtension(path);
                entry.SetLabel(avatarLabel, true, false);
                if (essentials < essentialCount) { entry.SetLabel(essentialLabel, true, false); essentials++; }
                marked++;
            }

            settings.SetDirty(AddressableAssetSettings.ModificationEvent.BatchModification, null, true, true);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CONTENT] marked {marked} avatars across category groups (pack-separately, remote); " +
                      $"{essentials} tagged '{essentialLabel}'. Labels: '{avatarLabel}','{essentialLabel}'.");
        }

        static string CategoryOf(string assetPath)
        {
            // .../Avatars/<Category>/<Name>/Export/<file>.fbx  → <Category>
            var exportDir = Path.GetDirectoryName(assetPath);       // .../<Name>/Export
            var nameDir = Path.GetDirectoryName(exportDir);         // .../<Name>
            var catDir = Path.GetDirectoryName(nameDir);            // .../<Category>
            string cat = catDir != null ? Path.GetFileName(catDir) : "Misc";
            return $"Models_{cat}";
        }

        static AddressableAssetGroup GetOrCreateRemoteGroup(AddressableAssetSettings settings, string name)
        {
            var group = settings.FindGroup(name);
            if (group == null)
                group = settings.CreateGroup(name, false, false, false, null,
                    typeof(BundledAssetGroupSchema), typeof(ContentUpdateGroupSchema));

            var schema = group.GetSchema<BundledAssetGroupSchema>();
            schema.BundleMode = BundledAssetGroupSchema.BundlePackingMode.PackSeparately; // one bundle per avatar
            schema.IncludeInBuild = true;
            // point at the REMOTE profile variables (the build script sets their values)
            schema.BuildPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteBuildPath);
            schema.LoadPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteLoadPath);
            return group;
        }

        static BuildConfig FindBuildConfig()
        {
            var guid = AssetDatabase.FindAssets("t:BuildConfig").FirstOrDefault();
            if (guid == null) { Debug.LogWarning("[CONTENT] no BuildConfig asset found — using defaults. Create one via Assets ▸ Create ▸ Maradel ▸ Build Config."); return null; }
            return AssetDatabase.LoadAssetAtPath<BuildConfig>(AssetDatabase.GUIDToAssetPath(guid));
        }
    }
}
#endif
