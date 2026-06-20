using System;
using Maradel.Face;
using Maradel.UI;
using UnityEngine;
#if MARADEL_SOCKETIO
using System.Threading.Tasks;
using SocketIOClient;
#endif

namespace Maradel.Speech
{
    /// <summary>
    /// One drop-in component to PROVE the whole audio path end-to-end. Add it to a single empty
    /// GameObject and press Play — it self-creates an AudioSource (2D, audible) + a
    /// UnityWebRequestAudioFeed, connects to Maradel's Socket.IO, plays each voice:chunk WAV, and
    /// draws a big always-on status HUD: socket connection, events received, and audio state.
    ///
    /// Why you might "not hear Unity": a 3D AudioSource away from the AudioListener is silent —
    /// this forces spatialBlend=0 (2D) + volume=1 so the voice is always audible. The HUD shows
    /// every reason it could be quiet. Use the Beep button to confirm Unity can output sound at all.
    /// </summary>
    [AddComponentMenu("Maradel/Maradel Voice Probe (OnGUI)")]
    public sealed class MaradelVoiceProbe : MonoBehaviour
    {
        [SerializeField] MaradelVoiceConfig config = new();
        [SerializeField] bool autoConnect = true;
        [SerializeField] bool verbose = true;

        [Header("Overlay")]
        [Range(0.2f, 3f)][SerializeField] float guiScale = 1f;
        [Range(0f, 1f)][SerializeField] float overlayAlpha = 0.9f;
        [Tooltip("Vertical offset (design units, 0..1000 across the square) so this panel sits " +
                 "below the gallery overlay instead of overlapping it.")]
        [SerializeField] float overlayOffsetY = 330f;
        [SerializeField] float overlayOffsetX = 20f;

        AudioSource _src;
        UnityWebRequestAudioFeed _feed;
        GUIStyle _rich;
        bool _hasListener;

        // diagnostics
        int _chunks;
        string _lastChunk = "—";
        bool _speaking;
        string _socketState = "Disconnected";
        string _socketColor = "grey";
        string _lastError = "";

        void Log(string m) { if (verbose) Debug.Log($"[VoiceProbe] {m}", this); }

        void Awake()
        {
            _src = GetComponent<AudioSource>() ?? gameObject.AddComponent<AudioSource>();
            _src.playOnAwake = false;
            _src.spatialBlend = 0f; // 2D — always audible regardless of position (the #1 "silent" cause)
            _src.volume = 1f;
            _src.mute = false;

            _feed = GetComponent<UnityWebRequestAudioFeed>() ?? gameObject.AddComponent<UnityWebRequestAudioFeed>();
            _feed.SetVerbose(verbose);     // full per-step download/play logging
            _feed.SetSaveIncoming(verbose); // save each WAV to <persistentDataPath>/MaradelVoice
            _feed.OnPlaybackStarted += () => Log("audio playback started");
            _feed.OnPlaybackDrained += () => Log("audio playback drained");

            _hasListener = FindFirstObjectByType<AudioListener>() != null;
            if (!_hasListener)
                Debug.LogWarning("[VoiceProbe] No AudioListener in scene (usually on Main Camera) — " +
                                 "you will hear nothing. Add one.", this);
        }

        void Start()
        {
#if MARADEL_SOCKETIO
            if (autoConnect) _ = Connect();
#else
            Debug.LogWarning("[VoiceProbe] MARADEL_SOCKETIO not defined — socket disabled. " +
                             "Use the Speak (preview) button for HTTP-only testing.", this);
#endif
        }

        // ── preview / beep (work without socket) ──

        public void SpeakPreview(string text)
        {
            string url = config.PreviewUrl(text);
            Log($"preview: {url}");
            _feed.Enqueue(url, _chunks++, 0f);
        }

        public void Beep()
        {
            int sr = 44100, len = sr / 2;
            var clip = AudioClip.Create("beep", len, 1, sr, false);
            var data = new float[len];
            for (int i = 0; i < len; i++) data[i] = 0.3f * Mathf.Sin(2f * Mathf.PI * 440f * i / sr);
            clip.SetData(data, 0);
            _src.PlayOneShot(clip);
            Log("beep (local sine) — if you don't hear this, the problem is Unity audio output, not the network");
        }

        // ── OnGUI HUD ──

        void OnGUI()
        {
            _rich ??= new GUIStyle(GUI.skin.label) { richText = true };
            var prev = GuiOverlay.Begin(guiScale, overlayAlpha);

            GUILayout.BeginArea(new Rect(overlayOffsetX, overlayOffsetY, 660, 400), GUI.skin.box);
            GUILayout.Label("<b>Maradel Voice Probe</b>", _rich);
            GUILayout.Label($"backend: {config.BaseUrl}", _rich);

            GUILayout.Space(4);
            GUILayout.Label($"SOCKET: <b><color={_socketColor}>{_socketState}</color></b>" +
                            (string.IsNullOrEmpty(_lastError) ? "" : $"  <color=#FF4040>{_lastError}</color>"), _rich);
            GUILayout.Label($"speaking: {(_speaking ? "<color=#7CFC00>YES</color>" : "no")}   " +
                            $"chunks received: <b>{_chunks}</b>   last: {_lastChunk}", _rich);

            GUILayout.Space(4);
            string audioColor = _src.isPlaying ? "#7CFC00" : "grey";
            GUILayout.Label($"AUDIO: <color={audioColor}>{(_src.isPlaying ? "PLAYING" : "idle")}</color>   " +
                            $"clip: {(_src.clip ? _src.clip.name : "—")}", _rich);
            GUILayout.Label($"volume: {_src.volume:0.0}   mute: {_src.mute}   spatialBlend(0=2D): {_src.spatialBlend:0.0}   " +
                            $"AudioListener.volume: {AudioListener.volume:0.0}", _rich);
            GUILayout.Label($"AudioListener in scene: {(_hasListener ? "<color=#7CFC00>yes</color>" : "<color=#FF4040>NO — add one!</color>")}", _rich);

            GUILayout.Space(6);
            GUILayout.BeginHorizontal();
#if MARADEL_SOCKETIO
            if (GUILayout.Button("Connect", GUILayout.Height(38))) _ = Connect();
            if (GUILayout.Button("Disconnect", GUILayout.Height(38))) _ = Disconnect();
#else
            GUILayout.Label("<color=#FFD700>MARADEL_SOCKETIO off</color>", _rich);
#endif
            if (GUILayout.Button("Speak (preview)", GUILayout.Height(38))) SpeakPreview("Hello from Unity.");
            if (GUILayout.Button("Stop", GUILayout.Width(90), GUILayout.Height(38))) _feed.Stop();
            if (GUILayout.Button("Beep", GUILayout.Width(90), GUILayout.Height(38))) Beep();
            GUILayout.EndHorizontal();

            GUILayout.EndArea();
            GuiOverlay.End(prev);
        }

#if MARADEL_SOCKETIO
        SocketIOUnity _socket;

        struct ChunkMsg { public string sessionId { get; set; } public int index { get; set; } public string url { get; set; } public float durationSec { get; set; } }
        struct SpeakingMsg { public string sessionId { get; set; } public bool on { get; set; } }

        public async Task Connect()
        {
            if (_socket != null) return;
            _socket = new SocketIOUnity(new Uri(config.BaseUrl), new SocketIOOptions
            {
                Transport = SocketIOClient.Transport.TransportProtocol.WebSocket,
                Reconnection = true,
            });

            _socket.OnAny((name, response) => Log($"◀ '{name}': {response}")); // log every backend event

            _socket.OnUnityThread("voice:chunk", res =>
            {
                var m = res.GetValue<ChunkMsg>();
                _chunks++;
                _lastChunk = $"#{m.index} {m.durationSec:0.00}s";
                string full = config.FileUrl(m.url);
                Log($"chunk {_lastChunk} {full}");
                _feed.Enqueue(full, m.index, m.durationSec);
            });
            _socket.OnUnityThread("voice:speaking", res =>
            {
                var m = res.GetValue<SpeakingMsg>();
                _speaking = m.on;
                // DO NOT Stop() on on:false — Maradel finished synthesizing, but Unity is still
                // downloading/playing the queued chunks (it lags the backend). Let the queue drain;
                // the feed resets when empty. Stopping here truncated all audio.
                Log($"speaking = {m.on}{(m.on ? "" : " (letting queue play out)")}");
            });

            _socket.OnConnected += (_, _) => { SetState("Connected", "#7CFC00"); _lastError = ""; Log("connected"); };
            _socket.OnDisconnected += (_, r) => { SetState("Disconnected", "grey"); Log($"disconnected: {r}"); };
            _socket.OnError += (_, e) => { SetState("Error", "#FF4040"); _lastError = e; Debug.LogError($"[VoiceProbe] {e}", this); };

            SetState("Connecting", "#FFD700");
            Log($"connecting to {config.BaseUrl} …");
            try { await _socket.ConnectAsync(); }
            catch (Exception e) { SetState("Error", "#FF4040"); _lastError = e.Message; Debug.LogError($"[VoiceProbe] connect failed: {e.Message}", this); }
        }

        public async Task Disconnect()
        {
            if (_socket == null) return;
            try { await _socket.DisconnectAsync(); } catch { }
            _socket.Dispose(); _socket = null;
            SetState("Disconnected", "grey");
        }

        void SetState(string s, string color) { _socketState = s; _socketColor = color; }
        async void OnDestroy() => await Disconnect();
#endif
    }
}
