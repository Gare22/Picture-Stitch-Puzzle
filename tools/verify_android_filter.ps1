# verify_android_filter.ps1
#
# Post-export guard: fails loudly if an APK does not contain the
# picturepuzzle://callback VIEW intent-filter.
#
# Background: the oauth_deeplink_manifest EditorExportPlugin re-injects the
# filter into the generated AndroidManifest.xml on every export. It only runs
# when the plugin is actually loaded in the exporting process (fresh headless
# CLI process, or a GUI editor session that was started AFTER the plugin was
# registered; otherwise the export can silently produce a filter-less APK and
# deep links fail to resolve). This script catches that case before install.
#
# Usage:
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\verify_android_filter.ps1 -ApkPath exports\testbuild_10.apk
#
# Exit codes: 0 = filter present, 1 = missing (checked below).

param(
    [Parameter(Mandatory = $true)]
    [string]$ApkPath,

    [string]$AaptPath = "C:\Android\Sdk\build-tools\36.1.0\aapt.exe"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $ApkPath)) {
    Write-Error "APK not found: $ApkPath"
    exit 1
}
if (-not (Test-Path -LiteralPath $AaptPath)) {
    Write-Error "aapt not found at $AaptPath - pass -AaptPath to override."
    exit 1
}

$manifest = & $AaptPath dump xmltree $ApkPath AndroidManifest.xml
if ($LASTEXITCODE -ne 0) {
    Write-Error "aapt failed on $ApkPath"
    exit 1
}

$hasScheme = ($manifest | Select-String -Pattern 'android:scheme\(0x01010027\)="picturepuzzle"').Count -gt 0
$hasHost   = ($manifest | Select-String -Pattern 'android:host\(0x01010028\)="callback"').Count -gt 0

if ($hasScheme -and $hasHost) {
    Write-Output "PASS: $ApkPath contains picturepuzzle://callback VIEW intent-filter."
    exit 0
}

Write-Output "FAIL: $ApkPath is MISSING the picturepuzzle://callback intent-filter."
Write-Output "  scheme present: $hasScheme  |  host present: $hasHost"
Write-Output "The export skipped the oauth_deeplink_manifest plugin. Fixes:"
Write-Output "  1. Close and reopen the Godot editor (plugins load at startup), then re-export."
Write-Output "  2. Or in Project Settings -> Plugins, toggle OAuthDeepLinkManifest OFF then ON to reload it in-session."
Write-Output "  3. Or export via CLI (fresh process always loads plugins):"
Write-Output "     `"C:\Users\Garrett Tallent\Desktop\Godot\Godot_v4.6.3-stable_win64.exe`" --headless --path . --export-debug `"Android`" `"exports\<name>.apk`""
exit 1