<#
  build.ps1 - one-shot Keli build pipeline (run from the root that holds the 3 folders).

  Steps:
    1. Unity (batchmode, headless) re-exports the Android unityLibrary -> unity-artifact/android/unityLibrary
       (clears the old export first; uses BatchExport.ExportAndroid -> flutter_embed's batch exporter)
    2. Mirror that export into the Keli app's android/unityLibrary  (robocopy /MIR)
    3. flutter build apk --release   (recompiles IL2CPP from the new Unity code)
    4. Read version from pubspec.yaml -> name  keli-<version>-build<build>.apk
    5. Upload it to nukshare (egregor-share, :7777)  PUT /api/shared/<name>

  Everything is logged to build-logs/build-<timestamp>.log (and the console).

  Switches:
    -SkipUnity   skip step 1 (reuse the existing unity-artifact export)
    -NoUpload    build but don't upload
#>
param([switch]$SkipUnity, [switch]$NoUpload)

$ErrorActionPreference = 'Stop'
$ROOT = $PSScriptRoot

# -- locations (edit here if the toolchain moves) --
$UnityExe   = 'C:\Program Files\Unity\Hub\Editor\6000.5.0f1\Editor\Unity.exe'
$JavaHome   = 'C:\Program Files\Unity\Hub\Editor\6000.5.0f1\Editor\Data\PlaybackEngines\AndroidPlayer\OpenJDK'
$Flutter    = 'C:\Users\KlimentShchukin\flutter\bin\flutter.bat'
$UnityProj  = Join-Path $ROOT 'maradel-face'
$ArtifactUL = Join-Path $ROOT 'unity-artifact\android\unityLibrary'
$Keli       = Join-Path $ROOT 'keli-client-for-windows-build\client'
$KeliUL     = Join-Path $Keli 'android\unityLibrary'
$Apk        = Join-Path $Keli 'build\app\outputs\flutter-apk\app-release.apk'
$Share      = 'http://192.168.0.229:7777/api/shared'

$Stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogDir = Join-Path $ROOT 'build-logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$Log    = Join-Path $LogDir "build-$Stamp.log"

function Log($m) { ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $m) | Tee-Object -FilePath $Log -Append }
function Die($m) { Log "ERROR: $m"; Log '=== BUILD FAILED ==='; exit 1 }

Log "=== BUILD START ($Stamp) - root: $ROOT ==="

# 1 -- Unity export ---------------------------------------------------------
if (-not $SkipUnity) {
    if (-not (Test-Path $UnityExe)) { Die "Unity not found: $UnityExe" }
    $running = @(Get-Process Unity -ErrorAction SilentlyContinue)
    if ($running.Count -gt 0) {
        Die ("Unity Editor is already running (PID {0}) with the project open - batch export can't open a locked project. Close Unity and re-run, or use -SkipUnity to reuse the existing export." -f ($running.Id -join ','))
    }
    Log "clearing old export: $ArtifactUL"
    if (Test-Path $ArtifactUL) { Remove-Item -Recurse -Force $ArtifactUL }
    New-Item -ItemType Directory -Force -Path $ArtifactUL | Out-Null

    $uLog = Join-Path $LogDir "unity-$Stamp.log"
    Log "Unity batch export -> $ArtifactUL  (log: $uLog)"
    # NB: Unity.exe detaches on Windows (PowerShell '&' returns immediately with no exit code), so we
    # launch it and POLL until no Unity process remains, then verify the export by its output.
    $args = @('-batchmode','-quit','-nographics','-silent-crashes',
              '-projectPath',$UnityProj,'-buildTarget','Android',
              '-executeMethod','BatchExport.ExportAndroid','-exportPath',$ArtifactUL,
              '-logFile',$uLog)
    Start-Process -FilePath $UnityExe -ArgumentList $args -NoNewWindow | Out-Null
    Start-Sleep -Seconds 6
    $waited = 0; $limit = 2400  # 40 min cap
    while (@(Get-Process Unity -ErrorAction SilentlyContinue).Count -gt 0) {
        Start-Sleep -Seconds 10; $waited += 10
        if ($waited % 60 -eq 0) { Log "  ...Unity still running (${waited}s)" }
        if ($waited -ge $limit) { Die "Unity export timed out after ${limit}s - see $uLog" }
    }
    if (-not (Test-Path (Join-Path $ArtifactUL 'build.gradle'))) { Die "Unity export produced no unityLibrary - see $uLog" }
    Log "Unity export OK (${waited}s)"
} else {
    Log "skipping Unity export (-SkipUnity)"
}

# 2 -- sync export -> Keli unityLibrary -------------------------------------
if (-not (Test-Path (Join-Path $ArtifactUL 'build.gradle'))) { Die "no export at $ArtifactUL" }
Log "mirroring export -> $KeliUL"
robocopy $ArtifactUL $KeliUL /MIR /MT:16 /NFL /NDL /NJH /NJS /R:1 /W:1 | Out-Null
if ($LASTEXITCODE -ge 8) { Die "robocopy failed ($LASTEXITCODE)" }
Log "sync OK (robocopy code $LASTEXITCODE)"

# 3 -- flutter build apk ----------------------------------------------------
$env:JAVA_HOME = $JavaHome
Log "flutter build apk --release  (JAVA_HOME=$JavaHome)"
Push-Location $Keli
try {
    & $Flutter build apk --release 2>&1 | Tee-Object -FilePath $Log -Append
    $fb = $LASTEXITCODE
} finally { Pop-Location }
if ($fb -ne 0) { Die "flutter build failed ($fb)" }
if (-not (Test-Path $Apk)) { Die "APK not produced at $Apk" }

# 4 -- name by version ------------------------------------------------------
$verLine = (Select-String -Path (Join-Path $Keli 'pubspec.yaml') -Pattern '^\s*version:\s*(.+?)\s*$').Matches[0].Groups[1].Value
$parts   = $verLine -split '\+'
$apkName = "keli-$($parts[0])-build$($parts[1]).apk"
$mb      = [math]::Round((Get-Item $Apk).Length / 1MB, 1)
Log "built $apkName ($mb MB)"

# 5 -- upload to nukshare (egregor-share :7777) -----------------------------
if (-not $NoUpload) {
    # (a) versioned archive copy
    Log "uploading -> $Share/$apkName"
    $code = (& curl.exe -s -m 600 -T $Apk "$Share/$apkName" -w '%{http_code}' -o "$LogDir\upload-$Stamp.json")
    Log "upload HTTP $code"
    if ($code -notmatch '^2\d\d$') { Die "upload failed (HTTP $code)" }
    Log "uploaded: $Share/$apkName"

    # (b) AUTO-UPDATE channel — the Keli backend serves ~/shared/keli/{keli.apk,version.json};
    #     the installed app polls /version.json and pulls /keli.apk when build is higher.
    Log "publishing auto-update -> $Share/keli/keli.apk + version.json (v$($parts[0]) build $($parts[1]))"
    $ca = (& curl.exe -s -m 600 -T $Apk "$Share/keli/keli.apk" -w '%{http_code}' -o "$LogDir\upd-apk-$Stamp.txt")
    $verFile = Join-Path $LogDir "version-$Stamp.json"
    Set-Content -Path $verFile -Value ('{"version":"' + $parts[0] + '","build":' + $parts[1] + '}') -NoNewline -Encoding ascii
    $cv = (& curl.exe -s -m 60 -T $verFile "$Share/keli/version.json" -w '%{http_code}' -o "$LogDir\upd-ver-$Stamp.txt")
    Log "auto-update: keli.apk HTTP $ca, version.json HTTP $cv"
    if ($ca -notmatch '^2\d\d$' -or $cv -notmatch '^2\d\d$') { Die "auto-update publish failed (apk $ca, version $cv)" }
} else {
    Log "skipping upload (-NoUpload)"
}

Log "=== BUILD DONE -> $apkName ==="
