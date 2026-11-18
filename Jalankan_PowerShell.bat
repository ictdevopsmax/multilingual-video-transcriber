@echo off
title Transkripsi Video Hybrid - PowerShell GUI
cd /d "%~dp0"

:: Konfigurasi encoding UTF-8 untuk konsol dan Python subprocess
chcp 65001 >nul
set "PYTHONIOENCODING=utf-8"
set "PYTHONUTF8=1"

set "PATH=%~dp0tools;%PATH%"
echo Menjalankan aplikasi Transkripsi Video (PowerShell GUI)...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0powershell\transkripsi_gui.ps1"
if %errorlevel% neq 0 (
    echo.
    echo [!] Terjadi kesalahan saat menjalankan PowerShell GUI (Kode: %errorlevel%).
    pause
)

