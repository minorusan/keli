using Maradel.Face;
using Maradel.UI;
using UnityEngine;

namespace Maradel.Speech
{
    /// <summary>
    /// Legacy OnGUI control + status overlay for the speech hook. Square-viewport anchored,
    /// transparency via <see cref="overlayAlpha"/>. Shows play + WebSocket connection status,
    /// lets you speak a one-shot <c>/voice/preview</c> WAV through the lipsync chain, and toggle
    /// the live radio. Verbose logging is opt-in.
    /// </summary>
    [AddComponentMenu("Maradel/Maradel Voice Tester (OnGUI)")]
    public sealed class MaradelVoiceTester : MonoBehaviour
    {
        [SerializeField] MaradelVoiceConfig config = new();

        [Tooltip("Feed on the lipsync AudioSource — used to fetch+play the preview WAV.")]
        [SerializeField] UnityWebRequestAudioFeed audioFeed;

        [Tooltip("Optional live MP3 radio player to toggle from the GUI.")]
        [SerializeField] MaradelStreamPlayer streamPlayer;

#if MARADEL_SOCKETIO
        [Tooltip("Optional socket client — its connection state is shown in the status panel.")]
        [SerializeField] MaradelVoiceSocketClient socketClient;
#endif

        [Header("Overlay")]
        [Range(0.2f, 3f)][SerializeField] float guiScale = 1f;
        [Tooltip("Overlay transparency: 0 = invisible, 1 = opaque.")]
        [Range(0f, 1f)][SerializeField] float overlayAlpha = 0.85f;

        [SerializeField] bool verboseLogging = false;
        [SerializeField] string text = "Testing one two three.";

        int _previewIndex;
        GUIStyle _rich;

        void Log(string m) { if (verboseLogging) Debug.Log($"[VoiceTester] {m}", this); }

        public void SpeakPreview()
        {
            if (audioFeed == null)
            {
                Debug.LogError($"{nameof(MaradelVoiceTester)}: assign a UnityWebRequestAudioFeed.", this);
                return;
            }
            string url = config.PreviewUrl(text);
            Log($"speak preview: {url}");
            audioFeed.Enqueue(url, _previewIndex++, 0f);
        }

        void OnGUI()
        {
            _rich ??= new GUIStyle(GUI.skin.label) { richText = true };

            var prev = GuiOverlay.Begin(guiScale, overlayAlpha);
            Rect sq = GuiOverlay.SquareViewport();

            // Lay out in design units (0..1000 across the square edge).
            GUILayout.BeginArea(new Rect(20, 360, 620, 320), GUI.skin.box);

            GUILayout.Label("<b>Maradel Voice</b>", _rich);
            GUILayout.Label($"square viewport: {sq.width:0}px  @({sq.x:0},{sq.y:0})", _rich);
            GUILayout.Label($"state: <b>{(Application.isPlaying ? "<color=#7CFC00>RUNNING</color>" : "edit")}</b>" +
                            $"   audio: {(audioFeed != null && audioFeed.IsPlaying ? "<color=#7CFC00>playing</color>" : "idle")}", _rich);

            GUILayout.Label($"socket: {SocketStatus()}", _rich);

            GUILayout.Space(6);
            text = GUILayout.TextField(text, GUILayout.Height(26));

            GUILayout.BeginHorizontal();
            if (GUILayout.Button("Speak (preview WAV)", GUILayout.Height(40))) SpeakPreview();
            if (audioFeed != null && GUILayout.Button("Stop", GUILayout.Width(100), GUILayout.Height(40)))
            { Log("stop"); audioFeed.Stop(); }
            GUILayout.EndHorizontal();

            if (streamPlayer != null)
            {
                GUILayout.BeginHorizontal();
                GUILayout.Label(streamPlayer.IsStreaming ? "<color=#7CFC00>Radio: ON</color>" : "Radio: off",
                    _rich, GUILayout.Width(130));
                if (!streamPlayer.IsStreaming && GUILayout.Button("Connect /voice/stream", GUILayout.Height(28)))
                { Log("radio connect"); streamPlayer.Connect(); }
                if (streamPlayer.IsStreaming && GUILayout.Button("Disconnect", GUILayout.Height(28)))
                { Log("radio disconnect"); streamPlayer.Disconnect(); }
                GUILayout.EndHorizontal();
            }

            GUILayout.EndArea();
            GuiOverlay.End(prev);
        }

        string SocketStatus()
        {
#if MARADEL_SOCKETIO
            if (socketClient == null) return "<color=grey>no client assigned</color>";
            string color = socketClient.State switch
            {
                MaradelVoiceSocketClient.ConnState.Connected => "#7CFC00",
                MaradelVoiceSocketClient.ConnState.Connecting => "#FFD700",
                MaradelVoiceSocketClient.ConnState.Error => "#FF4040",
                _ => "grey",
            };
            string extra = socketClient.State == MaradelVoiceSocketClient.ConnState.Error && !string.IsNullOrEmpty(socketClient.LastError)
                ? $" ({socketClient.LastError})" : (socketClient.IsSpeaking ? "  <color=#7CFC00>● speaking</color>" : "");
            return $"<b><color={color}>{socketClient.State}</color></b>{extra}";
#else
            return "<color=grey>(MARADEL_SOCKETIO off)</color>";
#endif
        }
    }
}
