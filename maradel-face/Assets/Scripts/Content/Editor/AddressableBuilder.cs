#if ADDRESSABLES
using System.Linq;
using UnityEditor;
using UnityEditor.AddressableAssets;
using UnityEditor.AddressableAssets.Build;
using UnityEditor.AddressableAssets.Settings;
using UnityEditor.AddressableAssets.Settings.GroupSchemas;
using UnityEngine;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// Remote content build driven by <see cref="BuildConfig"/>:
    ///   1. write remote load/build paths into the active Addressables profile,
    ///   2. force every group remote + include-in-build (each group keeps its own packing mode),
    ///   3. stamp the player version, then BuildPlayerContent().
    /// Output lands at BuildConfig.remoteBuildPath — upload that to the server at remoteLoadPath.
    /// Menu: Maradel ▸ Addressables ▸ 2. Build Remote (from BuildConfig).
    /// </summary>
    public static class AddressableBuilder
    {
        [MenuItem("Maradel/Addressables/2. Build Remote (from BuildConfig)")]
        public static void BuildRemote()
        {
            var cfg = FindBuildConfig();
            if (cfg == null) { Debug.LogError("[CONTENT] no BuildConfig asset — create one (Assets ▸ Create ▸ Maradel ▸ Build Config)."); return; }
            var result = BuildContent(cfg);
            if (result == null) return;
            if (!string.IsNullOrEmpty(result.Error))
                Debug.LogError($"[CONTENT] BUILD FAILED: {result.Error}");
            else
                Debug.Log($"[CONTENT] BUILD OK in {result.Duration:0.0}s → '{cfg.remoteBuildPath}'. " +
                          $"Upload that folder to '{cfg.remoteLoadPath}'. version={cfg.contentVersion}");
        }

        /// <summary>Configure the active profile + all groups for REMOTE pack-separately, then build
        /// the content (remote catalog on, version stamped). Reusable by the full pipeline.</summary>
        public static AddressablesPlayerBuildResult BuildContent(BuildConfig cfg)
        {
            var settings = AddressableAssetSettingsDefaultObject.Settings;
            if (settings == null) { Debug.LogError("[CONTENT] no AddressableAssetSettings — run 'Mark Models Addressable' first."); return null; }

            string profileId = settings.activeProfileId;
            settings.profileSettings.SetValue(profileId, AddressableAssetSettings.kRemoteLoadPath, cfg.remoteLoadPath);
            settings.profileSettings.SetValue(profileId, AddressableAssetSettings.kRemoteBuildPath, cfg.remoteBuildPath);
            Debug.Log($"[CONTENT] profile remote paths set — {cfg.Summary}");

            int groups = 0;
            foreach (var g in settings.groups.Where(g => g != null && g.HasSchema<BundledAssetGroupSchema>()))
            {
                var s = g.GetSchema<BundledAssetGroupSchema>();
                s.BuildPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteBuildPath);
                s.LoadPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteLoadPath);
                s.IncludeInBuild = true;
                // NB: do NOT override BundleMode here — respect each group's own packing
                // (models = PackSeparately per AddressableModelSetup; Anim_Gestures = PackTogether → 1 small bundle).
                groups++;
            }
            Debug.Log($"[CONTENT] {groups} groups set remote + include-in-build (packing per-group, preserved)");

            settings.OverridePlayerVersion = cfg.contentVersion;
            settings.BuildRemoteCatalog = true;
            EditorUtility.SetDirty(settings);
            AssetDatabase.SaveAssets();

            Debug.Log("[CONTENT] building Addressables content …");
            AddressableAssetSettings.CleanPlayerContent();
            AddressableAssetSettings.BuildPlayerContent(out AddressablesPlayerBuildResult result);
            return result;
        }

        static BuildConfig FindBuildConfig()
        {
            var guid = AssetDatabase.FindAssets("t:BuildConfig").FirstOrDefault();
            return guid == null ? null : AssetDatabase.LoadAssetAtPath<BuildConfig>(AssetDatabase.GUIDToAssetPath(guid));
        }
    }
}
#endif
