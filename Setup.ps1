<#
================================================================================
  NTD Laptop-Vorbereitung  -  Setup.ps1
  Ein Klick, alles automatisch, mit Statusanzeige.

  Aufgaben:
    1. VS Code installieren (System-Setup, offline vom Stick)
    2. Windows-Hintergrundbild auf Standard setzen (alle Laptops gleich)
    3. Desktop komplett leeren (User- + Public-Desktop + OneDrive-Umleitung)
    4. Ordner C:\CodeTemp anlegen

  Robust gegen "strange" Pfade:
    - beliebiger USB-Laufwerksbuchstabe  -> $PSScriptRoot
    - Leerzeichen / Sonderzeichen        -> durchgehend -LiteralPath / Quoting
    - OneDrive-umgeleiteter Desktop      -> GetFolderPath + Registry-Gegenpruefung
    - lokalisiertes / non-English Windows-> Known-Folder-APIs statt fester Namen
================================================================================
#>

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 0) SELF-ELEVATION  (sauber per UAC anfragen)
# ---------------------------------------------------------------------------
$id        = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Fordere Administratorrechte an (UAC)..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`""
        )
    } catch {
        Write-Host "Adminrechte wurden abgelehnt. Abbruch." -ForegroundColor Red
        Start-Sleep -Seconds 4
    }
    exit
}

# ---------------------------------------------------------------------------
#  KONFIGURATION
# ---------------------------------------------------------------------------
$ScriptDir      = $PSScriptRoot
$InstallerDir   = Join-Path $ScriptDir 'installers'
$CodeTempPath   = 'C:\CodeTemp'

# ---------------------------------------------------------------------------
#  LOGGING  (pro Laptop eine Datei auf dem Stick, Fallback wenn schreibgeschuetzt)
# ---------------------------------------------------------------------------
function Resolve-LogDir {
    $candidates = @(
        (Join-Path $ScriptDir 'logs'),        # bevorzugt: auf den Stick
        'C:\CodeTemp\NTD-Logs',               # Fallback lokal
        (Join-Path $env:TEMP 'NTD-Logs')      # letzter Fallback
    )
    foreach ($c in $candidates) {
        try {
            if (-not (Test-Path -LiteralPath $c)) { New-Item -ItemType Directory -Path $c -Force -ErrorAction Stop | Out-Null }
            $t = Join-Path $c ('.w_' + [guid]::NewGuid().ToString('N') + '.tmp')
            Set-Content -LiteralPath $t -Value 'x' -ErrorAction Stop
            Remove-Item -LiteralPath $t -Force -ErrorAction SilentlyContinue
            return $c
        } catch { }
    }
    return $env:TEMP
}
$script:LogDir  = Resolve-LogDir
$script:LogFile = Join-Path $script:LogDir ("{0}_{1}.log" -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd_HHmmss'))

function Write-Log {
    param([string]$Line)
    try { Add-Content -LiteralPath $script:LogFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Line) -Encoding UTF8 -ErrorAction Stop } catch { }
}

# ---------------------------------------------------------------------------
#  PROZESS MIT LIVE-FORTSCHRITT (Spinner + Sekundenzaehler, Ausgabe -> Log)
# ---------------------------------------------------------------------------
function Start-Watched {
    param([string]$FilePath, [string[]]$Arguments, [string]$Label, [int]$TimeoutSec = 600)
    $so = [System.IO.Path]::GetTempFileName()
    $se = [System.IO.Path]::GetTempFileName()
    $p  = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru -WindowStyle Hidden `
          -RedirectStandardOutput $so -RedirectStandardError $se
    $spin = '|/-\'; $i = 0; $t0 = Get-Date; $timedOut = $false
    while (-not $p.HasExited) {
        $el = [int]((Get-Date) - $t0).TotalSeconds
        Write-Host ("`r  [ {0}  ] {1} ... {2}s   " -f $spin[$i % 4], $Label, $el) -NoNewline -ForegroundColor Cyan
        if ($el -ge $TimeoutSec) { $timedOut = $true; try { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } catch {}; break }
        Start-Sleep -Milliseconds 250; $i++
    }
    Start-Sleep -Milliseconds 200
    $out = @()
    try { $out += Get-Content -LiteralPath $so -ErrorAction SilentlyContinue } catch {}
    try { $out += Get-Content -LiteralPath $se -ErrorAction SilentlyContinue } catch {}
    Remove-Item -LiteralPath $so, $se -Force -ErrorAction SilentlyContinue
    $code = if ($timedOut) { -999 } else { $p.ExitCode }
    return [pscustomobject]@{ ExitCode = $code; Output = $out; TimedOut = $timedOut }
}

# ---------------------------------------------------------------------------
#  STATUS-FRAMEWORK
# ---------------------------------------------------------------------------
$script:Results = @()

function Write-Banner {
    Clear-Host
    Write-Host ""
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "        N T D   -   L A P T O P   V O R B E R E I T U N G"        -ForegroundColor Cyan
    Write-Host "  ============================================================" -ForegroundColor Cyan
    Write-Host "        Computer : $env:COMPUTERNAME" -ForegroundColor DarkGray
    Write-Host "        Benutzer : $env:USERNAME"     -ForegroundColor DarkGray
    Write-Host "        Quelle   : $ScriptDir"        -ForegroundColor DarkGray
    Write-Host ""
}

function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action
    )
    Write-Host ("  [ ... ] {0}" -f $Name) -ForegroundColor White -NoNewline
    Write-Log ("STEP  : {0}" -f $Name)
    $detail = ''
    $ok = $true
    $errRec = $null
    try {
        $detail = & $Action
    } catch {
        $ok = $false
        $errRec = $_
        $detail = $_.Exception.Message
    }
    # Zeile leeren und Ergebnis schreiben
    Write-Host ("`r{0}`r" -f (' ' * 72)) -NoNewline
    if ($ok) {
        Write-Host ("  [ OK  ] {0}" -f $Name) -ForegroundColor Green
        if ($detail) { Write-Host ("         -> {0}" -f $detail) -ForegroundColor DarkGray }
        Write-Log ("  OK  : {0} {1}" -f $Name, $detail)
    } else {
        Write-Host ("  [FEHLR] {0}" -f $Name) -ForegroundColor Red
        if ($detail) { Write-Host ("         -> {0}" -f $detail) -ForegroundColor DarkYellow }
        Write-Log ("  FAIL: {0} -> {1}" -f $Name, $detail)
        if ($errRec) { Write-Log ("        StackTrace: {0}" -f $errRec.ScriptStackTrace) }
    }
    $script:Results += [pscustomobject]@{ Name = $Name; Ok = $ok; Detail = $detail }
}

# ---------------------------------------------------------------------------
#  AUFGABEN
# ---------------------------------------------------------------------------

function Test-VSCodeInstalled {
    # Robuste Erkennung - auch wenn als Admin elevated (dann zeigt LOCALAPPDATA aufs Admin-Profil!)
    $probe = @(
        "$env:ProgramFiles\Microsoft VS Code\Code.exe",
        "${env:ProgramFiles(x86)}\Microsoft VS Code\Code.exe"
    )
    # User-Setup in JEDEM Profil (VS-Code-Standard-Installation)
    $probe += (Get-ChildItem 'C:\Users' -Directory -ErrorAction SilentlyContinue |
               ForEach-Object { Join-Path $_.FullName 'AppData\Local\Programs\Microsoft VS Code\Code.exe' })
    foreach ($p in $probe) { if ($p -and (Test-Path -LiteralPath $p)) { return $true } }
    # Registry-Fallback (Uninstall-Eintraege)
    $keys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
            'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    foreach ($k in $keys) {
        if (Get-ItemProperty $k -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -like 'Microsoft Visual Studio Code*' }) { return $true }
    }
    return $false
}

function Task-InstallVSCode {
    # Nur installieren, wenn VS Code fehlt (nichts neu installieren/herunterladen)
    if (Test-VSCodeInstalled) { return "bereits vorhanden" }

    # Passenden System-Installer vom Stick waehlen (offline, bulletproof)
    # Architektur robust bestimmen (auch unter WOW64 / ARM64-Emulation)
    $arch = $env:PROCESSOR_ARCHITECTURE
    if ($env:PROCESSOR_ARCHITEW6432) { $arch = $env:PROCESSOR_ARCHITEW6432 }
    $wantArm = ($arch -eq 'ARM64')

    $all = @(Get-ChildItem -LiteralPath $InstallerDir -Filter 'VSCode*Setup*.exe' -ErrorAction SilentlyContinue)
    if ($wantArm) {
        $exe = $all | Where-Object { $_.Name -match 'arm64' } | Select-Object -First 1
    } else {
        $exe = $all | Where-Object { $_.Name -notmatch 'arm64' } | Sort-Object Length -Descending | Select-Object -First 1
    }
    if (-not $exe) { $exe = $all | Sort-Object Length -Descending | Select-Object -First 1 }

    # Bereits installiert?
    $already = Test-Path 'C:\Program Files\Microsoft VS Code\Code.exe'

    if ($exe) {
        # Laufendes VS Code vorher beenden, sonst haengt der Installer (wartet aufs Schliessen)
        Get-Process -Name 'Code','Code - Insiders' -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop } catch {}
        }
        Start-Sleep -Milliseconds 500
        $args = '/VERYSILENT','/NORESTART','/SP-','/SUPPRESSMSGBOXES',
                '/CLOSEAPPLICATIONS','/FORCECLOSEAPPLICATIONS','/NOCANCEL',
                '/MERGETASKS=!runcode,desktopicon,addcontextmenufiles,addcontextmenufolders,addtopath'
        $r = Start-Watched -FilePath $exe.FullName -Arguments $args -Label "VS Code installieren (vom Stick)"
        foreach ($l in $r.Output) { Write-Log ("      | $l") }
        if ($r.ExitCode -ne 0) { throw "Installer ExitCode $($r.ExitCode)" }
        return "installiert vom Stick ($($exe.Name))"
    }

    # Fallback: winget (nur falls Installer fehlt und Internet vorhanden)
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) {
        $r = Start-Watched -FilePath $winget.Source -Label "VS Code installieren (winget)" -Arguments @(
            'install','--id','Microsoft.VisualStudioCode','--scope','machine','--silent',
            '--accept-package-agreements','--accept-source-agreements'
        )
        foreach ($l in $r.Output) { Write-Log ("      | $l") }
        if ($r.ExitCode -ne 0) { throw "winget ExitCode $($r.ExitCode)" }
        return "installiert via winget (Fallback)"
    }

    if ($already) { return "bereits vorhanden" }
    throw "Kein Installer in '$InstallerDir' und kein winget verfuegbar."
}

function Task-SetWallpaper {
    # IMMER das Windows-11-Standardbild, kein anderes
    $wp = 'C:\Windows\Web\Wallpaper\Windows\img0.jpg'
    if (-not (Test-Path -LiteralPath $wp)) {
        $wp = (Get-ChildItem 'C:\Windows\Web\Wallpaper\Windows' -Include *.jpg -Recurse -ErrorAction SilentlyContinue |
               Select-Object -First 1 -ExpandProperty FullName)
    }
    if (-not $wp) { throw "Windows-Standardbild nicht gefunden." }

    # Registry (Fuellen)
    $key = 'HKCU:\Control Panel\Desktop'
    Set-ItemProperty -Path $key -Name WallPaper       -Value $wp   -Force
    Set-ItemProperty -Path $key -Name WallpaperStyle  -Value '10'  -Force   # 10 = Fuellen
    Set-ItemProperty -Path $key -Name TileWallpaper   -Value '0'   -Force

    # Live anwenden via SystemParametersInfo
    if (-not ("Wp" -as [type])) {
        Add-Type @"
using System.Runtime.InteropServices;
public class Wp {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
    public static extern bool SystemParametersInfo(uint a, uint u, string p, uint f);
}
"@
    }
    # SPI_SETDESKWALLPAPER=0x0014 ; SPIF_UPDATEINIFILE|SPIF_SENDWININICHANGE = 0x03
    [void][Wp]::SystemParametersInfo(0x0014, 0, $wp, 0x03)
    return "gesetzt: $wp"
}

function Task-CleanDesktops {
    # Alle relevanten Desktop-Pfade robust ermitteln
    $paths = New-Object System.Collections.Generic.List[string]
    foreach ($sf in 'Desktop','CommonDesktopDirectory') {
        $p = [Environment]::GetFolderPath($sf)
        if ($p) { [void]$paths.Add($p) }
    }
    # OneDrive-/Redirect-Gegenpruefung ueber Registry (User Shell Folders)
    try {
        $usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        $raw = (Get-ItemProperty -Path $usf -Name 'Desktop' -ErrorAction SilentlyContinue).Desktop
        if ($raw) { $expanded = [Environment]::ExpandEnvironmentVariables($raw); if ($expanded) { [void]$paths.Add($expanded) } }
    } catch {}

    $targets = $paths | Sort-Object -Unique | Where-Object { Test-Path -LiteralPath $_ }
    $deleted = 0; $failed = 0
    foreach ($d in $targets) {
        Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($_.Name -ieq 'desktop.ini') { return }   # Systemdatei bewahren
            try {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction Stop
                $deleted++
            } catch { $failed++ }
        }
    }
    # Explorer aktualisieren
    try { Start-Process -FilePath 'cmd.exe' -ArgumentList '/c','ie4uinit.exe','-show' -WindowStyle Hidden -ErrorAction SilentlyContinue } catch {}
    $msg = "$deleted Objekt(e) entfernt aus $($targets.Count) Desktop-Pfad(en)"
    if ($failed -gt 0) { $msg += "; $failed gesperrt/uebersprungen" }
    return $msg
}

function Task-CreateCodeTemp {
    if (-not (Test-Path -LiteralPath $CodeTempPath)) {
        New-Item -ItemType Directory -Path $CodeTempPath -Force | Out-Null
        return "$CodeTempPath angelegt"
    }
    return "$CodeTempPath bereits vorhanden"
}

function Task-CloseTeams {
    # Microsoft Teams (neu + klassisch) beenden
    $names = 'ms-teams', 'Teams', 'msteams'
    $stopped = 0
    foreach ($n in $names) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | ForEach-Object {
            try { Stop-Process -Id $_.Id -Force -ErrorAction Stop; $stopped++ } catch {}
        }
    }
    if ($stopped -eq 0) { return "Teams war nicht aktiv" }
    return "$stopped Teams-Prozess(e) beendet"
}

function Task-EmptyRecycleBin {
    try {
        Clear-RecycleBin -Force -Confirm:$false -ErrorAction Stop
        return "Papierkorb geleert"
    } catch {
        if ($_.Exception.Message -match 'leer|empty|Der Papierkorb') { return "Papierkorb war bereits leer" }
        throw
    }
}

function Task-InstallGit {
    # Robuste Erkennung (PATH ist im frisch elevierten Prozess oft stale)
    $gitFound = $false
    if (Get-Command git.exe -ErrorAction SilentlyContinue) { $gitFound = $true }
    if (-not $gitFound) {
        $paths = @(
            "$env:ProgramFiles\Git\cmd\git.exe",
            "${env:ProgramFiles(x86)}\Git\cmd\git.exe",
            "$env:LOCALAPPDATA\Programs\Git\cmd\git.exe"
        )
        foreach ($p in $paths) { if ($p -and (Test-Path -LiteralPath $p)) { $gitFound = $true; break } }
    }
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $gitFound -and $winget) {
        try { if ((& $winget.Source list --id Git.Git -e 2>$null) -match 'Git.Git') { $gitFound = $true } } catch {}
    }
    if ($gitFound) { return "Git bereits vorhanden" }

    if (-not $winget) { throw "winget nicht verfuegbar (Git-Installation braucht winget/Internet)." }
    $r = Start-Watched -FilePath $winget.Source -Label "Git installieren (winget)" -TimeoutSec 600 -Arguments @(
        'install','--id','Git.Git','-e','--source','winget','--scope','machine','--silent',
        '--accept-package-agreements','--accept-source-agreements'
    )
    foreach ($l in $r.Output) { Write-Log ("      | $l") }
    if ($r.ExitCode -eq 0) { return "Git installiert" }
    if ($r.ExitCode -eq -1978335189) { return "Git bereits aktuell" }   # kein anwendbares Update
    throw "winget ExitCode $($r.ExitCode)"
}

function Task-InstallExtensions {
    # code CLI finden
    $codeCmd = 'C:\Program Files\Microsoft VS Code\bin\code.cmd'
    if (-not (Test-Path -LiteralPath $codeCmd)) {
        $alt = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\bin\code.cmd'
        if (Test-Path -LiteralPath $alt) { $codeCmd = $alt } else { throw "code CLI nicht gefunden." }
    }

    $extListFile = Join-Path $InstallerDir 'extensions.txt'
    $vsixDir     = Join-Path $InstallerDir 'extensions'

    $ids = @()
    if (Test-Path -LiteralPath $extListFile) {
        $ids = Get-Content -LiteralPath $extListFile |
               ForEach-Object { $_.Trim() } |
               Where-Object { $_ -and -not $_.StartsWith('#') }
    }
    $vsixFiles = @()
    if (Test-Path -LiteralPath $vsixDir) {
        $vsixFiles = @(Get-ChildItem -LiteralPath $vsixDir -Filter *.vsix -ErrorAction SilentlyContinue)
    }
    if ($ids.Count -eq 0 -and $vsixFiles.Count -eq 0) { return "keine Extensions konfiguriert" }

    $ok = 0; $fail = 0; $usedVsix = @()

    foreach ($id in $ids) {
        # .vsix vom Stick bevorzugen, sonst online per ID
        $match = $vsixFiles | Where-Object { $_.BaseName -like "$id*" } | Select-Object -First 1
        if ($match) { $target = $match.FullName; $label = "$id (vsix)"; $usedVsix += $match.Name }
        else        { $target = $id;            $label = "$id (online)" }
        $r = Start-Watched -FilePath $codeCmd -Label "Extension: $label" -TimeoutSec 300 -Arguments @('--install-extension', $target, '--force')
        Write-Log ("    EXT $label exit=$($r.ExitCode)")
        foreach ($line in $r.Output) { Write-Log ("      | $line") }
        if ($r.ExitCode -eq 0) { $ok++ } else { $fail++ }
    }
    # zusaetzliche .vsix ohne passende ID ebenfalls installieren
    foreach ($v in $vsixFiles) {
        if ($usedVsix -contains $v.Name) { continue }
        $r = Start-Watched -FilePath $codeCmd -Label "Extension: $($v.Name)" -TimeoutSec 300 -Arguments @('--install-extension', $v.FullName, '--force')
        Write-Log ("    EXT $($v.Name) exit=$($r.ExitCode)")
        foreach ($line in $r.Output) { Write-Log ("      | $line") }
        if ($r.ExitCode -eq 0) { $ok++ } else { $fail++ }
    }

    $msg = "$ok Extension(s) installiert"
    if ($fail -gt 0) { $msg += "; $fail fehlgeschlagen (siehe Log)" }
    return $msg
}

# ---------------------------------------------------------------------------
#  ABLAUF
# ---------------------------------------------------------------------------
Write-Banner
Write-Host "  Starte Vorbereitung..." -ForegroundColor White
Write-Host ""

# Log-Kopf mit Systeminfos (fuer spaetere Fehleranalyse)
Write-Log "==================== NTD Laptop-Vorbereitung START ===================="
Write-Log ("Computer : {0}" -f $env:COMPUTERNAME)
Write-Log ("Benutzer : {0}" -f $env:USERNAME)
Write-Log ("Quelle   : {0}" -f $ScriptDir)
Write-Log ("Log      : {0}" -f $script:LogFile)
Write-Log ("Architektur: {0}" -f $env:PROCESSOR_ARCHITECTURE)
try {
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
    $cs = Get-CimInstance Win32_ComputerSystem  -ErrorAction Stop
    Write-Log ("OS       : {0} {1} (Build {2})" -f $os.Caption, $os.OSArchitecture, $os.BuildNumber)
    Write-Log ("Modell   : {0} / {1} (SN {2})" -f $cs.Manufacturer, $cs.Model, ((Get-CimInstance Win32_BIOS -ErrorAction SilentlyContinue).SerialNumber))
} catch { Write-Log ("Systeminfo nicht ermittelbar: {0}" -f $_.Exception.Message) }

Invoke-Step "Teams beenden"                 { Task-CloseTeams }
Invoke-Step "Desktop leeren"                { Task-CleanDesktops }
Invoke-Step "Papierkorb leeren"             { Task-EmptyRecycleBin }
Invoke-Step "VS Code installieren"          { Task-InstallVSCode }
Invoke-Step "VS Code Extensions"            { Task-InstallExtensions }
Invoke-Step "Git installieren"              { Task-InstallGit }
Invoke-Step "Hintergrundbild setzen"        { Task-SetWallpaper }
Invoke-Step "Ordner C:\CodeTemp anlegen"    { Task-CreateCodeTemp }

# ---------------------------------------------------------------------------
#  ZUSAMMENFASSUNG
# ---------------------------------------------------------------------------
$okCount   = ($script:Results | Where-Object Ok).Count
$total     = $script:Results.Count
Write-Log ("ERGEBNIS : {0}/{1} Schritte erfolgreich" -f $okCount, $total)
Write-Log "==================== ENDE ===================="
Write-Host ""
Write-Host "  ------------------------------------------------------------" -ForegroundColor Cyan
if ($okCount -eq $total) {
    Write-Host "        FERTIG  -  $okCount/$total Schritte erfolgreich" -ForegroundColor Green
} else {
    Write-Host "        ABGESCHLOSSEN MIT FEHLERN  -  $okCount/$total ok" -ForegroundColor Yellow
}
Write-Host "  ------------------------------------------------------------" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Log gespeichert: $script:LogFile" -ForegroundColor DarkGray
Write-Host "  Dieses Fenster kann geschlossen werden." -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Weiter mit einer beliebigen Taste..." -ForegroundColor DarkGray
try { [void][System.Console]::ReadKey($true) } catch { Start-Sleep -Seconds 5 }
