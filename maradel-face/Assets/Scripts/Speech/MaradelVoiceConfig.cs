using System;
using UnityEngine;

namespace Maradel.Speech
{
    /// <summary>
    /// Connection settings + URL builders for Maradel's voice backend (see Docs/SPEECH_HOOK.md).
    /// Default LAN host 192.168.0.229:9100; use localhost when running the backend locally.
    /// </summary>
    [Serializable]
    public sealed class MaradelVoiceConfig
    {
        [Tooltip("Maradel backend host (no scheme). LAN default: 192.168.0.229")]
        public string host = "192.168.0.229";

        [Tooltip("Maradel backend port (MARADEL_PORT, default 9100). Same port as Socket.IO.")]
        public int port = 9100;

        public string BaseUrl => $"http://{host}:{port}";

        /// <summary>Endless MP3 radio: GET /voice/stream (24 kHz mono, audio/mpeg).</summary>
        public string StreamUrl => $"{BaseUrl}/voice/stream";

        /// <summary>Absolute URL for a per-chunk WAV. <paramref name="relativeUrl"/> comes from
        /// the voice:chunk event (e.g. "/voice/file/&lt;sid&gt;/&lt;index&gt;.wav").</summary>
        public string FileUrl(string relativeUrl)
        {
            if (string.IsNullOrEmpty(relativeUrl)) return null;
            return relativeUrl.StartsWith("http") ? relativeUrl : BaseUrl + relativeUrl;
        }

        /// <summary>One-shot synthesized WAV: GET /voice/preview?text=...  (handy for testing).</summary>
        public string PreviewUrl(string text, string voice = null, float speed = 1f)
        {
            string q = $"{BaseUrl}/voice/preview?text={Uri.EscapeDataString(text ?? "")}";
            if (!string.IsNullOrEmpty(voice)) q += $"&voice={Uri.EscapeDataString(voice)}";
            if (Math.Abs(speed - 1f) > 0.001f) q += $"&speed={speed}";
            return q;
        }
    }
}
