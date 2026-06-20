using System.Collections;
using UnityEngine;
using UnityEngine.Networking;

namespace Maradel.Speech
{
    /// <summary>
    /// Zero-dependency live hook: streams Maradel's endless <c>/voice/stream</c> MP3 radio into an
    /// AudioSource. Put a <c>uLipSync</c> (or <c>AudioTap</c>) component on the SAME GameObject and
    /// it analyzes the live voice → lipsync, no Socket.IO, no extra package.
    ///
    /// Experimental: endless-MP3 streaming is reliable on desktop but finicky on Android (per
    /// SPEECH_HOOK.md). For the shipped tablet path prefer the per-chunk WAV route
    /// (<see cref="MaradelVoiceSocketClient"/> + UnityWebRequestAudioFeed).
    /// </summary>
    [RequireComponent(typeof(AudioSource))]
    [AddComponentMenu("Maradel/Maradel Stream Player")]
    public sealed class MaradelStreamPlayer : MonoBehaviour
    {
        [SerializeField] MaradelVoiceConfig config = new();
        [SerializeField] AudioSource audioSource;
        [SerializeField] bool playOnStart = false;

        UnityWebRequest _req;
        public bool IsStreaming { get; private set; }

        void Awake()
        {
            if (audioSource == null) audioSource = GetComponent<AudioSource>();
            audioSource.playOnAwake = false;
        }

        void Start()
        {
            if (playOnStart) Connect();
        }

        public void Connect()
        {
            if (IsStreaming) return;
            StartCoroutine(StreamRoutine());
        }

        public void Disconnect()
        {
            IsStreaming = false;
            if (audioSource != null) audioSource.Stop();
            StopAllCoroutines();
            if (_req != null) { _req.Abort(); _req.Dispose(); _req = null; }
        }

        IEnumerator StreamRoutine()
        {
            IsStreaming = true;
            _req = UnityWebRequestMultimedia.GetAudioClip(config.StreamUrl, AudioType.MPEG);
            var dh = (DownloadHandlerAudioClip)_req.downloadHandler;
            dh.streamAudio = true; // progressive: clip becomes playable before the (endless) DL "finishes"

            _req.SendWebRequest(); // do NOT yield to completion — the body never closes

            // Buffer until the streaming clip is available, then play.
            while (IsStreaming)
            {
                if (_req.result == UnityWebRequest.Result.ConnectionError ||
                    _req.result == UnityWebRequest.Result.ProtocolError)
                {
                    Debug.LogError($"{nameof(MaradelStreamPlayer)}: {_req.error} ({config.StreamUrl})", this);
                    IsStreaming = false;
                    yield break;
                }

                AudioClip clip = null;
                try { clip = dh.audioClip; } catch { /* not enough buffered yet */ }
                if (clip != null && clip.loadState == AudioDataLoadState.Loaded)
                {
                    audioSource.clip = clip;
                    audioSource.Play();
                    break;
                }
                yield return null;
            }

            // Stay alive while the radio plays; the request keeps feeding the streaming clip.
            while (IsStreaming && _req != null && !_req.isDone) yield return null;
        }

        void OnDestroy() => Disconnect();
    }
}
