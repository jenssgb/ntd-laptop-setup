<#
================================================================================
  NTD Laptop-Vorbereitung  -  ONLINE Bootstrap
  Fuer den Einzeiler:  irm https://raw.githubusercontent.com/jenssgb/ntd-laptop-setup/main/online.ps1 | iex

  Ablauf:
    1. Fordert Adminrechte an (UAC) und startet sich elevated neu.
    2. Laedt Setup.ps1 + extensions.txt + VS-Code-Installer nach %TEMP%\NTD_Laptops.
    3. Startet Setup.ps1 (identische Logik wie die Stick-Variante).

  Unterschied zum Stick: VS Code wird direkt von Microsoft geladen (Online),
  nicht vom Stick. Alles andere ist identisch.
================================================================================
#>

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RepoRaw = 'https://raw.githubusercontent.com/jenssgb/ntd-laptop-setup/main'
$SelfUrl = "$RepoRaw/online.ps1"

# --- Self-Elevation (UAC) ---
$id  = [Security.Principal.WindowsIdentity]::GetCurrent()
$pri = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pri.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Fordere Administratorrechte an (UAC)..." -ForegroundColor Yellow
    try {
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-Command',
            "irm '$SelfUrl' | iex"
        )
    } catch {
        Write-Host "Adminrechte abgelehnt. Abbruch." -ForegroundColor Red
        Start-Sleep 4
    }
    return
}

# --- Staging-Ordner vorbereiten (wie ein Stick) ---
$base = Join-Path $env:TEMP 'NTD_Laptops'
$inst = Join-Path $base 'installers'
New-Item -ItemType Directory -Force -Path $inst | Out-Null

Write-Host "Lade Setup-Dateien..." -ForegroundColor Cyan
Invoke-WebRequest "$RepoRaw/Setup.ps1"                 -OutFile (Join-Path $base 'Setup.ps1')        -UseBasicParsing
Invoke-WebRequest "$RepoRaw/installers/extensions.txt" -OutFile (Join-Path $inst 'extensions.txt')   -UseBasicParsing

Write-Host "Lade VS Code (ca. 190 MB) von Microsoft..." -ForegroundColor Cyan
Invoke-WebRequest 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64' `
    -OutFile (Join-Path $inst 'VSCodeSetup-x64.exe') -UseBasicParsing

# --- Hauptskript starten (bereits elevated) ---
& (Join-Path $base 'Setup.ps1')
