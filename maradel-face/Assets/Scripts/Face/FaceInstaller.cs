// Zenject wiring for the Maradel-driven build (Milestones 2–3).
// Guarded on ZENJECT so the project compiles before Extenject is installed.
// Enable: add ZENJECT to Scripting Define Symbols, install Extenject, add this to the SceneContext.
#if ZENJECT
using UnityEngine;
using Zenject;

namespace Maradel.Face
{
    public sealed class FaceInstaller : MonoInstaller
    {
        [Tooltip("Prefab MonoBehaviour implementing IFaceRig (e.g. SkinnedMeshFaceRig).")]
        [SerializeField] MonoBehaviour faceRigComponent;
        [SerializeField] VisemeMap visemeMap;
        [SerializeField] UnityWebRequestAudioFeed audioFeed;

        [Header("Provider — leave uLipSync null to fall back to amplitude")]
#if ULIPSYNC
        [SerializeField] uLipSync.uLipSync uLipSyncComponent;
#endif
        [SerializeField] float amplitudeGain = 3f;
        [SerializeField] AudioTap audioTap; // only used by amplitude fallback

        public override void InstallBindings()
        {
            Container.Bind<IFaceRig>().FromInstance((IFaceRig)faceRigComponent).AsSingle();
            if (visemeMap != null) Container.Bind<VisemeMap>().FromInstance(visemeMap).AsSingle();
            Container.Bind<IAudioFeed>().FromInstance(audioFeed).AsSingle();

#if ULIPSYNC
            if (uLipSyncComponent != null)
                Container.Bind<ILipSyncProvider>()
                         .FromInstance(new ULipSyncProvider(uLipSyncComponent, visemeMap)).AsSingle();
            else
#endif
            {
                var amp = new AmplitudeLipSyncProvider(amplitudeGain);
                if (audioTap != null) audioTap.OnAudio += amp.Feed;
                Container.Bind<ILipSyncProvider>().FromInstance(amp).AsSingle();
            }

            Container.Bind<LipSyncController>().AsSingle();
            Container.BindInterfacesTo<LipSyncControllerInitializer>().AsSingle().NonLazy();
            Container.Bind<FlutterFaceBridge>().FromComponentInHierarchy().AsSingle().NonLazy();
        }

        /// <summary>Bridges Zenject's lifecycle to the plain-C# controller.</summary>
        sealed class LipSyncControllerInitializer : IInitializable, System.IDisposable
        {
            readonly LipSyncController _ctl;
            public LipSyncControllerInitializer(LipSyncController ctl) => _ctl = ctl;
            public void Initialize() => _ctl.Initialize();
            public void Dispose() => _ctl.Dispose();
        }
    }
}
#endif
