namespace Maradel.Face
{
    /// <summary>
    /// Default mapping from uLipSync phoneme labels to our <see cref="Viseme"/> enum, used when
    /// no <see cref="VisemeMap"/> override is supplied. Matches uLipSync's common 5-vowel sample
    /// profile (A/I/U/E/O) plus N and silence. With <see cref="RocketboxFaceRig"/> this means the
    /// whole pipeline runs with no authored asset at all.
    /// </summary>
    public static class PhonemeMap
    {
        public static Viseme FromPhoneme(string phoneme)
        {
            if (string.IsNullOrEmpty(phoneme)) return Viseme.Sil;
            switch (phoneme.Trim().ToUpperInvariant())
            {
                case "A": return Viseme.Aa;
                case "I": return Viseme.Ih;
                case "U": return Viseme.Ou;
                case "E": return Viseme.E;
                case "O": return Viseme.Oh;
                case "N": return Viseme.Nn;
                case "-":
                case "SIL":
                case "SILENCE": return Viseme.Sil;
                default: return Viseme.Sil;
            }
        }
    }
}
