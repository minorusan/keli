#if ADDRESSABLES
using System;
using System.Collections;
using System.Collections.Generic;
using Maradel.Content;
using UnityEngine;
using UnityEngine.AddressableAssets;
using UnityEngine.Animations;
using UnityEngine.Playables;
using UnityEngine.ResourceManagement.AsyncOperations;

namespace Maradel.Speech
{
    /// <summary>
    /// Plays a full-body Rocketbox gesture for an emotion id on the avatar's Animator (Generic rig,
    /// shared Bip01 skeleton → any clip plays on any avatar). Clips are loaded as Addressables
    /// (label "anim"; see AddressableAnimSetup) and played via the Playables API (no controller).
    /// Wired into the EmotionSequencer via <c>SetGesturePlayer</c> (<see cref="IGesturePlayer"/>).
    /// </summary>
    [AddComponentMenu("Maradel/Animation Director")]
    public sealed class AnimationDirector : MonoBehaviour, IGesturePlayer
    {
        // Clips are STEMS (no gender prefix); the avatar's gender prepends "f_" or "m_" at play time.
        // The Rocketbox set has matching f_/m_ variants for every gesture & idle below (verified), EXCEPT
        // "self-assured" which is female-only → MaleStemOverride supplies a male substitute.
        /// <summary>emotion id → gesture clip STEM (gender prefix added per avatar).</summary>
        static readonly Dictionary<string, string> StemByEmotion = new()
        {
            { "neutral",      "gestic_listen_neutral_01" },
            { "happy",        "gestic_listen_accept_01" },
            { "joyful",       "cheer_01" },
            { "excited",      "gestic_listen_excited_01" },
            { "amused",       "gestic_laugh_low" },
            { "playful",      "gestic_talk_cool" },
            { "affectionate", "gestic_listen_accept_02" },
            { "proud",        "gestic_listen_self-assured_01" },
            { "confident",    "gestic_listen_self-assured_01" },
            { "curious",      "gestic_thoughtful_01" },
            { "thoughtful",   "gestic_thoughtful_01" },
            { "focused",      "idle_neutral_01" },
            { "surprised",    "gestic_listen_excited_01" },
            { "impressed",    "claphands_01" },
            { "concerned",    "gestic_listen_nervous_01" },
            { "confused",     "gestic_shrug_01" },
            { "skeptical",    "gestic_listen_deny_01" },
            { "annoyed",      "gestic_listen_angry_01" },
            { "disappointed", "gestic_listen_sad_01" },
            { "sad",          "gestic_listen_sad_01" },
            { "tired",        "idle_yawn_01" },
            { "embarrassed",  "gestic_listen_nervous_01" },
        };

        /// <summary>Stems with no male variant → male substitute (the "self-assured" gesture is female-only).</summary>
        static readonly Dictionary<string, string> MaleStemOverride = new()
        {
            { "proud",     "gestic_listen_accept_01" },
            { "confident", "gestic_listen_accept_01" },
        };

        /// <summary>Curated standing IDLE clip STEMS (subtle near-neutral; f_/m_ both exist for all of these).</summary>
        static readonly string[] IdleStems =
        {
            "idle_neutral_01", "idle_neutral_02", "idle_neutral_03", "idle_neutral_04",
            "idle_neutral_05", "idle_neutral_06",
            "idle_breathe_01", "idle_breathe_02", "idle_breathe_03",
            "idle_look_around_01", "idle_look_around_02", "idle_look_around_03",
            "idle_roll_head_01", "idle_shake_arms_01", "idle_stretch_arms_01",
            "idle_touch_hair_01", "idle_scratch_head_01", "idle_waiting_01",
        };

        /// <summary>All emotion ids that have a body gesture (for UI / testing).</summary>
        public static readonly string[] EmotionIds = new List<string>(StemByEmotion.Keys).ToArray();

        public static string Prefix(bool male) => male ? "m_" : "f_";

        /// <summary>Resolve emotion → gendered clip address (falls back to neutral; male override applied).</summary>
        public static string ClipFor(string emotion, bool male)
        {
            string e = (emotion ?? "").ToLowerInvariant();
            string stem = male && MaleStemOverride.TryGetValue(e, out var mo) ? mo
                        : StemByEmotion.TryGetValue(e, out var s) ? s : StemByEmotion["neutral"];
            return Prefix(male) + stem;
        }

        /// <summary>Every gendered clip address (both f_ and m_) used by gestures + idles — for marking
        /// addressable. Distinct because some emotions share a stem.</summary>
        public static IEnumerable<string> AllClipAddresses()
        {
            var set = new HashSet<string>();
            foreach (var male in new[] { false, true })
            {
                foreach (var e in StemByEmotion.Keys) set.Add(ClipFor(e, male));
                foreach (var s in IdleStems) set.Add(Prefix(male) + s);
            }
            return set;
        }

        [SerializeField] Animator animator;
        bool _male; // false = female (f_ clips), true = male (m_ clips)

        PlayableGraph _graph;
        bool _hasGraph;
        AsyncOperationHandle<AnimationClip> _clip;
        bool _hasClip;
        string[] _idles = BuildIdles(false);

        static string[] BuildIdles(bool male)
        {
            var p = Prefix(male);
            var a = new string[IdleStems.Length];
            for (int i = 0; i < IdleStems.Length; i++) a[i] = p + IdleStems[i];
            return a;
        }

        public IReadOnlyList<string> IdleClips => _idles;

        /// <summary>Gendered clip address for an emotion using THIS avatar's gender (for UI display).</summary>
        public string GenderedClip(string emotion) => ClipFor(emotion, _male);

        public void Configure(Animator a, bool male)
        {
            animator = a;
            if (_male != male || _idles == null) _idles = BuildIdles(male);
            _male = male;
        }

        /// <summary>Play the gesture for an emotion, held for the clip's length but CAPPED at
        /// <paramref name="maxSeconds"/> (≤0 = no cap). Interruptible via <paramref name="cancelled"/>.</summary>
        public IEnumerator PlayAndHold(string emotion, float maxSeconds, Func<bool> cancelled)
            => PlayAddress(ClipFor(emotion, _male), maxSeconds, $"gesture '{emotion}'", cancelled);

        /// <summary>Play an explicit clip address once for its full length (used for idles). Interruptible.</summary>
        public IEnumerator PlayClip(string address, Func<bool> cancelled)
            => PlayAddress(address, 0f, "idle", cancelled);

        /// <summary>Load + play a clip address via Playables and HOLD for min(clip length, cap). Duration is
        /// CALCULATED from the loaded clip. <paramref name="cancelled"/> is polled every frame → cut short.</summary>
        IEnumerator PlayAddress(string addr, float maxSeconds, string why, Func<bool> cancelled)
        {
            if (animator == null) { Debug.LogError("[ANIM] no Animator on the avatar — can't play (avatar FBX rig may be 'None').", this); yield break; }

            Debug.Log($"[ANIM] loading {why} clip '{addr}' …", this);
            var h = Addressables.LoadAssetAsync<AnimationClip>(addr);
            yield return h;
            if (h.Status != AsyncOperationStatus.Succeeded || h.Result == null)
            {
                Debug.LogWarning($"[ANIM] {why} clip '{addr}' failed: {RemoteAvatars.BundleErrorReason(h)}");
                Addressables.Release(h);
                yield break;
            }
            if (animator == null || (cancelled != null && cancelled())) { Addressables.Release(h); yield break; }

            if (_hasGraph) { _graph.Destroy(); _hasGraph = false; }
            AnimationPlayableUtilities.PlayClip(animator, h.Result, out _graph);
            _hasGraph = true;
            float len = h.Result.length;
            float hold = maxSeconds > 0f ? Mathf.Min(len, maxSeconds) : len;
            Debug.Log($"[ANIM] {why} '{addr}' playing — hold {hold:0.0}s (clip {len:0.0}s{(maxSeconds > 0f ? $", cap {maxSeconds:0.0}s" : "")})", this);

            if (_hasClip) Addressables.Release(_clip); // release the previous clip
            _clip = h; _hasClip = true;

            float t = 0f;
            while (t < hold)
            {
                if (cancelled != null && cancelled()) { Debug.Log($"[ANIM] {why} '{addr}' interrupted at {t:0.0}/{hold:0.0}s", this); yield break; }
                t += Time.deltaTime;
                yield return null;
            }
            Debug.Log($"[ANIM] {why} '{addr}' done", this);
        }

        void OnDestroy()
        {
            if (_hasGraph) _graph.Destroy();
            if (_hasClip) Addressables.Release(_clip);
        }
    }
}
#endif
