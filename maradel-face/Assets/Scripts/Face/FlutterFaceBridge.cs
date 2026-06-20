// Inbound entry point for flutter_embed_unity: sendToUnity("FlutterFace","OnMessage", json).
// Guarded on ZENJECT because it resolves LipSyncController via injection.
// Enable: add ZENJECT (and FLUTTER_EMBED_UNITY) to Scripting Define Symbols.
#if ZENJECT
using System;
using UnityEngine;
using Zenject;

namespace Maradel.Face
{
    /// <summary>
    /// The GameObject named "FlutterFace" carries this. It forwards controller events out to
    /// Flutter and routes inbound messages to <see cref="LipSyncController"/>.
    /// </summary>
    public sealed class FlutterFaceBridge : MonoBehaviour
    {
        [Inject] LipSyncController _ctl;

        void Start()
        {
            _ctl.OnReady           += () => FlutterFace.Emit(FlutterFace.Ready);
            _ctl.OnSpeakingStarted += () => FlutterFace.Emit(FlutterFace.SpeakingStarted);
            _ctl.OnSpeakingStopped += () => FlutterFace.Emit(FlutterFace.SpeakingStopped);
        }

        // flutter_embed_unity invokes this by name on the "FlutterFace" GameObject.
        public void OnMessage(string raw)
        {
            FlutterFace.Envelope env;
            try { env = JsonUtility.FromJson<FlutterFace.Envelope>(raw); }
            catch (Exception e) { FlutterFace.Emit(FlutterFace.Error, new Err { message = e.Message }); return; }

            switch (env.type)
            {
                case FlutterFace.PlayChunk:
                {
                    var p = JsonUtility.FromJson<PlayChunkMsg>(env.json);
                    _ctl.PlayChunk(p.url, p.index, p.durationSec);
                    break;
                }
                case FlutterFace.Stop:    _ctl.Stop(); break;
                case FlutterFace.SetMood: _ctl.SetMood(JsonUtility.FromJson<MoodMsg>(env.json).mood); break;
            }
        }

        [Serializable] struct PlayChunkMsg { public string url; public int index; public float durationSec; }
        [Serializable] struct MoodMsg      { public string mood; }
        [Serializable] struct Err          { public string message; }
    }
}
#endif
