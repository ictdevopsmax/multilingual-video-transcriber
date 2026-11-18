@echo off
title Server Vosk Offline WebSocket (Side Panel Ekstensi)
cd /d "%~dp0"
echo ======================================================================
echo    MEMULAI SERVER VOSK OFFLINE WEBSOCKET (PORT 2700)
echo    Untuk Ekstensi Chrome / Edge: Transkripsi Video Side Panel
echo ======================================================================
echo.

python -u server_vosk_local.py
if %errorlevel% neq 0 (
    echo.
    echo [!] Terjadi kesalahan pada server (Kode: %errorlevel%).
    pause
)
