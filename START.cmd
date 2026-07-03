@echo off
REM ============================================================
REM  NTD Laptop-Vorbereitung  -  Ein-Klick-Launcher
REM  Startet Setup.ps1 mit ExecutionPolicy Bypass.
REM  Die eigentliche Admin-Anforderung (UAC) macht Setup.ps1.
REM ============================================================
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Setup.ps1"
