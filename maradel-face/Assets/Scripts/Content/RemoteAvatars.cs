// Runtime Addressables helpers. Guarded so the project compiles before the package resolves.
// Enable: install com.unity.addressables, then add scripting define symbol  ADDRESSABLES.
#if ADDRESSABLES
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;
using UnityEngine.ResourceManagement.ResourceLocations;

namespace Maradel.Content
{
    /// <summary>Shared Addressables helpers: enumerate avatars, log content state, and translate
    /// the usual opaque AssetBundle failures into human reasons so the Console is actionable.</summary>
    public static class RemoteAvatars
    {
        public const string TAG = "[CONTENT]";

        public static void Log(string m) => Debug.Log($"{TAG} {m}");
        public static void Warn(string m) => Debug.LogWarning($"{TAG} {m}");
        public static void Err(string m) => Debug.LogError($"{TAG} {m}");

        /// <summary>Resolve all avatar keys (addresses) for a label. Caller releases the handle.</summary>
        public static AsyncOperationHandle<IList<IResourceLocation>> LocationsForLabel(string label)
            => Addressables.LoadResourceLocationsAsync(label, typeof(GameObject));

        /// <summary>Coaching for a failed handle — maps common AssetBundle errors to likely causes.</summary>
        public static string BundleErrorReason(AsyncOperationHandle h)
        {
            string msg = h.OperationException != null ? h.OperationException.Message : "(no exception)";
            string low = msg.ToLowerInvariant();
            string reason;
            if (low.Contains("crc") || low.Contains("hash"))
                reason = "BUNDLE HASH/CRC MISMATCH — the bundle on the server differs from the catalog. " +
                         "Rebuild content AND re-upload, or you uploaded a stale/partial bundle.";
            else if (low.Contains("catalog"))
                reason = "CATALOG MISMATCH — app's catalog vs server catalog differ. Re-run the remote " +
                         "build and upload catalog_*.json/.hash; bump BuildConfig.contentVersion.";
            else if (low.Contains("404") || low.Contains("not found"))
                reason = "404 NOT FOUND — bundle/catalog missing at the remote load path. Check the URL " +
                         "and that you uploaded ServerData to that path.";
            else if (low.Contains("connection") || low.Contains("curl") || low.Contains("unable to") || low.Contains("timeout"))
                reason = "NETWORK — server unreachable / offline / firewall. Check the host:port and LAN.";
            else if (low.Contains("unityeditor") || low.Contains("scene"))
                reason = "BUILD/SRC MISMATCH — content built against different scripts/assets than the running " +
                         "player. Rebuild Addressables after code/asset changes.";
            else
                reason = "Unrecognized bundle error — see message.";
            return $"{reason}\n  raw: {msg}";
        }

        /// <summary>Log cache + version info to the [CACHE] file + overlay — spot stale downloads.</summary>
        public static void LogContentState(BuildConfig cfg)
        {
            CacheLog.Log($"content: version={(cfg ? cfg.contentVersion : "?")} loadPath={(cfg ? cfg.remoteLoadPath : "?")}");
            CacheLog.LogCacheState("state");
        }
    }
}
#endif
