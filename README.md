# NTD Laptop-Vorbereitung (USB-Stick)

Ein-Klick-Vorbereitung für 32 Laptops. Stick anstecken, **`START.cmd` doppelklicken**, einmal UAC bestätigen, fertig.

## Was passiert (mit Live-Statusanzeige)

1. **VS Code** installieren – System-Setup für alle Benutzer, komplett silent, offline vom Stick.
2. **Hintergrundbild** auf Windows-Standard (`img0.jpg`) setzen – auf allen Laptops identisch.
3. **Desktop komplett leeren** – User-Desktop, Public-Desktop und (falls vorhanden) OneDrive-umgeleiteter Desktop. `desktop.ini` bleibt erhalten.
4. **Ordner `C:\CodeTemp`** anlegen.

Am Ende: Zusammenfassung `x/4 Schritte erfolgreich`.

## Bedienung

1. Stick anstecken.
2. Doppelklick auf **`START.cmd`**.
3. UAC-Abfrage mit **Ja** bestätigen (Adminrechte werden sauber angefragt – kein „Als Administrator ausführen“ nötig).
4. Warten bis „FERTIG“. Fenster schließen.

## Admin-Konzept

Selbst-Elevation per UAC (`Start-Process -Verb RunAs`). Ein Klick + einmal „Ja“. Kein Rechtsklick-Menü, keine PowerShell-Blockade (`-ExecutionPolicy Bypass`).

## Robustheit („strange Pfade“)

- **Beliebiger USB-Laufwerksbuchstabe** → alles relativ über `$PSScriptRoot`.
- **Leerzeichen/Sonderzeichen im Pfad** → durchgehend `-LiteralPath` / Quoting.
- **OneDrive-umgeleiteter / lokalisierter Desktop** → `[Environment]::GetFolderPath()` + Registry-Gegenprüfung statt `%USERPROFILE%\Desktop`.
- **x64 & ARM64** → passender Installer wird automatisch gewählt.
- Jeder Schritt in `try/catch`; gesperrte Dateien werden übersprungen, nicht abgebrochen.

## Dateien

| Datei | Zweck |
|------|-------|
| `START.cmd` | Ein-Klick-Launcher |
| `Setup.ps1` | Hauptlogik + Statusanzeige (self-elevating) |
| `Download-VSCode.ps1` | Installer neu/aktuell herunterladen (Rechner mit Internet) |
| `installers\VSCodeSetup-x64.exe` | Offline-Installer (bereits enthalten) |
| `installers\VSCodeSetup-arm64.exe` | optional für ARM64-Laptops (`Download-VSCode.ps1`) |
| `installers\wallpaper.jpg` | optional: Firmen-Bild statt Windows-Standard |

## Anpassen

- **Eigenes Hintergrundbild:** `wallpaper.jpg` in `installers\` legen – wird automatisch bevorzugt.
- **Installer aktualisieren:** `Download-VSCode.ps1` auf einem Rechner mit Internet ausführen.
