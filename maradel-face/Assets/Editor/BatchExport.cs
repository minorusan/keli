using UnityEditor;
using UnityEngine;

/// <summary>
/// CI batch-export entry for the Android Unity-as-a-library module. Forces the settings the vendored
/// flutter_embed precheck requires (so it never fails on a stale toggle), then hands off to
/// <c>ProjectExporterBatchmode.ExportProjectAndroid</c> (reads <c>-exportPath</c>, deletes the old
/// export, builds the Gradle <c>unityLibrary</c> module — no dialogs).
///
/// Invoke:
///   Unity.exe -batchmode -quit -nographics -projectPath &lt;proj&gt; -buildTarget Android \
///     -executeMethod BatchExport.ExportAndroid -exportPath &lt;...\android\unityLibrary&gt; -logFile &lt;log&gt;
/// </summary>
public static class BatchExport
{
    public static void ExportAndroid()
    {
        EditorUserBuildSettings.exportAsGoogleAndroidProject = true; // "Export Project" — precheck requires it
        PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARMv7 | AndroidArchitecture.ARM64;
        Debug.Log("[BatchExport] exportAsGoogleAndroidProject=true, archs=ARMv7|ARM64 → ProjectExporterBatchmode.ExportProjectAndroid");
        ProjectExporterBatchmode.ExportProjectAndroid(); // throws on precheck failure → Unity exits non-zero
    }
}
