#if ADDRESSABLES
using System.Linq;
using Maradel.Speech;
using UnityEditor;
using UnityEditor.AddressableAssets;
using UnityEditor.AddressableAssets.Settings;
using UnityEditor.AddressableAssets.Settings.GroupSchemas;
using UnityEngine;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// Marks every gesture + idle clip used by <see cref="AnimationDirector"/> (BOTH genders, f_ and m_;
    /// see <see cref="AnimationDirector.AllClipAddresses"/>) as Addressables (group "Anim_Gestures", label
    /// "anim" + "essential" so they preload; address = the clip file name). Each is the FBX under
    /// Animations/all_animations_max_motextr_static. Menu: Maradel ▸ Addressables ▸ Mark Animations.
    /// </summary>
    public static class AddressableAnimSetup
    {
        const string AnimRoot = "Assets/App/Content/Models/Microsoft-Rocketbox-master/Assets/Animations/all_animations_max_motextr_static";
        const string GroupName = "Anim_Gestures";

        /// <summary>Auto-mark on editor load / recompile if the group is missing any clip the code expects
        /// (e.g. after the gender/idle clip list grew). Idempotent + cheap; only does work when out of date.</summary>
        [InitializeOnLoadMethod]
        static void AutoMarkIfStale()
        {
            EditorApplication.delayCall += () =>
            {
                var settings = AddressableAssetSettingsDefaultObject.GetSettings(false);
                if (settings == null) return; // addressables not initialised yet
                var group = settings.FindGroup(GroupName);
                int have = group == null ? 0 : group.entries.Count;
                int want = AnimationDirector.AllClipAddresses().Count();
                if (have < want)
                {
                    Debug.Log($"[CONTENT] Anim_Gestures has {have}/{want} clips — auto-marking (gender/idle clips added).");
                    MarkAnimations();
                }
            };
        }

        [MenuItem("Maradel/Addressables/Mark Animations")]
        public static void MarkAnimations()
        {
            var settings = AddressableAssetSettingsDefaultObject.GetSettings(true);
            if (settings == null) { Debug.LogError("[CONTENT] no AddressableAssetSettings."); return; }
            settings.AddLabel("anim");
            settings.AddLabel("essential");

            var group = settings.FindGroup(GroupName)
                ?? settings.CreateGroup(GroupName, false, false, false, null,
                       typeof(BundledAssetGroupSchema), typeof(ContentUpdateGroupSchema));
            var schema = group.GetSchema<BundledAssetGroupSchema>();
            schema.BundleMode = BundledAssetGroupSchema.BundlePackingMode.PackTogether; // small clips → one bundle
            schema.IncludeInBuild = true;
            schema.BuildPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteBuildPath);
            schema.LoadPath.SetVariableByName(settings, AddressableAssetSettings.kRemoteLoadPath);

            int ok = 0, miss = 0;
            foreach (var clipName in AnimationDirector.AllClipAddresses())
            {
                var guid = AssetDatabase.FindAssets($"{clipName} t:Model", new[] { AnimRoot })
                    .FirstOrDefault(g => System.IO.Path.GetFileNameWithoutExtension(AssetDatabase.GUIDToAssetPath(g))
                        .Equals(clipName + ".max", System.StringComparison.OrdinalIgnoreCase)
                        || System.IO.Path.GetFileName(AssetDatabase.GUIDToAssetPath(g)).Equals(clipName + ".max.fbx", System.StringComparison.OrdinalIgnoreCase));
                if (guid == null) { Debug.LogWarning($"[CONTENT] gesture clip FBX not found: {clipName}"); miss++; continue; }

                var entry = settings.CreateOrMoveEntry(guid, group, false, false);
                entry.address = clipName;
                entry.SetLabel("anim", true, false);
                entry.SetLabel("essential", true, false);
                ok++;
            }

            settings.SetDirty(AddressableAssetSettings.ModificationEvent.BatchModification, null, true, true);
            AssetDatabase.SaveAssets();
            Debug.Log($"[CONTENT] marked {ok} gesture clips addressable (label anim+essential, pack-together, remote); {miss} missing.");
        }
    }
}
#endif
