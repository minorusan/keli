using System;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Pure codec/transport for the Flutter (flutter_embed_unity) bridge — message-name
    /// constants + JSON envelope helpers. No DI (statics can't be injected); the injected
    /// MonoBehaviour <see cref="FlutterFaceBridge"/> holds the controller.
    /// </summary>
    public static class FlutterFace
    {
        // inbound (Flutter -> Unity)
        public const string PlayChunk = "playChunk"; // {url, index, durationSec}
        public const string Stop      = "stop";
        public const string SetMood   = "setMood";   // {mood}
        public const string PushPcm   = "pushPcm";   // {b64, sampleRate, channels} (optional)

        // outbound (Unity -> Flutter)
        public const string Ready           = "ready";
        public const string SpeakingStarted = "speakingStarted";
        public const string SpeakingStopped = "speakingStopped";
        public const string VisemeFrame     = "visemeFrame"; // {dominant, volume}
        public const string Error           = "error";       // {message}

        [Serializable] public struct Envelope { public string type; public string json; }

        public static void Emit(string type, object payload = null)
        {
            var env = new Envelope
            {
                type = type,
                json = JsonUtility.ToJson(payload ?? new EmptyPayload())
            };
            string wire = JsonUtility.ToJson(env);
#if FLUTTER_EMBED_UNITY
            global::SendToFlutter.Send(wire); // SendToFlutter is in the global namespace (Assets/FlutterEmbed)
#else
            Debug.Log($"[FlutterFace -> (no bridge)] {wire}");
#endif
        }

        [Serializable] struct EmptyPayload { }
    }
}
