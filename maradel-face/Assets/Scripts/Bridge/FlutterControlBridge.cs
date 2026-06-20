using UnityEngine;
using Maradel.Speech;

namespace Maradel.Bridge
{
    /// <summary>
    /// The GameObject named exactly <b>"FlutterFace"</b> carries this. flutter_embed_unity 2.0.0
    /// delivers Flutter→Unity calls as <c>OnMessage(string)</c> on that GameObject; Unity→Flutter is
    /// <c>SendToFlutter.Send(string)</c> (wrapped by <see cref="Maradel.Face.FlutterFace"/>).
    ///
    /// This is the CONTROL channel only (embed/show/hide/face-swap/scale) — voice + lipsync already
    /// arrive independently over the broadcast Socket.IO (see UNITY_HANDOFF §10/§11). Non-Zenject:
    /// it finds the <see cref="RocketboxAutoRig"/> in the scene and drives it.
    ///
    /// Inbound JSON: { "type": "...", "value": 0.0, "index": 0 }
    ///   type = next | prev | load | scale | show | hide
    /// </summary>
    [AddComponentMenu("Maradel/Flutter Control Bridge")]
    public sealed class FlutterControlBridge : MonoBehaviour
    {
        RocketboxAutoRig _rig;

        [System.Serializable]
        struct Msg { public string type; public float value; public int index; public string text; }

        /// <summary>Ensure a "FlutterFace" GameObject with this bridge exists, so the embed package
        /// always has an OnMessage target (inert in the editor / when not embedded).</summary>
        [RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.AfterSceneLoad)]
        static void Bootstrap()
        {
            if (GameObject.Find("FlutterFace") != null) return;
            var go = new GameObject("FlutterFace");
            go.AddComponent<FlutterControlBridge>();
            Debug.Log("[BRIDGE] created 'FlutterFace' GameObject (Flutter↔Unity control target)");
        }

        RocketboxAutoRig Rig => _rig != null ? _rig : (_rig = FindFirstObjectByType<RocketboxAutoRig>());

        // ── flutter_embed_unity calls this by name on the "FlutterFace" GameObject ──
        public void OnMessage(string raw)
        {
            // Bridge test: ALWAYS log what Flutter sent so it's visible in the Unity console, even when
            // it isn't a control message (a plain string typed in the Flutter "Bridge → Unity" tool).
            Debug.Log($"[BRIDGE] <- flutter: {raw}");

            Msg m;
            try { m = JsonUtility.FromJson<Msg>(raw); }
            catch (System.Exception) { return; } // not control JSON — already logged above
            if (string.IsNullOrEmpty(m.type)) return;

            Debug.Log($"[BRIDGE] control: type={m.type} value={m.value} index={m.index}");
            var rig = Rig;
            if (rig == null) { Debug.LogWarning("[BRIDGE] no RocketboxAutoRig in scene to control."); return; }

            switch ((m.type ?? "").ToLowerInvariant())
            {
                case "next":  rig.NextAvatar(); break;
                case "prev":  rig.PrevAvatar(); break;
                case "load":  rig.LoadAvatarAt(m.index); break;
                case "scale": rig.SetModelScale(m.value); break;
                case "show":  rig.SetVisible(true); break;
                case "hide":  rig.SetVisible(false); break;
                case "get_skins": rig.SendSkins(); break;            // Flutter asks → Unity replies with the skin list
                case "set_skin":  rig.SetSkinByName(m.text); break;  // load the skin by its real name
                default:      Debug.LogWarning($"[BRIDGE] unknown control type '{m.type}'"); break;
            }
        }

        /// <summary>Outbound to Flutter (e.g. notify face changed). No-op until the embed package + the
        /// FLUTTER_EMBED_UNITY define are present.</summary>
        public static void Emit(string type, object payload = null) => Maradel.Face.FlutterFace.Emit(type, payload);
    }
}
