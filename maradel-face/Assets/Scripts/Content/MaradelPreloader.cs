#if ADDRESSABLES
using System;
using System.Collections;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;

namespace Maradel.Content
{
    /// <summary>
    /// Boot screen: initializes Addressables and downloads all bundles labeled "essential" (from
    /// <see cref="BuildConfig"/>) with a progress bar (<see cref="DownloadProgress"/>), then raises
    /// <see cref="OnReady"/>. Logs sizes, versions, and decoded bundle errors.
    /// </summary>
    [AddComponentMenu("Maradel/Maradel Preloader")]
    public sealed class MaradelPreloader : MonoBehaviour
    {
        [SerializeField] BuildConfig config;
        [Tooltip("Start preloading on Start().")]
        [SerializeField] bool preloadOnStart = true;

        public event Action OnReady;
        public bool IsReady { get; private set; }

        void Start()
        {
            if (config == null) { RemoteAvatars.Err("MaradelPreloader: no BuildConfig assigned."); return; }
            if (preloadOnStart) StartCoroutine(Preload());
        }

        public IEnumerator Preload()
        {
            RemoteAvatars.Log($"preloader start — {config.Summary}");

            // 1. init Addressables (loads the catalog; first network touch)
            var init = Addressables.InitializeAsync();
            yield return init;
            if (init.Status == AsyncOperationStatus.Failed)
            {
                RemoteAvatars.Err("Addressables init FAILED:\n  " + RemoteAvatars.BundleErrorReason(init));
                yield break;
            }
            RemoteAvatars.LogContentState(config);

            // 1b. AUTO-UPDATE: check the remote catalog for changes; if the content was rebuilt+
            // re-uploaded, the catalog hash differs → pull it so changed bundles re-download.
            var check = Addressables.CheckForCatalogUpdates(false);
            yield return check;
            var cats = check.Result;
            if (cats != null && cats.Count > 0)
            {
                CacheLog.Log($"{cats.Count} catalog update(s) found → updating (changed bundles re-fetch on next load)");
                var upd = Addressables.UpdateCatalogs(cats, false);
                yield return upd;
                CacheLog.Log($"catalog update {(upd.Status == AsyncOperationStatus.Succeeded ? "OK" : "FAILED")}");
                Addressables.Release(upd);
                RemoteAvatars.LogContentState(config); // cache after update
            }
            else CacheLog.Log("no catalog updates — content is current");
            Addressables.Release(check);

            // 2. how big is "essential"?
            var sizeOp = Addressables.GetDownloadSizeAsync(config.essentialLabel);
            yield return sizeOp;
            long bytes = sizeOp.Status == AsyncOperationStatus.Succeeded ? sizeOp.Result : 0;
            Addressables.Release(sizeOp);
            RemoteAvatars.Log($"essential download size = {bytes / (1024 * 1024f):0.0} MB " +
                              (bytes == 0 ? "(already cached or nothing labeled essential)" : ""));

            // 3. download essential with progress
            if (bytes > 0)
            {
                DownloadProgress.Begin($"Downloading essentials");
                var dl = Addressables.DownloadDependenciesAsync(config.essentialLabel, false);
                while (!dl.IsDone)
                {
                    var s = dl.GetDownloadStatus();
                    DownloadProgress.Report(s.Percent, s.DownloadedBytes, s.TotalBytes);
                    yield return null;
                }
                if (dl.Status == AsyncOperationStatus.Failed)
                {
                    RemoteAvatars.Err("essential download FAILED:\n  " + RemoteAvatars.BundleErrorReason(dl));
                    DownloadProgress.End();
                    Addressables.Release(dl);
                    yield break;
                }
                Addressables.Release(dl);
                DownloadProgress.End();
                RemoteAvatars.Log("essential bundles downloaded + cached");
            }
            else DownloadProgress.End();

            IsReady = true;
            RemoteAvatars.Log("preloader DONE — content ready");
            OnReady?.Invoke();
        }
    }
}
#endif
