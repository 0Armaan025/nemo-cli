[CmdletBinding()]
param(
    [switch] $NoPath,
    [string] $TargetDir,
    [switch] $Hardcoded
)

$ErrorActionPreference = "Stop"

$sourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $TargetDir) {
    if ($env:LOCALAPPDATA) {
        $TargetDir = Join-Path $env:LOCALAPPDATA "NemoCli"
    }
    else {
        $TargetDir = Join-Path $env:USERPROFILE ".nemo-cli"
    }
}

New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
if ($Hardcoded) {
    $hardcodedPs1 = Join-Path $sourceDir "nemo-hardcoded.ps1"
    if (-not (Test-Path -LiteralPath $hardcodedPs1)) {
        throw "Hardcoded script not found: $hardcodedPs1"
    }
    Copy-Item -LiteralPath $hardcodedPs1 -Destination (Join-Path $TargetDir "nemo.ps1") -Force
    $cmdContent = @"
@echo off
setlocal DisableDelayedExpansion
set "NEMO_PS1=%~dp0nemo.ps1"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%NEMO_PS1%" %*
exit /b %ERRORLEVEL%
"@
    [System.IO.File]::WriteAllText((Join-Path $TargetDir "nemo.cmd"), $cmdContent)
}
else {
    Copy-Item -LiteralPath (Join-Path $sourceDir "nemo.ps1") -Destination (Join-Path $TargetDir "nemo.ps1") -Force
    Copy-Item -LiteralPath (Join-Path $sourceDir "nemo.cmd") -Destination (Join-Path $TargetDir "nemo.cmd") -Force
}

if (-not $NoPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (-not $userPath) { $userPath = "" }
    if ($userPath -notlike "*$TargetDir*") {
        if ([string]::IsNullOrWhiteSpace($userPath)) {
            $newPath = $TargetDir
        }
        else {
            $newPath = $userPath.TrimEnd(';') + ";" + $TargetDir
        }
        [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
        Write-Host "Added to user PATH: $TargetDir (open a new terminal)."
    }
    else {
        Write-Host "Already on user PATH: $TargetDir"
    }
}

if (-not $Hardcoded) {
    $keyHome = $env:USERPROFILE
    if (-not $keyHome) { $keyHome = $env:HOME }
    if ($keyHome) {
        $keyPath = Join-Path $keyHome ".nvidia-key"
        if (-not $env:NVIDIA_API_KEY -and -not (Test-Path -LiteralPath $keyPath)) {
            Write-Warning "No NVIDIA key found. Put your key in $keyPath or set NVIDIA_API_KEY."
        }
    }
}
else {
    Write-Host "Installed with embedded API key. Do not share or upload the installed nemo.ps1."
}

Write-Host "Installed nemo.cmd and nemo.ps1 to $TargetDir"
Write-Host "Try: nemo `"write a python function that merges two sorted lists`""
