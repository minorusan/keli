using UnityEngine;

namespace Maradel.Content
{
    /// <summary>
    /// Central config for the Addressables remote pipeline. Create one via
    /// Assets ▸ Create ▸ Maradel ▸ Build Config and assign it on the build script + preloader.
    /// The editor build script writes <see cref="remoteLoadPath"/> into the Addressables profile;
    /// the runtime reads labels/version from here.
    /// </summary>
    [CreateAssetMenu(menuName = "Maradel/Build Config", fileName = "BuildConfig")]
    public sealed class BuildConfig : ScriptableObject
    {
        [Header("Remote content server")]
        [Tooltip("Where the bundles + catalog are SERVED from at runtime (egregor-share path-style route). " +
                 "[BuildTarget] is substituted by Addressables (e.g. StandaloneWindows64, Android).")]
        public string remoteLoadPath = "http://192.168.0.11:7777/api/shared/addressables/[BuildTarget]";

        [Tooltip("Where the build script WRITES the bundles on disk; tool/upload-addressables.ps1 then " +
                 "PUTs them to the pi (which symlinks shared/addressables → /mnt/cache/addressables).")]
        public string remoteBuildPath = "ServerData/[BuildTarget]";

        [Tooltip("Bumped each content build. Shown in logs; use to spot stale catalogs / mismatches.")]
        public string contentVersion = "1.0.0";

        [Header("Labels")]
        [Tooltip("Label applied to every avatar so the runtime can enumerate them.")]
        public string avatarLabel = "avatar";

        [Tooltip("Label whose bundles the preload screen downloads up front.")]
        public string essentialLabel = "essential";

        [Tooltip("How many of the discovered avatars (alphabetical) to also tag 'essential' " +
                 "so they're preloaded. 0 = none preloaded (all on-demand).")]
        public int essentialCount = 1;

        public string Summary => $"v{contentVersion}  load='{remoteLoadPath}'  build='{remoteBuildPath}'  " +
                                 $"labels[avatar='{avatarLabel}', essential='{essentialLabel}' x{essentialCount}]";
    }
}
