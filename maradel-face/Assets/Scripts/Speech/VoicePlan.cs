namespace Maradel.Speech
{
    /// <summary>
    /// Expected payload for a single reply — the backend sends ONE <c>voice:plan</c> event whose
    /// <see cref="beats"/> are played in sequence. Each beat is a FACE beat (talk + lipsync + face
    /// emotion, camera centred on the face, audio plays here) or a BODY beat (full-body gesture for
    /// the emotion, camera centred on the body, silent). Any order/length:
    ///   [face]                     → just talk
    ///   [body, face]               → gesture, then talk
    ///   [face, body]               → talk, then gesture
    ///   [body, face, body]         → …
    ///
    /// JSON (camelCase; deserialized by System.Text.Json → PROPERTIES):
    /// {
    ///   "sessionId": "abc",
    ///   "beats": [
    ///     { "kind": "body", "emotion": "excited", "durationSec": 2.5 },
    ///     { "kind": "face", "emotion": "happy",
    ///       "chunks": [ { "index":0, "url":"/voice/file/..wav", "durationSec":1.2 } ] }
    ///   ]
    /// }
    /// </summary>
    public sealed class VoicePlan
    {
        public string sessionId { get; set; }
        public VoiceBeat[] beats { get; set; }
    }

    public sealed class VoiceBeat
    {
        /// <summary>"face" (talk/lipsync/expression, camera on face) or "body" (gesture, camera on body).</summary>
        public string kind { get; set; }
        /// <summary>Emotion id (one of the backend's AVATAR_EMOTIONS) → expression (face) or gesture (body).</summary>
        public string emotion { get; set; }
        /// <summary>Body beats: how long to hold the gesture (s). 0 → use the clip length / a default.</summary>
        public float durationSec { get; set; }
        /// <summary>Face beats: the audio to speak during this beat (may be empty for a silent face pose).</summary>
        public VoiceChunkRef[] chunks { get; set; }

        public bool IsBody => string.Equals(kind, "body", System.StringComparison.OrdinalIgnoreCase);
    }

    public sealed class VoiceChunkRef
    {
        public int index { get; set; }
        public string url { get; set; }      // path or absolute; the socket client prefixes the base URL
        public float durationSec { get; set; }
    }
}
