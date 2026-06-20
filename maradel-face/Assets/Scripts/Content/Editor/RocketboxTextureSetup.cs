using System.IO;
using UnityEditor;
using UnityEngine;

namespace Maradel.Content.EditorTools
{
    /// <summary>
    /// The Rocketbox avatars ship proper <c>*_normal.tga</c> / <c>*_normal_wrinkle.tga</c> maps, but they
    /// import as plain colour textures by default — so the close-up face gets NO surface detail. This
    /// marks them as Normal Maps on import, and a menu reimports the ones already in the project.
    /// (Materials then sample them correctly; <see cref="Maradel.Speech.RocketboxAutoRig"/> enables the
    /// <c>_NORMALMAP</c> keyword + skin smoothness at runtime.)
    /// </summary>
    public class RocketboxTextureSetup : AssetPostprocessor
    {
        const string Root = "Assets/App/Content/Models/Microsoft-Rocketbox-master/Assets/Avatars";

        void OnPreprocessTexture()
        {
            if (!assetPath.Replace('\\', '/').StartsWith(Root)) return;
            if (!Path.GetFileName(assetPath).ToLowerInvariant().Contains("normal")) return;
            var ti = (TextureImporter)assetImporter;
            if (ti.textureType != TextureImporterType.NormalMap)
                ti.textureType = TextureImporterType.NormalMap; // also forces linear sampling
        }

        [MenuItem("Maradel/Visuals/Fix Avatar Normal Maps")]
        public static void FixNormals()
        {
            var guids = AssetDatabase.FindAssets("normal t:Texture2D", new[] { Root });
            int fixedCount = 0, total = 0;
            foreach (var g in guids)
            {
                string path = AssetDatabase.GUIDToAssetPath(g);
                if (!Path.GetFileName(path).ToLowerInvariant().Contains("normal")) continue;
                total++;
                if (AssetImporter.GetAtPath(path) is not TextureImporter ti) continue;
                if (ti.textureType == TextureImporterType.NormalMap) continue;
                ti.textureType = TextureImporterType.NormalMap;
                ti.SaveAndReimport();
                fixedCount++;
            }
            Debug.Log($"[VISUALS] normal maps: set {fixedCount} of {total} to NormalMap (the rest were already correct). " +
                      "Rebuild Addressables so the bundles pick up the corrected textures.");
        }
    }
}
