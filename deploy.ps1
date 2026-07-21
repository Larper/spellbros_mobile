# Deploys the web build to https://everydaylife.neven.one via the cPanel API.
#
# Usage:  powershell -File deploy.ps1          (or ./deploy.ps1 from a PS prompt)
#         -SkipExport   reuse build/web as-is instead of re-exporting
#
# Auth: reads the cPanel API token from ~\.cpanel-token.txt (never committed).
# The token was created in cPanel > Security > Manage API Tokens and can be
# revoked there at any time.

param([switch]$SkipExport)

$ErrorActionPreference = "Stop"

$CpHost = "server108.web-hosting.com:2083"
$CpUser = "nevesbxc"
$DocRoot = "/home/nevesbxc/everydaylife.neven.one"
$SiteUrl = "https://everydaylife.neven.one"
$Godot = "C:\Program Files (x86)\Godot\godot.exe"

$proj = $PSScriptRoot
$webDir = Join-Path $proj "build\web"
$tokenFile = Join-Path $env:USERPROFILE ".cpanel-token.txt"

if (-not (Test-Path $tokenFile)) { throw "Token file not found: $tokenFile" }
$token = (Get-Content $tokenFile -Raw).Trim()

if (-not $SkipExport) {
    Write-Host "Exporting web build..."
    # godot.exe is a GUI-subsystem binary: PowerShell won't wait for it unless
    # launched via Start-Process -Wait
    $godotArgs = @("--headless", "--path", "`"$proj`"", "--export-release", "Web",
            "`"$(Join-Path $webDir 'index.html')`"")
    $p = Start-Process -FilePath $Godot -ArgumentList $godotArgs -NoNewWindow -Wait -PassThru
    if ($p.ExitCode -ne 0) { throw "Godot export failed (exit $($p.ExitCode))" }
    if (-not (Test-Path (Join-Path $webDir "index.wasm"))) { throw "Export produced no index.wasm" }
}

$files = Get-ChildItem $webDir -File -Force
if ($files.Count -lt 9) { throw "build\web looks incomplete ($($files.Count) files)" }

Write-Host "Uploading $($files.Count) files to ${DocRoot}..."
$curlArgs = @("-sS", "-H", "Authorization: cpanel ${CpUser}:${token}")
$i = 1
foreach ($f in $files) {
    $curlArgs += @("-F", "file-${i}=@$($f.FullName)")
    $i++
}
$curlArgs += @("-F", "dir=$DocRoot", "-F", "overwrite=1", "https://$CpHost/execute/Fileman/upload_files")
$respRaw = & curl.exe @curlArgs
$resp = $respRaw | ConvertFrom-Json
if ($resp.status -ne 1) { throw "Upload failed: $($resp.errors -join '; ')" }
$failed = @($resp.data.uploads | Where-Object { $_.status -ne 1 })
if ($failed.Count -gt 0) { throw "Some files failed: $(($failed | ForEach-Object { $_.file + ' (' + $_.reason + ')' }) -join '; ')" }
Write-Host "Uploaded $($resp.data.uploads.Count) files OK."

# verify the live site serves the build we just pushed (byte-size match on the wasm)
$localWasm = (Get-Item (Join-Path $webDir "index.wasm")).Length
$head = Invoke-WebRequest -Uri "$SiteUrl/index.wasm" -Method Head -UseBasicParsing
$remoteWasm = [int64]$head.Headers["Content-Length"]
if ($remoteWasm -ne $localWasm) {
    throw "Live index.wasm is $remoteWasm bytes but local is $localWasm - deploy mismatch?"
}
Write-Host "Live check OK: $SiteUrl serves the new build ($localWasm bytes wasm)."
