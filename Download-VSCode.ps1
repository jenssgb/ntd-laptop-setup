<#
  Download-VSCode.ps1
  Laedt die aktuellen VS-Code-System-Installer in .\installers\.
  Auf einem Rechner MIT Internet einmal ausfuehren, dann Stick verteilen.
#>
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'
$dir = Join-Path $PSScriptRoot 'installers'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$downloads = @{
    'VSCodeSetup-x64.exe' = 'https://code.visualstudio.com/sha/download?build=stable&os=win32-x64'
}

foreach ($name in $downloads.Keys) {
    $out = Join-Path $dir $name
    Write-Host "Lade $name ..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $downloads[$name] -OutFile $out -UseBasicParsing
    $sig = Get-AuthenticodeSignature $out
    $mb  = "{0:N1} MB" -f ((Get-Item $out).Length / 1MB)
    if ($sig.Status -eq 'Valid') {
        Write-Host "  OK  $mb  (signiert: $($sig.SignerCertificate.Subject.Split(',')[0]))" -ForegroundColor Green
    } else {
        Write-Host "  WARNUNG: Signatur $($sig.Status)" -ForegroundColor Yellow
    }
}
Write-Host "`nFertig. Stick kann verteilt werden." -ForegroundColor Green
