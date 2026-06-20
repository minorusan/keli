// Per-chunk voice path (recommended for the shipped tablet): subscribe to Maradel's Socket.IO
// voice:speaking / voice:chunk events and feed each finite WAV to the lipsync AudioSource.
//
// Requires: SocketIOUnity package (https://github.com/itisnajim/SocketIOUnity.git) +
//           scripting define symbol  MARADEL_SOCKETIO.
#if MARADEL_SOCKETIO
using System;
using System.Threading.Tasks;
using UnityEngine;
using SocketIOClient;
using Maradel.Face;

namespace Maradel.Speech
{
    /// <summary>
    /// Connects to Maradel (:9100). On each <c>voice:chunk</c> it enqueues the WAV into the
    /// <see cref="UnityWebRequestAudioFeed"/> on the lipsync AudioSource (uLipSync analyzes it as
    /// it plays). <c>voice:speaking{on:false}</c> stops/drains. Uses SocketIOUnity's
    /// <c>OnUnityThread</c> so handlers run on the main thread — no manual marshalling.
    /// </summary>
    [AddComponentMenu("Maradel/Maradel Voice Socket Client")]
    public sealed class MaradelVoiceSocketClient : MonoBehaviour
    {
        [SerializeField] MaradelVoiceConfig config = new();

        [Tooltip("Feed on the AudioSource that uLipSync analyzes (downloads + plays the chunks).")]
        [SerializeField] UnityWebRequestAudioFeed audioFeed;

        [SerializeField] bool connectOnStart = true;
        [Tooltip("Log every connection change, speaking toggle, and chunk to the Console.")]
        [SerializeField] bool verboseLogging = true;
        // NB: voice:chunk ALWAYS drives audio+lipsync in real time now (the mic loop sends no
        // voice:plan); voice:plan drives only emotion/camera beats. (was: planDrivesAudio gate)

        public enum ConnState { Disconnected, Connecting, Connected, Error }

        public event Action<bool> OnSpeaking;     // mirror of voice:speaking{on}
        public event Action<VoicePlan> OnPlan;    // voice:plan — emotion/beat sequence for a reply

        public ConnState State { get; private set; } = ConnState.Disconnected;
        public string LastError { get; private set; }
        public bool IsSpeaking { get; private set; }

        SocketIOUnity _socket;

        void Log(string msg) { if (verboseLogging) Debug.Log($"[MaradelVoice] {msg}", this); }

        /// <summary>Set config + feed at runtime (used by RocketboxAutoRig before this Start()s).</summary>
        public void Configure(MaradelVoiceConfig cfg, UnityWebRequestAudioFeed feed)
        {
            if (cfg != null) config = cfg;
            if (feed != null) audioFeed = feed;
        }

        // GetValue<T>() uses System.Text.Json → binds PROPERTIES, case-sensitive. Names match
        // Maradel's JSON keys exactly (see Docs/SPEECH_HOOK.md).
        struct ChunkMsg
        {
            public string sessionId { get; set; }
            public int index { get; set; }
            public string url { get; set; }
            public float durationSec { get; set; }
        }
        struct SpeakingMsg
        {
            public string sessionId { get; set; }
            public bool on { get; set; }
        }

        async void Start()
        {
            if (connectOnStart) await Connect();
        }

        public async Task Connect()
        {
            if (_socket != null) return;

            _socket = new SocketIOUnity(new Uri(config.BaseUrl), new SocketIOOptions
            {
                Transport = SocketIOClient.Transport.TransportProtocol.WebSocket,
                Reconnection = true,
                // EIO defaults to v4 (matches a modern socket.io server). If Maradel runs
                // socket.io v2, set: EIO = EngineIO.V3.
            });

            // CATCH-ALL: log EVERY event the backend emits (name + raw payload) so coverage is total
            // and we can see exactly what's sent (voice, emotion, anything new). Verbose only.
            _socket.OnAny((name, response) =>
            {
                if (verboseLogging) Debug.Log($"[MaradelVoice] ◀ '{name}': {response}");
            });

            _socket.OnUnityThread("voice:chunk", res =>
            {
                var m = res.GetValue<ChunkMsg>();
                // The streaming voice:chunk drives BOTH audio AND lipsync in REAL TIME. We always
                // enqueue it: the mic voice-loop sends ONLY chunks (no voice:plan), so ignoring them
                // froze the mouth on Sil. Unity's own voice is muted (uLipSync outputSoundGain=0) so
                // this is silent — the Flutter voice_player is the audible owner — but uLipSync still
                // analyzes it → the mouth moves. voice:plan now drives ONLY emotion/camera beats
                // (it no longer re-enqueues audio — see EmotionSequencer.PlayFaceAudio).
                Log($"chunk #{m.index} ({m.durationSec:0.00}s) {config.FileUrl(m.url)}");
                if (audioFeed != null) audioFeed.Enqueue(config.FileUrl(m.url), m.index, m.durationSec);
            });

            _socket.OnUnityThread("voice:plan", res =>
            {
                var plan = res.GetValue<VoicePlan>();
                // prefix relative chunk urls with the base so the feed can fetch them
                if (plan?.beats != null)
                    foreach (var b in plan.beats)
                        if (b?.chunks != null)
                            foreach (var c in b.chunks) c.url = config.FileUrl(c.url);
                Log($"plan: {(plan?.beats?.Length ?? 0)} beats");
                OnPlan?.Invoke(plan);
            });

            _socket.OnUnityThread("voice:speaking", res =>
            {
                var m = res.GetValue<SpeakingMsg>();
                IsSpeaking = m.on;
                Log($"speaking = {m.on}");
                // Do NOT Stop() on on:false — Unity lags the backend (still downloading/playing the
                // queued chunks). Let the feed drain on its own; stopping here truncates the audio.
                OnSpeaking?.Invoke(m.on);
            });

            _socket.OnConnected += (_, _) => { State = ConnState.Connected; LastError = null; Log($"connected to {config.BaseUrl}"); };
            _socket.OnDisconnected += (_, reason) => { State = ConnState.Disconnected; Log($"disconnected: {reason}"); };
            _socket.OnError += (_, err) => { State = ConnState.Error; LastError = err; Debug.LogError($"[MaradelVoice] error: {err}", this); };

            State = ConnState.Connecting;
            Log($"connecting to {config.BaseUrl} …");
            try { await _socket.ConnectAsync(); }
            catch (Exception e)
            {
                State = ConnState.Error;
                LastError = e.Message;
                Debug.LogError($"[MaradelVoice] connect failed: {e.Message}", this);
            }
        }

        public async Task Disconnect()
        {
            if (_socket == null) return;
            try { await _socket.DisconnectAsync(); } catch { }
            _socket.Dispose();
            _socket = null;
            State = ConnState.Disconnected;
            Log("disposed");
        }

        async void OnDestroy() => await Disconnect();
    }
}
#endif
