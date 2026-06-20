namespace Maradel.Face
{
    /// <summary>
    /// Abstraction over the face model's SkinnedMeshRenderer. The provided prefab's
    /// MonoBehaviour implements this directly, or a thin adapter wraps it. Swapping the
    /// avatar is a data change (a new <see cref="VisemeMap"/>), never a code change.
    /// </summary>
    public interface IFaceRig
    {
        /// <summary>True once blendshape indices are resolved and the rig can be driven.</summary>
        bool IsReady { get; }

        /// <summary>Set one viseme's weight (0..1). Several may be set per frame; the rig blends.</summary>
        void SetViseme(Viseme v, float weight01);

        /// <summary>Crude jaw-open for the amplitude-only PoC (Milestone 0). 0 = closed, 1 = wide.</summary>
        void SetMouthOpen(float amount01);

        /// <summary>Idle life: blink, brows, micro-smile.</summary>
        void SetExpression(Expression e, float weight01);

        /// <summary>Zero all mouth visemes (call on speaking stop).</summary>
        void ResetMouth();
    }
}
