using System.Text;
using Maradel.Content;
using Maradel.Diagnostics;
using Maradel.Face;
using Maradel.UI;
using UnityEngine;
#if ADDRESSABLES
using UnityEngine.AddressableAssets;
using UnityEngine.ResourceManagement.AsyncOperations;
#endif

namespace Maradel.Speech
{
    /// <summary>
    /// Drop this on a Rocketbox <c>*_facial</c> avatar (root) and it AUTO-WIRES the whole talking
    /// head: finds the facial skinned mesh (the one with <c>SR_01</c>), adds an audible AudioSource,
    /// the WAV feed, uLipSync, RocketboxFaceRig, builds the provider+controller, and (optionally)
    /// connects to Maradel. Every step is logged with the <c>[SYNC_BEH]</c> tag so you can grep the
    /// Console to confirm exactly what was found and added.
    ///
    /// Rocketbox layout (explored): the active skinned mesh is <c>&lt;id&gt;_hipoly</c> (e.g.
    /// f001_hipoly); lower-LOD meshes are deactivated by FixRocketboxMaxImport. SR_01..15 = the 15
    /// Oculus visemes. This finds the mesh by blendshape name, so it's avatar-agnostic.
    /// </summary>
    [AddComponentMenu("Maradel/Rocketbox Auto Rig")]
    public sealed class RocketboxAutoRig : MonoBehaviour
    {
        const string TAG = "[SYNC_BEH]";
        const string PrefAvatar = "maradel.lastAvatar";
        const string PrefScale = "maradel.modelScale";
        const string PrefView = "maradel.bodyView";

        [SerializeField] MaradelVoiceConfig config = new();
        [Tooltip("Also add + connect MaradelVoiceSocketClient so Maradel drives the face.")]
        [SerializeField] bool connectToMaradel = true;
        [SerializeField] bool saveIncoming = false;

        [Header("Avatar — auto-loaded REMOTELY via Addressables (label from BuildConfig); ◀/▶ downloads on demand")]
        [Tooltip("Autozoom: auto-frame the head to the camera on every load (from calibration).")]
        [SerializeField] bool frameToCamera = true;
        [Tooltip("Camera offset from the Bip01 Head bone, world space. Calibration avg ≈ (0, 0.076, -2.22).")]
        [SerializeField] Vector3 frameOffset = new Vector3(0f, 0.076f, -2.22f);
        [Tooltip("Camera FOV used for head framing (you converged on ~16).")]
        [SerializeField] float frameFov = 16f;
        [Tooltip("BODY perspective: camera offset from the head bone (from body snapshots ≈ 0,-0.43,-2.22).")]
        [SerializeField] Vector3 frameOffsetBody = new Vector3(0f, -0.43f, -2.22f);
        [Tooltip("BODY perspective FOV (wider, fits the whole avatar — your body snaps used 39).")]
        [SerializeField] float frameFovBody = 39f;
        [Tooltip("Avatar facing so the face points at the camera. Rocketbox face = +Z local; 180° → faces -Z.")]
        [SerializeField] Vector3 avatarFaceEuler = new Vector3(0f, 180f, 0f);
        [Tooltip("Uniform scale applied to the avatar (live-adjustable via the overlay –/+).")]
        [SerializeField] float modelScale = 1f;
        [Tooltip("Anchor bone present on every Rocketbox face — used for camera calibration/autozoom.")]
        [SerializeField] string anchorBoneName = "Bip01 Head";

        [Tooltip("Optional BuildConfig — supplies the 'avatar' label used to enumerate remote avatars.")]
        [SerializeField] BuildConfig buildConfig;

        GameObject _avatar;
        System.Collections.Generic.List<string> _avatarPaths = new(); // Addressable keys
        int _avatarIndex;
        bool _busy;       // a load/download is in flight
        bool _instValid;  // _avatar came from Addressables.InstantiateAsync (release vs Destroy)
        Transform _anchor;          // Bip01 Head on the current avatar
        CameraCalibration _calib;   // saved camera snapshots
        EmotionSequencer _seq;      // plays voice:plan beat sequences
        ExpressionController _expr; // face emotion → AK_/AU_ blendshape expression
#if ADDRESSABLES
        AnimationDirector _anim;    // body emotion → Rocketbox gesture clip
#endif
        System.Collections.Generic.List<string> _folders = new(); // categories (Adults/Children/Professions)
        bool _listOpen;             // browse scroll-list open
        Vector2 _listScroll;
        bool _cacheOpen;            // detailed cache overlay open
        Vector2 _cacheScroll;
        bool _overlayOpen = true;   // whole overlay shown vs collapsed to a small button
        bool _bodyView;             // false = FACE perspective, true = BODY (full-body) perspective
        bool _snapBody;             // Save Camera tags snapshot as "body" (true) or "face" (false)
        int _faceEmoIndex;          // manual-test FACE picker (index into ExpressionController.EmotionIds)
        int _bodyEmoIndex;          // manual-test BODY picker (index into AnimationDirector.EmotionIds)
        bool _readyEmitted;         // fired the Flutter "ready" event once (first avatar wired)
        string _dumpStatus = "";    // status of the last log Dump upload
        string _bridgeMsg = "";     // Unity→Flutter bridge test box
        [System.Serializable] class BridgeText { public string text; }
        string _search = "";        // model search query (live filter + autosuggest)
        string _copyMsg = "";       // transient "copied: <name>" toast
        bool _logOpen;              // bottom log window open
        bool _devOpen;             // "Dev" tools section (testers/calib/cache) open
        Vector2 _logScroll;
        GUIStyle _small;
        Transform _lightsRoot;      // 3-point portrait lighting (created once)
        Light _keyLight, _fillLight, _rimLight;

        // Forward backend speaking state out to Flutter (no-op/log when not embedded).
        static void EmitSpeaking(bool on) =>
            Maradel.Face.FlutterFace.Emit(on ? Maradel.Face.FlutterFace.SpeakingStarted : Maradel.Face.FlutterFace.SpeakingStopped);
        Transform ScaleTarget => _avatar != null ? _avatar.transform : transform;
        string AvatarLabel => buildConfig != null ? buildConfig.avatarLabel : "avatar";

        bool _autoLoaded;

        /// <summary>
        /// Runs automatically when Play starts — if no RocketboxAutoRig is in the scene, create one.
        /// So you press Play and the talking head sets itself up: nothing to drag, nothing to assign.
        /// </summary>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void AutoBootstrap()
        {
            if (FindFirstObjectByType<RocketboxAutoRig>() != null) return; // already set up in the scene
            var go = new GameObject("MaradelFace (auto)");
            go.AddComponent<RocketboxAutoRig>();
            Debug.Log($"{TAG} auto-bootstrap created '{go.name}' — no RocketboxAutoRig was in the scene");
        }

#if ULIPSYNC
        [Tooltip("OPTIONAL override. Leave empty — the rig auto-finds a uLipSync Profile in the " +
                 "project/packages (uLipSync ships sample profiles).")]
        [SerializeField] uLipSync.Profile profile;
#endif

        SkinnedMeshRenderer _face;
        RocketboxFaceRig _rig;
        AudioSource _audio;
        UnityWebRequestAudioFeed _feed;

        // status (shown in the OnGUI overlay)
        string _statusMesh = "—";
        string _statusProfile = "—";
        int _vizFrames;
        GUIStyle _rich;
#if MARADEL_SOCKETIO
        MaradelVoiceSocketClient _sock;
#endif
#if ULIPSYNC
        uLipSync.uLipSync _ulip;
        ULipSyncProvider _provider;
        LipSyncController _controller;
        bool _loggedFirstFrame;
#endif

        static void L(string m, Object ctx) => Debug.Log($"{TAG} {m}", ctx);
        static void W(string m, Object ctx) => Debug.LogWarning($"{TAG} {m}", ctx);

        // Unity-null-safe get-or-add (the '??' operator does NOT respect Unity's fake-null).
        static T Ensure<T>(GameObject go) where T : Component
        {
            var c = go.GetComponent<T>();
            return c != null ? c : go.AddComponent<T>();
        }

        void Awake() => Build();

        [ContextMenu("Auto-Wire Lipsync")]
        public void Build()
        {
            L("=== auto-wire START ===", this);
            _calib ??= CameraCalibration.Load();
            modelScale = PlayerPrefs.GetFloat(PrefScale, modelScale); // restore last prefs (GUI scale is shared in GuiOverlay)
            _bodyView = PlayerPrefs.GetInt(PrefView, 0) == 1;

            ApplyRenderQuality(); // MSAA + anisotropic (close-up face aliases hard at AA 0)
            EnsureLights();       // 3-point portrait lighting (key/fill/rim) so the face isn't flat
            SetupCameraOpaqueBlack(); // clear to OPAQUE black from frame 0 — kills the green/garbage on the embedded Android surface

            // ── one-time infrastructure (audio, feed, analyzer, socket) ──
            _audio = Ensure<AudioSource>(gameObject);
            _audio.playOnAwake = false; _audio.spatialBlend = 0f; _audio.volume = 1f; _audio.mute = false;
            L($"AudioSource ready (2D, vol={_audio.volume})", this);

            _feed = Ensure<UnityWebRequestAudioFeed>(gameObject);
            _feed.SetVerbose(true); _feed.SetSaveIncoming(saveIncoming);
            L("UnityWebRequestAudioFeed ready (verbose on)", this);

#if ULIPSYNC
            _ulip = Ensure<uLipSync.uLipSync>(gameObject);
            if (profile == null) profile = AutoFindProfile();
            if (profile != null)
            {
                _ulip.profile = profile;
                _statusProfile = $"{profile.name} [{PhonemeList(profile)}]";
                L($"uLipSync profile AUTO-FOUND = '{profile.name}' phonemes=[{PhonemeList(profile)}]", this);
            }
            else { _statusProfile = "NOT FOUND"; W("no uLipSync Profile found — is uLipSync installed?", this); }
            if (_provider == null) _provider = new ULipSyncProvider(_ulip);
#else
            _statusProfile = "(ULIPSYNC off)";
            W("ULIPSYNC not defined — analyzer/provider skipped.", this);
#endif

#if MARADEL_SOCKETIO
            if (connectToMaradel)
            {
                _sock = Ensure<MaradelVoiceSocketClient>(gameObject);
                _sock.Configure(config, _feed);

                // emotion/beat sequencer: plays voice:plan beats (face↔body camera, audio on face beats)
                _seq = Ensure<EmotionSequencer>(gameObject);
                _seq.Configure(this, _feed);
                _sock.OnPlan -= _seq.PlayPlan; _sock.OnPlan += _seq.PlayPlan; // idempotent on re-Build
                _sock.OnSpeaking -= EmitSpeaking; _sock.OnSpeaking += EmitSpeaking; // → Flutter speakingStarted/Stopped

                // emotion → visible motion (created once, subscribed once; bound per-avatar in WireFaceRig)
                _expr = Ensure<ExpressionController>(gameObject);
                _seq.OnFaceEmotion -= _expr.SetEmotion; _seq.OnFaceEmotion += _expr.SetEmotion;
#if ADDRESSABLES
                _anim = Ensure<AnimationDirector>(gameObject);
                _seq.SetGesturePlayer(_anim); // sequencer drives + WAITS on the gesture (clip length)
#endif
                L($"Socket + Sequencer + Expression + Gesture controllers wired (host {config.BaseUrl})", this);
            }
#else
            W("MARADEL_SOCKETIO not defined — no socket.", this);
#endif

            // ── avatar: wire an in-scene one, else discover the remote list and load the first ──
            if (HasFacialMesh())
            {
                L("avatar already in hierarchy — wiring it (Left/Right disabled)", this);
                WireFaceRig();
            }
            else
            {
#if ADDRESSABLES
                StartCoroutine(LoadAvatarListThenFirst());
#else
                Debug.LogError($"{TAG} models moved to Addressables — install com.unity.addressables, add the " +
                               "ADDRESSABLES define, run 'Mark Models Addressable' + build content.", this);
#endif
            }

            DumpHierarchy();
            L("=== auto-wire DONE ===", this);
        }

        void OnGUI()
        {
            _rich ??= new GUIStyle(GUI.skin.label) { richText = true };
            _small ??= new GUIStyle(GUI.skin.label) { richText = true, fontSize = 11, wordWrap = false };
            var prev = GuiOverlay.Begin(0.92f); // shared persistent scale

            // collapsed → just a small "show" button
            if (!_overlayOpen)
            {
                GUILayout.BeginArea(new Rect(20, 20, 220, 46), GUI.skin.box);
                if (GUILayout.Button("≡ Maradel", GUILayout.Height(36))) _overlayOpen = true;
                GUILayout.EndArea();
                GuiOverlay.End(prev);
                return;
            }

            bool searching = !string.IsNullOrEmpty(_search);
            bool showList = searching || _listOpen;
            float areaH = 426f
                        + (showList ? 240f : 0f)
                        + (_logOpen ? 200f : 0f)
                        + (_devOpen ? 330f : 0f)
                        + (_devOpen && _cacheOpen ? 250f : 0f);
            GUILayout.BeginArea(new Rect(20, 20, 780, areaH), GUI.skin.box);

            // header: title + close
            GUILayout.BeginHorizontal();
            GUILayout.Label("<b>Maradel · Models</b>", _rich);
            GUILayout.FlexibleSpace();
            if (GUILayout.Button("✕", GUILayout.Width(40), GUILayout.Height(32))) _overlayOpen = false;
            GUILayout.EndHorizontal();

            // GUI scale — large + centered (sizes the whole overlay; easy to hit on the tablet)
            GuiOverlay.ScaleControls(_rich, centered: true);

            // current model + left/right
            int total = _avatarPaths != null ? _avatarPaths.Count : 0;
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("◀", GUILayout.Width(50), GUILayout.Height(40))) PrevAvatar();
            string avName = (total > 0 && _avatar != null)
                ? $"{_avatar.name.Replace("(Clone)", "")}  ({_avatarIndex + 1}/{total})"
                : (_autoLoaded ? _avatar?.name : "loading…");
            GUILayout.Label($"<b>{avName}</b>", _rich);
            GUILayout.FlexibleSpace();
            if (GUILayout.Button("▶", GUILayout.Width(50), GUILayout.Height(40))) NextAvatar();
            GUILayout.EndHorizontal();

            // search + browse toggle
            GUILayout.BeginHorizontal();
            GUILayout.Label("🔍", _rich, GUILayout.Width(22));
            _search = GUILayout.TextField(_search ?? "", GUILayout.Height(28));
            if (GUILayout.Button("✕", GUILayout.Width(30), GUILayout.Height(28))) { _search = ""; GUI.FocusControl(null); }
            if (GUILayout.Button(_listOpen ? "Hide ▲" : "Browse ▼", GUILayout.Width(110), GUILayout.Height(28))) _listOpen = !_listOpen;
            GUILayout.EndHorizontal();
            if (!string.IsNullOrEmpty(_copyMsg)) GUILayout.Label($"<color=#7CFC00>{_copyMsg}</color>", _small);

            // suggestions (when typing) OR full category list (Browse) — each row: load + copy-name
            if (showList && total > 0)
            {
                string q = _search.ToLowerInvariant();
                _listScroll = GUILayout.BeginScrollView(_listScroll, GUILayout.Height(230f));
                string lastCat = null;
                int shown = 0;
                for (int i = 0; i < total; i++)
                {
                    string file = System.IO.Path.GetFileName(_avatarPaths[i]);
                    if (searching && file.ToLowerInvariant().IndexOf(q) < 0) continue;
                    if (!searching)
                    {
                        string cat = CategoryOfKey(_avatarPaths[i]);
                        if (cat != lastCat) { GUILayout.Label($"<b>— {cat} —</b>", _rich); lastCat = cat; }
                    }
                    GUILayout.BeginHorizontal();
                    string mark = i == _avatarIndex ? "<color=#7CFC00>● </color>" : "";
                    if (GUILayout.Button($"{mark}{file}", GUILayout.Height(26))) { LoadAvatarAt(i); _listOpen = false; _search = ""; GUI.FocusControl(null); }
                    if (GUILayout.Button("⧉", GUILayout.Width(36), GUILayout.Height(26))) CopyName(file); // copy name to clipboard
                    GUILayout.EndHorizontal();
                    if (++shown >= 500) break;
                }
                if (shown == 0) GUILayout.Label("<color=#9aa>no matches</color>", _rich);
                GUILayout.EndScrollView();
            }

            // perspective + scale
            GUILayout.BeginHorizontal();
            GUILayout.Label($"view <b>{(_bodyView ? "BODY" : "FACE")}</b>", _rich, GUILayout.Width(96));
            if (GUILayout.Button(_bodyView ? "→ FACE" : "→ BODY", GUILayout.Width(96), GUILayout.Height(28))) SetPerspective(!_bodyView);
            GUILayout.Label($"scale x{modelScale:0.00}", _rich, GUILayout.Width(96));
            if (GUILayout.Button("–", GUILayout.Width(34), GUILayout.Height(28))) SetModelScale(modelScale * 0.8f);
            if (GUILayout.Button("+", GUILayout.Width(34), GUILayout.Height(28))) SetModelScale(modelScale * 1.25f);
            if (GUILayout.Button("reset", GUILayout.Width(60), GUILayout.Height(28))) SetModelScale(1f);
            GUILayout.EndHorizontal();

            // download status
            if (DownloadProgress.Active)
                GuiOverlay.ProgressBar($"{DownloadProgress.Label}  {DownloadProgress.SizeText}", DownloadProgress.Value01);

            // compact status line
            string meshCol = _face != null ? "#7CFC00" : "#FF4040";
            string sock = "(no socket)";
#if MARADEL_SOCKETIO
            if (_sock != null) sock = _sock.State + (_sock.IsSpeaking ? " <color=#7CFC00>●</color>" : "");
#endif
            GUILayout.Label($"<size=11>mesh <color={meshCol}>{(_face != null ? "ok" : "none")}</color> · profile {_statusProfile} · socket {sock} · viz {_vizFrames}</size>", _rich);

            // actions: Send Logs · Log window · Dev tools
            GUILayout.BeginHorizontal();
            if (GUILayout.Button("📤 Send Logs", GUILayout.Height(30))) DumpLog();
            if (GUILayout.Button(_logOpen ? "Log ▲" : "Log ▼", GUILayout.Width(90), GUILayout.Height(30))) _logOpen = !_logOpen;
            if (GUILayout.Button(_devOpen ? "Dev ▲" : "Dev ▼", GUILayout.Width(90), GUILayout.Height(30))) _devOpen = !_devOpen;
            GUILayout.EndHorizontal();
            if (!string.IsNullOrEmpty(_dumpStatus)) GUILayout.Label($"<size=11><color=#9cf>{_dumpStatus}</color></size>", _rich);

            if (_devOpen) DrawDevTools();

            // bottom log window — live tail of the session log
            if (_logOpen)
            {
                _logScroll = GUILayout.BeginScrollView(_logScroll, GUILayout.Height(190f));
                var tail = SessionLog.Tail();
                for (int i = tail.Length - 1; i >= 0; i--) GUILayout.Label(tail[i], _small); // newest first
                GUILayout.EndScrollView();
            }

            GUILayout.EndArea();
            GuiOverlay.End(prev);
        }

        /// <summary>Copy a model's name to the system clipboard (for the per-row ⧉ button).</summary>
        void CopyName(string n) { GUIUtility.systemCopyBuffer = n; _copyMsg = $"copied: {n}"; L($"copied to clipboard: {n}", this); }

        /// <summary>Dev/diagnostic tools, collapsed behind the "Dev" toggle so the main overlay stays a
        /// clean model browser: emotion testers, body/idle tuning, camera calibration, cache.</summary>
        void DrawDevTools()
        {
            // Unity→Flutter bridge test: type a string, Send → Flutter (shows in Flutter's console log).
            GUILayout.BeginHorizontal();
            GUILayout.Label("<b>→Flutter</b>", _rich, GUILayout.Width(74));
            _bridgeMsg = GUILayout.TextField(_bridgeMsg ?? "", GUILayout.Height(28));
            if (GUILayout.Button("Send", GUILayout.Width(70), GUILayout.Height(28)))
            {
                var t = (_bridgeMsg ?? "").Trim();
                if (t.Length > 0)
                {
                    Maradel.Bridge.FlutterControlBridge.Emit("bridge", new BridgeText { text = t });
                    Debug.Log($"[BRIDGE] -> flutter: {t}");
                }
            }
            GUILayout.EndHorizontal();

            if (GUILayout.Button("▶ Test Plan", GUILayout.Height(28))) TestEmotionPlan();

            var faceEmos = Face.ExpressionController.EmotionIds;
            if (faceEmos != null && faceEmos.Length > 0)
            {
                if (_faceEmoIndex < 0 || _faceEmoIndex >= faceEmos.Length) _faceEmoIndex = 0;
                GUILayout.BeginHorizontal();
                GUILayout.Label("<b>FACE</b>", _rich, GUILayout.Width(54));
                if (GUILayout.Button("◀", GUILayout.Width(36), GUILayout.Height(28))) _faceEmoIndex = (_faceEmoIndex - 1 + faceEmos.Length) % faceEmos.Length;
                GUILayout.Label($"<b>{faceEmos[_faceEmoIndex]}</b> ({_faceEmoIndex + 1}/{faceEmos.Length})", _rich, GUILayout.Width(190));
                if (GUILayout.Button("▶", GUILayout.Width(36), GUILayout.Height(28))) _faceEmoIndex = (_faceEmoIndex + 1) % faceEmos.Length;
                if (GUILayout.Button("▶ talk", GUILayout.Height(28))) TestSingleEmotion(faceEmos[_faceEmoIndex], false);
                GUILayout.EndHorizontal();
            }
#if ADDRESSABLES
            var bodyEmos = AnimationDirector.EmotionIds;
            if (bodyEmos != null && bodyEmos.Length > 0)
            {
                if (_bodyEmoIndex < 0 || _bodyEmoIndex >= bodyEmos.Length) _bodyEmoIndex = 0;
                string be = bodyEmos[_bodyEmoIndex];
                GUILayout.BeginHorizontal();
                GUILayout.Label("<b>BODY</b>", _rich, GUILayout.Width(54));
                if (GUILayout.Button("◀", GUILayout.Width(36), GUILayout.Height(28))) _bodyEmoIndex = (_bodyEmoIndex - 1 + bodyEmos.Length) % bodyEmos.Length;
                string beClip = _anim != null ? _anim.GenderedClip(be) : be;
                GUILayout.Label($"<b>{be}</b> <color=#9aa>→ {beClip}</color>", _rich, GUILayout.Width(330));
                if (GUILayout.Button("▶", GUILayout.Width(36), GUILayout.Height(28))) _bodyEmoIndex = (_bodyEmoIndex + 1) % bodyEmos.Length;
                if (GUILayout.Button("▶ gesture", GUILayout.Height(28))) TestSingleEmotion(be, true);
                GUILayout.EndHorizontal();
            }
            if (_seq != null)
            {
                GUILayout.BeginHorizontal();
                GUILayout.Label($"body ≤ speech +<b>{_seq.BodyOverhangPct * 100:0}%</b>", _rich, GUILayout.Width(150));
                if (GUILayout.Button("–", GUILayout.Width(34), GUILayout.Height(26))) _seq.BodyOverhangPct -= 0.05f;
                if (GUILayout.Button("+", GUILayout.Width(34), GUILayout.Height(26))) _seq.BodyOverhangPct += 0.05f;
                GUILayout.Space(14);
                if (GUILayout.Button(_seq.IdleEnabled ? "idle: ON" : "idle: OFF", GUILayout.Width(86), GUILayout.Height(26))) _seq.IdleEnabled = !_seq.IdleEnabled;
                if (GUILayout.Button(_seq.IdleRandom ? "random" : "only first", GUILayout.Width(92), GUILayout.Height(26))) _seq.IdleRandom = !_seq.IdleRandom;
                GUILayout.EndHorizontal();
            }
#endif
            // camera calibration
            GUILayout.BeginHorizontal();
            string anchorTxt = _anchor != null ? "<color=#7CFC00>head ok</color>" : "<color=#FF4040>no head</color>";
            GUILayout.Label($"anchor {anchorTxt} · saved {(_calib != null ? _calib.snapshots.Count : 0)}", _rich, GUILayout.Width(230));
            if (GUILayout.Button(_snapBody ? "kind: BODY" : "kind: FACE", GUILayout.Width(110), GUILayout.Height(28))) _snapBody = !_snapBody;
            if (GUILayout.Button("📷 Save Camera", GUILayout.Height(28))) SaveCameraSnapshot();
            GUILayout.EndHorizontal();

            // cache
            GUILayout.BeginHorizontal();
            if (GUILayout.Button(_cacheOpen ? "Cache ▲" : "Cache ▼", GUILayout.Width(110), GUILayout.Height(28))) _cacheOpen = !_cacheOpen;
            GUILayout.Label($"<size=11>cache {CacheLog.CacheUsedBytes / (1024 * 1024f):0.1} MB used</size>", _rich);
            GUILayout.EndHorizontal();
            if (_cacheOpen)
            {
                _cacheScroll = GUILayout.BeginScrollView(_cacheScroll, GUILayout.Height(210));
                var recent = CacheLog.Recent;
                for (int i = recent.Count - 1; i >= 0; i--) GUILayout.Label(recent[i], _small);
                GUILayout.EndScrollView();
            }
        }

        public void SetModelScale(float s)
        {
            modelScale = Mathf.Max(0.01f, s);
            ScaleTarget.localScale = Vector3.one * modelScale;
            PlayerPrefs.SetFloat(PrefScale, modelScale); PlayerPrefs.Save();
            L($"model scale = {modelScale:0.00}", this);
        }

        /// <summary>Show/hide the current avatar (Flutter control "show"/"hide").</summary>
        public void SetVisible(bool visible)
        {
            if (_avatar != null) _avatar.SetActive(visible);
            L($"avatar visible = {visible}", this);
        }

        /// <summary>Capture the current camera framing of this avatar's head bone → calibration JSON.
        /// Scroll to an avatar, frame it nicely in the Game view, hit Save. Builds the autozoom dataset.</summary>
        public void SaveCameraSnapshot()
        {
            var cam = Camera.main;
            if (cam == null) { Debug.LogWarning($"{TAG} Save Camera: no Main Camera.", this); return; }
            if (_anchor == null) { Debug.LogWarning($"{TAG} Save Camera: no '{anchorBoneName}' bone on avatar.", this); return; }

            _calib ??= CameraCalibration.Load();
            var vp = cam.WorldToViewportPoint(_anchor.position);
            float baseY = _avatar != null ? _avatar.transform.position.y : transform.position.y; // feet/floor
            var snap = new CameraSnapshot
            {
                avatar = _avatar != null ? _avatar.name.Replace("(Clone)", "") : name,
                kind = _snapBody ? "body" : "face",
                modelScale = modelScale,
                characterHeight = _face != null ? _face.bounds.size.y : 0f,
                headHeightAboveFloor = _anchor.position.y - baseY, // LONG leg: head → floor
                fov = cam.fieldOfView,
                camDistance = Vector3.Distance(cam.transform.position, _anchor.position),
                headWorldPos = _anchor.position,
                camPos = cam.transform.position,
                camEuler = cam.transform.eulerAngles,
                headViewport = new Vector2(vp.x, vp.y),
            };
            _calib.snapshots.Add(snap);
            _calib.Save();
            L($"SAVED camera #{_calib.snapshots.Count}: {snap.avatar} headH(longLeg)={snap.headHeightAboveFloor:0.00} " +
              $"fov={snap.fov:0} dist(shortLeg)={snap.camDistance:0.00} vp=({vp.x:0.00},{vp.y:0.00})", this);
        }

        /// <summary>Log a full inventory of the instantiated hierarchy so we can SEE what was
        /// discovered (skinned meshes, blendshapes, skeleton root, pre-existing components).</summary>
        void DumpHierarchy()
        {
            var sb = new StringBuilder($"hierarchy scan of '{name}':\n");

            var smrs = GetComponentsInChildren<SkinnedMeshRenderer>(true);
            sb.AppendLine($"  SkinnedMeshRenderers: {smrs.Length}");
            foreach (var r in smrs)
            {
                var m = r.sharedMesh;
                int bs = m != null ? m.blendShapeCount : 0;
                bool hasViseme = false;
                for (int i = 0; i < bs; i++)
                    if (m.GetBlendShapeName(i).IndexOf("AA_VI_", System.StringComparison.OrdinalIgnoreCase) >= 0) { hasViseme = true; break; }
                sb.AppendLine($"    - '{Path(r.transform)}' active={r.gameObject.activeInHierarchy} " +
                              $"enabled={r.enabled} blendshapes={bs} hasViseme={hasViseme}");
                if (bs > 0)
                {
                    var names = new System.Collections.Generic.List<string>(bs);
                    for (int i = 0; i < bs; i++) names.Add($"{i}:{m.GetBlendShapeName(i)}");
                    sb.AppendLine("      shapes: " + string.Join(" | ", names));
                }
            }

            var skel = FindDeep(transform, "Bip01") ?? FindDeep(transform, "Bip02");
            sb.AppendLine($"  skeleton root: {(skel != null ? Path(skel) : "NOT FOUND")}");
            sb.AppendLine($"  existing AudioSource={GetComponent<AudioSource>() != null} " +
                          $"uLipSync={(GetComponentInChildren<MonoBehaviour>() != null && HasULipSync())} " +
                          $"RocketboxFaceRig={GetComponentInChildren<RocketboxFaceRig>() != null}");
            L(sb.ToString(), this);
        }

        bool HasULipSync()
        {
#if ULIPSYNC
            return GetComponent<uLipSync.uLipSync>() != null;
#else
            return false;
#endif
        }

        static Transform FindDeep(Transform root, string name)
        {
            if (root.name == name) return root;
            for (int i = 0; i < root.childCount; i++)
            {
                var r = FindDeep(root.GetChild(i), name);
                if (r != null) return r;
            }
            return null;
        }

#if ULIPSYNC
        static string PhonemeList(uLipSync.Profile p)
        {
            if (p.mfccs == null || p.mfccs.Count == 0) return "NONE";
            var names = new System.Collections.Generic.List<string>();
            foreach (var m in p.mfccs) names.Add(m.name);
            return string.Join(",", names);
        }

        uLipSync.Profile AutoFindProfile()
        {
#if UNITY_EDITOR
            uLipSync.Profile best = null;
            int bestCount = -1;
            foreach (var guid in UnityEditor.AssetDatabase.FindAssets("t:Profile"))
            {
                var path = UnityEditor.AssetDatabase.GUIDToAssetPath(guid);
                var p = UnityEditor.AssetDatabase.LoadAssetAtPath<uLipSync.Profile>(path);
                if (p == null) continue; // not a uLipSync Profile
                int c = p.mfccs != null ? p.mfccs.Count : 0;
                L($"  profile candidate '{p.name}' phonemes={c} @ {path}", this);
                // prefer the most-trained profile; tie-break toward the generic "Sample" one
                if (c > bestCount || (c == bestCount && p.name.Contains("Sample")))
                { bestCount = c; best = p; }
            }
            return best;
#else
            var all = Resources.LoadAll<uLipSync.Profile>(""); // build: drop a profile under Resources/
            return (all != null && all.Length > 0) ? all[0] : null;
#endif
        }
#endif

        // ── avatar switching (◀ / ▶) — remote, download-on-demand ──
        public void NextAvatar() { if (!_busy) LoadAvatarAt(_avatarIndex + 1); }
        public void PrevAvatar() { if (!_busy) LoadAvatarAt(_avatarIndex - 1); }

        // ── folder/group navigation (Adults / Children / Professions) ──
        static string CategoryOfKey(string key)
        {
            if (key.IndexOf("_Adult_", System.StringComparison.OrdinalIgnoreCase) >= 0) return "Adults";
            if (key.IndexOf("_Child_", System.StringComparison.OrdinalIgnoreCase) >= 0) return "Children";
            return "Professions";
        }

        string CurrentFolder =>
            _avatarPaths != null && _avatarPaths.Count > 0 ? CategoryOfKey(_avatarPaths[_avatarIndex]) : "—";

        public void NextFolder() => JumpFolder(+1);
        public void PrevFolder() => JumpFolder(-1);

        void JumpFolder(int dir)
        {
            if (_busy || _folders.Count == 0) return;
            int fi = _folders.IndexOf(CurrentFolder);
            fi = ((fi + dir) % _folders.Count + _folders.Count) % _folders.Count;
            string target = _folders[fi];
            for (int i = 0; i < _avatarPaths.Count; i++)
                if (CategoryOfKey(_avatarPaths[i]) == target) { LoadAvatarAt(i); return; }
        }

        public void LoadAvatarAt(int index)
        {
#if ADDRESSABLES
            if (_busy) { L("busy — ignoring load (avoids concurrent spawns)", this); return; }
            if (isActiveAndEnabled) StartCoroutine(LoadAvatarRoutine(index));
#else
            Debug.LogError($"{TAG} Addressables not enabled — can't load avatars.", this);
#endif
        }

        // ── skin browser bridge (Flutter asks get_skins → we reply; set_skin loads by real name) ──
        [System.Serializable] public class SkinList { public SkinCategory[] categories; }
        [System.Serializable] public class SkinCategory { public string name; public string[] skins; }

        /// <summary>Reply to Flutter with the available skins grouped by category (real file names).</summary>
        public void SendSkins()
        {
#if ADDRESSABLES
            var cats = new System.Collections.Generic.List<SkinCategory>();
            if (_folders != null && _avatarPaths != null)
            {
                foreach (var folder in _folders)
                {
                    var skins = new System.Collections.Generic.List<string>();
                    foreach (var k in _avatarPaths)
                        if (CategoryOfKey(k) == folder) skins.Add(System.IO.Path.GetFileName(k));
                    cats.Add(new SkinCategory { name = folder, skins = skins.ToArray() });
                }
            }
            Maradel.Bridge.FlutterControlBridge.Emit("skins", new SkinList { categories = cats.ToArray() });
            Debug.Log($"[BRIDGE] -> flutter: skins ({(_avatarPaths?.Count ?? 0)} skins in {cats.Count} categories)", this);
#else
            Debug.LogWarning("[BRIDGE] get_skins: Addressables not enabled");
#endif
        }

        /// <summary>Load the skin whose real (file) name matches <paramref name="name"/>.</summary>
        public void SetSkinByName(string name)
        {
#if ADDRESSABLES
            if (string.IsNullOrEmpty(name) || _avatarPaths == null) return;
            for (int i = 0; i < _avatarPaths.Count; i++)
            {
                if (string.Equals(System.IO.Path.GetFileName(_avatarPaths[i]), name, System.StringComparison.OrdinalIgnoreCase) ||
                    string.Equals(_avatarPaths[i], name, System.StringComparison.OrdinalIgnoreCase))
                { L($"set_skin '{name}' → index {i}", this); LoadAvatarAt(i); return; }
            }
            Debug.LogWarning($"[BRIDGE] set_skin: no skin matching '{name}'", this);
#endif
        }

#if ADDRESSABLES
        System.Collections.IEnumerator LoadAvatarListThenFirst()
        {
            var locs = Addressables.LoadResourceLocationsAsync(AvatarLabel, typeof(GameObject));
            yield return locs;

            _avatarPaths = new System.Collections.Generic.List<string>();
            if (locs.Status == AsyncOperationStatus.Succeeded && locs.Result != null)
                foreach (var l in locs.Result)
                    if (!_avatarPaths.Contains(l.PrimaryKey)) _avatarPaths.Add(l.PrimaryKey);
            _avatarPaths.Sort(System.StringComparer.OrdinalIgnoreCase);
            Addressables.Release(locs);

            // group into folders by name (Adults / Children / Professions)
            _folders.Clear();
            foreach (var k in _avatarPaths)
            {
                var c = CategoryOfKey(k);
                if (!_folders.Contains(c)) _folders.Add(c);
            }
            _folders.Sort(System.StringComparer.OrdinalIgnoreCase);

            L($"discovered {_avatarPaths.Count} remote avatars in {_folders.Count} folders (label '{AvatarLabel}')", this);
            if (_avatarPaths.Count > 0)
            {
                int start = 0;
                string last = PlayerPrefs.GetString(PrefAvatar, "");
                if (!string.IsNullOrEmpty(last)) { int i = _avatarPaths.IndexOf(last); if (i >= 0) { start = i; L($"restoring last avatar '{last}'", this); } }
                yield return LoadAvatarRoutine(start);
            }
            else Debug.LogError($"{TAG} no avatars labeled '{AvatarLabel}'. Run 'Mark Models Addressable' + build content.", this);
        }

        System.Collections.IEnumerator LoadAvatarRoutine(int index)
        {
            if (_avatarPaths == null || _avatarPaths.Count == 0) { Debug.LogError($"{TAG} no avatars discovered.", this); yield break; }
            _busy = true;
            var _loadSw = System.Diagnostics.Stopwatch.StartNew();
            _avatarIndex = ((index % _avatarPaths.Count) + _avatarPaths.Count) % _avatarPaths.Count;
            string key = _avatarPaths[_avatarIndex];
            string shortName = System.IO.Path.GetFileName(key);

            // download-on-demand with progress (no-op if already cached)
            var sizeOp = Addressables.GetDownloadSizeAsync(key);
            yield return sizeOp;
            long bytes = sizeOp.Status == AsyncOperationStatus.Succeeded ? sizeOp.Result : 0;
            Addressables.Release(sizeOp);

            if (bytes > 0)
            {
                L($"downloading '{shortName}' ({bytes / (1024 * 1024f):0.0} MB)", this);
                CacheLog.Log($"download '{shortName}' — {bytes / (1024 * 1024f):0.1} MB (not cached)");
                DownloadProgress.Begin($"Downloading {shortName}");
                var dl = Addressables.DownloadDependenciesAsync(key, false);
                while (!dl.IsDone)
                {
                    var s = dl.GetDownloadStatus();
                    DownloadProgress.Report(s.Percent, s.DownloadedBytes, s.TotalBytes);
                    yield return null;
                }
                bool ok = dl.Status == AsyncOperationStatus.Succeeded;
                if (!ok) { Debug.LogError($"{TAG} download FAILED for '{key}':\n  " + RemoteAvatars.BundleErrorReason(dl), this); CacheLog.Log($"download FAILED '{shortName}'"); }
                Addressables.Release(dl);
                DownloadProgress.End();
                if (!ok) { _busy = false; yield break; }
                CacheLog.LogCacheState($"cached '{shortName}'");
            }
            else CacheLog.Log($"'{shortName}' already cached (0 to download)");

            // remove EVERY existing avatar under the mount — not just the tracked one — so a leftover
            // from a concurrent load / domain-reload re-run can never leave "two standing".
            for (int c = transform.childCount - 1; c >= 0; c--)
            {
                var child = transform.GetChild(c).gameObject;
                if (_instValid && child == _avatar) Addressables.ReleaseInstance(child);
                else Destroy(child);
            }
            _avatar = null; _instValid = false;

            var inst = Addressables.InstantiateAsync(key, transform);
            yield return inst;
            if (inst.Status != AsyncOperationStatus.Succeeded || inst.Result == null)
            {
                Debug.LogError($"{TAG} instantiate FAILED for '{key}':\n  " + RemoteAvatars.BundleErrorReason(inst), this);
                _busy = false; yield break;
            }

            _avatar = inst.Result;
            _instValid = true;
            _avatar.transform.localPosition = Vector3.zero;
            _avatar.transform.localRotation = Quaternion.identity;
            _avatar.transform.localScale = Vector3.one * modelScale;
            _autoLoaded = true;
            PlayerPrefs.SetString(PrefAvatar, key); PlayerPrefs.Save(); // remember last picked
            L($"AVATAR [{_avatarIndex + 1}/{_avatarPaths.Count}] '{shortName}' (scale {modelScale:0.00})", this);

            WireFaceRig();                       // sets _face, _rig, _anchor, controller
            if (frameToCamera) AutoFrameHead();  // autozoom — moves the CAMERA (no avatar drift)
            _loadSw.Stop();
            Debug.Log($"[Time] avatar '{shortName}' load+wire {_loadSw.ElapsedMilliseconds}ms (download {bytes / (1024 * 1024f):0.1}MB)", this);
            _busy = false;
        }
#endif

        // ── Visual quality (Tier 0/1/2) ─────────────────────────────────────────────────────────────
        /// <summary>Force Camera.main to clear to OPAQUE black immediately. On the embedded Android surface
        /// an un-cleared / alpha&lt;1 framebuffer shows as a green tint (uninitialised GPU memory / the
        /// driver's default clear). Opaque black from frame 0 (before any avatar loads) keeps it clean.</summary>
        void SetupCameraOpaqueBlack()
        {
            var cam = Camera.main;
            if (cam == null) { L("SetupCameraOpaqueBlack: no Camera.main yet", this); return; }
            cam.clearFlags = CameraClearFlags.SolidColor;
            cam.backgroundColor = new Color(0f, 0f, 0f, 1f); // alpha 1 = opaque — the key bit vs the green garbage
            cam.allowMSAA = true;
            L("camera → opaque black clear (kills green on embedded surface)", this);
        }

        /// <summary>Crank per-pixel quality — it's ONE framed model, so the GPU has budget to burn even on
        /// an old tablet. Generous but sane: no HDRP, no heavy full-screen post; just MSAA, all lights
        /// per-pixel, crisp shadows over a tiny distance, and full-resolution skin textures.</summary>
        void ApplyRenderQuality()
        {
            QualitySettings.antiAliasing = 4;                                   // 4x MSAA (sane max for Adreno; smooth silhouette)
            QualitySettings.anisotropicFiltering = AnisotropicFiltering.ForceEnable;
            QualitySettings.pixelLightCount = 4;                                // key+fill+rim all PER-PIXEL — trivial for one model
            QualitySettings.globalTextureMipmapLimit = 0;                       // full-res skin textures, never downscaled
            QualitySettings.shadows = ShadowQuality.All;                        // hard + soft
            QualitySettings.shadowResolution = ShadowResolution.VeryHigh;       // crisp — we only shadow one head
            QualitySettings.shadowProjection = ShadowProjection.StableFit;      // StableFit (not CloseFit) → no shadow shimmer when the camera lerps / avatar gestures
            QualitySettings.shadowCascades = 0;                                 // single close model → no cascades
            QualitySettings.shadowDistance = 6f;                                // tiny scene → very high shadowmap density
            QualitySettings.shadowNearPlaneOffset = 1f;
            L("render quality: MSAA 4x, 4 per-pixel lights, full-res textures, VeryHigh close-fit shadows @6m", this);
        }

        /// <summary>Create a 3-point portrait light rig once (key + fill + rim) and a soft cool ambient,
        /// so the face has shape and edge separation instead of one flat key light.</summary>
        void EnsureLights()
        {
            if (_lightsRoot != null) return;

            // turn off any pre-existing directional light (the scene's default key) so it doesn't
            // double up with our rig — we own the lighting from here.
            foreach (var existing in FindObjectsByType<Light>(FindObjectsInactive.Exclude, FindObjectsSortMode.None))
                if (existing.type == LightType.Directional) { existing.enabled = false; L($"disabled pre-existing light '{existing.name}'", this); }

            var root = new GameObject("MaradelLights");
            root.transform.SetParent(transform, false);
            _lightsRoot = root.transform;

            _keyLight  = MakeLight("Key",  new Color(1.00f, 0.96f, 0.88f), 1.10f, LightShadows.Soft);
            _fillLight = MakeLight("Fill", new Color(0.82f, 0.87f, 1.00f), 0.40f, LightShadows.None);
            _rimLight  = MakeLight("Rim",  new Color(0.90f, 0.95f, 1.00f), 1.00f, LightShadows.None); // moderate → no blowout on the rim

            // ONLY the key casts shadows (avoids multi-light shadow weirdness); bias tuned against acne on the skinned mesh
            _keyLight.shadowBias = 0.04f;
            _keyLight.shadowNormalBias = 0.5f;

            // deterministic ambient/reflections — don't rely on the scene's skybox/GI (which may differ when embedded)
            RenderSettings.ambientMode = UnityEngine.Rendering.AmbientMode.Flat;
            RenderSettings.ambientLight = new Color(0.17f, 0.19f, 0.24f); // soft cool fill so shadows aren't crushed black
            RenderSettings.reflectionIntensity = 0.35f;                  // tame env reflection so the skybox doesn't show in glossy eyes
            L("3-point lights (key shadows only) + flat ambient + tamed reflections", this);
        }

        Light MakeLight(string name, Color color, float intensity, LightShadows shadows)
        {
            var go = new GameObject("Light_" + name);
            go.transform.SetParent(_lightsRoot, false);
            var l = go.AddComponent<Light>();
            l.type = LightType.Directional;
            l.color = color;
            l.intensity = intensity;
            l.shadows = shadows;
            l.shadowStrength = 0.55f;
            l.renderMode = LightRenderMode.ForcePixel;      // per-pixel (we have the budget for one model)
            return l;                                       // (new Lights default to Realtime mode — no need to set it)
        }

        /// <summary>Aim the 3 lights at the head so the framing is flattering regardless of avatar height.
        /// Directional light position is irrelevant — LookAt only sets the shine direction.</summary>
        void AimLights(Vector3 head)
        {
            if (_lightsRoot == null) return;
            Aim(_keyLight,  head + new Vector3(-0.7f, 0.9f, -1.4f), head); // key: camera-side, upper-left
            Aim(_fillLight, head + new Vector3( 1.1f, 0.25f, -1.1f), head); // fill: opposite, low, dim, cool
            Aim(_rimLight,  head + new Vector3( 0.25f, 1.1f, 1.6f), head); // rim: behind+above → edge light
        }

        static void Aim(Light l, Vector3 from, Vector3 target)
        {
            if (l == null) return;
            l.transform.position = from;
            l.transform.LookAt(target);
        }

        /// <summary>Wire the supplied normal/specular maps to actually shade the skin: enable the normal-map
        /// keyword where a bump map is present, give skin a sensible smoothness, and kill metallic. The
        /// Rocketbox textures are great; the auto-FBX materials just weren't using them.</summary>
        void ImproveSkinMaterials()
        {
            if (_avatar == null) return;
            int tuned = 0;
            foreach (var smr in _avatar.GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                // a runtime/skinned avatar can't be lightmapped — but it CAN sample scene probes:
                // light probes (baked indirect) + a reflection probe (env spec on eyes/skin/teeth).
                smr.lightProbeUsage = UnityEngine.Rendering.LightProbeUsage.BlendProbes;
                smr.reflectionProbeUsage = UnityEngine.Rendering.ReflectionProbeUsage.BlendProbes;

                var mats = smr.materials; // live per-renderer instances
                for (int i = 0; i < mats.Length; i++)
                {
                    var m = mats[i];
                    if (m == null) continue;
                    if (m.HasProperty("_BumpMap") && m.GetTexture("_BumpMap") != null) { m.EnableKeyword("_NORMALMAP"); m.SetFloat("_BumpScale", 1f); }
                    if (m.HasProperty("_Metallic")) m.SetFloat("_Metallic", 0f);
                    if (m.HasProperty("_SpecGlossMap") && m.GetTexture("_SpecGlossMap") != null) m.EnableKeyword("_SPECGLOSSMAP");
                    // skin-ish smoothness only on the body/head/skin materials (leave hair/eyes alone)
                    string n = (m.name + " " + smr.name).ToLowerInvariant();
                    if (n.Contains("head") || n.Contains("body") || n.Contains("skin") || n.Contains("face"))
                    {
                        if (m.HasProperty("_Glossiness")) m.SetFloat("_Glossiness", 0.28f);
                        if (m.HasProperty("_Smoothness")) m.SetFloat("_Smoothness", 0.28f);
                    }
                    tuned++;
                }
            }
            L($"skin materials tuned: {tuned} (normal-map keyword on, metallic off, skin smoothness)", this);
        }

        /// <summary>Detect gender from the avatar/mesh NAME (Rocketbox: "Female_*"/"Male_*"). NB: "female"
        /// contains "male", so test "female" first. Defaults to female if undetermined.</summary>
        bool IsMaleAvatar()
        {
            string n = ((_avatar != null ? _avatar.name : "") + " " + (_face != null ? _face.name : "")).ToLowerInvariant();
            if (n.Contains("female")) return false;
            return n.Contains("male"); // "male" without "female" → male
        }

        /// <summary>(Re)find the facial mesh on the current avatar, attach the rig, and rebuild the
        /// controller so the (possibly new) rig is driven. Called on load and on every avatar switch.</summary>
        void WireFaceRig()
        {
            _face = FindFacialMesh();
            _statusMesh = _face != null
                ? $"{_face.name} ({_face.sharedMesh.blendShapeCount} shapes)"
                : "NOT FOUND — no AA_VI_* viseme blendshapes";
            if (_face != null)
            {
                _rig = Ensure<RocketboxFaceRig>(_face.gameObject);
                L($"facial mesh = '{Path(_face.transform)}' rig.IsReady={_rig.IsReady}", _face);
                if (!_readyEmitted) { _readyEmitted = true; Maradel.Face.FlutterFace.Emit(Maradel.Face.FlutterFace.Ready); } // → Flutter "ready"
            }
            else { _rig = null; Debug.LogError($"{TAG} no AA_VI_* facial mesh on this avatar.", this); }

            _anchor = FindDeep(_avatar != null ? _avatar.transform : transform, anchorBoneName);
            if (_anchor == null) L($"anchor bone '{anchorBoneName}' not found on this avatar", this);

            ImproveSkinMaterials(); // wire the normal/spec maps + skin smoothness
            AimLights(_anchor != null ? _anchor.position
                    : (_avatar != null ? _avatar.transform.position + Vector3.up * 1.6f : transform.position)); // point the 3 lights at this head

            // bind the emotion controllers to THIS avatar's mesh + animator
            if (_expr != null) _expr.Configure(_face);
#if ADDRESSABLES
            if (_anim != null)
            {
                Animator anim = _avatar != null ? _avatar.GetComponentInChildren<Animator>() : null;
                if (anim == null && _avatar != null)
                {
                    // Rocketbox FBX imported with rig = None → no Animator. Add a bare one on the avatar
                    // root so Playables can drive the Generic Bip01 clips (no controller/avatar needed).
                    anim = _avatar.AddComponent<Animator>();
                    L("no Animator on avatar — added one for gestures (Generic clips bind by transform path)", _avatar);
                }
                if (anim != null) anim.applyRootMotion = false;
                bool male = IsMaleAvatar();
                _anim.Configure(anim, male);
                L($"gesture animator = {(anim != null ? Path(anim.transform) : "NULL — gestures disabled")}; gender = {(male ? "MALE (m_ clips)" : "FEMALE (f_ clips)")}", this);
            }
#endif

#if ULIPSYNC
            _controller?.Dispose();
            _controller = null;
            _loggedFirstFrame = false;
            if (_rig != null && _provider != null)
            {
                _controller = new LipSyncController(_rig, _provider, _feed);
                _controller.OnSpeakingStarted += () => L("speaking STARTED (audio playing)", this);
                _controller.OnSpeakingStopped += () => L("speaking STOPPED (queue drained)", this);
                _controller.OnVisemeFrame += f =>
                {
                    _vizFrames++;
                    if (_loggedFirstFrame) return;
                    _loggedFirstFrame = true;
                    L($"FIRST viseme frame: dominant={f.Dominant} vol={f.Volume:0.00} → driving blendshapes", this);
                };
                _controller.Initialize();
                L("LipSyncController (re)wired for current avatar", this);
            }
#endif
        }

        /// <summary>AUTOZOOM (from calibration): face the avatar at the camera and snap Camera.main to a
        /// fixed offset from the head bone, so every avatar is framed identically (head = same apparent
        /// size; taller heads just push the camera up). No drift — moves the camera, not the avatar.</summary>
        public void AutoFrameHead()
        {
            var cam = Camera.main;
            if (cam == null) { L("AutoFrameHead: no Main Camera", this); return; }
            if (_avatar != null) _avatar.transform.rotation = Quaternion.Euler(avatarFaceEuler);
            if (_anchor == null) { L("AutoFrameHead: no head bone", this); return; }

            Vector3 off = _bodyView ? frameOffsetBody : frameOffset;
            float fov = _bodyView ? frameFovBody : frameFov;
            cam.transform.position = _anchor.position + off; // read after rotating the avatar
            cam.transform.rotation = Quaternion.identity;
            cam.fieldOfView = fov;
            cam.allowMSAA = true; // let the close-up face use the 4x MSAA we enabled
            cam.clearFlags = CameraClearFlags.SolidColor; cam.backgroundColor = Color.black; // solid black behind the face
            L($"auto-framed [{(_bodyView ? "BODY" : "FACE")}] head @{_anchor.position} → cam {cam.transform.position} fov {fov}", this);
        }

        /// <summary>Fire a sample voice:plan (body gesture → talking face) to test the sequence live
        /// without the backend. Camera switches + talks for real; expression/gesture are intent-logged.</summary>
        public void TestEmotionPlan()
        {
            if (_seq == null) { L("TestEmotionPlan: no EmotionSequencer (needs MARADEL_SOCKETIO + connect)", this); return; }
            var plan = new VoicePlan
            {
                sessionId = "test",
                beats = new[]
                {
                    new VoiceBeat { kind = "body", emotion = "excited", durationSec = 2.5f },
                    new VoiceBeat { kind = "face", emotion = "happy", chunks = new[]
                    {
                        new VoiceChunkRef { index = 0, url = config.PreviewUrl("Testing the emotion sequence."), durationSec = 0f }
                    }},
                },
            };
            L("TestEmotionPlan: playing [body:excited → face:happy]", this);
            _seq.PlayPlan(plan);
        }

        /// <summary>Fire a SINGLE emotion through the full sequencer (camera lerp + expression/gesture).
        /// FACE → expression + talk a sample line; BODY → play the gesture and hold for its clip length.</summary>
        public void TestSingleEmotion(string emotion, bool body)
        {
            if (_seq == null) { L("TestSingleEmotion: no EmotionSequencer (needs MARADEL_SOCKETIO + connect)", this); return; }
            var beat = body
                ? new VoiceBeat { kind = "body", emotion = emotion }
                : new VoiceBeat { kind = "face", emotion = emotion, chunks = new[]
                  {
                      new VoiceChunkRef { index = 0, url = config.PreviewUrl($"Testing the {emotion} emotion."), durationSec = 0f }
                  }};
            L($"TestSingleEmotion: playing [{(body ? "body" : "face")}:{emotion}]", this);
            _seq.PlayPlan(new VoicePlan { sessionId = "test", beats = new[] { beat } });
        }

        /// <summary>Upload the current session log file to nukshare (egregor-share API) at
        /// keli/unity/logs/&lt;file&gt;. Uses HttpClient (bypasses Unity's http policy, works on the tablet).</summary>
        public void DumpLog()
        {
            if (!SessionLog.Active) { _dumpStatus = "no session log"; L("DumpLog: no session log", this); return; }
            _dumpStatus = "uploading…";
            _ = UploadLogAsync();
        }

        async System.Threading.Tasks.Task UploadLogAsync()
        {
            // timestamped name so every "Send Logs" is a distinct file on nukshare (no overwrite)
            string baseName = System.IO.Path.GetFileNameWithoutExtension(SessionLog.FileName);
            string device = SystemInfo.deviceModel.Replace(' ', '_').Replace('/', '-');
            string name = $"{baseName}__{device}__{System.DateTime.Now:yyyyMMdd-HHmmss}.log";
            string url = $"http://192.168.0.229:7777/api/shared/keli/logs/{name}"; // same folder as the Flutter logs
            try
            {
                byte[] data = SessionLog.ReadAllBytes();
                using var http = new System.Net.Http.HttpClient { Timeout = System.TimeSpan.FromSeconds(60) };
                var resp = await http.PutAsync(url, new System.Net.Http.ByteArrayContent(data));
                _dumpStatus = resp.IsSuccessStatusCode
                    ? $"saved {data.Length / 1024}KB → keli/logs/{name}"
                    : $"FAILED http {(int)resp.StatusCode}";
            }
            catch (System.Exception e) { _dumpStatus = $"FAILED {e.Message}"; }
            Debug.Log($"[SessionLog] dump → {url} : {_dumpStatus}", this);
        }

        /// <summary>Switch FACE ↔ BODY camera perspective and re-frame immediately (persisted).</summary>
        public void SetPerspective(bool body)
        {
            _bodyView = body;
            PlayerPrefs.SetInt(PrefView, body ? 1 : 0); PlayerPrefs.Save();
            AutoFrameHead();
        }

        /// <summary>LERP Camera.main to the face/body framing over <paramref name="seconds"/> (used by the
        /// sequencer for smooth beat transitions). seconds &lt;= 0 snaps.</summary>
        public System.Collections.IEnumerator LerpFrame(bool body, float seconds)
        {
            var cam = Camera.main;
            _bodyView = body;
            if (_avatar != null) _avatar.transform.rotation = Quaternion.Euler(avatarFaceEuler);
            if (cam == null || _anchor == null) { L("LerpFrame: no camera/anchor", this); yield break; }

            Vector3 tPos = _anchor.position + (body ? frameOffsetBody : frameOffset);
            float tFov = body ? frameFovBody : frameFov;
            Quaternion tRot = Quaternion.identity;

            if (seconds <= 0f)
            {
                cam.transform.SetPositionAndRotation(tPos, tRot); cam.fieldOfView = tFov;
                yield break;
            }

            Vector3 sPos = cam.transform.position; Quaternion sRot = cam.transform.rotation; float sFov = cam.fieldOfView;
            L($"lerp camera → {(body ? "BODY" : "FACE")} over {seconds:0.0}s", this);
            float t = 0f;
            while (t < seconds)
            {
                t += Time.deltaTime;
                float u = Mathf.SmoothStep(0f, 1f, Mathf.Clamp01(t / seconds));
                cam.transform.SetPositionAndRotation(Vector3.Lerp(sPos, tPos, u), Quaternion.Slerp(sRot, tRot, u));
                cam.fieldOfView = Mathf.Lerp(sFov, tFov, u);
                yield return null;
            }
            cam.transform.SetPositionAndRotation(tPos, tRot); cam.fieldOfView = tFov;
            L($"lerp done [{(body ? "BODY" : "FACE")}] cam {tPos} fov {tFov}", this);
        }

        /// <summary>One-frame smooth step of Camera.main toward the face/body framing — INTERRUPTIBLE:
        /// call it every frame with the currently-desired perspective and the camera always heads there,
        /// even if the target flips mid-move (used by the sequencer's camera director). <paramref
        /// name="seconds"/> is the approximate settle time. Returns true once essentially settled.</summary>
        public bool StepCameraToward(bool body, float dt, float seconds)
        {
            var cam = Camera.main;
            _bodyView = body;
            if (_avatar != null) _avatar.transform.rotation = Quaternion.Euler(avatarFaceEuler);
            if (cam == null || _anchor == null) return true;

            Vector3 tPos = _anchor.position + (body ? frameOffsetBody : frameOffset);
            float tFov = body ? frameFovBody : frameFov;

            // exponential smoothing → frame-rate independent, redirects instantly when `body` flips
            float k = seconds <= 0f ? 1f : 1f - Mathf.Exp(-dt / Mathf.Max(0.0001f, seconds * 0.5f));
            cam.transform.position = Vector3.Lerp(cam.transform.position, tPos, k);
            cam.transform.rotation = Quaternion.Slerp(cam.transform.rotation, Quaternion.identity, k);
            cam.fieldOfView = Mathf.Lerp(cam.fieldOfView, tFov, k);
            return (cam.transform.position - tPos).sqrMagnitude < 0.0001f && Mathf.Abs(cam.fieldOfView - tFov) < 0.05f;
        }

        bool HasFacialMesh()
        {
            foreach (var r in GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                var m = r.sharedMesh;
                if (m == null) continue;
                for (int i = 0; i < m.blendShapeCount; i++)
                    if (m.GetBlendShapeName(i).IndexOf("AA_VI_", System.StringComparison.OrdinalIgnoreCase) >= 0) return true;
            }
            return false;
        }

        SkinnedMeshRenderer FindFacialMesh()
        {
            SkinnedMeshRenderer fallback = null;
            foreach (var r in GetComponentsInChildren<SkinnedMeshRenderer>(true))
            {
                var m = r.sharedMesh;
                if (m == null) continue;
                bool hasSR = false;
                for (int i = 0; i < m.blendShapeCount; i++)
                    if (m.GetBlendShapeName(i).IndexOf("AA_VI_", System.StringComparison.OrdinalIgnoreCase) >= 0)
                    { hasSR = true; break; }
                if (!hasSR) continue;

                if (r.gameObject.activeInHierarchy && r.enabled)
                {
                    L($"candidate (ACTIVE): '{Path(r.transform)}'", r);
                    return r; // prefer the visible mesh
                }
                L($"candidate (inactive): '{Path(r.transform)}'", r);
                fallback ??= r;
            }
            return fallback;
        }

        static string Path(Transform t)
        {
            var sb = new StringBuilder(t.name);
            for (var p = t.parent; p != null; p = p.parent) sb.Insert(0, p.name + "/");
            return sb.ToString();
        }
    }
}
