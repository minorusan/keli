using System;
using System.Collections;
using System.Collections.Generic;
using Maradel.Face;
using UnityEngine;

namespace Maradel.Speech
{
    /// <summary>A gesture/idle player the sequencer can drive. <paramref name="cancelled"/> is polled while
    /// a clip is held — return true to cut it short (a newer message arrived / talking started).</summary>
    public interface IGesturePlayer
    {
        IEnumerator PlayAndHold(string emotion, float maxSeconds, Func<bool> cancelled); // gesture, capped at maxSeconds (≤0 = uncapped)
        IEnumerator PlayClip(string address, Func<bool> cancelled);                      // explicit clip (idles), full length
        IReadOnlyList<string> IdleClips { get; }                                         // curated idle clip addresses
    }

    /// <summary>
    /// Plays <see cref="VoicePlan"/>s on three independent, always-running tracks:
    ///   • SPEECH (queue, NEVER interrupted) — each plan's face beats are spoken in full; new plans wait
    ///     their turn in <see cref="_speechQueue"/>.
    ///   • BODY (latest-wins, INTERRUPTIBLE) — only the most-recent plan's gesture plays; a new plan cancels
    ///     the running gesture (via a generation token) and replaces it. Stale gestures are dropped.
    ///   • CAMERA director — frames the avatar: <b>FACE while talking, BODY the rest of the time</b>
    ///     (interruptible smoothing, with a short hold so it doesn't flick between phrases).
    /// So: a new message NEVER cuts off speech, but DOES take over the body, and the body shown is always
    /// the last message's gesture. Every transition is logged with [EMOTE].
    /// </summary>
    [AddComponentMenu("Maradel/Emotion Sequencer")]
    public sealed class EmotionSequencer : MonoBehaviour
    {
        const string TAG = "[EMOTE]";

        [SerializeField] RocketboxAutoRig rig;
        [SerializeField] UnityWebRequestAudioFeed feed;

        [Header("Timing (all configurable)")]
        [Tooltip("Approx. seconds for the camera to settle when it moves between face/body framing.")]
        [SerializeField] float cameraLerpTime = 0.4f;
        [Tooltip("Gap between the expression being set and the VOICE starting (camera↔voice sync).")]
        [SerializeField] float voiceDelay = 0.1f;
        [Tooltip("Keep the camera on the face this long after talking stops (avoids flicker between phrases).")]
        [SerializeField] float bodyReturnDelay = 0.35f;
        [Tooltip("Body hold time when there's no gesture player / clip length (fallback).")]
        [SerializeField] float defaultBodyDuration = 2.5f;

        [Header("Body length vs speech")]
        [Tooltip("Cap the gesture at this fraction LONGER than the speech, then drop to idle. 0.25 = +25%. Needs chunk durations.")]
        [Range(0f, 1f)][SerializeField] float bodyOverhangPct = 0.25f;

        [Header("Idle (when not busy)")]
        [Tooltip("Play idle clips at random intervals when not talking and no gesture is playing.")]
        [SerializeField] bool idleEnabled = true;
        [Tooltip("Pick a RANDOM idle each time (on) vs always the first idle clip only (off).")]
        [SerializeField] bool idleRandom = true;
        [Tooltip("Min/Max seconds to wait between idle clips.")]
        [SerializeField] float idleGapMin = 3f;
        [SerializeField] float idleGapMax = 9f;

        [SerializeField] bool verbose = true;

        // live-tunable from the OnGUI overlay
        public float BodyOverhangPct { get => bodyOverhangPct; set => bodyOverhangPct = Mathf.Clamp(value, 0f, 2f); }
        public bool IdleEnabled { get => idleEnabled; set => idleEnabled = value; }
        public bool IdleRandom { get => idleRandom; set => idleRandom = value; }
        public float IdleGapMin { get => idleGapMin; set => idleGapMin = Mathf.Max(0f, value); }
        public float IdleGapMax { get => idleGapMax; set => idleGapMax = Mathf.Max(idleGapMin, value); }

        public event Action<string> OnFaceEmotion; // expression (instant blendshape pose)
        public event Action<string> OnBodyEmotion; // informational

        IGesturePlayer _gesture;

        // SPEECH channel: FIFO queue, never interrupted.
        readonly Queue<VoicePlan> _speechQueue = new();
        bool _talking; // true while audio is actually playing → camera director frames the face

        // BODY channel: latest-wins. _bodyGen bumps on every new plan; the body track cancels its current
        // gesture when the gen it started with no longer matches.
        VoicePlan _bodyLatest;
        int _bodyGen;

        bool _runnersStarted;

        public void Configure(RocketboxAutoRig r, UnityWebRequestAudioFeed f) { if (r) rig = r; if (f) feed = f; }
        public void SetGesturePlayer(IGesturePlayer g) => _gesture = g;

        void Log(string m) { if (verbose) Debug.Log($"{TAG} {m}", this); }

        public void PlayPlan(VoicePlan plan)
        {
            if (plan?.beats == null || plan.beats.Length == 0) { Log("empty plan — nothing to play"); return; }
            string summary = string.Join(", ", Array.ConvertAll(plan.beats, b => $"{b.kind}:{b.emotion}"));

            // SPEECH: queue it — it waits behind whatever is currently being spoken (never cut off).
            _speechQueue.Enqueue(plan);
            // BODY: this is now the latest message → bump the generation so the body track interrupts the
            // currently-playing gesture and switches to this plan's gesture.
            _bodyLatest = plan;
            _bodyGen++;
            Log($"queued plan [{summary}] — speech waits in queue (len {_speechQueue.Count}); body → latest (gen {_bodyGen}, interrupts current gesture)");

            EnsureRunners();
        }

        void EnsureRunners()
        {
            if (_runnersStarted) return;
            _runnersStarted = true;
            StartCoroutine(SpeechRunner());
            StartCoroutine(BodyRunner());
            StartCoroutine(CameraDirector());
            Log("tracks started (speech / body / camera)");
        }

        // ── SPEECH: dequeue and speak each plan's face beats in full, one plan at a time ──────────────
        IEnumerator SpeechRunner()
        {
            while (true)
            {
                if (_speechQueue.Count == 0) { yield return null; continue; }
                var plan = _speechQueue.Dequeue();
                var faceBeats = Array.FindAll(plan.beats, b => !b.IsBody);
                if (faceBeats.Length == 0) { yield return null; continue; } // body-only plan: nothing to speak
                Log($"[speech] speaking plan — {faceBeats.Length} face beat(s); {_speechQueue.Count} plan(s) still queued");

                for (int i = 0; i < faceBeats.Length; i++)
                {
                    var beat = faceBeats[i];
                    OnFaceEmotion?.Invoke(beat.emotion); // set the expression
                    Log($"  FACE {i + 1}/{faceBeats.Length} '{beat.emotion}' expression set");
                    if (voiceDelay > 0f) yield return new WaitForSeconds(voiceDelay);
                    Log($"  talking ({(beat.chunks != null ? beat.chunks.Length : 0)} chunk(s)) — camera → FACE");
                    _talking = true;
                    yield return PlayFaceAudio(beat); // NEVER interrupted — plays to the end
                    _talking = false;
                    Log("  talking done");
                }
            }
        }

        // ── BODY: play the LATEST plan's gesture (capped to speech length), then random idles when free ──
        IEnumerator BodyRunner()
        {
            int playedGen = 0;       // _bodyGen starts at 0; first PlayPlan bumps it to 1
            float nextIdleAt = 0f;   // Time.time at which the next idle may start
            while (true)
            {
                // 1. a newer message → play its gesture(s), capped at (speech length × (1 + overhang))
                if (_bodyLatest != null && _bodyGen != playedGen)
                {
                    int gen = _bodyGen;
                    playedGen = gen;
                    var bodyBeats = Array.FindAll(_bodyLatest.beats, b => b.IsBody);
                    if (bodyBeats.Length > 0)
                    {
                        float speechLen = SpeechLengthOf(_bodyLatest);
                        float cap = speechLen > 0f ? speechLen * (1f + Mathf.Max(0f, bodyOverhangPct)) : 0f; // 0 = no cap (unknown speech length)
                        Log($"[body] latest (gen {gen}) → {bodyBeats.Length} gesture(s); speech≈{speechLen:0.0}s, cap {(cap > 0f ? $"{cap:0.0}s (+{bodyOverhangPct * 100:0}%)" : "none")}");

                        float used = 0f;
                        for (int i = 0; i < bodyBeats.Length && _bodyGen == gen; i++)
                        {
                            float remaining = cap > 0f ? cap - used : 0f;
                            if (cap > 0f && remaining <= 0.05f) { Log("  [body] speech-length cap reached → idle"); break; }
                            var beat = bodyBeats[i];
                            OnBodyEmotion?.Invoke(beat.emotion);
                            float start = Time.time;
                            if (_gesture != null)
                                yield return _gesture.PlayAndHold(beat.emotion, remaining, () => _bodyGen != gen);
                            else
                            {
                                float d = beat.durationSec > 0f ? beat.durationSec : defaultBodyDuration;
                                if (cap > 0f) d = Mathf.Min(d, remaining);
                                float t = 0f; while (t < d && _bodyGen == gen) { t += Time.deltaTime; yield return null; }
                            }
                            used += Time.time - start;
                        }
                        Log(_bodyGen != gen ? $"  [body] gen {gen} interrupted (now gen {_bodyGen})" : $"  [body] gen {gen} done → idle");
                    }
                    nextIdleAt = Time.time; // after a gesture, allow an idle promptly (avoid a frozen pose)
                    continue;
                }

                // 2. not busy → play random idles at random intervals
                if (idleEnabled && !_talking && _gesture != null && _gesture.IdleClips != null && _gesture.IdleClips.Count > 0)
                {
                    if (Time.time >= nextIdleAt)
                    {
                        var idles = _gesture.IdleClips;
                        string idle = idleRandom ? idles[UnityEngine.Random.Range(0, idles.Count)] : idles[0];
                        Log($"[idle] {(idleRandom ? "random" : "fixed")} idle '{idle}'");
                        // idle is cut short if a message arrives (gen changes) or talking starts
                        yield return _gesture.PlayClip(idle, () => _bodyGen != playedGen || _talking);
                        float gap = UnityEngine.Random.Range(idleGapMin, idleGapMax);
                        nextIdleAt = Time.time + gap;
                        Log($"[idle] next in {gap:0.0}s");
                    }
                }
                yield return null;
            }
        }

        /// <summary>Total spoken seconds in a plan = sum of its face beats' chunk durations (0 if unknown).</summary>
        static float SpeechLengthOf(VoicePlan plan)
        {
            float s = 0f;
            foreach (var b in plan.beats)
                if (!b.IsBody && b.chunks != null)
                    foreach (var c in b.chunks) s += Mathf.Max(0f, c.durationSec);
            return s;
        }

        // ── CAMERA: FACE while talking, BODY otherwise (with a short hold so phrase gaps don't flicker) ──
        IEnumerator CameraDirector()
        {
            bool? logged = null;
            float silentFor = 999f;
            while (true)
            {
                if (_talking) silentFor = 0f; else silentFor += Time.deltaTime;
                bool body = silentFor > bodyReturnDelay; // linger on the face briefly after talk stops
                if (logged != body) { Log($"  [camera] → {(body ? "BODY (idle/gesture)" : "FACE (talking)")}"); logged = body; }
                if (rig != null) rig.StepCameraToward(body, Time.deltaTime, cameraLerpTime);
                yield return null;
            }
        }

        IEnumerator PlayFaceAudio(VoiceBeat beat)
        {
            if (feed == null || beat.chunks == null || beat.chunks.Length == 0) yield break;
            bool drained = false;
            Action onDrained = () => drained = true;
            feed.OnPlaybackDrained += onDrained;
            foreach (var c in beat.chunks) feed.Enqueue(c.url, c.index, c.durationSec);
            while (!drained) yield return null;
            feed.OnPlaybackDrained -= onDrained;
        }
    }
}
