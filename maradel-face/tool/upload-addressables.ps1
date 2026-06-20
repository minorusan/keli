# Upload built Addressables bundles + catalog to the egregor-share API (pi, 192.168.0.11:7777).
# Files land on the HDD via the path-style /api/shared route (which we symlink to /mnt/cache).
#
# Usage:
#   pwsh tool/upload-addressables.ps1 -Target StandaloneWindows64
#   pwsh tool/upload-addressables.ps1 -Target Android -ApiBase http://192.168.0.11:7777 -RemoteRoot addressables
#
# Serve URL (set as Addressables RemoteLoadPath / BuildConfig.remoteLoadPath):
#   http://192.168.0.11:7777/api/shared/<RemoteRoot>/<Target>

param(
    [string]$Target   = "StandaloneWindows64",
    [string]$ApiBase  = "http://192.168.0.11:7777",
    [string]$RemoteRoot = "addressables",
    [string]$Source   = ""   # defaults to <project>/ServerData/<Target>
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrEmpty($Source)) { $Source = Join-Path $projectRoot "ServerData/$Target" }

if (-not (Test-Path $Source)) {
    Write-Error "Source not found: $Source  (run 'Maradel > Addressables > 2. Build Remote' first)"
    exit 1
}

$files = Get-ChildItem -Path $Source -Recurse -File
if ($files.Count -eq 0) { Write-Error "No files under $Source"; exit 1 }

$total = ($files | Measure-Object Length -Sum).Sum
Write-Host ("[upload] {0} files, {1:N1} MB  →  {2}/api/shared/{3}/{4}" -f $files.Count, ($total/1MB), $ApiBase, $RemoteRoot, $Target)

$ok = 0; $fail = 0; $done = 0
foreach ($f in $files) {
    $rel = $f.FullName.Substring($Source.Length).TrimStart('\','/').Replace('\','/')
    $url = "$ApiBase/api/shared/$RemoteRoot/$Target/$rel"
    # PUT raw bytes (curl -T). Subdirs auto-created server-side. No auth on the LAN.
    $code = (& curl.exe -s -o $null -w "%{http_code}" -T "$($f.FullName)" "$url")
    $done++
    if ($code -eq "200" -or $code -eq "201" -or $code -eq "204") {
        $ok++
        Write-Host ("  [{0}/{1}] {2}  ({3:N0} KB)  {4}" -f $done, $files.Count, $rel, ($f.Length/1KB), $code)
    } else {
        $fail++
        Write-Warning ("  FAIL {0}  http={1}  url={2}" -f $rel, $code, $url)
    }
}

Write-Host ("[upload] done: {0} ok, {1} failed." -f $ok, $fail)
if ($fail -eq 0) {
    Write-Host ("[upload] set Addressables RemoteLoadPath to:  {0}/api/shared/{1}/{2}" -f $ApiBase, $RemoteRoot, $Target)
} else { exit 1 }
