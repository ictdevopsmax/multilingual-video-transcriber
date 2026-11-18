@echo off
setlocal
title Transkripsi Video Hybrid - C# .NET GUI
cd /d "%~dp0"

echo ======================================================================
echo    MEMULAI APLIKASI TRANSKRIPSI VIDEO (C# .NET GUI)
echo ======================================================================
echo.

:: 1. Periksa ketersediaan .NET SDK / Runtime (dotnet)
where dotnet >nul 2>&1
if not errorlevel 1 goto dotnet_ok

echo [!] .NET CLI belum terpasang atau belum terdaftar di PATH.
echo     Silakan pasang .NET SDK 8.0/10.0 dari https://dotnet.microsoft.com/
echo.
pause
exit /b 1

:dotnet_ok
for /f "tokens=*" %%V in ('dotnet --version 2^>nul') do set "DOTNET_VER=%%V"
echo [OK] .NET SDK / Runtime ditemukan: v%DOTNET_VER%

:: 2. Tambahkan folder tools (FFmpeg) ke PATH
set "PATH=%~dp0tools;%PATH%"
if exist "%~dp0tools\ffmpeg.exe" (
    echo [OK] FFmpeg lokal siap: %~dp0tools\ffmpeg.exe
)

echo.
echo [*] Membangun dan menjalankan Transkripsi Video C# GUI...
cd /d "%~dp0csharp"
dotnet run
if errorlevel 1 (
    echo.
    echo [!] Aplikasi C# berhenti dengan error.
    pause
)
