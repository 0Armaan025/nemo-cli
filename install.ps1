[CmdletBinding()]
param(
    [switch] $NoPath,
    [string] $TargetDir
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
Copy-Item -LiteralPath (Join-Path $sourceDir "nemo.ps1") -Destination (Join-Path $TargetDir "nemo.ps1") -Force
Copy-Item -LiteralPath (Join-Path $sourceDir "nemo.cmd") -Destination (Join-Path $TargetDir "nemo.cmd") -Force

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

$keyHome = $env:USERPROFILE
if (-not $keyHome) { $keyHome = $env:HOME }
if ($keyHome) {
    $keyPath = Join-Path $keyHome ".nvidia-key"
    if (-not $env:NVIDIA_API_KEY -and -not (Test-Path -LiteralPath $keyPath)) {
        Write-Warning "No NVIDIA key found. Put your key in $keyPath or set NVIDIA_API_KEY."
    }
}

Write-Host "Installed nemo.cmd and nemo.ps1 to $TargetDir"
Write-Host "Try: nemo `"write a python function that merges two sorted lists`""
