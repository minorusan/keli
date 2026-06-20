using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using UnityEngine;

namespace Maradel.Face
{
    /// <summary>
    /// Default <see cref="IAudioFeed"/>: downloads Maradel WAV chunks and plays them in arrival
    /// order through one AudioSource. uLipSync (and/or <see cref="AudioTap"/>) live on the same
    /// GameObject as that AudioSource, so analysis is automatic.
    ///
    /// Downloads via <see cref="HttpClient"/> (not UnityWebRequest) so it is NOT subject to Unity's
    /// "Allow downloads over HTTP" (insecureHttpOption) editor policy — plain http:// LAN URLs work
    /// out of the box. WAV bytes are decoded by <see cref="WavAudio"/> into an AudioClip, and can be
    /// saved to disk for inspection.
    /// </summary>
    [RequireComponent(typeof(AudioSource))]
    [AddComponentMenu("Maradel/Unity Web Request Audio Feed")]
    public sealed class UnityWebRequestAudioFeed : MonoBehaviour, IAudioFeed
    {
        [SerializeField] AudioSource audioSource;
        [Tooltip("Log every enqueue, download result, clip detail, and playback step.")]
        [SerializeField] bool verboseLogging = false;
        [Tooltip("Save each downloaded WAV to <persistentDataPath>/MaradelVoice for inspection.")]
        [SerializeField] bool saveIncoming = false;

        public event Action OnPlaybackStarted;
        public event Action OnPlaybackDrained;

        static readonly HttpClient _http = new HttpClient();
        readonly Queue<Pending> _queue = new();
        bool _pumping;

        struct Pending { public string url; public int index; public float dur; }

        public bool IsPlaying => _pumping || (audioSource != null && audioSource.isPlaying);

        public void SetVerbose(bool v) => verboseLogging = v;
        public void SetSaveIncoming(bool v) => saveIncoming = v;
        void Log(string m) { if (verboseLogging) Debug.Log($"[AudioFeed] {m}", this); }

        void Awake()
        {
            if (audioSource == null) audioSource = GetComponent<AudioSource>();
            audioSource.playOnAwake = false;
        }

        public void Enqueue(string url, int index, float durationSec)
        {
            Log($"enqueue #{index} ({durationSec:0.00}s) {url}  (queue={_queue.Count + 1}, pumping={_pumping})");
            _queue.Enqueue(new Pending { url = url, index = index, dur = durationSec });
            if (!_pumping) StartCoroutine(Pump());
        }

        public void Stop()
        {
            _queue.Clear();
            if (audioSource != null) audioSource.Stop();
            StopAllCoroutines();
            _pumping = false;
            Log("stop");
        }

        IEnumerator Pump()
        {
            _pumping = true;
            bool announcedStart = false;
            try
            {
                while (_queue.Count > 0)
                {
                    var p = _queue.Dequeue();

                    Log($"download #{p.index} → {p.url}");
                    var _respSw = System.Diagnostics.Stopwatch.StartNew(); // [Time] request → playback
                    Task<byte[]> task = null;
                    try { task = _http.GetByteArrayAsync(p.url); }
                    catch (Exception e) { Debug.LogWarning($"[AudioFeed] #{p.index} request error: {e.Message}"); continue; }

                    while (!task.IsCompleted) yield return null;

                    if (task.IsFaulted || task.IsCanceled)
                    {
                        Debug.LogWarning($"[AudioFeed] #{p.index} DOWNLOAD FAILED: " +
                                         $"{task.Exception?.GetBaseException().Message} url={p.url}");
                        continue;
                    }

                    byte[] bytes = task.Result;
                    Log($"download #{p.index} OK: {bytes.Length} bytes");

                    if (saveIncoming) SaveToDisk(p.index, bytes);

                    if (!WavAudio.TryDecode(bytes, $"voice_{p.index}", out var clip, out var err))
                    {
                        Debug.LogWarning($"[AudioFeed] #{p.index} WAV decode failed: {err} ({bytes.Length} bytes)");
                        continue;
                    }
                    Log($"decoded #{p.index}: samples={clip.samples} ch={clip.channels} hz={clip.frequency} len={clip.length:0.00}s");

                    if (!announcedStart) { announcedStart = true; OnPlaybackStarted?.Invoke(); }

                    audioSource.clip = clip;
                    audioSource.Play();
                    _respSw.Stop();
                    Debug.Log($"[Time] voice #{p.index} response {_respSw.ElapsedMilliseconds}ms (request→play, {bytes.Length / 1024}KB)", this);
                    Log($"play #{p.index}: isPlaying={audioSource.isPlaying} vol={audioSource.volume} mute={audioSource.mute} " +
                        $"spatialBlend={audioSource.spatialBlend} listenerVol={AudioListener.volume} listenerPause={AudioListener.pause}");

                    // ROBUST WAIT — do NOT trust isPlaying right after Play(): on device the audio engine
                    // starts on the next DSP buffer (~20–40ms later), so `while(isPlaying)` exits on frame 1
                    // and the clip gets cut → the intermittent "plays from time to time" + dead lipsync.
                    // Wait the clip's FULL duration (start latency tolerated); bail early only if it truly stops.
                    float t0 = Time.realtimeSinceStartup;
                    float dur = clip.length;
                    bool everPlayed = false;
                    while (true)
                    {
                        float elapsed = Time.realtimeSinceStartup - t0;
                        if (audioSource.isPlaying) everPlayed = true;
                        if (elapsed >= dur + 0.20f) break;                                  // clip should be done by now
                        if (everPlayed && elapsed > 0.25f && !audioSource.isPlaying) break;  // genuinely stopped early (Stop()/interrupt)
                        yield return null;
                    }
                    if (!everPlayed)
                        Debug.LogWarning($"[AudioFeed] #{p.index} NEVER reported isPlaying in {dur:0.00}s — audio focus lost or DSP stalled (this is a 'silent' utterance).", this);
                    Log($"finished #{p.index} (everPlayed={everPlayed}, waited≈{dur:0.00}s)");
                }
            }
            finally
            {
                _pumping = false; // ALWAYS reset, even on early-out — never get stuck
                Log("queue drained");
                OnPlaybackDrained?.Invoke();
            }
        }

        void SaveToDisk(int index, byte[] bytes)
        {
            try
            {
                string dir = Path.Combine(Application.persistentDataPath, "MaradelVoice");
                Directory.CreateDirectory(dir);
                string file = Path.Combine(dir, $"chunk_{index}_{bytes.Length}.wav");
                File.WriteAllBytes(file, bytes);
                Log($"saved #{index} → {file}");
            }
            catch (Exception e) { Debug.LogWarning($"[AudioFeed] save #{index} failed: {e.Message}"); }
        }
    }
}
