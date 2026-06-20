namespace Maradel.Content
{
    /// <summary>
    /// Tiny global bus the download code writes to and the UI reads. Decouples the Addressables
    /// layer (which may be compiled out) from the progress bar view.
    /// </summary>
    public static class DownloadProgress
    {
        public static bool Active;        // a download is in flight
        public static float Value01;      // 0..1
        public static string Label = "";  // what's downloading
        public static long DownloadedBytes;
        public static long TotalBytes;

        public static void Begin(string label)
        {
            Active = true; Value01 = 0f; Label = label; DownloadedBytes = 0; TotalBytes = 0;
        }

        public static void Report(float v01, long downloaded, long total)
        {
            Value01 = v01; DownloadedBytes = downloaded; TotalBytes = total;
        }

        public static void End()
        {
            Active = false; Value01 = 1f;
        }

        public static string SizeText =>
            TotalBytes > 0 ? $"{DownloadedBytes / (1024 * 1024f):0.0} / {TotalBytes / (1024 * 1024f):0.0} MB" : "";
    }
}
