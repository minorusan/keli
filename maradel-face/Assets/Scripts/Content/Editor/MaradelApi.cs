#if ADDRESSABLES
using System;
using System.Net.Http;
using System.Text;
using UnityEngine;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// Editor-side client for the egregor-share API on the pi (192.168.0.11:7777).
    /// Uses HttpClient (blocking .Result) — reliable synchronous I/O during a build.
    /// </summary>
    public static class MaradelApi
    {
        public static string ApiBase = "http://192.168.0.11:7777";
        static readonly HttpClient _http = new HttpClient { Timeout = TimeSpan.FromMinutes(10) };

        /// <summary>PUT raw bytes to /api/shared/&lt;rel&gt; (path-style; subdirs auto-created).</summary>
        public static bool PutShared(string rel, byte[] bytes, out int code)
        {
            string url = $"{ApiBase}/api/shared/{rel}";
            try { var r = _http.PutAsync(url, new ByteArrayContent(bytes)).Result; code = (int)r.StatusCode; return r.IsSuccessStatusCode; }
            catch (Exception e) { code = 0; Debug.LogWarning($"[BUILD] PUT {rel}: {e.Message}"); return false; }
        }

        /// <summary>DELETE an absolute path (recursive) via /api/file?path=.</summary>
        public static bool DeleteAbs(string absPath, out int code)
        {
            string url = $"{ApiBase}/api/file?path={Uri.EscapeDataString(absPath)}";
            try { var r = _http.DeleteAsync(url).Result; code = (int)r.StatusCode; return r.IsSuccessStatusCode; }
            catch (Exception e) { code = 0; Debug.LogWarning($"[BUILD] DELETE {absPath}: {e.Message}"); return false; }
        }

        public static bool Mkdir(string absPath)
        {
            try
            {
                var body = new StringContent($"{{\"path\":{ToJson(absPath)}}}", Encoding.UTF8, "application/json");
                return _http.PostAsync($"{ApiBase}/api/mkdir", body).Result.IsSuccessStatusCode;
            }
            catch (Exception e) { Debug.LogWarning($"[BUILD] mkdir {absPath}: {e.Message}"); return false; }
        }

        /// <summary>GET /api/fs?path= → JSON listing of one directory, or null on error.</summary>
        public static string ListAbs(string absPath)
        {
            try { return _http.GetStringAsync($"{ApiBase}/api/fs?path={Uri.EscapeDataString(absPath)}").Result; }
            catch (Exception e) { Debug.LogWarning($"[BUILD] LIST {absPath}: {e.Message}"); return null; }
        }

        [Serializable] public class FsEntry { public string name; public string type; public long size; }
        [Serializable] public class FsResp { public string path; public FsEntry[] entries; }

        /// <summary>Recursively count files under an absolute dir via the API (for verification).</summary>
        public static int CountFilesRecursive(string absPath, out long totalBytes)
        {
            totalBytes = 0;
            string json = ListAbs(absPath);
            if (string.IsNullOrEmpty(json)) return 0;
            FsResp resp;
            try { resp = JsonUtility.FromJson<FsResp>(json); } catch { return 0; }
            if (resp?.entries == null) return 0;

            int count = 0;
            foreach (var e in resp.entries)
            {
                string child = absPath.TrimEnd('/') + "/" + e.name;
                if (e.type == "file") { count++; totalBytes += e.size; }
                else { count += CountFilesRecursive(child, out long sub); totalBytes += sub; }
            }
            return count;
        }

        static string ToJson(string s) => "\"" + s.Replace("\\", "\\\\").Replace("\"", "\\\"") + "\"";
    }
}
#endif
